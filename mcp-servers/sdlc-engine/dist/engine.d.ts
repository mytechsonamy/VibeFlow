import { PhaseId, PhaseRegistry } from "./phases.js";
import { PhaseTransitionValidator, TransitionResult } from "./validation.js";
import { ProjectState, StateStore } from "./state/store.js";
export interface AdvancePhaseInput {
    readonly projectId: string;
    readonly to: PhaseId;
    readonly force?: boolean;
    /**
     * Sprint 17-C: operator-supplied justification when advancing under
     * a HUMAN_APPROVAL_REQUIRED consensus. When set, the transition is
     * recorded as a `consensus.human_override_accepted` event alongside
     * the normal phase-advance event. load-sdlc-context.sh reads these
     * to surface a visible "advanced under human override" advisory on
     * subsequent SessionStart calls.
     */
    readonly humanOverrideNote?: string;
    /**
     * Sprint 26-B: when true, advance also enforces the TARGET phase's
     * entryCriteria (not just the source's exitCriteria). Sourced from
     * `gates.enforceEntryCriteria`; the tools layer injects it. Default
     * off ⇒ unchanged behaviour.
     */
    readonly enforceEntryCriteria?: boolean;
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
    /**
     * Sprint 48: open a new SDLC cycle. The engine models one linear pass, so a
     * completed cycle leaves `currentPhase` pinned at DEPLOYMENT — and the
     * Sprint-42 lifecycle then wants cycle N+1 to walk from REQUIREMENTS again.
     * This resets `currentPhase` to the first phase, clears criteria + consensus,
     * and increments `cycle`, so `phase-runner` no longer hits a phase-mismatch
     * (engine=DEPLOYMENT vs lifecycle=REQUIREMENTS). It is forward-safe: unlike a
     * backward `advancePhase`, it is an explicit, audited cycle boundary, not a
     * silent rewind within a cycle.
     */
    startCycle(input: {
        projectId: string;
        note?: string;
    }): Promise<ProjectState>;
    private seed;
}
export declare class PhaseTransitionError extends Error {
    readonly errors: readonly string[];
    readonly state: ProjectState;
    constructor(errors: readonly string[], state: ProjectState);
}
