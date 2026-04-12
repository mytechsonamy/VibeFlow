import { NormalizedRun, NormalizedTest } from "../src/parsers.js";

/**
 * Fixture helpers for observability tests.
 *
 * `mkRun` builds a NormalizedRun directly — tests that care about the
 * downstream metrics / flakiness / trends logic skip the parser layer
 * entirely and work against the normalized shape.
 *
 * `vitestReport` / `jestReport` / `playwrightReport` build minimal valid
 * reporter payloads so the parser tests can round-trip real JSON
 * without pulling in real test runners.
 */

export function mkTest(
  partial: Partial<NormalizedTest> = {},
): NormalizedTest {
  return {
    id: "src/a.ts::default",
    file: "src/a.ts",
    name: "default",
    status: "passed",
    durationMs: 10,
    errorMessage: null,
    retries: 0,
    ...partial,
  };
}

export function mkRun(
  tests: readonly NormalizedTest[],
  partial: Partial<NormalizedRun> = {},
): NormalizedRun {
  const totalDurationMs =
    partial.totalDurationMs ??
    tests.reduce((acc, t) => acc + (t.durationMs ?? 0), 0);
  return {
    framework: "vitest",
    startedAt: "2026-04-13T00:00:00Z",
    finishedAt: "2026-04-13T00:00:10Z",
    totalDurationMs,
    tests,
    ...partial,
  };
}

export function vitestReport(
  opts: {
    filePath?: string;
    cases?: Array<{
      title: string;
      status: "passed" | "failed" | "skipped" | "pending";
      duration?: number;
      message?: string;
      invocations?: number;
    }>;
    startTime?: number;
    endTime?: number;
  } = {},
): unknown {
  const file = opts.filePath ?? "/app/src/a.ts";
  const cases = opts.cases ?? [];
  return {
    numTotalTests: cases.length,
    startTime: opts.startTime ?? 0,
    endTime: opts.endTime ?? 1000,
    testResults: [
      {
        testFilePath: file,
        assertionResults: cases.map((c) => ({
          ancestorTitles: [],
          title: c.title,
          fullName: c.title,
          status: c.status,
          duration: c.duration ?? 5,
          failureMessages: c.message ? [c.message] : [],
          invocations: c.invocations,
          location: { line: 1, column: 1 },
        })),
      },
    ],
  };
}

export function jestReport(
  opts: Parameters<typeof vitestReport>[0] = {},
): unknown {
  // Jest has the same overall shape as vitest's json reporter but no
  // `location` on the assertion. Strip it so autoDetect picks jest.
  const base = vitestReport(opts) as {
    testResults: Array<{
      assertionResults: Array<Record<string, unknown>>;
    }>;
  };
  for (const tr of base.testResults) {
    for (const a of tr.assertionResults) {
      delete a.location;
    }
  }
  return base;
}

export function playwrightReport(
  opts: {
    file?: string;
    specs?: Array<{
      title: string;
      status: "passed" | "failed" | "skipped";
      duration?: number;
      message?: string;
      retries?: number;
      projectName?: string;
    }>;
    startTime?: string;
    duration?: number;
  } = {},
): unknown {
  const file = opts.file ?? "/e2e/login.spec.ts";
  const specs = opts.specs ?? [];
  return {
    config: { version: "1.40.0" },
    suites: [
      {
        file,
        title: "login",
        specs: specs.map((s) => ({
          title: s.title,
          file,
          tests: [
            {
              projectName: s.projectName ?? "default",
              results: [
                {
                  status: s.status,
                  duration: s.duration ?? 5,
                  retry: s.retries ?? 0,
                  error: s.message ? { message: s.message } : undefined,
                },
              ],
            },
          ],
        })),
      },
    ],
    stats: {
      startTime: opts.startTime ?? "2026-04-13T00:00:00Z",
      duration: opts.duration ?? 1000,
    },
  };
}
