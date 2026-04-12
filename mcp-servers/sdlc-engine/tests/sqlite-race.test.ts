import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { SqliteStateStore } from "../src/state/sqlite.js";
import { SdlcEngine } from "../src/engine.js";
import { PhaseRegistry } from "../src/phases.js";

describe("Bug #6 — state persistence race condition", () => {
  let tmpDir: string;
  let dbPath: string;
  let store: SqliteStateStore;

  beforeEach(async () => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sdlc-engine-test-"));
    dbPath = path.join(tmpDir, "state.db");
    store = new SqliteStateStore(dbPath);
    await store.init();
  });

  afterEach(async () => {
    await store.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("serializes concurrent writes and increments revision monotonically", async () => {
    const engine = new SdlcEngine(store, new PhaseRegistry());
    await engine.getOrInit("project-1");

    // Fire 50 concurrent satisfy-criterion calls against the same project.
    // Without locking, optimistic revision checks would collide and some
    // writes would be lost.
    const criteria = Array.from({ length: 50 }, (_, i) => `c${i}`);
    await Promise.all(
      criteria.map((c) =>
        engine.satisfyCriterion({ projectId: "project-1", criterion: c }),
      ),
    );

    const final = await store.read("project-1");
    expect(final).not.toBeNull();
    // 1 initial + 50 writes = revision 51
    expect(final!.revision).toBe(51);
    // Every criterion must be persisted (no lost writes).
    const saved = new Set(final!.satisfiedCriteria);
    for (const c of criteria) {
      expect(saved.has(c)).toBe(true);
    }
  });

  it("never produces skipped revision numbers under contention", async () => {
    const engine = new SdlcEngine(store, new PhaseRegistry());
    await engine.getOrInit("project-2");

    const observed: number[] = [];
    const ops = Array.from({ length: 20 }, (_, i) =>
      engine
        .satisfyCriterion({ projectId: "project-2", criterion: `c${i}` })
        .then((s) => observed.push(s.revision)),
    );
    await Promise.all(ops);

    observed.sort((a, b) => a - b);
    // Revisions should be strictly increasing: 2..21 after the initial 1.
    expect(observed).toEqual(Array.from({ length: 20 }, (_, i) => i + 2));
  });

  it("transact() rolls back on mutator error and leaves revision unchanged", async () => {
    const engine = new SdlcEngine(store, new PhaseRegistry());
    const initial = await engine.getOrInit("project-3");
    expect(initial.revision).toBe(1);

    await expect(
      store.transact("project-3", () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow(/boom/);

    const after = await store.read("project-3");
    expect(after!.revision).toBe(1);
  });
});
