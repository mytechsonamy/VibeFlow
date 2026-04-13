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
