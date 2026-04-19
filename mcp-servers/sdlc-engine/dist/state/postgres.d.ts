import { StateStore, ProjectState, StateMutator } from "./store.js";
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
    query<R = unknown>(sql: string, params?: readonly unknown[]): Promise<PgQueryResult<R>>;
    release(err?: Error | boolean): void;
}
export interface PgPoolLike {
    query<R = unknown>(sql: string, params?: readonly unknown[]): Promise<PgQueryResult<R>>;
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
export declare class PostgresStateStore implements StateStore {
    private readonly pool;
    private readonly locks;
    private closed;
    private constructor();
    /**
     * Production factory: dynamically imports `pg`, constructs a Pool with
     * safe defaults, wires the error handler, and returns a store.
     */
    static create(connectionString: string, opts?: PgPoolOptions): Promise<PostgresStateStore>;
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
    static fromPool(pool: PgPoolLike): PostgresStateStore;
    init(): Promise<void>;
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
    private probePoolerMode;
    read(projectId: string): Promise<ProjectState | null>;
    transact<T>(projectId: string, mutator: StateMutator<T>): Promise<T>;
    close(): Promise<void>;
    /**
     * Observability hook for team mode: expose pool saturation without
     * leaking the underlying Pool instance to callers. Used by tests to
     * assert that every checkout is matched by a release.
     */
    metrics(): PgPoolMetrics;
}
