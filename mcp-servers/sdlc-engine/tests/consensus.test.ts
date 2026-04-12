import { describe, expect, it } from "vitest";
import {
  ConsensusStatus,
  parseConsensusStatus,
  ConsensusStatusSchema,
  statusFromScore,
} from "../src/consensus.js";

describe("Bug #1 — consensus status parsing is case-insensitive", () => {
  it.each([
    ["APPROVED", ConsensusStatus.APPROVED],
    ["approved", ConsensusStatus.APPROVED],
    ["Approved", ConsensusStatus.APPROVED],
    ["  approved  ", ConsensusStatus.APPROVED],
    ["approve", ConsensusStatus.APPROVED],
    ["NEEDS_REVISION", ConsensusStatus.NEEDS_REVISION],
    ["needs-revision", ConsensusStatus.NEEDS_REVISION],
    ["Needs_Revision", ConsensusStatus.NEEDS_REVISION],
    ["revision", ConsensusStatus.NEEDS_REVISION],
    ["REJECTED", ConsensusStatus.REJECTED],
    ["rejected", ConsensusStatus.REJECTED],
    ["Reject", ConsensusStatus.REJECTED],
  ])("parses %s → %s", (input, expected) => {
    expect(parseConsensusStatus(input)).toBe(expected);
  });

  it("rejects unknown strings", () => {
    expect(() => parseConsensusStatus("maybe")).toThrow(/Unknown consensus/);
  });

  it("rejects non-string input", () => {
    expect(() => parseConsensusStatus(42)).toThrow(/expected string/);
    expect(() => parseConsensusStatus(null)).toThrow(/expected string/);
  });

  it("always returns the canonical enum value, never a raw string", () => {
    const parsed = parseConsensusStatus("approved");
    // Enum comparison must work — catches string-literal regression.
    expect(parsed === ConsensusStatus.APPROVED).toBe(true);
    // Typeof is still 'string' (TS enum values are strings), so the
    // safety is that we flow everything through the enum type, not
    // through raw input. This assertion fails if someone bypasses
    // the parser.
    expect(Object.values(ConsensusStatus)).toContain(parsed);
  });

  it("zod schema accepts lowercase input", () => {
    const result = ConsensusStatusSchema.parse("approved");
    expect(result).toBe(ConsensusStatus.APPROVED);
  });

  it("zod schema rejects unknown input with a clear error", () => {
    const result = ConsensusStatusSchema.safeParse("maybe");
    expect(result.success).toBe(false);
  });
});

describe("statusFromScore", () => {
  it("returns APPROVED for high agreement and no critical issues", () => {
    expect(statusFromScore(0.95, 0)).toBe(ConsensusStatus.APPROVED);
    expect(statusFromScore(0.9, 0)).toBe(ConsensusStatus.APPROVED);
  });

  it("returns REJECTED when 2+ critical issues regardless of agreement", () => {
    expect(statusFromScore(1.0, 2)).toBe(ConsensusStatus.REJECTED);
    expect(statusFromScore(0.95, 3)).toBe(ConsensusStatus.REJECTED);
  });

  it("returns REJECTED when agreement below 0.5", () => {
    expect(statusFromScore(0.4, 0)).toBe(ConsensusStatus.REJECTED);
  });

  it("returns NEEDS_REVISION in the middle band", () => {
    expect(statusFromScore(0.7, 0)).toBe(ConsensusStatus.NEEDS_REVISION);
    expect(statusFromScore(0.85, 1)).toBe(ConsensusStatus.NEEDS_REVISION);
  });

  it("rejects invalid inputs", () => {
    expect(() => statusFromScore(1.5, 0)).toThrow();
    expect(() => statusFromScore(0.5, -1)).toThrow();
    expect(() => statusFromScore(0.5, 1.5)).toThrow();
  });
});
