import { NormalizedRun, NormalizedTest } from "./parsers.js";

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

const DEFAULT_WINDOW_SIZE = 5;
const DEFAULT_REGRESSION_RATIO = 1.5;
const DEFAULT_MIN_OBSERVATIONS_PER_TEST = 3;
const DEFAULT_PER_TEST_LIMIT = 20;

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

export function analyzeTrend(
  runs: readonly NormalizedRun[],
  opts: TrendWindowConfig = {},
): TrendReport {
  const windowSize = opts.windowSize ?? DEFAULT_WINDOW_SIZE;
  const regressionRatio = opts.regressionRatio ?? DEFAULT_REGRESSION_RATIO;
  const minObs = opts.minObservationsPerTest ?? DEFAULT_MIN_OBSERVATIONS_PER_TEST;
  const perTestLimit = opts.perTestLimit ?? DEFAULT_PER_TEST_LIMIT;

  const overall = computeOverall(runs, windowSize, regressionRatio);
  const perTest = computePerTest(runs, minObs, regressionRatio, perTestLimit);

  return {
    overall,
    perTest,
    observedAt: new Date().toISOString(),
  };
}

function computeOverall(
  runs: readonly NormalizedRun[],
  windowSize: number,
  regressionRatio: number,
): OverallTrend {
  if (runs.length < 2) {
    return {
      runCount: runs.length,
      baselineAvgDurationMs: null,
      latestDurationMs: runs[runs.length - 1]?.totalDurationMs ?? null,
      latestDeltaRatio: null,
      regression: false,
      direction: "insufficient-data",
    };
  }

  const latest = runs[runs.length - 1]!;
  const prior = runs.slice(
    Math.max(0, runs.length - 1 - windowSize),
    runs.length - 1,
  );
  const baselineAvg =
    prior.length > 0
      ? prior.reduce((acc, r) => acc + r.totalDurationMs, 0) / prior.length
      : null;

  const latestDurationMs = latest.totalDurationMs;
  const latestDeltaRatio =
    baselineAvg !== null && baselineAvg > 0
      ? latestDurationMs / baselineAvg
      : null;

  let direction: OverallTrend["direction"] = "stable";
  if (latestDeltaRatio !== null) {
    if (latestDeltaRatio >= regressionRatio) direction = "slowdown";
    else if (latestDeltaRatio <= 1 / regressionRatio) direction = "speedup";
    else direction = "stable";
  } else {
    direction = "insufficient-data";
  }

  return {
    runCount: runs.length,
    baselineAvgDurationMs: baselineAvg,
    latestDurationMs,
    latestDeltaRatio,
    regression: direction === "slowdown",
    direction,
  };
}

function computePerTest(
  runs: readonly NormalizedRun[],
  minObservations: number,
  regressionRatio: number,
  limit: number,
): PerTestTrend[] {
  // Collect per-test observations in run order, preserving insertion.
  const byTest = new Map<string, NormalizedTest[]>();
  runs.forEach((run) => {
    for (const t of run.tests) {
      const list = byTest.get(t.id) ?? [];
      list.push(t);
      byTest.set(t.id, list);
    }
  });

  const out: PerTestTrend[] = [];
  for (const [id, observations] of byTest) {
    if (observations.length < minObservations) continue;

    const durations = observations
      .map((t) => t.durationMs)
      .filter((d): d is number => typeof d === "number");
    if (durations.length < minObservations) continue;

    const latestMs = durations[durations.length - 1] ?? null;
    const priorDurations = durations.slice(0, -1);
    if (priorDurations.length === 0 || latestMs === null) continue;

    const baselineAvg =
      priorDurations.reduce((acc, d) => acc + d, 0) / priorDurations.length;
    const deltaRatio = baselineAvg > 0 ? latestMs / baselineAvg : 1;
    const first = observations[0]!;
    out.push({
      id,
      file: first.file,
      name: first.name,
      observations: observations.length,
      baselineAvgMs: baselineAvg,
      latestMs,
      deltaRatio,
      regression: deltaRatio >= regressionRatio,
    });
  }

  // Worst regression first so the report surfaces the high-leverage items.
  out.sort((a, b) => b.deltaRatio - a.deltaRatio);
  return out.slice(0, limit);
}
