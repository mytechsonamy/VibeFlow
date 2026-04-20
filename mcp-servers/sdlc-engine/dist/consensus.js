import { z } from "zod";
/**
 * Canonical consensus status values. All comparisons MUST use this enum —
 * never string literals (Bug #1 regressed when mixed-case strings like
 * "Approved" were compared against "APPROVED" in if/switch branches).
 */
export var ConsensusStatus;
(function (ConsensusStatus) {
    ConsensusStatus["APPROVED"] = "APPROVED";
    ConsensusStatus["NEEDS_REVISION"] = "NEEDS_REVISION";
    ConsensusStatus["REJECTED"] = "REJECTED";
    /**
     * Sprint 17-C: emitted by the aggregator when `consensus.maxIterations`
     * rounds complete without reaching `consensus.approvalThreshold`
     * agreement but the run is not a hard reject (no rejected-majority,
     * no ≥2 deduped critical findings). Advance accepts this status as
     * equivalent to APPROVED with an audit event.
     */
    ConsensusStatus["HUMAN_APPROVAL_REQUIRED"] = "HUMAN_APPROVAL_REQUIRED";
})(ConsensusStatus || (ConsensusStatus = {}));
const STATUS_ALIASES = new Map([
    ["approved", ConsensusStatus.APPROVED],
    ["approve", ConsensusStatus.APPROVED],
    ["needs_revision", ConsensusStatus.NEEDS_REVISION],
    ["needs-revision", ConsensusStatus.NEEDS_REVISION],
    ["needsrevision", ConsensusStatus.NEEDS_REVISION],
    ["revision", ConsensusStatus.NEEDS_REVISION],
    ["rejected", ConsensusStatus.REJECTED],
    ["reject", ConsensusStatus.REJECTED],
    ["human_approval_required", ConsensusStatus.HUMAN_APPROVAL_REQUIRED],
    ["human-approval-required", ConsensusStatus.HUMAN_APPROVAL_REQUIRED],
    ["humanapprovalrequired", ConsensusStatus.HUMAN_APPROVAL_REQUIRED],
    ["human_approval", ConsensusStatus.HUMAN_APPROVAL_REQUIRED],
]);
/**
 * Case-insensitive, alias-tolerant parser. Accepts any of:
 *   "APPROVED", "approved", "Approved", "approve"
 *   "NEEDS_REVISION", "needs-revision", "revision"
 *   "REJECTED", "rejected", "reject"
 */
export function parseConsensusStatus(raw) {
    if (typeof raw !== "string") {
        throw new Error(`Invalid consensus status: expected string, got ${typeof raw}`);
    }
    const normalized = raw.trim().toLowerCase();
    const status = STATUS_ALIASES.get(normalized);
    if (!status) {
        throw new Error(`Unknown consensus status: "${raw}" ` +
            `(expected one of APPROVED, NEEDS_REVISION, REJECTED)`);
    }
    return status;
}
/** Zod schema for MCP tool inputs — goes through parseConsensusStatus. */
export const ConsensusStatusSchema = z
    .string()
    .transform((value, ctx) => {
    try {
        return parseConsensusStatus(value);
    }
    catch (err) {
        ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: err.message,
        });
        return z.NEVER;
    }
});
/**
 * Derive a status from agreement ratio and critical issue count.
 * Thresholds per CLAUDE.md "Consensus Thresholds" section.
 */
export function statusFromScore(agreement, criticalIssues) {
    if (!Number.isFinite(agreement) || agreement < 0 || agreement > 1) {
        throw new Error(`agreement must be in [0, 1], got ${agreement}`);
    }
    if (!Number.isInteger(criticalIssues) || criticalIssues < 0) {
        throw new Error(`criticalIssues must be a non-negative integer`);
    }
    if (criticalIssues >= 2)
        return ConsensusStatus.REJECTED;
    if (agreement < 0.5)
        return ConsensusStatus.REJECTED;
    if (agreement >= 0.9 && criticalIssues === 0)
        return ConsensusStatus.APPROVED;
    return ConsensusStatus.NEEDS_REVISION;
}
/**
 * Phase-advance gate: Sprint 17-C accepts HUMAN_APPROVAL_REQUIRED as
 * a valid terminal status (operator has explicitly signed off via the
 * orchestrator's `humanOverrideNote` argument). The event log records
 * the override so load-sdlc-context can surface it on next
 * SessionStart.
 */
export function isConsensusAdvanceValid(status) {
    return (status === ConsensusStatus.APPROVED ||
        status === ConsensusStatus.HUMAN_APPROVAL_REQUIRED);
}
//# sourceMappingURL=consensus.js.map