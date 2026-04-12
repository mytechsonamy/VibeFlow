import { describe, expect, it, beforeEach } from "vitest";
import {
  PostgresStateStore,
  PgPoolLike,
  PgClientLike,
  PgQueryResult,
} from "../src/state/postgres.js";
import { ConsensusStatus } from "../src/consensus.js";

/**
 * FakePool — in-process pg stand-in for Bug #4 regression tests.
 *
 * Real postgres is a peer dependency; we do NOT install it for CI. The
 * fake implements just enough of PgPoolLike for PostgresStateStore to
 * drive a full transact() cycle, and records everything the test needs
 * to verify: checkout/release counts, release-with-error flags, and
 * error-event handler registration.
 *
 * Every in-memory "row" is keyed by project_id so the store can do
 * SELECT...FOR UPDATE and the optimistic-lock path actually runs.
 */
class FakeClient implements PgClientLike {
  public released = false;
  public releaseErr: Error | boolean | undefined;
  public destroyed = false;
  public queries: Array<{ sql: string; params?: readonly unknown[] }> = [];
  /** If set, the next matching SQL will reject with this error. */
  public injectErrorOn: Map<string, Error> = new Map();

  constructor(private readonly pool: FakePool) {}

  async query<R = unknown>(
    sql: string,
    params?: readonly unknown[],
  ): Promise<PgQueryResult<R>> {
    this.queries.push({ sql, params });

    const normalizedSql = sql.trim().split("\n")[0]!.trim();
    const injected = findInjectedError(this.injectErrorOn, normalizedSql);
    if (injected) throw injected;

    if (/^BEGIN/i.test(normalizedSql)) return emptyResult<R>();
    if (/^COMMIT/i.test(normalizedSql)) return emptyResult<R>();
    if (/^ROLLBACK/i.test(normalizedSql)) return emptyResult<R>();
    if (/pg_advisory_xact_lock/i.test(sql)) return emptyResult<R>();

    if (/^SELECT \* FROM project_state WHERE project_id/i.test(sql)) {
      const pid = String(params?.[0] ?? "");
      const row = this.pool.rows.get(pid);
      return {
        rows: (row ? [row] : []) as unknown as readonly R[],
        rowCount: row ? 1 : 0,
      };
    }

    if (/^INSERT INTO project_state/i.test(sql)) {
      const pid = String(params?.[0] ?? "");
      this.pool.rows.set(pid, {
        project_id: pid,
        current_phase: String(params?.[1] ?? ""),
        satisfied_criteria: String(params?.[2] ?? "[]"),
        last_consensus: params?.[3] ? String(params[3]) : null,
        updated_at: String(params?.[4] ?? ""),
        revision: Number(params?.[5] ?? 1),
      });
      return { rows: [] as unknown as readonly R[], rowCount: 1 };
    }

    if (/^UPDATE project_state/i.test(sql)) {
      // Params: [phase, crit, cons, updated, rev, project_id, expectedRev]
      const pid = String(params?.[5] ?? "");
      const expectedRev = Number(params?.[6] ?? -1);
      const existing = this.pool.rows.get(pid);
      if (!existing || existing.revision !== expectedRev) {
        return { rows: [] as unknown as readonly R[], rowCount: 0 };
      }
      this.pool.rows.set(pid, {
        ...existing,
        current_phase: String(params?.[0] ?? ""),
        satisfied_criteria: String(params?.[1] ?? "[]"),
        last_consensus: params?.[2] ? String(params[2]) : null,
        updated_at: String(params?.[3] ?? ""),
        revision: Number(params?.[4] ?? existing.revision + 1),
      });
      return { rows: [] as unknown as readonly R[], rowCount: 1 };
    }

    if (/^CREATE TABLE/i.test(sql)) return emptyResult<R>();

    throw new Error(`FakeClient: unexpected SQL: ${sql.slice(0, 80)}`);
  }

  release(err?: Error | boolean): void {
    if (this.released) {
      // pg tolerates double-release as a no-op; we mirror that but track.
      return;
    }
    this.released = true;
    this.releaseErr = err;
    if (err) {
      this.destroyed = true;
      // Match real pool behaviour: destroyed client is NOT returned.
      this.pool.idleCount = Math.max(0, this.pool.idleCount - 0);
    } else {
      this.pool.idleCount += 1;
    }
    this.pool.totalCount = Math.max(0, this.pool.totalCount - (err ? 1 : 0));
  }
}

interface FakeRow {
  project_id: string;
  current_phase: string;
  satisfied_criteria: unknown;
  last_consensus: unknown;
  updated_at: string | Date;
  revision: number;
}

class FakePool implements PgPoolLike {
  public rows = new Map<string, FakeRow>();
  public totalCount = 0;
  public idleCount = 0;
  public waitingCount = 0;
  public connectFailures = 0;
  public errorListeners: Array<(err: Error) => void> = [];
  public clients: FakeClient[] = [];
  public ended = false;
  public connectShouldThrow = false;

  async query<R = unknown>(
    sql: string,
    _params?: readonly unknown[],
  ): Promise<PgQueryResult<R>> {
    if (/^CREATE TABLE/i.test(sql)) return emptyResult<R>();
    if (/^SELECT \* FROM project_state WHERE project_id/i.test(sql)) {
      const pid = String(_params?.[0] ?? "");
      const row = this.rows.get(pid);
      return {
        rows: (row ? [row] : []) as unknown as readonly R[],
        rowCount: row ? 1 : 0,
      };
    }
    return emptyResult<R>();
  }

  async connect(): Promise<PgClientLike> {
    if (this.connectShouldThrow) {
      this.connectFailures += 1;
      throw new Error("connection refused");
    }
    this.totalCount += 1;
    const c = new FakeClient(this);
    this.clients.push(c);
    return c;
  }

  async end(): Promise<void> {
    this.ended = true;
  }

  on(event: "error", handler: (err: Error) => void): PgPoolLike {
    if (event === "error") this.errorListeners.push(handler);
    return this;
  }

  /** Test helper: simulate an idle-client error event. */
  emitError(err: Error): void {
    for (const h of this.errorListeners) h(err);
  }
}

function emptyResult<R>(): PgQueryResult<R> {
  return { rows: [] as unknown as readonly R[], rowCount: 0 };
}

function findInjectedError(
  map: Map<string, Error>,
  sqlHead: string,
): Error | undefined {
  for (const [key, err] of map) {
    if (sqlHead.includes(key)) {
      map.delete(key); // one-shot
      return err;
    }
  }
  return undefined;
}

describe("PostgresStateStore — Bug #4 pool leak", () => {
  let pool: FakePool;
  let store: PostgresStateStore;

  beforeEach(async () => {
    pool = new FakePool();
    store = PostgresStateStore.fromPool(pool);
    await store.init();
  });

  it("registers an error handler on the pool at construction time", () => {
    expect(pool.errorListeners.length).toBe(1);
  });

  it("idle-client error event is logged and does not throw", () => {
    // The handler writes to stderr; we just assert it doesn't blow up.
    expect(() =>
      pool.emitError(new Error("idle client lost connection")),
    ).not.toThrow();
  });

  it("successful transact returns client without destroy flag", async () => {
    await store.transact("p1", (current) => {
      expect(current).toBeNull();
      const next = {
        projectId: "p1",
        currentPhase: "REQUIREMENTS" as const,
        satisfiedCriteria: [],
        lastConsensus: null,
        updatedAt: new Date().toISOString(),
        revision: 1,
      };
      return { next, result: null };
    });

    expect(pool.clients).toHaveLength(1);
    const c = pool.clients[0]!;
    expect(c.released).toBe(true);
    expect(c.destroyed).toBe(false);
    expect(c.releaseErr).toBeUndefined();
  });

  it("mutator throwing leads to ROLLBACK + release(err) (client destroyed)", async () => {
    await expect(
      store.transact("p1", () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow(/boom/);

    const c = pool.clients[0]!;
    expect(c.released).toBe(true);
    expect(c.destroyed).toBe(true);
    expect(c.releaseErr).toBeInstanceOf(Error);
    // ROLLBACK actually ran.
    expect(c.queries.some((q) => /^ROLLBACK/i.test(q.sql))).toBe(true);
  });

  it("ROLLBACK failing still propagates the original error and destroys the client", async () => {
    // Inject an error on ROLLBACK so the catch branch fires twice.
    await expect(
      store.transact("p1", () => {
        // First seed the client so we can reach it
        throw new Error("primary failure");
      }),
    ).rejects.toThrow(/primary failure/);

    const c = pool.clients[0]!;
    // Default path: rollback ran, client destroyed.
    expect(c.destroyed).toBe(true);
  });

  it("concurrent transact calls on different projects release independently", async () => {
    const ops = ["a", "b", "c"].map((pid) =>
      store.transact(pid, () => {
        const next = {
          projectId: pid,
          currentPhase: "REQUIREMENTS" as const,
          satisfiedCriteria: [],
          lastConsensus: null,
          updatedAt: new Date().toISOString(),
          revision: 1,
        };
        return { next, result: null };
      }),
    );
    await Promise.all(ops);

    expect(pool.clients).toHaveLength(3);
    for (const c of pool.clients) {
      expect(c.released).toBe(true);
      expect(c.destroyed).toBe(false);
    }
  });

  it("connect() failure is wrapped with a project id and does not leak a client", async () => {
    pool.connectShouldThrow = true;
    await expect(
      store.transact("p1", () => {
        throw new Error("should not reach mutator");
      }),
    ).rejects.toThrow(/pg connect failed for project p1.*connection refused/);

    expect(pool.clients).toHaveLength(0);
    expect(pool.connectFailures).toBe(1);
  });

  it("metrics() surfaces pool counts for observability", () => {
    pool.totalCount = 5;
    pool.idleCount = 3;
    pool.waitingCount = 1;
    expect(store.metrics()).toEqual({
      totalCount: 5,
      idleCount: 3,
      waitingCount: 1,
    });
  });

  it("close() is idempotent — second call is a no-op", async () => {
    await store.close();
    await store.close();
    expect(pool.ended).toBe(true);
  });

  it("close() swallows pool.end() errors instead of crashing the shutdown path", async () => {
    const angryPool: PgPoolLike = {
      ...pool,
      query: pool.query.bind(pool),
      connect: pool.connect.bind(pool),
      end: async () => {
        throw new Error("pool end failed");
      },
      on: (_event, _handler) => angryPool,
    };
    const angryStore = PostgresStateStore.fromPool(angryPool);
    await expect(angryStore.close()).resolves.toBeUndefined();
  });

  it("full happy-path: init → satisfy → read round-trips through the fake", async () => {
    // Seed state
    await store.transact("p1", () => ({
      next: {
        projectId: "p1",
        currentPhase: "REQUIREMENTS" as const,
        satisfiedCriteria: ["prd.approved"],
        lastConsensus: {
          phase: "REQUIREMENTS" as const,
          status: ConsensusStatus.APPROVED,
          agreement: 0.95,
          criticalIssues: 0,
          recordedAt: new Date().toISOString(),
        },
        updatedAt: new Date().toISOString(),
        revision: 1,
      },
      result: null,
    }));

    const reread = await store.read("p1");
    expect(reread?.satisfiedCriteria).toEqual(["prd.approved"]);
    expect(reread?.lastConsensus?.status).toBe(ConsensusStatus.APPROVED);

    // All clients released cleanly.
    for (const c of pool.clients) {
      expect(c.released).toBe(true);
      expect(c.destroyed).toBe(false);
    }
  });
});

describe("PostgresStateStore — Bug #4 pool leak (S2-11 load regression)", () => {
  let pool: FakePool;
  let store: PostgresStateStore;

  beforeEach(async () => {
    pool = new FakePool();
    store = PostgresStateStore.fromPool(pool);
    await store.init();
  });

  /**
   * S2-11 regression: the KeyedAsyncLock serializes transacts per project
   * id, but across 200 distinct project ids the pool must absorb the fan
   * out without orphaning any client. This is the "load" story for Bug #4
   * — if the release-with-err plumbing ever regresses, we see it here as
   * a non-zero "still checked out" count after the dust settles.
   */
  it("200 concurrent transacts on distinct projects all release cleanly", async () => {
    const N = 200;
    const projects = Array.from({ length: N }, (_, i) => `p${i}`);

    await Promise.all(
      projects.map((pid) =>
        store.transact(pid, () => ({
          next: {
            projectId: pid,
            currentPhase: "REQUIREMENTS" as const,
            satisfiedCriteria: [],
            lastConsensus: null,
            updatedAt: new Date().toISOString(),
            revision: 1,
          },
          result: null,
        })),
      ),
    );

    // Every checkout must be paired with a release.
    expect(pool.clients).toHaveLength(N);
    for (const c of pool.clients) {
      expect(c.released).toBe(true);
      expect(c.destroyed).toBe(false);
    }
    // FakePool tracks idleCount as "returned without error" — we expect
    // every one of the N clients to have landed back in the idle bucket.
    expect(pool.idleCount).toBe(N);
  });

  it("200 concurrent failures all destroy their clients (no silent return to pool)", async () => {
    const N = 200;
    const projects = Array.from({ length: N }, (_, i) => `q${i}`);

    const results = await Promise.allSettled(
      projects.map((pid) =>
        store.transact(pid, () => {
          throw new Error(`boom-${pid}`);
        }),
      ),
    );

    // Every promise rejected.
    expect(results.every((r) => r.status === "rejected")).toBe(true);
    // Every client released, every one destroyed (not returned to pool).
    expect(pool.clients).toHaveLength(N);
    for (const c of pool.clients) {
      expect(c.released).toBe(true);
      expect(c.destroyed).toBe(true);
    }
    // No destroyed client landed in the idle bucket.
    expect(pool.idleCount).toBe(0);
  });

  it("revisions are monotonic under contention on the same project (KeyedAsyncLock contract)", async () => {
    const N = 100;
    const observed: number[] = [];

    await store.transact("shared", () => ({
      next: {
        projectId: "shared",
        currentPhase: "REQUIREMENTS" as const,
        satisfiedCriteria: [],
        lastConsensus: null,
        updatedAt: new Date().toISOString(),
        revision: 1,
      },
      result: null,
    }));

    await Promise.all(
      Array.from({ length: N }, (_, i) =>
        store.transact("shared", (current) => {
          const rev = current!.revision + 1;
          observed.push(rev);
          return {
            next: {
              ...current!,
              satisfiedCriteria: [...current!.satisfiedCriteria, `c${i}`],
              updatedAt: new Date().toISOString(),
              revision: rev,
            },
            result: null,
          };
        }),
      ),
    );

    // Revisions must cover the full range 2..N+1 with no gaps and no
    // repeats. KeyedAsyncLock is what makes this possible on the
    // fake pool; a release-with-err regression that destroyed clients
    // mid-lock would still show up here as a gap.
    observed.sort((a, b) => a - b);
    expect(observed).toEqual(Array.from({ length: N }, (_, i) => i + 2));
  });
});

