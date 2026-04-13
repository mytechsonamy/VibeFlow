import { NormalizedRun } from "./parsers.js";
/**
 * Cross-run flakiness detection.
 *
 * A test is "flaky" when it has both passed AND failed in the recent
 * history window AND the failures don't all cluster in the latest run
 * (pure regressions are failures, not flakes — they deserve their own
 * finding). The scoring function outputs 0..1 where:
 *
 *   0.0 = stable (all runs agree)
 *   1.0 = maximum flakiness (50/50 with failures interleaved)
 *
 * History is a directory of NormalizedRun JSON files; this module
 * reads them synchronously (tests and metrics runs are small enough
 * that async I/O adds no measurable benefit). File modification time
 * is the ordering key — the filename itself is never parsed.
 *
 * We also expose `analyzeHistory` as a pure function that takes an
 * array of `NormalizedRun` directly, so tests don't need to spill
 * synthetic JSON to disk.
 */
export interface FlakyFinding {
    readonly id: string;
    readonly file: string;
    readonly name: string;
    readonly totalObservations: number;
    readonly passes: number;
    readonly failures: number;
    readonly skipped: number;
    readonly score: number;
    readonly status: "stable" | "flaky" | "regressing";
    /** Indexes into the input run array (0 = oldest). Pass-after-fail signals flakiness. */
    readonly firstFailureAt: number;
    readonly lastFailureAt: number;
}
export interface FlakinessReport {
    readonly runCount: number;
    readonly observedAt: string;
    readonly flaky: readonly FlakyFinding[];
    readonly regressing: readonly FlakyFinding[];
    readonly stableCount: number;
}
export interface FlakinessOptions {
    /** Only tests with more observations than this are scored. */
    readonly minObservations?: number;
    /** Scores >= this are labeled "flaky". */
    readonly flakinessThreshold?: number;
}
export declare function analyzeHistory(runs: readonly NormalizedRun[], opts?: FlakinessOptions): FlakinessReport;
/**
 * Read a history directory of NormalizedRun JSON files and compute
 * flakiness. Files are sorted by `mtime` ascending so the oldest run
 * comes first. Anything that can't be parsed is skipped with a warning
 * written to stderr — never silently merged.
 */
export declare function analyzeHistoryDir(dir: string, opts?: FlakinessOptions): FlakinessReport;
export declare function loadHistoryDir(dir: string): NormalizedRun[];
