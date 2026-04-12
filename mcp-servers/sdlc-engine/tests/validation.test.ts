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
    });
    expect(result.ok).toBe(false);
    expect(
      result.errors.some((e) => /testability\.score>=60/.test(e)),
    ).toBe(true);
  });

  it("blocks advance when last consensus is NEEDS_REVISION", () => {
    const v = mkValidator();
    const result = v.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: ["prd.approved", "testability.score>=60"],
      lastConsensus: ConsensusStatus.NEEDS_REVISION,
    });
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => /consensus is NEEDS_REVISION/.test(e))).toBe(
      true,
    );
  });

  it("blocks advance when last consensus is REJECTED", () => {
    const v = mkValidator();
    const result = v.validate({
      from: "REQUIREMENTS",
      to: "DESIGN",
      satisfiedCriteria: ["prd.approved", "testability.score>=60"],
      lastConsensus: ConsensusStatus.REJECTED,
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
