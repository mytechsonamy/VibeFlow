/**
 * Git-churn-based hotspot analysis: files that change often and accumulate
 * lots of edits are riskier to modify. We rank by `commits × total lines
 * changed` over a configurable window (default: last 180 days).
 *
 * Rationale: this is a proxy for "places where regressions happen" — a file
 * that has been touched 40 times in 6 months and gained 1200 lines is a
 * different risk profile than a file touched twice. Downstream skills
 * (test-strategy-planner, arch-guardrails) can use this list to prioritize.
 *
 * Pure-function version of the algorithm also lives in `rankHotspots` so
 * tests can exercise it without spawning git.
 */
export interface FileChurn {
    readonly path: string;
    readonly commits: number;
    readonly linesAdded: number;
    readonly linesDeleted: number;
    readonly score: number;
}
export interface HotspotOptions {
    readonly root: string;
    readonly sinceDays?: number;
    readonly limit?: number;
}
export interface HotspotResult {
    readonly root: string;
    readonly sinceDays: number;
    readonly files: readonly FileChurn[];
}
export declare function findHotspots(opts: HotspotOptions): HotspotResult;
export declare function isGitRepo(root: string): boolean;
/**
 * Parse `git log --numstat --format=` output. Each line is
 * `<added>\t<deleted>\t<path>`. Binary files show `-\t-\t<path>` and are
 * aggregated but contribute 0 line changes.
 */
export declare function parseNumstat(raw: string): Map<string, FileChurn>;
export declare function rankHotspots(churn: ReadonlyMap<string, FileChurn>, limit: number): FileChurn[];
/** Verify a directory truly contains a git repo (tests need this). */
export declare function hasGitDir(root: string): boolean;
