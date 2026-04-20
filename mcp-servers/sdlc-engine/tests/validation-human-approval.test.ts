import { describe, expect, it } from "vitest";
import { PhaseRegistry } from "../src/phases.js";
import { PhaseTransitionValidator } from "../src/validation.js";
import {
  ConsensusStatus,
  isConsensusAdvanceValid,
  parseConsensusStatus,
} from "../src/consensus.js";

// Sprint 17-C: HUMAN_APPROVAL_REQUIRED is emitted by the aggregator when
// `consensus.maxIterations` rounds complete without reaching
// `consensus.approvalThreshold` agreement, and the run is not a hard
// reject. The phase-gate accepts this status as valid (pass-with-audit
// mode) — the operator's explicit override (supplied to advance via
// humanOverrideNote) is sufficient to proceed.

describe("ConsensusStatus — HUMAN_APPROVAL_REQUIRED", () => {
  it("exposes HUMAN_APPROVAL_REQUIRED as an enum value", () => {
    expect(ConsensusStatus.HUMAN_APPROVAL_REQUIRED).toBe(
      "HUMAN_APPROVAL_REQUIRED",
    );
  });

  it("parseConsensusStatus accepts case-insensitive + kebab/underscore aliases", () => {
    expect(parseConsensusStatus("HUMAN_APPROVAL_REQUIRED")).toBe(
      ConsensusStatus.HUMAN_APPROVAL_REQUIRED,
    );
    expect(parseConsensusStatus("human_approval_required")).toBe(
      ConsensusStatus.HUMAN_APPROVAL_REQUIRED,
    );
    expect(parseConsensusStatus("human-approval-required")).toBe(
      ConsensusStatus.HUMAN_APPROVAL_REQUIRED,
    );
    expect(parseConsensusStatus("human_approval")).toBe(
      ConsensusStatus.HUMAN_APPROVAL_REQUIRED,
    );
  });

  it("isConsensusAdvanceValid accepts APPROVED and HUMAN_APPROVAL_REQUIRED", () => {
    expect(isConsensusAdvanceValid(ConsensusStatus.APPROVED)).toBe(true);
    expect(isConsensusAdvanceValid(ConsensusStatus.HUMAN_APPROVAL_REQUIRED)).toBe(
      true,
    );
  });

  it("isConsensusAdvanceValid rejects NEEDS_REVISION / REJECTED / null", () => {
    expect(isConsensusAdvanceValid(ConsensusStatus.NEEDS_REVISION)).toBe(false);
    expect(isConsensusAdvanceValid(ConsensusStatus.REJECTED)).toBe(false);
    expect(isConsensusAdvanceValid(null)).toBe(false);
    expect(isConsensusAdvanceValid(undefined)).toBe(false);
  });
});

describe("PhaseTransitionValidator — HUMAN_APPROVAL_REQUIRED pass-through", () => {
  const validator = new PhaseTransitionValidator(new PhaseRegistry());
  const requirementsSatisfied = [
    "prd.approved",
    "testability.score>=60",
  ] as const;

  it("allows REQUIREMENTS→DESIGN when lastConsensus is HUMAN_APPROVAL_REQUIRED for the same phase", () => {
    const result = validator.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: [...requirementsSatisfied],
      lastConsensus: ConsensusStatus.HUMAN_APPROVAL_REQUIRED,
      lastConsensusPhase: "REQUIREMENTS",
    });
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it("still blocks when HUMAN_APPROVAL_REQUIRED is from the wrong phase", () => {
    // Scope check still applies: the override was recorded during
    // ARCHITECTURE consensus, but we're advancing REQUIREMENTS. Stale
    // override shouldn't carry forward.
    const result = validator.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: [...requirementsSatisfied],
      lastConsensus: ConsensusStatus.HUMAN_APPROVAL_REQUIRED,
      lastConsensusPhase: "ARCHITECTURE",
    });
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) =>
      e.includes("consensus.requirements.approved"),
    )).toBe(true);
  });

  it("still blocks NEEDS_REVISION even when phase matches", () => {
    const result = validator.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: [...requirementsSatisfied],
      lastConsensus: ConsensusStatus.NEEDS_REVISION,
      lastConsensusPhase: "REQUIREMENTS",
    });
    expect(result.ok).toBe(false);
  });
});
