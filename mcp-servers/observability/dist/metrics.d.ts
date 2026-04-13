import { NormalizedRun, NormalizedTest } from "./parsers.js";
/**
 * Aggregate metrics over a single `NormalizedRun`.
 *
 * Everything here is a pure function of the input run — no file I/O,
 * no time sources, no globals. Tests exercise these helpers directly
 * by building synthetic runs.
 */
export interface RunMetrics {
    readonly framework: string;
    readonly totalTests: number;
    readonly passed: number;
    readonly failed: number;
    readonly skipped: number;
    readonly pending: number;
    readonly passRate: number;
    readonly totalDurationMs: number;
    readonly durationP50Ms: number | null;
    readonly durationP95Ms: number | null;
    readonly durationP99Ms: number | null;
    readonly slowestTests: readonly NormalizedTest[];
    readonly failingTests: readonly NormalizedTest[];
    readonly perFile: readonly FileRollup[];
}
export interface FileRollup {
    readonly file: string;
    readonly totalTests: number;
    readonly passed: number;
    readonly failed: number;
    readonly totalDurationMs: number;
}
export interface MetricsOptions {
    readonly slowestLimit?: number;
}
export declare function computeMetrics(run: NormalizedRun, opts?: MetricsOptions): RunMetrics;
/**
 * Percentile helper using linear interpolation between adjacent ranks.
 * Matches numpy.percentile(interpolation='linear') well enough for a
 * metrics dashboard; not cryptographic-grade.
 */
export declare function percentile(sortedAsc: readonly number[], p: number): number | null;
