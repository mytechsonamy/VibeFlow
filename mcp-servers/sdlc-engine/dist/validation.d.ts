import { PhaseId, PhaseRegistry } from "./phases.js";
import { ConsensusStatus } from "./consensus.js";
export interface PhaseTransitionRequest {
    readonly from: PhaseId;
    readonly to: PhaseId;
    readonly satisfiedCriteria: readonly string[];
    readonly lastConsensus?: ConsensusStatus | null;
    /**
     * Sprint 15-C: if the source phase carries a `consensus.<phase>.approved`
     * exit criterion, the validator also checks that `lastConsensusPhase`
     * matches — stale consensus from an earlier phase no longer satisfies
     * the gate.
     */
    readonly lastConsensusPhase?: PhaseId | null;
    /** When true, bypass gate criteria — still enforces structural rules. */
    readonly force?: boolean;
    /**
     * Sprint 26-B: opt-in entry-gate. When true, the validator also
     * requires the TARGET phase's `entryCriteria` to be satisfied (in
     * addition to the source phase's `exitCriteria`). Default behaviour
     * (false/undefined) leaves entryCriteria informational, so consumers
     * mid-flight are never broken. Sourced from `gates.enforceEntryCriteria`.
     */
    readonly enforceEntryCriteria?: boolean;
}
export interface TransitionResult {
    readonly ok: boolean;
    readonly errors: readonly string[];
}
/**
 * Phase transition validation (Bug #5 fix).
 *
 * Previously the engine would advance phase state without checking:
 *   - whether the target was actually the next phase (allowed skips)
 *   - whether exit criteria for the source phase were met
 *   - whether the source phase had a passing consensus
 *
 * The validator enforces all three. Structural rules (unknown phase,
 * same-phase, backward jumps) are always enforced; gate rules can be
 * bypassed with `force: true` but structural rules cannot.
 */
export declare class PhaseTransitionValidator {
    private readonly registry;
    constructor(registry: PhaseRegistry);
    validate(req: PhaseTransitionRequest): TransitionResult;
}
