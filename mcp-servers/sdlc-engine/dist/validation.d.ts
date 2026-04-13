import { PhaseId, PhaseRegistry } from "./phases.js";
import { ConsensusStatus } from "./consensus.js";
export interface PhaseTransitionRequest {
    readonly from: PhaseId;
    readonly to: PhaseId;
    readonly satisfiedCriteria: readonly string[];
    readonly lastConsensus?: ConsensusStatus | null;
    /** When true, bypass gate criteria — still enforces structural rules. */
    readonly force?: boolean;
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
