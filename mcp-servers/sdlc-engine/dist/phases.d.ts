import { z } from "zod";
export declare const PhaseIdSchema: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
export type PhaseId = z.infer<typeof PhaseIdSchema>;
export interface PhaseDefinition {
    readonly id: PhaseId;
    readonly label: string;
    readonly entryCriteria: readonly string[];
    readonly exitCriteria: readonly string[];
}
export declare const DEFAULT_PHASE_ORDER: readonly PhaseDefinition[];
/**
 * Regex for the Sprint 15-C scope-aware consensus criterion. Matches
 * `consensus.<phase-slug>.approved`. `<phase-slug>` is lowercase
 * PhaseId, e.g. `consensus.requirements.approved`.
 */
export declare const CONSENSUS_CRITERION_PATTERN: RegExp;
/**
 * Phase order is data-driven (Bug #9 fix): sequencing is derived from the
 * registry contents, never from hardcoded if/switch chains.
 */
export declare class PhaseRegistry {
    private readonly phases;
    private readonly indexById;
    constructor(phases?: readonly PhaseDefinition[]);
    all(): readonly PhaseDefinition[];
    has(id: PhaseId): boolean;
    get(id: PhaseId): PhaseDefinition;
    indexOf(id: PhaseId): number;
    next(id: PhaseId): PhaseDefinition | null;
    first(): PhaseDefinition;
    last(): PhaseDefinition;
    isFinal(id: PhaseId): boolean;
}
