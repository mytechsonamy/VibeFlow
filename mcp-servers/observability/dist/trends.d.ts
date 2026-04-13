import { NormalizedRun } from "./parsers.js";
/**
 * Performance trend analysis over a sequence of runs.
 *
 * We compute a moving average of total duration and of per-test
 * duration, then flag delta spikes. The moving average is a simple
 * arithmetic mean over the previous N runs — not exponentially
 * weighted — because operators read the report as a raw history, and
 * the simple window is easier to explain.
 *
 * Pure function of the input runs; tests call `analyzeTrend` directly.
 */
export interface TrendWindowConfig {
    /** Window size for the moving average. Default 5. */
    readonly windowSize?: number;
    /**
     * Flag a regression when the latest value is this much slower than
     * the moving average baseline. Default 1.5 (i.e. 50% slower).
     */
    readonly regressionRatio?: number;
    /** Per-test trend only considers tests that appear in ≥ this many runs. */
    readonly minObservationsPerTest?: number;
    /** Cap on the number of per-test trend entries returned. Default 20. */
    readonly perTestLimit?: number;
}
export interface OverallTrend {
    readonly runCount: number;
    readonly baselineAvgDurationMs: number | null;
    readonly latestDurationMs: number | null;
    readonly latestDeltaRatio: number | null;
    readonly regression: boolean;
    readonly direction: "speedup" | "stable" | "slowdown" | "insufficient-data";
}
export interface PerTestTrend {
    readonly id: string;
    readonly file: string;
    readonly name: string;
    readonly observations: number;
    readonly baselineAvgMs: number;
    readonly latestMs: number | null;
    readonly deltaRatio: number;
    readonly regression: boolean;
}
export interface TrendReport {
    readonly overall: OverallTrend;
    readonly perTest: readonly PerTestTrend[];
    readonly observedAt: string;
}
export declare function analyzeTrend(runs: readonly NormalizedRun[], opts?: TrendWindowConfig): TrendReport;
