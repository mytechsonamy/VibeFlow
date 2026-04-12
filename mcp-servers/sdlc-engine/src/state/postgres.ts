import type { Pool } from "pg";
import {
  StateStore,
  ProjectState,
  StateMutator,
  KeyedAsyncLock,
  assertRevisionIncrement,
  ConsensusRecord,
} from "./store.js";
import { PhaseId } from "../phases.js";
import { parseConsensusStatus } from "../consensus.js";

/**
 * Structural view of the tiny slice of pg.Pool / pg.PoolClient we actually
 * use. Decoupling from the real `pg` types lets tests inject a hand-rolled
 * fake pool without installing postgres (which is a peer dependency —
 * solo-mode users should not be forced to carry the cost).
 */
export interface PgQueryResult<R> {
  readonly rows: readonly R[];
  readonly rowCount: number | null;
}

export interface PgClientLike {
  query<R = unknown>(
    sql: string,
    params?: readonly unknown[],
  ): Promise<PgQueryResult<R>>;
  release(err?: Error | boolean): void;
}

export interface PgPoolLike {
  query<R = unknown>(
    sql: string,
    params?: readonly unknown[],
  ): Promise<PgQueryResult<R>>;
  connect(): Promise<PgClientLike>;
  end(): Promise<void>;
  on(event: "error", handler: (err: Error) => void): PgPoolLike;
  readonly totalCount: number;
  readonly idleCount: number;
  readonly waitingCount: number;
}

export interface PgPoolMetrics {
  readonly totalCount: number;
  readonly idleCount: number;
  readonly waitingCount: number;
}

/**
 * Pool options — all optional. Defaults are tuned for team mode under
 * regular load; if you need heavier concurrency set `max` and
 * `idleTimeoutMillis` explicitly. `connectionTimeoutMillis` in particular
 * is critical: without it, a dead DB manifests as a hung promise instead
 * of a clear error.
 */
export interface PgPoolOptions {
  readonly connectionTimeoutMillis?: number;
  readonly idleTimeoutMillis?: number;
  readonly max?: number;
}

const DEFAULT_POOL_OPTIONS: Required<PgPoolOptions> = {
  connectionTimeoutMillis: 10_000,
  idleTimeoutMillis: 30_000,
  max: 10,
};

interface StateRow {
  project_id: string;
  current_phase: string;
  satisfied_criteria: unknown;
  last_consensus: unknown;
  updated_at: string | Date;
  revision: number;
}

export class PostgresStateStore implements StateStore {
  private readonly locks = new KeyedAsyncLock();
  private closed = false;

  private constructor(private readonly pool: PgPoolLike) {}

  /**
   * Production factory: dynamically imports `pg`, constructs a Pool with
   * safe defaults, wires the error handler, and returns a store.
   */
  static async create(
    connectionString: string,
    opts: PgPoolOptions = {},
  ): Promise<PostgresStateStore> {
    let pgModule: typeof import("pg");
    try {
      pgModule = (await import("pg")) as typeof import("pg");
    } catch {
      throw new Error(
        "PostgresStateStore requires the 'pg' package. " +
          "Install it with: npm install pg",
      );
    }
    // pg exports both CJS default and named Pool; handle both.
    const PoolCtor =
      (pgModule as unknown as { Pool?: typeof Pool; default?: { Pool: typeof Pool } }).Pool ??
      (pgModule as unknown as { default: { Pool: typeof Pool } }).default.Pool;

    const pool = new PoolCtor({
      connectionString,
      connectionTimeoutMillis:
        opts.connectionTimeoutMillis ?? DEFAULT_POOL_OPTIONS.connectionTimeoutMillis,
      idleTimeoutMillis:
        opts.idleTimeoutMillis ?? DEFAULT_POOL_OPTIONS.idleTimeoutMillis,
      max: opts.max ?? DEFAULT_POOL_OPTIONS.max,
    });
    return PostgresStateStore.fromPool(pool as unknown as PgPoolLike);
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
  static fromPool(pool: PgPoolLike): PostgresStateStore {
    pool.on("error", (err: Error) => {
      process.stderr.write(
        `[sdlc-engine] pg idle client error: ${err.message}\n`,
      );
    });
    return new PostgresStateStore(pool);
  }

  async init(): Promise<void> {
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
  }

  async read(projectId: string): Promise<ProjectState | null> {
    const res = await this.pool.query<StateRow>(
      "SELECT * FROM project_state WHERE project_id = $1",
      [projectId],
    );
    return res.rows.length > 0 ? rowToState(res.rows[0]!) : null;
  }

  async transact<T>(
    projectId: string,
    mutator: StateMutator<T>,
  ): Promise<T> {
    return this.locks.acquire(projectId, async () => {
      let client: PgClientLike;
      try {
        client = await this.pool.connect();
      } catch (err) {
        // Distinguish transport/connect failures from in-transaction query
        // errors so operators can tell "DB down" apart from "optimistic
        // lock lost". Nothing to release here — the client was never
        // checked out.
        throw new Error(
          `pg connect failed for project ${projectId}: ${
            (err as Error).message
          }`,
        );
      }

      let releaseErr: Error | undefined;
      try {
        await client.query("BEGIN");
        // Advisory lock: serializes writes across processes for this
        // project. Paired with SELECT...FOR UPDATE on the row itself.
        await client.query(
          "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
          [projectId],
        );

        const res = await client.query<StateRow>(
          "SELECT * FROM project_state WHERE project_id = $1 FOR UPDATE",
          [projectId],
        );
        const current = res.rows.length > 0 ? rowToState(res.rows[0]!) : null;

        const { next, result } = mutator(current);
        assertRevisionIncrement(current, next, projectId);

        if (current === null) {
          await client.query(
            `INSERT INTO project_state
               (project_id, current_phase, satisfied_criteria, last_consensus, updated_at, revision)
             VALUES ($1, $2, $3, $4, $5, $6)`,
            [
              next.projectId,
              next.currentPhase,
              JSON.stringify(next.satisfiedCriteria),
              next.lastConsensus ? JSON.stringify(next.lastConsensus) : null,
              next.updatedAt,
              next.revision,
            ],
          );
        } else {
          const update = await client.query(
            `UPDATE project_state
               SET current_phase = $1,
                   satisfied_criteria = $2,
                   last_consensus = $3,
                   updated_at = $4,
                   revision = $5
             WHERE project_id = $6 AND revision = $7`,
            [
              next.currentPhase,
              JSON.stringify(next.satisfiedCriteria),
              next.lastConsensus ? JSON.stringify(next.lastConsensus) : null,
              next.updatedAt,
              next.revision,
              next.projectId,
              current.revision,
            ],
          );
          if (update.rowCount !== 1) {
            throw new Error(
              `Optimistic lock failed for project ${projectId}: ` +
                `expected revision ${current.revision}`,
            );
          }
        }

        await client.query("COMMIT");
        return result;
      } catch (err) {
        releaseErr = err as Error;
        // Rollback is best-effort — if it also fails we still propagate
        // the ORIGINAL error and let `release(err)` destroy the client.
        await client!.query("ROLLBACK").catch((rollErr: unknown) => {
          process.stderr.write(
            `[sdlc-engine] pg ROLLBACK failed for project ${projectId}: ${
              (rollErr as Error).message
            }\n`,
          );
        });
        throw err;
      } finally {
        // Bug #4 core fix: pass `releaseErr` to `release()` so pg destroys
        // the client rather than returning it to the pool. A client that
        // hit a mid-transaction error may have a broken transaction state
        // (aborted, unflushed buffers, closed underlying socket) — reusing
        // it is how leaks compound over time.
        try {
          client!.release(releaseErr);
        } catch (relErr) {
          // `release()` throwing would mask the original error. Log and
          // swallow — the pool is already in a bad shape.
          process.stderr.write(
            `[sdlc-engine] pg client.release failed for project ${projectId}: ${
              (relErr as Error).message
            }\n`,
          );
        }
      }
    });
  }

  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    try {
      await this.pool.end();
    } catch (err) {
      // Shutdown errors are logged but not propagated — the caller has
      // already decided we're going down. Crashing on the way out just
      // hides the original reason.
      process.stderr.write(
        `[sdlc-engine] pg pool.end() failed: ${(err as Error).message}\n`,
      );
    }
  }

  /**
   * Observability hook for team mode: expose pool saturation without
   * leaking the underlying Pool instance to callers. Used by tests to
   * assert that every checkout is matched by a release.
   */
  metrics(): PgPoolMetrics {
    return {
      totalCount: this.pool.totalCount,
      idleCount: this.pool.idleCount,
      waitingCount: this.pool.waitingCount,
    };
  }
}

function rowToState(row: StateRow): ProjectState {
  const satisfied =
    typeof row.satisfied_criteria === "string"
      ? (JSON.parse(row.satisfied_criteria) as string[])
      : (row.satisfied_criteria as string[]);
  const consensusRaw =
    typeof row.last_consensus === "string"
      ? row.last_consensus
        ? JSON.parse(row.last_consensus)
        : null
      : row.last_consensus;
  return {
    projectId: row.project_id,
    currentPhase: row.current_phase as PhaseId,
    satisfiedCriteria: satisfied,
    lastConsensus: consensusRaw ? parseConsensusRow(consensusRaw) : null,
    updatedAt:
      row.updated_at instanceof Date
        ? row.updated_at.toISOString()
        : String(row.updated_at),
    revision: row.revision,
  };
}

function parseConsensusRow(raw: unknown): ConsensusRecord {
  if (!raw || typeof raw !== "object") {
    throw new Error("Corrupt consensus record in database");
  }
  const r = raw as Record<string, unknown>;
  return {
    phase: r.phase as PhaseId,
    status: parseConsensusStatus(r.status),
    agreement: Number(r.agreement),
    criticalIssues: Number(r.criticalIssues),
    recordedAt: String(r.recordedAt),
  };
}
