import { NormalizedRun } from "./parsers.js";
import { computeMetrics, RunMetrics } from "./metrics.js";
import { analyzeHistory, FlakinessReport } from "./flakiness.js";
import { analyzeTrend, TrendReport } from "./trends.js";

/**
 * Health-dashboard summary builder.
 *
 * Consumed by `/vibeflow:status` and by `release-decision-engine` to
 * get a one-shot health snapshot without every consumer re-running
 * metrics + flakiness + trends themselves.
 */

export type HealthGrade = "green" | "yellow" | "red";

export interface HealthDashboard {
  readonly grade: HealthGrade;
  readonly passRate: number;
  readonly failingCount: number;
  readonly flakyCount: number;
  readonly regressingCount: number;
  readonly trendDirection: TrendReport["overall"]["direction"];
  readonly latestRunDurationMs: number | null;
  readonly baselineAvgDurationMs: number | null;
  readonly totalRuns: number;
  readonly generatedAt: string;
  readonly notes: readonly string[];
}

export interface DashboardInputs {
  readonly runs: readonly NormalizedRun[];
}

export function buildHealthDashboard(inputs: DashboardInputs): HealthDashboard {
  const runs = inputs.runs;
  const notes: string[] = [];
  if (runs.length === 0) {
    return {
      grade: "red",
      passRate: 0,
      failingCount: 0,
      flakyCount: 0,
      regressingCount: 0,
      trendDirection: "insufficient-data",
      latestRunDurationMs: null,
      baselineAvgDurationMs: null,
      totalRuns: 0,
      generatedAt: new Date().toISOString(),
      notes: ["no runs available — dashboard unavailable"],
    };
  }

  const latest = runs[runs.length - 1]!;
  const metrics: RunMetrics = computeMetrics(latest);
  const flakiness: FlakinessReport = analyzeHistory(runs);
  const trend: TrendReport = analyzeTrend(runs);

  if (metrics.failed > 0) {
    notes.push(`${metrics.failed} tests failed in the latest run`);
  }
  if (flakiness.flaky.length > 0) {
    notes.push(`${flakiness.flaky.length} flaky tests in the history window`);
  }
  if (flakiness.regressing.length > 0) {
    notes.push(
      `${flakiness.regressing.length} regressing tests (failing consistently in the latest window)`,
    );
  }
  if (trend.overall.regression) {
    notes.push(
      `performance regression: latest run is ${trend.overall.latestDeltaRatio?.toFixed(2)}× the baseline`,
    );
  }

  // Grade resolution:
  //   - red: any regressing test OR any failing test OR pass rate < 0.95
  //   - yellow: any flaky test OR pass rate < 0.99 OR trend slowdown
  //   - green: everything else
  let grade: HealthGrade = "green";
  if (
    flakiness.regressing.length > 0 ||
    metrics.failed > 0 ||
    metrics.passRate < 0.95
  ) {
    grade = "red";
  } else if (
    flakiness.flaky.length > 0 ||
    metrics.passRate < 0.99 ||
    trend.overall.regression
  ) {
    grade = "yellow";
  }

  return {
    grade,
    passRate: metrics.passRate,
    failingCount: metrics.failed,
    flakyCount: flakiness.flaky.length,
    regressingCount: flakiness.regressing.length,
    trendDirection: trend.overall.direction,
    latestRunDurationMs: trend.overall.latestDurationMs,
    baselineAvgDurationMs: trend.overall.baselineAvgDurationMs,
    totalRuns: runs.length,
    generatedAt: new Date().toISOString(),
    notes,
  };
}
