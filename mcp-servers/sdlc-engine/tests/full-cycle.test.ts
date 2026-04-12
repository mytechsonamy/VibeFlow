import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { SqliteStateStore } from "../src/state/sqlite.js";
import { SdlcEngine, PhaseTransitionError } from "../src/engine.js";
import { PhaseRegistry, PhaseId } from "../src/phases.js";
import { ConsensusStatus } from "../src/consensus.js";

describe("SdlcEngine full phase cycle", () => {
  let tmpDir: string;
  let store: SqliteStateStore;
  let engine: SdlcEngine;
  const registry = new PhaseRegistry();

  beforeEach(async () => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sdlc-engine-cycle-"));
    store = new SqliteStateStore(path.join(tmpDir, "state.db"));
    await store.init();
    engine = new SdlcEngine(store, registry);
  });

  afterEach(async () => {
    await store.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  async function advanceWithGates(
    projectId: string,
    from: PhaseId,
    to: PhaseId,
  ) {
    const phase = registry.get(from);
    for (const c of phase.exitCriteria) {
      await engine.satisfyCriterion({ projectId, criterion: c });
    }
    await engine.recordConsensus({
      projectId,
      phase: from,
      agreement: 0.95,
      criticalIssues: 0,
    });
    return engine.advancePhase({ projectId, to });
  }

  it("walks REQUIREMENTS → DEPLOYMENT through every gate", async () => {
    await engine.getOrInit("p1");

    const steps: [PhaseId, PhaseId][] = [
      ["REQUIREMENTS", "DESIGN"],
      ["DESIGN", "ARCHITECTURE"],
      ["ARCHITECTURE", "PLANNING"],
      ["PLANNING", "DEVELOPMENT"],
      ["DEVELOPMENT", "TESTING"],
      ["TESTING", "DEPLOYMENT"],
    ];

    for (const [from, to] of steps) {
      const { state, transition } = await advanceWithGates("p1", from, to);
      expect(transition.ok).toBe(true);
      expect(state.currentPhase).toBe(to);
      // Each new phase resets the criterion slate.
      expect(state.satisfiedCriteria).toEqual([]);
    }

    const final = await store.read("p1");
    expect(final?.currentPhase).toBe("DEPLOYMENT");
    expect(registry.isFinal(final!.currentPhase)).toBe(true);

    // Revisions: 1 (init) + 6 steps × (2 criteria + 1 consensus + 1 advance) = 1 + 24 = 25.
    expect(final?.revision).toBe(25);
  });

  it("cannot advance past the final phase", async () => {
    // Force-walk to DEPLOYMENT quickly.
    await engine.getOrInit("p1");
    const order: PhaseId[] = [
      "DESIGN",
      "ARCHITECTURE",
      "PLANNING",
      "DEVELOPMENT",
      "TESTING",
      "DEPLOYMENT",
    ];
    for (const to of order) {
      await engine.advancePhase({ projectId: "p1", to, force: true });
    }

    // No legal target beyond DEPLOYMENT.
    await expect(
      engine.advancePhase({
        projectId: "p1",
        // biome-ignore lint/suspicious/noExplicitAny: intentional bad input
        to: "POST_LAUNCH" as any,
      }),
    ).rejects.toBeInstanceOf(PhaseTransitionError);
  });

  it("degraded consensus (NEEDS_REVISION) blocks the next advance", async () => {
    await engine.getOrInit("p1");
    await engine.satisfyCriterion({ projectId: "p1", criterion: "prd.approved" });
    await engine.satisfyCriterion({
      projectId: "p1",
      criterion: "testability.score>=60",
    });
    const after = await engine.recordConsensus({
      projectId: "p1",
      phase: "REQUIREMENTS",
      agreement: 0.7,
      criticalIssues: 0,
    });
    expect(after.lastConsensus?.status).toBe(ConsensusStatus.NEEDS_REVISION);

    await expect(
      engine.advancePhase({ projectId: "p1", to: "DESIGN" }),
    ).rejects.toThrowError(/consensus is NEEDS_REVISION/);

    // Force=true bypasses the consensus gate and completes the advance.
    const { state } = await engine.advancePhase({
      projectId: "p1",
      to: "DESIGN",
      force: true,
    });
    expect(state.currentPhase).toBe("DESIGN");
  });

  it("recovers the same state after closing and reopening the store", async () => {
    await engine.getOrInit("p1");
    await advanceWithGates("p1", "REQUIREMENTS", "DESIGN");
    await store.close();

    const store2 = new SqliteStateStore(
      path.join(tmpDir, "state.db"),
    );
    await store2.init();
    const engine2 = new SdlcEngine(store2, registry);
    const reread = await engine2.read("p1");
    expect(reread?.currentPhase).toBe("DESIGN");
    expect(reread?.lastConsensus?.status).toBe(ConsensusStatus.APPROVED);
    await store2.close();
    // Reopen original handle for afterEach.
    store = new SqliteStateStore(path.join(tmpDir, "state.db"));
    await store.init();
  });

  it("satisfying the same criterion twice is idempotent (no duplicate entries)", async () => {
    await engine.getOrInit("p1");
    await engine.satisfyCriterion({ projectId: "p1", criterion: "prd.approved" });
    const after = await engine.satisfyCriterion({
      projectId: "p1",
      criterion: "prd.approved",
    });
    expect(after.satisfiedCriteria.filter((c) => c === "prd.approved").length).toBe(
      1,
    );
  });
});
