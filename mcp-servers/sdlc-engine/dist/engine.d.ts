import { PhaseId, PhaseRegistry } from "./phases.js";
import { PhaseTransitionValidator, TransitionResult } from "./validation.js";
import { ProjectState, StateStore } from "./state/store.js";
export interface AdvancePhaseInput {
    readonly projectId: string;
    readonly to: PhaseId;
    readonly force?: boolean;
}
export interface RecordConsensusInput {
    readonly projectId: string;
    readonly phase: PhaseId;
    readonly status?: string;
    readonly agreement: number;
    readonly criticalIssues: number;
}
export interface SatisfyCriterionInput {
    readonly projectId: string;
    readonly criterion: string;
}
export declare class SdlcEngine {
    private readonly store;
    private readonly registry;
    private readonly validator;
    constructor(store: StateStore, registry: PhaseRegistry, validator?: PhaseTransitionValidator);
    getOrInit(projectId: string): Promise<ProjectState>;
    read(projectId: string): Promise<ProjectState | null>;
    listPhases(): readonly import("./phases.js").PhaseDefinition[];
    satisfyCriterion(input: SatisfyCriterionInput): Promise<ProjectState>;
    recordConsensus(input: RecordConsensusInput): Promise<ProjectState>;
    advancePhase(input: AdvancePhaseInput): Promise<{
        state: ProjectState;
        transition: TransitionResult;
    }>;
    private seed;
}
export declare class PhaseTransitionError extends Error {
    readonly errors: readonly string[];
    readonly state: ProjectState;
    constructor(errors: readonly string[], state: ProjectState);
}
