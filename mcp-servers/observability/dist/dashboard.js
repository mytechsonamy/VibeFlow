import { computeMetrics } from "./metrics.js";
import { analyzeHistory } from "./flakiness.js";
import { analyzeTrend } from "./trends.js";
export function buildHealthDashboard(inputs) {
    const runs = inputs.runs;
    const notes = [];
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
    const latest = runs[runs.length - 1];
    const metrics = computeMetrics(latest);
    const flakiness = analyzeHistory(runs);
    const trend = analyzeTrend(runs);
    if (metrics.failed > 0) {
        notes.push(`${metrics.failed} tests failed in the latest run`);
    }
    if (flakiness.flaky.length > 0) {
        notes.push(`${flakiness.flaky.length} flaky tests in the history window`);
    }
    if (flakiness.regressing.length > 0) {
        notes.push(`${flakiness.regressing.length} regressing tests (failing consistently in the latest window)`);
    }
    if (trend.overall.regression) {
        notes.push(`performance regression: latest run is ${trend.overall.latestDeltaRatio?.toFixed(2)}× the baseline`);
    }
    // Grade resolution:
    //   - red: any regressing test OR any failing test OR pass rate < 0.95
    //   - yellow: any flaky test OR pass rate < 0.99 OR trend slowdown
    //   - green: everything else
    let grade = "green";
    if (flakiness.regressing.length > 0 ||
        metrics.failed > 0 ||
        metrics.passRate < 0.95) {
        grade = "red";
    }
    else if (flakiness.flaky.length > 0 ||
        metrics.passRate < 0.99 ||
        trend.overall.regression) {
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
//# sourceMappingURL=dashboard.js.map