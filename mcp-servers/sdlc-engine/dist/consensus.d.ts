import { z } from "zod";
/**
 * Canonical consensus status values. All comparisons MUST use this enum —
 * never string literals (Bug #1 regressed when mixed-case strings like
 * "Approved" were compared against "APPROVED" in if/switch branches).
 */
export declare enum ConsensusStatus {
    APPROVED = "APPROVED",
    NEEDS_REVISION = "NEEDS_REVISION",
    REJECTED = "REJECTED"
}
/**
 * Case-insensitive, alias-tolerant parser. Accepts any of:
 *   "APPROVED", "approved", "Approved", "approve"
 *   "NEEDS_REVISION", "needs-revision", "revision"
 *   "REJECTED", "rejected", "reject"
 */
export declare function parseConsensusStatus(raw: unknown): ConsensusStatus;
/** Zod schema for MCP tool inputs — goes through parseConsensusStatus. */
export declare const ConsensusStatusSchema: z.ZodEffects<z.ZodString, ConsensusStatus, string>;
/**
 * Derive a status from agreement ratio and critical issue count.
 * Thresholds per CLAUDE.md "Consensus Thresholds" section.
 */
export declare function statusFromScore(agreement: number, criticalIssues: number): ConsensusStatus;
