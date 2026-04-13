import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { SqliteStateStore } from "../src/state/sqlite.js";
import { SdlcEngine, PhaseTransitionError } from "../src/engine.js";
import { PhaseRegistry } from "../src/phases.js";
import { ConsensusStatus } from "../src/consensus.js";

describe("SdlcEngine integration", () => {
  let tmpDir: string;
  let store: SqliteStateStore;
  let engine: SdlcEngine;

  beforeEach(async () => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sdlc-engine-int-"));
    store = new SqliteStateStore(path.join(tmpDir, "state.db"));
    await store.init();
    engine = new SdlcEngine(store, new PhaseRegistry());
  });

  afterEach(async () => {
    await store.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("initializes a new project at the first phase", async () => {
    const state = await engine.getOrInit("p1");
    expect(state.currentPhase).toBe("REQUIREMENTS");
    expect(state.revision).toBe(1);
    expect(state.satisfiedCriteria).toEqual([]);
  });

  // Bug #13 (S4-09): getOrInit on an existing project must NOT enter
  // the mutator transaction. The previous implementation called
  // store.transact and tried to return { next: current, result: current }
  // — which fails the mutator's `next.revision === current.revision + 1`
  // assertion. Result: sdlc_get_state crashed on every project that
  // had been written to before. The fast-path read fix returns the
  // existing row without touching the mutator.
  it("getOrInit on an existing project returns it without bumping the revision (Bug #13)", async () => {
    const initial = await engine.getOrInit("p1");
    expect(initial.revision).toBe(1);

    // Bump the revision via a real write so the row carries history.
    await engine.satisfyCriterion({
      projectId: "p1",
      criterion: "prd.approved",
    });

    // Calling getOrInit again must NOT throw and must NOT bump
    // the revision — it should return the row as-is.
    const reread = await engine.getOrInit("p1");
    expect(reread.revision).toBe(2);                  // unchanged from the satisfy
    expect(reread.currentPhase).toBe("REQUIREMENTS");
    expect(reread.satisfiedCriteria).toContain("prd.approved");

    // And a third call still doesn't bump.
    const thirdRead = await engine.getOrInit("p1");
    expect(thirdRead.revision).toBe(2);
  });

  it("full happy-path advance from REQUIREMENTS to DESIGN", async () => {
    await engine.getOrInit("p1");
    await engine.satisfyCriterion({ projectId: "p1", criterion: "prd.approved" });
    await engine.satisfyCriterion({
      projectId: "p1",
      criterion: "testability.score>=60",
    });
    await engine.recordConsensus({
      projectId: "p1",
      phase: "REQUIREMENTS",
      agreement: 0.95,
      criticalIssues: 0,
    });

    const { state, transition } = await engine.advancePhase({
      projectId: "p1",
      to: "DESIGN",
    });
    expect(transition.ok).toBe(true);
    expect(state.currentPhase).toBe("DESIGN");
    // New phase starts with a clean criterion slate.
    expect(state.satisfiedCriteria).toEqual([]);
  });

  it("rejects skipping REQUIREMENTS → ARCHITECTURE via advancePhase", async () => {
    await engine.getOrInit("p1");
    await engine.satisfyCriterion({ projectId: "p1", criterion: "prd.approved" });
    await engine.satisfyCriterion({
      projectId: "p1",
      criterion: "testability.score>=60",
    });
    await engine.recordConsensus({
      projectId: "p1",
      phase: "REQUIREMENTS",
      agreement: 0.95,
      criticalIssues: 0,
    });

    await expect(
      engine.advancePhase({ projectId: "p1", to: "ARCHITECTURE" }),
    ).rejects.toBeInstanceOf(PhaseTransitionError);
  });

  it("recordConsensus accepts lowercase status", async () => {
    await engine.getOrInit("p1");
    const state = await engine.recordConsensus({
      projectId: "p1",
      phase: "REQUIREMENTS",
      agreement: 0.92,
      criticalIssues: 0,
      status: "approved",
    });
    expect(state.lastConsensus?.status).toBe(ConsensusStatus.APPROVED);
  });

  it("persists consensus record round-trip through SQLite", async () => {
    await engine.getOrInit("p1");
    await engine.recordConsensus({
      projectId: "p1",
      phase: "REQUIREMENTS",
      agreement: 0.91,
      criticalIssues: 0,
    });
    const reread = await store.read("p1");
    expect(reread?.lastConsensus?.status).toBe(ConsensusStatus.APPROVED);
    expect(reread?.lastConsensus?.agreement).toBe(0.91);
  });
});
