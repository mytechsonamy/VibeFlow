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
//# sourceMappingURL=consensus.js.map