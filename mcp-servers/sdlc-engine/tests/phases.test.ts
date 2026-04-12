import { describe, expect, it } from "vitest";
import {
  DEFAULT_PHASE_ORDER,
  PhaseDefinition,
  PhaseRegistry,
} from "../src/phases.js";

describe("Bug #9 — phase order is data-driven", () => {
  it("iterates phases in the order they were registered", () => {
    const registry = new PhaseRegistry();
    const ids = registry.all().map((p) => p.id);
    expect(ids).toEqual([
      "REQUIREMENTS",
      "DESIGN",
      "ARCHITECTURE",
      "PLANNING",
      "DEVELOPMENT",
      "TESTING",
      "DEPLOYMENT",
    ]);
  });

  it("next() uses registry order, not hardcoded switch", () => {
    const registry = new PhaseRegistry();
    expect(registry.next("REQUIREMENTS")?.id).toBe("DESIGN");
    expect(registry.next("DEPLOYMENT")).toBeNull();
  });

  it("accepts a custom phase order at construction time", () => {
    const custom: PhaseDefinition[] = [
      {
        id: "REQUIREMENTS",
        label: "Req",
        entryCriteria: [],
        exitCriteria: ["r.done"],
      },
      {
        id: "TESTING",
        label: "Test",
        entryCriteria: [],
        exitCriteria: ["t.done"],
      },
      {
        id: "DEPLOYMENT",
        label: "Deploy",
        entryCriteria: [],
        exitCriteria: [],
      },
    ];
    const registry = new PhaseRegistry(custom);
    expect(registry.next("REQUIREMENTS")?.id).toBe("TESTING");
    expect(registry.next("TESTING")?.id).toBe("DEPLOYMENT");
    expect(registry.isFinal("DEPLOYMENT")).toBe(true);
  });

  it("rejects an empty phase list", () => {
    expect(() => new PhaseRegistry([])).toThrow();
  });

  it("rejects duplicate phase ids", () => {
    const dup: PhaseDefinition[] = [
      {
        id: "REQUIREMENTS",
        label: "A",
        entryCriteria: [],
        exitCriteria: [],
      },
      {
        id: "REQUIREMENTS",
        label: "B",
        entryCriteria: [],
        exitCriteria: [],
      },
    ];
    expect(() => new PhaseRegistry(dup)).toThrow(/Duplicate phase/);
  });

  it("DEFAULT_PHASE_ORDER is frozen (immutability sanity check)", () => {
    expect(Object.isFrozen(DEFAULT_PHASE_ORDER)).toBe(true);
  });
});
