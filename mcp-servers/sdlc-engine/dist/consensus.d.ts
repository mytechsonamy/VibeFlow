import { z } from "zod";
/**
 * Canonical consensus status values. All comparisons MUST use this enum —
 * never string literals (Bug #1 regressed when mixed-case strings like
 * "Approved" were compared against "APPROVED" in if/switch branches).
 */
export declare enum ConsensusStatus {
    APPROVED = "APPROVED",
    NEEDS_REVISION = "NEEDS_REVISION",
    REJECTED = "REJECTED",
    /**
     * Sprint 17-C: emitted by the aggregator when `consensus.maxIterations`
     * rounds complete without reaching `consensus.approvalThreshold`
     * agreement but the run is not a hard reject (no rejected-majority,
     * no ≥2 deduped critical findings). Advance accepts this status as
     * equivalent to APPROVED with an audit event.
     */
    HUMAN_APPROVAL_REQUIRED = "HUMAN_APPROVAL_REQUIRED"
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
/**
 * Phase-advance gate: Sprint 17-C accepts HUMAN_APPROVAL_REQUIRED as
 * a valid terminal status (operator has explicitly signed off via the
 * orchestrator's `humanOverrideNote` argument). The event log records
 * the override so load-sdlc-context can surface it on next
 * SessionStart.
 */
export declare function isConsensusAdvanceValid(status: ConsensusStatus | null | undefined): boolean;
