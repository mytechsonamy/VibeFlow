import { describe, expect, it } from "vitest";
import { PhaseRegistry } from "../src/phases.js";
import { PhaseTransitionValidator } from "../src/validation.js";
import { ConsensusStatus } from "../src/consensus.js";

function mkValidator() {
  return new PhaseTransitionValidator(new PhaseRegistry());
}

describe("Bug #5 — phase transitions are validated", () => {
  it("allows sequential advance when exit criteria and consensus pass", () => {
    const v = mkValidator();
    const result = v.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: ["prd.approved", "testability.score>=60"],
      lastConsensus: ConsensusStatus.APPROVED,
      // Sprint 15-C: phase-scoped consensus criterion requires the
      // recorded consensus to name the matching phase.
      lastConsensusPhase: "REQUIREMENTS",
    });
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it("blocks skipping phases (REQUIREMENTS → ARCHITECTURE)", () => {
    const v = mkValidator();
    const result = v.validate({
      from: "REQUIREMENTS",
      to: "ARCHITECTURE",
      satisfiedCriteria: ["prd.approved", "testability.score>=60"],
      lastConsensus: ConsensusStatus.APPROVED,
      lastConsensusPhase: "REQUIREMENTS",
    });
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => /must advance exactly one step/.test(e))).toBe(
      true,
    );
  });

  it("blocks backward transitions even with force", () => {
    const v = mkValidator();
    const result = v.validate({
      from: "DESIGN",
      to: "REQUIREMENTS",
      satisfiedCriteria: [],
      force: true,
    });
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => /Backward/i.test(e))).toBe(true);
  });

  it("blocks same-phase transition", () => {
    const v = mkValidator();
    const result = v.validate({
      from: "DESIGN",
      to: "DESIGN",
      satisfiedCriteria: [],
    });
    expect(result.ok).toBe(false);
  });

  it("blocks advance when exit criteria are missing", () => {
    const v = mkValidator();
    const result = v.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: ["prd.approved"], // missing testability.score>=60
      lastConsensus: ConsensusStatus.APPROVED,
      lastConsensusPhase: "REQUIREMENTS",
    });
    expect(result.ok).toBe(false);
    expect(
      result.errors.some((e) => /testability\.score>=60/.test(e)),
    ).toBe(true);
  });

  it("blocks advance when last consensus is NEEDS_REVISION (scoped)", () => {
    // Sprint 15-C: REQUIREMENTS carries `consensus.requirements.approved`
    // as an exit criterion, so a NEEDS_REVISION verdict fails the
    // scoped check and the criterion is listed as missing.
    const v = mkValidator();
    const result = v.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: ["prd.approved", "testability.score>=60"],
      lastConsensus: ConsensusStatus.NEEDS_REVISION,
      lastConsensusPhase: "REQUIREMENTS",
    });
    expect(result.ok).toBe(false);
    expect(
      result.errors.some((e) => /consensus\.requirements\.approved/.test(e)),
    ).toBe(true);
  });

  it("blocks advance when last consensus is REJECTED", () => {
    const v = mkValidator();
    const result = v.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: ["prd.approved", "testability.score>=60"],
      lastConsensus: ConsensusStatus.REJECTED,
      lastConsensusPhase: "REQUIREMENTS",
    });
    expect(result.ok).toBe(false);
  });

  it("force=true bypasses gates but not structural rules", () => {
    const v = mkValidator();
    const ok = v.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: [],
      lastConsensus: ConsensusStatus.REJECTED,
      force: true,
    });
    expect(ok.ok).toBe(true);

    const structural = v.validate({
      from: "REQUIREMENTS",
      to: "ARCHITECTURE",
      satisfiedCriteria: [],
      force: true,
    });
    expect(structural.ok).toBe(false);
  });

  it("rejects unknown phases", () => {
    const v = mkValidator();
    const result = v.validate({
      from: "REQUIREMENTS",
      // biome-ignore lint/suspicious/noExplicitAny: intentional bad input
      to: "LAUNCH" as any,
      satisfiedCriteria: [],
    });
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => /Unknown target phase/.test(e))).toBe(true);
  });
});

describe("Sprint 26-B — opt-in entry-criteria enforcement", () => {
  // TESTING exit: coverage.met, mutation.score.acceptable,
  // consensus.testing.approved. DEPLOYMENT entry: release.decision.go.
  const testingExit = [
    "coverage.met",
    "mutation.score.acceptable",
  ];
  const advanceTestingToDeployment = (
    satisfied: string[],
    enforceEntryCriteria: boolean,
  ) =>
    mkValidator().validate({
      from: "TESTING",
      to: "DEPLOYMENT",
      satisfiedCriteria: satisfied,
      lastConsensus: ConsensusStatus.APPROVED,
      lastConsensusPhase: "TESTING",
      enforceEntryCriteria,
    });

  it("default (off) — advances with TESTING exit met even without release.decision.go", () => {
    const result = advanceTestingToDeployment(testingExit, false);
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it("on — blocks when the target entry criterion release.decision.go is unsatisfied", () => {
    const result = advanceTestingToDeployment(testingExit, true);
    expect(result.ok).toBe(false);
    expect(
      result.errors.some((e) =>
        /Entry criteria not met for DEPLOYMENT: release\.decision\.go/.test(e),
      ),
    ).toBe(true);
  });

  it("on — advances once release.decision.go is satisfied", () => {
    const result = advanceTestingToDeployment(
      [...testingExit, "release.decision.go"],
      true,
    );
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it("force bypasses the entry gate too", () => {
    const result = mkValidator().validate({
      from: "TESTING",
      to: "DEPLOYMENT",
      satisfiedCriteria: [],
      enforceEntryCriteria: true,
      force: true,
    });
    expect(result.ok).toBe(true);
  });
});
