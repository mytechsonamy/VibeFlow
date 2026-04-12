/**
 * Test-runner reporter parsers.
 *
 * Every framework the skill supports has its own JSON reporter shape.
 * This module is the only place that knows about those shapes; every
 * downstream module (metrics, flakiness, trends, dashboard) consumes
 * the `NormalizedRun` type produced here.
 *
 * Adding a new framework means:
 *   1. Add a `parseX` function below
 *   2. Teach `autoDetect` to recognize its shape
 *   3. Add its name to the `ReporterFramework` union
 *   4. Extend the integration harness `framework` sentinel
 */

export type ReporterFramework = "vitest" | "jest" | "playwright";

export interface NormalizedTest {
  /** Stable identifier: `<file>::<name>`. Used as the flakiness key. */
  readonly id: string;
  readonly file: string;
  readonly name: string;
  readonly status: "passed" | "failed" | "skipped" | "pending";
  readonly durationMs: number | null;
  readonly errorMessage: string | null;
  /** 0 when the framework doesn't track retries. */
  readonly retries: number;
}

export interface NormalizedRun {
  readonly framework: ReporterFramework;
  readonly startedAt: string;
  readonly finishedAt: string;
  readonly totalDurationMs: number;
  readonly tests: readonly NormalizedTest[];
}

export class ReporterParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ReporterParseError";
  }
}

/**
 * Parse a reporter payload without the caller having to name the
 * framework. Returns the normalized run; throws on malformed input
 * rather than guessing.
 */
export function parseReporter(raw: unknown): NormalizedRun {
  const framework = autoDetect(raw);
  switch (framework) {
    case "vitest":
      return parseVitest(raw as VitestReport);
    case "jest":
      return parseJest(raw as JestReport);
    case "playwright":
      return parsePlaywright(raw as PlaywrightReport);
  }
}

export function autoDetect(raw: unknown): ReporterFramework {
  if (!raw || typeof raw !== "object") {
    throw new ReporterParseError("reporter payload must be an object");
  }
  const r = raw as Record<string, unknown>;

  // vitest's json reporter has a top-level `testResults` + a
  // `numTotalTests` counter; distinguishable from jest by a `config`
  // object that names vitest, or by the unique `workerId` shape.
  if (
    "testResults" in r &&
    Array.isArray(r.testResults) &&
    typeof r.numTotalTests === "number"
  ) {
    // vitest carries the key `startTime` + `success`; jest carries the same
    // keys. Disambiguate by checking for vitest-specific metadata first,
    // then default to jest.
    const hint = (r as { config?: { name?: string } }).config?.name;
    if (hint === "vitest") return "vitest";
    // Look inside the first file for vitest-only fields (location.line).
    const firstFile = (r.testResults as Array<Record<string, unknown>>)[0];
    if (firstFile && Array.isArray(firstFile["assertionResults"])) {
      const firstAssertion = (firstFile["assertionResults"] as Array<Record<string, unknown>>)[0];
      if (firstAssertion && "location" in firstAssertion) return "vitest";
    }
    return "jest";
  }

  // playwright's json reporter has `suites` + `config.projects` at top level.
  if (Array.isArray(r.suites) && typeof r.config === "object") {
    return "playwright";
  }

  throw new ReporterParseError(
    "could not identify test framework from reporter payload (expected vitest/jest/playwright shape)",
  );
}

// ---------------------------------------------------------------------------
// vitest / jest (shared shape)
// ---------------------------------------------------------------------------

interface VitestReport {
  numTotalTests?: number;
  startTime?: number;
  endTime?: number;
  testResults?: VitestFileResult[];
  config?: { name?: string };
}

interface VitestFileResult {
  name?: string; // file path
  testFilePath?: string;
  startTime?: number;
  endTime?: number;
  assertionResults?: VitestAssertion[];
}

interface VitestAssertion {
  ancestorTitles?: string[];
  title?: string;
  fullName?: string;
  status?: string;
  duration?: number;
  failureMessages?: string[];
  invocations?: number; // vitest
  retryReasons?: unknown[]; // vitest alternative
  location?: { line?: number; column?: number };
}

type JestReport = VitestReport;

export function parseVitest(raw: VitestReport): NormalizedRun {
  return parseVitestJestShared(raw, "vitest");
}

export function parseJest(raw: JestReport): NormalizedRun {
  return parseVitestJestShared(raw, "jest");
}

function parseVitestJestShared(
  raw: VitestReport,
  framework: "vitest" | "jest",
): NormalizedRun {
  if (!raw || typeof raw !== "object") {
    throw new ReporterParseError(`${framework}: expected an object`);
  }
  const files = raw.testResults ?? [];
  const tests: NormalizedTest[] = [];

  for (const f of files) {
    const filePath = f.testFilePath ?? f.name ?? "<unknown>";
    const assertions = f.assertionResults ?? [];
    for (const a of assertions) {
      const name =
        a.fullName ??
        [...(a.ancestorTitles ?? []), a.title ?? "<anonymous>"].join(" > ");
      const status = normalizeStatus(a.status);
      const retries = computeRetries(a);
      tests.push({
        id: `${filePath}::${name}`,
        file: filePath,
        name,
        status,
        durationMs: typeof a.duration === "number" ? a.duration : null,
        errorMessage:
          a.failureMessages && a.failureMessages.length > 0
            ? String(a.failureMessages[0])
            : null,
        retries,
      });
    }
  }

  const startedAtMs = raw.startTime ?? 0;
  const finishedAtMs = raw.endTime ?? startedAtMs;
  const totalDurationMs = Math.max(0, finishedAtMs - startedAtMs);

  return {
    framework,
    startedAt: new Date(startedAtMs).toISOString(),
    finishedAt: new Date(finishedAtMs).toISOString(),
    totalDurationMs,
    tests,
  };
}

function computeRetries(a: VitestAssertion): number {
  if (typeof a.invocations === "number" && a.invocations > 0) {
    return Math.max(0, a.invocations - 1);
  }
  if (Array.isArray(a.retryReasons)) return a.retryReasons.length;
  return 0;
}

// ---------------------------------------------------------------------------
// playwright
// ---------------------------------------------------------------------------

interface PlaywrightReport {
  config: { version?: string };
  suites: PlaywrightSuite[];
  stats?: {
    startTime?: string;
    duration?: number;
  };
}

interface PlaywrightSuite {
  file?: string;
  title?: string;
  suites?: PlaywrightSuite[];
  specs?: PlaywrightSpec[];
}

interface PlaywrightSpec {
  id?: string;
  title?: string;
  file?: string;
  tests?: PlaywrightTestRow[];
}

interface PlaywrightTestRow {
  results?: PlaywrightResult[];
  projectName?: string;
}

interface PlaywrightResult {
  status?: string;
  duration?: number;
  error?: { message?: string };
  retry?: number;
}

export function parsePlaywright(raw: PlaywrightReport): NormalizedRun {
  if (!raw || typeof raw !== "object") {
    throw new ReporterParseError("playwright: expected an object");
  }
  const tests: NormalizedTest[] = [];
  walkSuites(raw.suites ?? [], [], tests);

  const startedMs = raw.stats?.startTime
    ? Date.parse(raw.stats.startTime)
    : 0;
  const totalDurationMs = raw.stats?.duration ?? 0;
  const finishedMs = startedMs + totalDurationMs;

  return {
    framework: "playwright",
    startedAt: new Date(startedMs).toISOString(),
    finishedAt: new Date(finishedMs).toISOString(),
    totalDurationMs,
    tests,
  };
}

function walkSuites(
  suites: PlaywrightSuite[],
  ancestors: string[],
  out: NormalizedTest[],
): void {
  for (const s of suites) {
    const here = [...ancestors, s.title ?? ""].filter((t) => t !== "");
    for (const spec of s.specs ?? []) {
      const filePath = spec.file ?? s.file ?? "<unknown>";
      const specName = [...here, spec.title ?? "<anonymous>"].join(" > ");
      // playwright may run the same spec across multiple projects / browsers.
      // We record one NormalizedTest per (spec, project) pair, keyed by id.
      for (const t of spec.tests ?? []) {
        // Pick the LAST result — playwright reports one result per attempt
        // in a `results` array; the final attempt is the ground truth.
        const results = t.results ?? [];
        const final = results[results.length - 1];
        if (!final) continue;
        const project = t.projectName ?? "default";
        const name = project === "default" ? specName : `${specName} [${project}]`;
        out.push({
          id: `${filePath}::${name}`,
          file: filePath,
          name,
          status: normalizeStatus(final.status),
          durationMs: typeof final.duration === "number" ? final.duration : null,
          errorMessage: final.error?.message ?? null,
          retries: typeof final.retry === "number" ? final.retry : 0,
        });
      }
    }
    if (s.suites && s.suites.length > 0) {
      walkSuites(s.suites, here, out);
    }
  }
}

// ---------------------------------------------------------------------------
// shared helpers
// ---------------------------------------------------------------------------

function normalizeStatus(raw: unknown): NormalizedTest["status"] {
  if (typeof raw !== "string") return "pending";
  const s = raw.toLowerCase();
  if (s === "passed" || s === "pass" || s === "expected") return "passed";
  if (s === "failed" || s === "fail" || s === "unexpected") return "failed";
  if (s === "skipped" || s === "skip" || s === "todo") return "skipped";
  if (s === "pending" || s === "disabled" || s === "flaky") return "pending";
  // Unknown status values collapse to pending so downstream code can
  // always pattern-match. A strict mode would throw; we surface in the
  // run output instead.
  return "pending";
}
