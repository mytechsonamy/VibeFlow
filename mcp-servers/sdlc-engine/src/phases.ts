import { z } from "zod";

export const PhaseIdSchema = z.enum([
  "REQUIREMENTS",
  "DESIGN",
  "ARCHITECTURE",
  "PLANNING",
  "DEVELOPMENT",
  "TESTING",
  "DEPLOYMENT",
]);
export type PhaseId = z.infer<typeof PhaseIdSchema>;

export interface PhaseDefinition {
  readonly id: PhaseId;
  readonly label: string;
  readonly entryCriteria: readonly string[];
  readonly exitCriteria: readonly string[];
}

export const DEFAULT_PHASE_ORDER: readonly PhaseDefinition[] = Object.freeze([
  {
    id: "REQUIREMENTS",
    label: "Requirements",
    entryCriteria: ["project.initialized"],
    exitCriteria: ["prd.approved", "testability.score>=60"],
  },
  {
    id: "DESIGN",
    label: "Design",
    entryCriteria: ["prd.approved"],
    exitCriteria: ["design.approved", "accessibility.verified"],
  },
  {
    id: "ARCHITECTURE",
    label: "Architecture",
    entryCriteria: ["design.approved"],
    exitCriteria: ["adr.recorded", "consensus.approved"],
  },
  {
    id: "PLANNING",
    label: "Planning",
    entryCriteria: ["adr.recorded"],
    exitCriteria: ["test-strategy.approved", "sprint.planned"],
  },
  {
    id: "DEVELOPMENT",
    label: "Development",
    entryCriteria: ["sprint.planned"],
    exitCriteria: ["code.reviewed", "quality.gates.passed"],
  },
  {
    id: "TESTING",
    label: "Testing",
    entryCriteria: ["code.reviewed"],
    exitCriteria: ["coverage.met", "mutation.score.acceptable"],
  },
  {
    id: "DEPLOYMENT",
    label: "Deployment",
    entryCriteria: ["release.decision.go"],
    exitCriteria: ["deployment.verified", "health.checks.passed"],
  },
]);

/**
 * Phase order is data-driven (Bug #9 fix): sequencing is derived from the
 * registry contents, never from hardcoded if/switch chains.
 */
export class PhaseRegistry {
  private readonly phases: readonly PhaseDefinition[];
  private readonly indexById: Map<PhaseId, number>;

  constructor(phases: readonly PhaseDefinition[] = DEFAULT_PHASE_ORDER) {
    if (phases.length === 0) {
      throw new Error("PhaseRegistry requires at least one phase");
    }
    const seen = new Set<PhaseId>();
    for (const p of phases) {
      if (seen.has(p.id)) {
        throw new Error(`Duplicate phase id in registry: ${p.id}`);
      }
      seen.add(p.id);
    }
    this.phases = phases;
    this.indexById = new Map(phases.map((p, i) => [p.id, i] as const));
  }

  all(): readonly PhaseDefinition[] {
    return this.phases;
  }

  has(id: PhaseId): boolean {
    return this.indexById.has(id);
  }

  get(id: PhaseId): PhaseDefinition {
    const idx = this.indexById.get(id);
    if (idx === undefined) {
      throw new Error(`Unknown phase: ${id}`);
    }
    return this.phases[idx]!;
  }

  indexOf(id: PhaseId): number {
    const idx = this.indexById.get(id);
    if (idx === undefined) {
      throw new Error(`Unknown phase: ${id}`);
    }
    return idx;
  }

  next(id: PhaseId): PhaseDefinition | null {
    const idx = this.indexOf(id);
    const nextIdx = idx + 1;
    return nextIdx < this.phases.length ? this.phases[nextIdx]! : null;
  }

  first(): PhaseDefinition {
    return this.phases[0]!;
  }

  last(): PhaseDefinition {
    return this.phases[this.phases.length - 1]!;
  }

  isFinal(id: PhaseId): boolean {
    return this.indexOf(id) === this.phases.length - 1;
  }
}
