import { CONSENSUS_CRITERION_PATTERN } from "./phases.js";
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
        // Sprint 15-C: walk exit criteria. Standard criteria are looked up
        // in the satisfied set as before. `consensus.<phase>.approved`
        // criteria additionally require that `lastConsensusPhase` matches
        // the phase slug AND `lastConsensus == APPROVED`. That keeps a
        // fresh REQUIREMENTS consensus from lingering into DESIGN advance.
        const missing = [];
        for (const criterion of current.exitCriteria) {
            const scopeMatch = CONSENSUS_CRITERION_PATTERN.exec(criterion);
            if (scopeMatch) {
                const expectedPhase = scopeMatch[1].toUpperCase();
                const lastPhaseOk = req.lastConsensusPhase !== undefined &&
                    req.lastConsensusPhase !== null &&
                    req.lastConsensusPhase === expectedPhase;
                // Sprint 17-C: HUMAN_APPROVAL_REQUIRED is accepted alongside
                // APPROVED (pass-with-audit mode). When the aggregator runs
                // out of negotiation rounds without ≥0.9 agreement but no
                // hard rejection, the operator's explicit override (via
                // advance's humanOverrideNote) is sufficient to proceed.
                // The event log records the override for audit surfacing on
                // next SessionStart.
                const lastVerdictOk = req.lastConsensus === ConsensusStatus.APPROVED ||
                    req.lastConsensus === ConsensusStatus.HUMAN_APPROVAL_REQUIRED;
                // Sprint 15-C back-compat: pre-v2.3.0 ARCHITECTURE projects
                // satisfied the old `consensus.approved` criterion directly.
                // Accept that as if they had the new scoped form. Drop in
                // v2.4.0 once the in-flight projects have turned over.
                const legacyArchitectureAlias = expectedPhase === "ARCHITECTURE" &&
                    satisfied.has("consensus.approved");
                if (!legacyArchitectureAlias && (!lastPhaseOk || !lastVerdictOk)) {
                    missing.push(criterion);
                }
            }
            else if (!satisfied.has(criterion)) {
                missing.push(criterion);
            }
        }
        if (missing.length > 0) {
            errors.push(`Exit criteria not met for ${req.from}: ${missing.join(", ")}`);
        }
        // Sprint 26-B: opt-in entry-gate. When enabled, the TARGET phase's
        // entryCriteria must also be satisfied — so e.g. DEPLOYMENT cannot be
        // entered without a recorded `release.decision.go`. Off by default
        // (entryCriteria stay informational), so existing advances are
        // unaffected.
        if (req.enforceEntryCriteria) {
            const target = this.registry.get(req.to);
            const missingEntry = target.entryCriteria.filter((c) => !satisfied.has(c));
            if (missingEntry.length > 0) {
                errors.push(`Entry criteria not met for ${req.to}: ${missingEntry.join(", ")}`);
            }
        }
        // Legacy global check — only fires when the from-phase does NOT
        // carry a phase-scoped consensus criterion (i.e. DEVELOPMENT,
        // which retains the old cross-phase APPROVED requirement). The
        // scope-aware branch above already handles phased fazes.
        const hasScopedConsensus = current.exitCriteria.some((c) => CONSENSUS_CRITERION_PATTERN.test(c));
        if (!hasScopedConsensus &&
            req.lastConsensus !== undefined &&
            req.lastConsensus !== null &&
            req.lastConsensus !== ConsensusStatus.APPROVED) {
            errors.push(`Cannot advance from ${req.from}: last consensus is ${req.lastConsensus}, expected ${ConsensusStatus.APPROVED}`);
        }
        return { ok: errors.length === 0, errors };
    }
}
//# sourceMappingURL=validation.js.map