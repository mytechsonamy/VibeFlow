import { NormalizedRun } from "./parsers.js";
import { TrendReport } from "./trends.js";
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
export declare function buildHealthDashboard(inputs: DashboardInputs): HealthDashboard;
