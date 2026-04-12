import * as fs from "node:fs";
import * as path from "node:path";
import { NormalizedRun, NormalizedTest } from "./parsers.js";

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
  readonly score: number; // 0..1
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

const DEFAULT_MIN_OBSERVATIONS = 3;
const DEFAULT_FLAKINESS_THRESHOLD = 0.15;

export function analyzeHistory(
  runs: readonly NormalizedRun[],
  opts: FlakinessOptions = {},
): FlakinessReport {
  const minObservations = opts.minObservations ?? DEFAULT_MIN_OBSERVATIONS;
  const threshold = opts.flakinessThreshold ?? DEFAULT_FLAKINESS_THRESHOLD;

  // Per-test observation list, preserving run order.
  const byTest = new Map<string, NormalizedTest[]>();
  runs.forEach((run) => {
    for (const t of run.tests) {
      const list = byTest.get(t.id) ?? [];
      list.push(t);
      byTest.set(t.id, list);
    }
  });

  const flaky: FlakyFinding[] = [];
  const regressing: FlakyFinding[] = [];
  let stableCount = 0;

  for (const [id, observations] of byTest) {
    if (observations.length < minObservations) {
      stableCount += 1;
      continue;
    }

    const passes = observations.filter((t) => t.status === "passed").length;
    const failures = observations.filter((t) => t.status === "failed").length;
    const skipped = observations.filter((t) => t.status === "skipped").length;
    const firstFailureAt = observations.findIndex((t) => t.status === "failed");
    const lastFailureAt = findLastFailureIndex(observations);
    const first = observations[0]!;

    const score = computeScore(observations);
    const finding: FlakyFinding = {
      id,
      file: first.file,
      name: first.name,
      totalObservations: observations.length,
      passes,
      failures,
      skipped,
      score,
      status: "stable",
      firstFailureAt,
      lastFailureAt,
    };

    if (failures === 0) {
      stableCount += 1;
      continue;
    }

    if (passes === 0) {
      // Every observation failed: this is a regression, not a flake.
      regressing.push({ ...finding, status: "regressing" });
      continue;
    }

    // Mixed pass/fail. Check for "failures only at the tail" — if the
    // earliest failure index >= the last pass index, it's a pure
    // regression; anything else is flakiness.
    const lastPassAt = findLastPassIndex(observations);
    if (firstFailureAt > lastPassAt) {
      regressing.push({ ...finding, status: "regressing" });
      continue;
    }

    if (score >= threshold) {
      flaky.push({ ...finding, status: "flaky" });
    } else {
      stableCount += 1;
    }
  }

  // Sort by score descending so the most flaky tests land first.
  flaky.sort((a, b) => b.score - a.score || a.id.localeCompare(b.id));
  regressing.sort((a, b) => a.id.localeCompare(b.id));

  return {
    runCount: runs.length,
    observedAt: new Date().toISOString(),
    flaky,
    regressing,
    stableCount,
  };
}

/**
 * Read a history directory of NormalizedRun JSON files and compute
 * flakiness. Files are sorted by `mtime` ascending so the oldest run
 * comes first. Anything that can't be parsed is skipped with a warning
 * written to stderr — never silently merged.
 */
export function analyzeHistoryDir(
  dir: string,
  opts: FlakinessOptions = {},
): FlakinessReport {
  const runs = loadHistoryDir(dir);
  return analyzeHistory(runs, opts);
}

export function loadHistoryDir(dir: string): NormalizedRun[] {
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) {
    throw new Error(`flakiness: history dir does not exist: ${dir}`);
  }
  const entries = fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith(".json"))
    .map((e) => {
      const full = path.join(dir, e.name);
      return { full, mtime: fs.statSync(full).mtimeMs };
    })
    .sort((a, b) => a.mtime - b.mtime);

  const runs: NormalizedRun[] = [];
  for (const { full } of entries) {
    try {
      const raw = fs.readFileSync(full, "utf8");
      const parsed = JSON.parse(raw) as NormalizedRun;
      // Minimal shape check — a missing `tests` array is a malformed run.
      if (!Array.isArray(parsed.tests)) {
        process.stderr.write(
          `[observability] skipping malformed history file ${full}: missing tests\n`,
        );
        continue;
      }
      runs.push(parsed);
    } catch (err) {
      process.stderr.write(
        `[observability] skipping unreadable history file ${full}: ${(err as Error).message}\n`,
      );
    }
  }
  return runs;
}

/**
 * Compute a 0..1 flakiness score from the observation sequence.
 *
 *   base        = min(passes, failures) / total
 *   interleave  = 1 for pass↔fail interleave, 0 for pure blocks
 *   score       = base * (0.5 + 0.5 * interleave)
 *
 * Tests failing once in the entire window still score nonzero (base
 * kicks in), but a test that alternates pass/fail rapidly scores much
 * higher. The 0.5 multiplier keeps "any mix" visible; the 0.5 bonus
 * emphasizes interleaved failures, which are the hardest to diagnose.
 */
function computeScore(observations: readonly NormalizedTest[]): number {
  const total = observations.length;
  const passes = observations.filter((t) => t.status === "passed").length;
  const failures = observations.filter((t) => t.status === "failed").length;
  if (total === 0) return 0;
  const executable = passes + failures;
  if (executable < 2) return 0;
  const base = Math.min(passes, failures) / executable;

  // Count pass→fail or fail→pass transitions vs the maximum possible.
  let transitions = 0;
  for (let i = 1; i < observations.length; i++) {
    const prev = observations[i - 1]!;
    const cur = observations[i]!;
    if (
      (prev.status === "passed" && cur.status === "failed") ||
      (prev.status === "failed" && cur.status === "passed")
    ) {
      transitions += 1;
    }
  }
  const maxTransitions = executable - 1;
  const interleave = maxTransitions > 0 ? transitions / maxTransitions : 0;

  return Math.min(1, base * (0.5 + 0.5 * interleave));
}

function findLastFailureIndex(observations: readonly NormalizedTest[]): number {
  for (let i = observations.length - 1; i >= 0; i--) {
    if (observations[i]!.status === "failed") return i;
  }
  return -1;
}

function findLastPassIndex(observations: readonly NormalizedTest[]): number {
  for (let i = observations.length - 1; i >= 0; i--) {
    if (observations[i]!.status === "passed") return i;
  }
  return -1;
}
