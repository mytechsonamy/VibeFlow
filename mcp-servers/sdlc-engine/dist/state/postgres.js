import { KeyedAsyncLock, assertRevisionIncrement, } from "./store.js";
import { parseConsensusStatus } from "../consensus.js";
const DEFAULT_POOL_OPTIONS = {
    connectionTimeoutMillis: 10_000,
    idleTimeoutMillis: 30_000,
    max: 10,
};
export class PostgresStateStore {
    pool;
    locks = new KeyedAsyncLock();
    closed = false;
    constructor(pool) {
        this.pool = pool;
    }
    /**
     * Production factory: dynamically imports `pg`, constructs a Pool with
     * safe defaults, wires the error handler, and returns a store.
     */
    static async create(connectionString, opts = {}) {
        let pgModule;
        try {
            pgModule = (await import("pg"));
        }
        catch {
            throw new Error("PostgresStateStore requires the 'pg' package. " +
                "Install it with: npm install pg");
        }
        // pg exports both CJS default and named Pool; handle both.
        const PoolCtor = pgModule.Pool ??
            pgModule.default.Pool;
        const pool = new PoolCtor({
            connectionString,
            connectionTimeoutMillis: opts.connectionTimeoutMillis ?? DEFAULT_POOL_OPTIONS.connectionTimeoutMillis,
            idleTimeoutMillis: opts.idleTimeoutMillis ?? DEFAULT_POOL_OPTIONS.idleTimeoutMillis,
            max: opts.max ?? DEFAULT_POOL_OPTIONS.max,
        });
        return PostgresStateStore.fromPool(pool);
    }
    /**
     * Test/injection factory. Registers the idle-client error handler on the
     * given pool and returns a store wrapping it.
     *
     * Bug #4 fix: without this handler, a disconnected or errored idle client
     * causes pg to emit `"error"` on the Pool. Unhandled `error` events on an
     * EventEmitter crash the Node process; by treating the event as a
     * logged warning we keep the process alive and let the pool reap the
     * broken client on its own.
     */
    static fromPool(pool) {
        pool.on("error", (err) => {
            process.stderr.write(`[sdlc-engine] pg idle client error: ${err.message}\n`);
        });
        return new PostgresStateStore(pool);
    }
    async init() {
        // Pool.query() auto-acquires and releases a client — there is no
        // manual release path here, so nothing to leak.
        await this.pool.query(`
      CREATE TABLE IF NOT EXISTS project_state (
        project_id TEXT PRIMARY KEY,
        current_phase TEXT NOT NULL,
        satisfied_criteria JSONB NOT NULL,
        last_consensus JSONB,
        updated_at TIMESTAMPTZ NOT NULL,
        revision INTEGER NOT NULL
      );
    `);
        // S10-01 — PgBouncer transaction-mode startup probe. Must run AFTER
        // the table CREATE so a fresh database still gets bootstrapped, but
        // BEFORE the first transact() call so a misconfigured pooler is
        // caught at boot rather than as flaky stale-read failures under load.
        await this.probePoolerMode();
    }
    /**
     * S10-01 — detect PgBouncer transaction-mode pooling.
     *
     * `pg_advisory_xact_lock` (used by transact()) only serializes writes
     * if every statement inside a single transaction lands on the same
     * backend. PgBouncer in `transaction` pool mode breaks that invariant
     * by re-binding the client connection to a different backend on every
     * BEGIN, which silently defeats the lock. The caveat was documented
     * in `docs/TEAM-MODE.md` since v1.2 but never detected at runtime —
     * operators only saw it as occasional stale-read failures.
     *
     * Mechanism: acquire ONE client from the pool and run two explicit
     * transactions on it. Inside each transaction, ask the backend for
     * its PID. In session mode the same backend services both → same
     * PID. In transaction mode a different backend may service the
     * second BEGIN → different PID → abort.
     *
     * Opt-out: `VF_SKIP_POOLER_CHECK=1` for operators who run transaction
     * mode deliberately and accept the advisory-lock caveat (typically a
     * read-mostly workload where contention is rare).
     */
    async probePoolerMode() {
        if (process.env.VF_SKIP_POOLER_CHECK === "1")
            return;
        let client;
        try {
            client = await this.pool.connect();
        }
        catch (err) {
            throw new Error(`PgBouncer probe failed during pool.connect(): ${err.message}`);
        }
        try {
            const pid1 = await readBackendPid(client);
            const pid2 = await readBackendPid(client);
            if (pid1 !== pid2) {
                throw new Error("PgBouncer transaction-mode pooling detected " +
                    `(backend pid changed ${pid1} → ${pid2} across two ` +
                    "transactions on the same pool client). " +
                    "pg_advisory_xact_lock cannot serialize writes when each " +
                    "BEGIN may bind a different backend. " +
                    "Fix: switch the pool to session mode, OR point VibeFlow at " +
                    "the direct Postgres endpoint instead of the PgBouncer pooler. " +
                    'See docs/TEAM-MODE.md § "PgBouncer transaction-pool caveat". ' +
                    "To bypass this check (accepting the advisory-lock caveat), " +
                    "set VF_SKIP_POOLER_CHECK=1.");
            }
        }
        finally {
            try {
                client.release();
            }
            catch (relErr) {
                process.stderr.write(`[sdlc-engine] pg client.release() failed during PgBouncer probe: ${relErr.message}\n`);
            }
        }
    }
    async read(projectId) {
        const res = await this.pool.query("SELECT * FROM project_state WHERE project_id = $1", [projectId]);
        return res.rows.length > 0 ? rowToState(res.rows[0]) : null;
    }
    async transact(projectId, mutator) {
        return this.locks.acquire(projectId, async () => {
            let client;
            try {
                client = await this.pool.connect();
            }
            catch (err) {
                // Distinguish transport/connect failures from in-transaction query
                // errors so operators can tell "DB down" apart from "optimistic
                // lock lost". Nothing to release here — the client was never
                // checked out.
                throw new Error(`pg connect failed for project ${projectId}: ${err.message}`);
            }
            let releaseErr;
            try {
                await client.query("BEGIN");
                // Advisory lock: serializes writes across processes for this
                // project. Paired with SELECT...FOR UPDATE on the row itself.
                await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [projectId]);
                const res = await client.query("SELECT * FROM project_state WHERE project_id = $1 FOR UPDATE", [projectId]);
                const current = res.rows.length > 0 ? rowToState(res.rows[0]) : null;
                const { next, result } = mutator(current);
                assertRevisionIncrement(current, next, projectId);
                if (current === null) {
                    await client.query(`INSERT INTO project_state
               (project_id, current_phase, satisfied_criteria, last_consensus, updated_at, revision)
             VALUES ($1, $2, $3, $4, $5, $6)`, [
                        next.projectId,
                        next.currentPhase,
                        JSON.stringify(next.satisfiedCriteria),
                        next.lastConsensus ? JSON.stringify(next.lastConsensus) : null,
                        next.updatedAt,
                        next.revision,
                    ]);
                }
                else {
                    const update = await client.query(`UPDATE project_state
               SET current_phase = $1,
                   satisfied_criteria = $2,
                   last_consensus = $3,
                   updated_at = $4,
                   revision = $5
             WHERE project_id = $6 AND revision = $7`, [
                        next.currentPhase,
                        JSON.stringify(next.satisfiedCriteria),
                        next.lastConsensus ? JSON.stringify(next.lastConsensus) : null,
                        next.updatedAt,
                        next.revision,
                        next.projectId,
                        current.revision,
                    ]);
                    if (update.rowCount !== 1) {
                        throw new Error(`Optimistic lock failed for project ${projectId}: ` +
                            `expected revision ${current.revision}`);
                    }
                }
                await client.query("COMMIT");
                return result;
            }
            catch (err) {
                releaseErr = err;
                // Rollback is best-effort — if it also fails we still propagate
                // the ORIGINAL error and let `release(err)` destroy the client.
                await client.query("ROLLBACK").catch((rollErr) => {
                    process.stderr.write(`[sdlc-engine] pg ROLLBACK failed for project ${projectId}: ${rollErr.message}\n`);
                });
                throw err;
            }
            finally {
                // Bug #4 core fix: pass `releaseErr` to `release()` so pg destroys
                // the client rather than returning it to the pool. A client that
                // hit a mid-transaction error may have a broken transaction state
                // (aborted, unflushed buffers, closed underlying socket) — reusing
                // it is how leaks compound over time.
                try {
                    client.release(releaseErr);
                }
                catch (relErr) {
                    // `release()` throwing would mask the original error. Log and
                    // swallow — the pool is already in a bad shape.
                    process.stderr.write(`[sdlc-engine] pg client.release failed for project ${projectId}: ${relErr.message}\n`);
                }
            }
        });
    }
    async close() {
        if (this.closed)
            return;
        this.closed = true;
        try {
            await this.pool.end();
        }
        catch (err) {
            // Shutdown errors are logged but not propagated — the caller has
            // already decided we're going down. Crashing on the way out just
            // hides the original reason.
            process.stderr.write(`[sdlc-engine] pg pool.end() failed: ${err.message}\n`);
        }
    }
    /**
     * Observability hook for team mode: expose pool saturation without
     * leaking the underlying Pool instance to callers. Used by tests to
     * assert that every checkout is matched by a release.
     */
    metrics() {
        return {
            totalCount: this.pool.totalCount,
            idleCount: this.pool.idleCount,
            waitingCount: this.pool.waitingCount,
        };
    }
}
/**
 * S10-01 helper — runs `SHOW search_path; SELECT pg_backend_pid()` inside
 * an explicit BEGIN/COMMIT transaction on the supplied client and returns
 * the backend PID. Extracted from `probePoolerMode` so the two-transaction
 * comparison reads as a straight pid1/pid2 diff. SHOW search_path is the
 * canary sanity-check from the spec — its result is discarded but its
 * presence forces the pooler to actually open a session if it deferred
 * the bind on BEGIN alone.
 */
async function readBackendPid(client) {
    await client.query("BEGIN");
    try {
        await client.query("SHOW search_path");
        const res = await client.query("SELECT pg_backend_pid() AS pid");
        const pid = Number(res.rows[0]?.pid);
        if (!Number.isFinite(pid) || pid <= 0) {
            throw new Error(`PgBouncer probe could not read pg_backend_pid (got '${res.rows[0]?.pid}')`);
        }
        await client.query("COMMIT");
        return pid;
    }
    catch (err) {
        await client.query("ROLLBACK").catch(() => undefined);
        throw err;
    }
}
function rowToState(row) {
    const satisfied = typeof row.satisfied_criteria === "string"
        ? JSON.parse(row.satisfied_criteria)
        : row.satisfied_criteria;
    const consensusRaw = typeof row.last_consensus === "string"
        ? row.last_consensus
            ? JSON.parse(row.last_consensus)
            : null
        : row.last_consensus;
    return {
        projectId: row.project_id,
        currentPhase: row.current_phase,
        satisfiedCriteria: satisfied,
        lastConsensus: consensusRaw ? parseConsensusRow(consensusRaw) : null,
        updatedAt: row.updated_at instanceof Date
            ? row.updated_at.toISOString()
            : String(row.updated_at),
        revision: row.revision,
    };
}
function parseConsensusRow(raw) {
    if (!raw || typeof raw !== "object") {
        throw new Error("Corrupt consensus record in database");
    }
    const r = raw;
    return {
        phase: r.phase,
        status: parseConsensusStatus(r.status),
        agreement: Number(r.agreement),
        criticalIssues: Number(r.criticalIssues),
        recordedAt: String(r.recordedAt),
    };
}
//# sourceMappingURL=postgres.js.map