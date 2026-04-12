import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  KeyedAsyncLock,
  assertRevisionIncrement,
  ProjectState,
} from "../src/state/store.js";
import { SqliteStateStore } from "../src/state/sqlite.js";
import { ConsensusStatus } from "../src/consensus.js";

describe("KeyedAsyncLock", () => {
  it("serializes concurrent calls under the same key", async () => {
    const lock = new KeyedAsyncLock();
    const log: string[] = [];
    const task = (label: string, ms: number) =>
      lock.acquire("k", async () => {
        log.push(`${label}:start`);
        await new Promise((r) => setTimeout(r, ms));
        log.push(`${label}:end`);
        return label;
      });

    const results = await Promise.all([task("a", 10), task("b", 1), task("c", 1)]);
    expect(results).toEqual(["a", "b", "c"]);
    // No overlap: every start is followed by its own end before the next start.
    expect(log).toEqual([
      "a:start",
      "a:end",
      "b:start",
      "b:end",
      "c:start",
      "c:end",
    ]);
  });

  it("does not serialize across different keys", async () => {
    const lock = new KeyedAsyncLock();
    let aStarted = false;
    let bStarted = false;

    const a = lock.acquire("a", async () => {
      aStarted = true;
      // Wait until b has also started — only possible if b is NOT blocked on a.
      await new Promise<void>((resolve) => {
        const check = () => (bStarted ? resolve() : setTimeout(check, 1));
        check();
      });
      return "a";
    });
    const b = lock.acquire("b", async () => {
      bStarted = true;
      return "b";
    });
    const [ra, rb] = await Promise.all([a, b]);
    expect(ra).toBe("a");
    expect(rb).toBe("b");
    expect(aStarted && bStarted).toBe(true);
  });

  it("releases the lock if the callback throws", async () => {
    const lock = new KeyedAsyncLock();
    await expect(
      lock.acquire("k", async () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow(/boom/);
    // Next acquire should proceed, not deadlock.
    const ok = await lock.acquire("k", async () => 42);
    expect(ok).toBe(42);
  });
});

describe("assertRevisionIncrement", () => {
  const base: ProjectState = {
    projectId: "p1",
    currentPhase: "REQUIREMENTS",
    satisfiedCriteria: [],
    lastConsensus: null,
    updatedAt: new Date(0).toISOString(),
    revision: 3,
  };

  it("accepts revision exactly one above current", () => {
    expect(() =>
      assertRevisionIncrement(base, { ...base, revision: 4 }, "p1"),
    ).not.toThrow();
  });

  it("rejects non-incrementing revisions", () => {
    expect(() =>
      assertRevisionIncrement(base, { ...base, revision: 3 }, "p1"),
    ).toThrow(/increment by exactly 1/);
    expect(() =>
      assertRevisionIncrement(base, { ...base, revision: 5 }, "p1"),
    ).toThrow(/increment by exactly 1/);
  });

  it("treats null current as revision 0 (next must be 1)", () => {
    expect(() =>
      assertRevisionIncrement(null, { ...base, revision: 1 }, "p1"),
    ).not.toThrow();
    expect(() =>
      assertRevisionIncrement(null, { ...base, revision: 2 }, "p1"),
    ).toThrow();
  });

  it("rejects projectId mutation", () => {
    expect(() =>
      assertRevisionIncrement(
        base,
        { ...base, projectId: "other", revision: 4 },
        "p1",
      ),
    ).toThrow(/cannot change projectId/);
  });
});

describe("SqliteStateStore edge cases", () => {
  let tmpDir: string;
  let dbPath: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sdlc-engine-store-"));
    dbPath = path.join(tmpDir, "state.db");
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("init() is idempotent (safe to call twice)", async () => {
    const store = new SqliteStateStore(dbPath);
    await store.init();
    await store.init();
    expect(await store.read("missing")).toBeNull();
    await store.close();
  });

  it("read() returns null for unknown project", async () => {
    const store = new SqliteStateStore(dbPath);
    await store.init();
    expect(await store.read("nope")).toBeNull();
    await store.close();
  });

  it("transact() creates new row, then updates it, persisting revision + consensus", async () => {
    const store = new SqliteStateStore(dbPath);
    await store.init();

    await store.transact("p1", (current) => {
      expect(current).toBeNull();
      const next: ProjectState = {
        projectId: "p1",
        currentPhase: "REQUIREMENTS",
        satisfiedCriteria: ["a"],
        lastConsensus: {
          phase: "REQUIREMENTS",
          status: ConsensusStatus.APPROVED,
          agreement: 0.92,
          criticalIssues: 0,
          recordedAt: new Date().toISOString(),
        },
        updatedAt: new Date().toISOString(),
        revision: 1,
      };
      return { next, result: null };
    });

    await store.transact("p1", (current) => {
      expect(current).not.toBeNull();
      const next: ProjectState = {
        ...current!,
        satisfiedCriteria: [...current!.satisfiedCriteria, "b"],
        updatedAt: new Date().toISOString(),
        revision: current!.revision + 1,
      };
      return { next, result: null };
    });

    const final = await store.read("p1");
    expect(final?.revision).toBe(2);
    expect(final?.satisfiedCriteria).toEqual(["a", "b"]);
    expect(final?.lastConsensus?.status).toBe(ConsensusStatus.APPROVED);
    expect(final?.lastConsensus?.agreement).toBe(0.92);
    await store.close();
  });

  it("transact() rejects a mutator that returns the wrong revision", async () => {
    const store = new SqliteStateStore(dbPath);
    await store.init();
    await expect(
      store.transact("p1", () => {
        const bad: ProjectState = {
          projectId: "p1",
          currentPhase: "REQUIREMENTS",
          satisfiedCriteria: [],
          lastConsensus: null,
          updatedAt: new Date().toISOString(),
          revision: 99,
        };
        return { next: bad, result: null };
      }),
    ).rejects.toThrow(/increment by exactly 1/);
    await store.close();
  });

  it("data survives closing and reopening the store", async () => {
    const s1 = new SqliteStateStore(dbPath);
    await s1.init();
    await s1.transact("p1", (current) => {
      expect(current).toBeNull();
      const next: ProjectState = {
        projectId: "p1",
        currentPhase: "DESIGN",
        satisfiedCriteria: ["c1"],
        lastConsensus: null,
        updatedAt: new Date().toISOString(),
        revision: 1,
      };
      return { next, result: null };
    });
    await s1.close();

    const s2 = new SqliteStateStore(dbPath);
    await s2.init();
    const reread = await s2.read("p1");
    expect(reread?.currentPhase).toBe("DESIGN");
    expect(reread?.satisfiedCriteria).toEqual(["c1"]);
    await s2.close();
  });
});
