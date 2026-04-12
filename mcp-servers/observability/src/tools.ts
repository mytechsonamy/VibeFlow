import * as fs from "node:fs";
import { z } from "zod";
import {
  parseReporter,
  NormalizedRun,
  ReporterParseError,
} from "./parsers.js";
import { computeMetrics } from "./metrics.js";
import {
  analyzeHistory,
  analyzeHistoryDir,
  loadHistoryDir,
} from "./flakiness.js";
import { analyzeTrend } from "./trends.js";
import { buildHealthDashboard } from "./dashboard.js";

export interface ToolDefinition {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  handler: (args: unknown) => Promise<unknown>;
}

const CollectMetricsInput = z
  .object({
    reporterPath: z.string().min(1).optional(),
    payload: z.unknown().optional(),
    slowestLimit: z.number().int().positive().max(100).optional(),
  })
  .refine((v) => v.reporterPath !== undefined || v.payload !== undefined, {
    message: "either reporterPath or payload is required",
  });

const TrackFlakyInput = z
  .object({
    historyDir: z.string().min(1).optional(),
    runs: z.array(z.unknown()).optional(),
    minObservations: z.number().int().positive().max(1000).optional(),
    flakinessThreshold: z.number().min(0).max(1).optional(),
  })
  .refine((v) => v.historyDir !== undefined || v.runs !== undefined, {
    message: "either historyDir or runs is required",
  });

const PerfTrendInput = z
  .object({
    historyDir: z.string().min(1).optional(),
    runs: z.array(z.unknown()).optional(),
    windowSize: z.number().int().positive().max(200).optional(),
    regressionRatio: z.number().min(1).max(10).optional(),
  })
  .refine((v) => v.historyDir !== undefined || v.runs !== undefined, {
    message: "either historyDir or runs is required",
  });

const HealthDashboardInput = z
  .object({
    historyDir: z.string().min(1).optional(),
    runs: z.array(z.unknown()).optional(),
  })
  .refine((v) => v.historyDir !== undefined || v.runs !== undefined, {
    message: "either historyDir or runs is required",
  });

export function buildTools(): ToolDefinition[] {
  return [
    {
      name: "ob_collect_metrics",
      description:
        "Parse a test-runner reporter (vitest/jest/playwright JSON) into " +
        "normalized metrics — pass rate, duration percentiles, slowest " +
        "tests, per-file rollups. Accepts either a reporterPath or an " +
        "inline payload.",
      inputSchema: {
        type: "object",
        properties: {
          reporterPath: { type: "string", minLength: 1 },
          payload: {},
          slowestLimit: { type: "integer", minimum: 1, maximum: 100 },
        },
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = CollectMetricsInput.parse(raw);
        const payload = await loadPayload(args.reporterPath, args.payload);
        const run = parseReporter(payload);
        return {
          run,
          metrics: computeMetrics(run, {
            ...(args.slowestLimit !== undefined ? { slowestLimit: args.slowestLimit } : {}),
          }),
        };
      },
    },
    {
      name: "ob_track_flaky",
      description:
        "Analyze a history of normalized runs for flaky and regressing " +
        "tests. Accepts a historyDir (directory of NormalizedRun JSON " +
        "files, sorted by mtime) or an inline runs array. Returns a " +
        "report with per-test scores 0..1 and stable/flaky/regressing " +
        "classification.",
      inputSchema: {
        type: "object",
        properties: {
          historyDir: { type: "string", minLength: 1 },
          runs: { type: "array" },
          minObservations: { type: "integer", minimum: 1, maximum: 1000 },
          flakinessThreshold: { type: "number", minimum: 0, maximum: 1 },
        },
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = TrackFlakyInput.parse(raw);
        const runs = await loadRuns(args.historyDir, args.runs);
        return analyzeHistory(runs, {
          ...(args.minObservations !== undefined ? { minObservations: args.minObservations } : {}),
          ...(args.flakinessThreshold !== undefined ? { flakinessThreshold: args.flakinessThreshold } : {}),
        });
      },
    },
    {
      name: "ob_perf_trend",
      description:
        "Compute an execution-time trend over a history of runs. Reports " +
        "overall slowdown/speedup and the top N per-test regressions " +
        "against a rolling baseline.",
      inputSchema: {
        type: "object",
        properties: {
          historyDir: { type: "string", minLength: 1 },
          runs: { type: "array" },
          windowSize: { type: "integer", minimum: 1, maximum: 200 },
          regressionRatio: { type: "number", minimum: 1, maximum: 10 },
        },
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = PerfTrendInput.parse(raw);
        const runs = await loadRuns(args.historyDir, args.runs);
        return analyzeTrend(runs, {
          ...(args.windowSize !== undefined ? { windowSize: args.windowSize } : {}),
          ...(args.regressionRatio !== undefined ? { regressionRatio: args.regressionRatio } : {}),
        });
      },
    },
    {
      name: "ob_health_dashboard",
      description:
        "Build a compact health-grade summary (green/yellow/red) from a " +
        "history of runs. Consumed by /vibeflow:status and by " +
        "release-decision-engine.",
      inputSchema: {
        type: "object",
        properties: {
          historyDir: { type: "string", minLength: 1 },
          runs: { type: "array" },
        },
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = HealthDashboardInput.parse(raw);
        const runs = await loadRuns(args.historyDir, args.runs);
        return buildHealthDashboard({ runs });
      },
    },
  ];
}

async function loadPayload(
  reporterPath: string | undefined,
  inline: unknown,
): Promise<unknown> {
  if (inline !== undefined) return inline;
  if (reporterPath === undefined) {
    throw new ReporterParseError("no payload and no reporterPath supplied");
  }
  if (!fs.existsSync(reporterPath)) {
    throw new ReporterParseError(`reporter file not found: ${reporterPath}`);
  }
  const raw = fs.readFileSync(reporterPath, "utf8");
  try {
    return JSON.parse(raw);
  } catch (err) {
    throw new ReporterParseError(
      `reporter file ${reporterPath} is not valid JSON: ${(err as Error).message}`,
    );
  }
}

async function loadRuns(
  historyDir: string | undefined,
  inline: readonly unknown[] | undefined,
): Promise<readonly NormalizedRun[]> {
  if (inline !== undefined) {
    // Accept inline payloads in either raw reporter form or already-
    // normalized form. If a payload has a `framework` field we trust
    // the caller; otherwise we try to parse it.
    return inline.map((entry) => {
      if (
        entry &&
        typeof entry === "object" &&
        "framework" in entry &&
        "tests" in entry
      ) {
        return entry as NormalizedRun;
      }
      return parseReporter(entry);
    });
  }
  if (historyDir === undefined) {
    throw new ReporterParseError("no runs and no historyDir supplied");
  }
  return loadHistoryDir(historyDir);
}

// Re-export for use in ob_track_flaky dir path, kept out of the public
// surface but imported above.
void analyzeHistoryDir;
