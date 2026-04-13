import { ConsensusStatus } from "./consensus.js";
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
export class PhaseTransitionValidator {
    registry;
    constructor(registry) {
        this.registry = registry;
    }
    validate(req) {
        const errors = [];
        if (!this.registry.has(req.from)) {
            errors.push(`Unknown source phase: ${req.from}`);
        }
        if (!this.registry.has(req.to)) {
            errors.push(`Unknown target phase: ${req.to}`);
        }
        if (errors.length > 0) {
            return { ok: false, errors };
        }
        if (req.from === req.to) {
            errors.push(`Cannot transition to the same phase (${req.from})`);
            return { ok: false, errors };
        }
        const fromIdx = this.registry.indexOf(req.from);
        const toIdx = this.registry.indexOf(req.to);
        if (toIdx < fromIdx) {
            errors.push(`Backward transition not permitted: ${req.from}→${req.to}`);
        }
        if (toIdx !== fromIdx + 1) {
            errors.push(`Invalid transition ${req.from}→${req.to}: ` +
                `phases must advance exactly one step ` +
                `(expected ${this.registry.next(req.from)?.id ?? "<final>"})`);
        }
        if (errors.length > 0) {
            // Structural violations are non-bypassable.
            return { ok: false, errors };
        }
        if (req.force) {
            return { ok: true, errors };
        }
        const current = this.registry.get(req.from);
        const satisfied = new Set(req.satisfiedCriteria);
        const missing = current.exitCriteria.filter((c) => !satisfied.has(c));
        if (missing.length > 0) {
            errors.push(`Exit criteria not met for ${req.from}: ${missing.join(", ")}`);
        }
        if (req.lastConsensus !== undefined &&
            req.lastConsensus !== null &&
            req.lastConsensus !== ConsensusStatus.APPROVED) {
            errors.push(`Cannot advance from ${req.from}: last consensus is ${req.lastConsensus}, expected ${ConsensusStatus.APPROVED}`);
        }
        return { ok: errors.length === 0, errors };
    }
}
//# sourceMappingURL=validation.js.map