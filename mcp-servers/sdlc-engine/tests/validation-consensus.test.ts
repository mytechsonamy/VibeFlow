import { describe, expect, it } from "vitest";
import { PhaseRegistry } from "../src/phases.js";
import { PhaseTransitionValidator } from "../src/validation.js";
import { ConsensusStatus } from "../src/consensus.js";

// Sprint 15-C: phase-scoped consensus check. Exit criteria of the
// form `consensus.<phase>.approved` require:
//   - req.lastConsensus === APPROVED
//   - req.lastConsensusPhase === <phase> (uppercased)
// OR (legacy alias, ARCHITECTURE only):
//   - satisfiedCriteria.includes("consensus.approved")
// `force: true` bypasses the whole gate.

describe("PhaseTransitionValidator — phase-scoped consensus", () => {
  const validator = new PhaseTransitionValidator(new PhaseRegistry());

  // REQUIREMENTS exit criteria:
  //   prd.approved, testability.score>=60, consensus.requirements.approved
  const requirementsSatisfied = [
    "prd.approved",
    "testability.score>=60",
  ] as const;

  it("blocks REQUIREMENTS→DESIGN when no consensus has been recorded", () => {
    const result = validator.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: [...requirementsSatisfied],
      lastConsensus: null,
      lastConsensusPhase: null,
    });
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) =>
      e.includes("consensus.requirements.approved"),
    )).toBe(true);
  });

  it("blocks REQUIREMENTS→DESIGN when the recorded consensus is for a different phase", () => {
    const result = validator.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: [...requirementsSatisfied],
      lastConsensus: ConsensusStatus.APPROVED,
      lastConsensusPhase: "ARCHITECTURE",
    });
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) =>
      e.includes("consensus.requirements.approved"),
    )).toBe(true);
  });

  it("allows REQUIREMENTS→DESIGN when a fresh in-phase APPROVED consensus is present", () => {
    const result = validator.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: [...requirementsSatisfied],
      lastConsensus: ConsensusStatus.APPROVED,
      lastConsensusPhase: "REQUIREMENTS",
    });
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it("leaves DEVELOPMENT→TESTING unchanged (no scoped consensus criterion)", () => {
    // DEVELOPMENT still gates on the legacy "any lastConsensus must be
    // APPROVED" rule because its exit criteria don't carry a scoped
    // consensus. Recording a NEEDS_REVISION consensus during DEV still
    // blocks advance — this pins Sprint 14 behaviour.
    const blocked = validator.validate({
      from: "DEVELOPMENT",
      to: "TESTING",
      satisfiedCriteria: ["code.reviewed", "quality.gates.passed"],
      lastConsensus: ConsensusStatus.NEEDS_REVISION,
      lastConsensusPhase: "DEVELOPMENT",
    });
    expect(blocked.ok).toBe(false);
    expect(blocked.errors.some((e) =>
      e.includes("last consensus is NEEDS_REVISION"),
    )).toBe(true);

    const passes = validator.validate({
      from: "DEVELOPMENT",
      to: "TESTING",
      satisfiedCriteria: ["code.reviewed", "quality.gates.passed"],
      lastConsensus: ConsensusStatus.APPROVED,
      lastConsensusPhase: "DEVELOPMENT",
    });
    expect(passes.ok).toBe(true);
  });

  it("force: true bypasses scoped consensus gate", () => {
    const result = validator.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: [...requirementsSatisfied],
      lastConsensus: null,
      lastConsensusPhase: null,
      force: true,
    });
    expect(result.ok).toBe(true);
  });

  it("legacy alias: ARCHITECTURE projects satisfied via old 'consensus.approved' still advance", () => {
    // Pre-v2.3.0 ARCHITECTURE projects carried 'consensus.approved' in
    // their satisfiedCriteria rather than a ConsensusRecord. The
    // validator accepts that as equivalent to the new
    // consensus.architecture.approved criterion until v2.4.0.
    const result = validator.validate({
      from: "ARCHITECTURE",
      to: "PLANNING",
      satisfiedCriteria: ["adr.recorded", "consensus.approved"],
      lastConsensus: null,
      lastConsensusPhase: null,
    });
    expect(result.ok).toBe(true);
  });
});
