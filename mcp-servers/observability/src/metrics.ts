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
  readonly passRate: number; // 0..1, excludes skipped from the denominator
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
  readonly slowestLimit?: number; // default 5
}

export function computeMetrics(
  run: NormalizedRun,
  opts: MetricsOptions = {},
): RunMetrics {
  const slowestLimit = opts.slowestLimit ?? 5;
  const tests = run.tests;

  const passed = tests.filter((t) => t.status === "passed").length;
  const failed = tests.filter((t) => t.status === "failed").length;
  const skipped = tests.filter((t) => t.status === "skipped").length;
  const pending = tests.filter((t) => t.status === "pending").length;

  const executable = passed + failed;
  const passRate = executable > 0 ? passed / executable : 0;

  const durations = tests
    .map((t) => t.durationMs)
    .filter((d): d is number => typeof d === "number");

  const sortedDurations = [...durations].sort((a, b) => a - b);
  const durationP50Ms = percentile(sortedDurations, 50);
  const durationP95Ms = percentile(sortedDurations, 95);
  const durationP99Ms = percentile(sortedDurations, 99);

  const slowestTests = [...tests]
    .filter((t) => typeof t.durationMs === "number")
    .sort((a, b) => (b.durationMs ?? 0) - (a.durationMs ?? 0))
    .slice(0, slowestLimit);

  const failingTests = tests.filter((t) => t.status === "failed");

  return {
    framework: run.framework,
    totalTests: tests.length,
    passed,
    failed,
    skipped,
    pending,
    passRate,
    totalDurationMs: run.totalDurationMs,
    durationP50Ms,
    durationP95Ms,
    durationP99Ms,
    slowestTests,
    failingTests,
    perFile: rollupPerFile(tests),
  };
}

function rollupPerFile(tests: readonly NormalizedTest[]): FileRollup[] {
  const byFile = new Map<string, FileRollup>();
  for (const t of tests) {
    const existing = byFile.get(t.file) ?? {
      file: t.file,
      totalTests: 0,
      passed: 0,
      failed: 0,
      totalDurationMs: 0,
    };
    byFile.set(t.file, {
      file: t.file,
      totalTests: existing.totalTests + 1,
      passed: existing.passed + (t.status === "passed" ? 1 : 0),
      failed: existing.failed + (t.status === "failed" ? 1 : 0),
      totalDurationMs: existing.totalDurationMs + (t.durationMs ?? 0),
    });
  }
  return [...byFile.values()].sort((a, b) => a.file.localeCompare(b.file));
}

/**
 * Percentile helper using linear interpolation between adjacent ranks.
 * Matches numpy.percentile(interpolation='linear') well enough for a
 * metrics dashboard; not cryptographic-grade.
 */
export function percentile(
  sortedAsc: readonly number[],
  p: number,
): number | null {
  if (sortedAsc.length === 0) return null;
  if (p <= 0) return sortedAsc[0]!;
  if (p >= 100) return sortedAsc[sortedAsc.length - 1]!;
  const rank = ((p / 100) * (sortedAsc.length - 1));
  const lower = Math.floor(rank);
  const upper = Math.ceil(rank);
  if (lower === upper) return sortedAsc[lower]!;
  const weight = rank - lower;
  return sortedAsc[lower]! * (1 - weight) + sortedAsc[upper]! * weight;
}
