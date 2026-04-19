import { describe, expect, it } from "vitest";
import {
  KeyedAsyncLock,
  assertRevisionIncrement,
  ProjectState,
} from "../src/state/store.js";

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
