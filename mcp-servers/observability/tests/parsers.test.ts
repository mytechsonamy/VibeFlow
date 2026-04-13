import { describe, expect, it } from "vitest";
import {
  parseReporter,
  parseVitest,
  parseJest,
  parsePlaywright,
  autoDetect,
  ReporterParseError,
} from "../src/parsers.js";
import {
  vitestReport,
  jestReport,
  playwrightReport,
} from "./_fixtures.js";

describe("autoDetect", () => {
  it("identifies vitest via the location field", () => {
    const raw = vitestReport({ cases: [{ title: "t", status: "passed" }] });
    expect(autoDetect(raw)).toBe("vitest");
  });

  it("identifies jest as the fallback for the testResults shape", () => {
    const raw = jestReport({ cases: [{ title: "t", status: "passed" }] });
    expect(autoDetect(raw)).toBe("jest");
  });

  it("identifies playwright via the suites + config.projects shape", () => {
    const raw = playwrightReport({
      specs: [{ title: "t", status: "passed" }],
    });
    expect(autoDetect(raw)).toBe("playwright");
  });

  it("throws for unrecognized payloads", () => {
    expect(() => autoDetect({ unknown: true })).toThrow(ReporterParseError);
  });

  it("throws for non-object input", () => {
    expect(() => autoDetect("a string")).toThrow(ReporterParseError);
  });
});

describe("parseVitest", () => {
  it("normalizes a happy-path vitest payload", () => {
    const raw = vitestReport({
      filePath: "/app/src/a.ts",
      cases: [
        { title: "first case", status: "passed", duration: 10 },
        { title: "second case", status: "failed", duration: 20, message: "boom" },
      ],
      startTime: 1000,
      endTime: 2000,
    });
    const run = parseVitest(raw as never);
    expect(run.framework).toBe("vitest");
    expect(run.tests).toHaveLength(2);
    expect(run.tests[0]!.status).toBe("passed");
    expect(run.tests[1]!.status).toBe("failed");
    expect(run.tests[1]!.errorMessage).toBe("boom");
    expect(run.totalDurationMs).toBe(1000);
  });

  it("computes retries from vitest `invocations`", () => {
    const raw = vitestReport({
      cases: [
        { title: "retried", status: "passed", invocations: 3 },
        { title: "first-try", status: "passed", invocations: 1 },
      ],
    });
    const run = parseVitest(raw as never);
    expect(run.tests[0]!.retries).toBe(2);
    expect(run.tests[1]!.retries).toBe(0);
  });
});

describe("parseJest", () => {
  it("normalizes jest payloads through the shared path", () => {
    const raw = jestReport({
      cases: [{ title: "only", status: "passed", duration: 30 }],
    });
    const run = parseJest(raw as never);
    expect(run.framework).toBe("jest");
    expect(run.tests[0]!.name).toBe("only");
  });
});

describe("parsePlaywright", () => {
  it("flattens suites + specs + results into a NormalizedRun", () => {
    const raw = playwrightReport({
      specs: [
        { title: "user can log in", status: "passed", duration: 50 },
        {
          title: "user sees an error on bad password",
          status: "failed",
          duration: 75,
          message: "expected error alert",
          retries: 1,
        },
      ],
      duration: 1234,
    });
    const run = parsePlaywright(raw as never);
    expect(run.framework).toBe("playwright");
    expect(run.tests).toHaveLength(2);
    expect(run.tests[1]!.retries).toBe(1);
    expect(run.tests[1]!.errorMessage).toBe("expected error alert");
    expect(run.totalDurationMs).toBe(1234);
  });

  it("tags cross-project specs with the project name in the test id", () => {
    const raw = playwrightReport({
      specs: [
        {
          title: "shared spec",
          status: "passed",
          projectName: "chromium",
        },
      ],
    });
    const run = parsePlaywright(raw as never);
    expect(run.tests[0]!.name).toContain("[chromium]");
  });
});

describe("parseReporter auto-dispatch", () => {
  it("dispatches to the correct parser", () => {
    const v = parseReporter(vitestReport({ cases: [{ title: "a", status: "passed" }] }));
    expect(v.framework).toBe("vitest");

    const j = parseReporter(jestReport({ cases: [{ title: "a", status: "passed" }] }));
    expect(j.framework).toBe("jest");

    const p = parseReporter(playwrightReport({ specs: [{ title: "a", status: "passed" }] }));
    expect(p.framework).toBe("playwright");
  });
});

// ---------------------------------------------------------------------------
// Edge-branch coverage — exercises the null/default fallback branches
// that unit tests skip by default (missing fields, unknown statuses,
// nested suites, empty payloads). Driven by coverage-gap analysis in
// parsers.ts (S4-01).
// ---------------------------------------------------------------------------

describe("parsers edge branches", () => {
  it("parseVitest handles empty testResults", () => {
    const run = parseVitest({ testResults: [], numTotalTests: 0 } as never);
    expect(run.tests).toEqual([]);
    expect(run.totalDurationMs).toBe(0);
  });

  it("parseVitest fills file path when testFilePath and name are missing", () => {
    const run = parseVitest({
      testResults: [
        { assertionResults: [{ title: "t", status: "passed" }] },
      ],
    } as never);
    expect(run.tests[0]!.file).toBe("<unknown>");
  });

  it("parseVitest joins ancestorTitles when fullName is missing", () => {
    const run = parseVitest({
      testResults: [
        {
          testFilePath: "/a.ts",
          assertionResults: [
            {
              ancestorTitles: ["outer", "inner"],
              title: "leaf",
              status: "passed",
            },
          ],
        },
      ],
    } as never);
    expect(run.tests[0]!.name).toBe("outer > inner > leaf");
  });

  it("parseVitest falls back to <anonymous> when title is missing", () => {
    const run = parseVitest({
      testResults: [
        {
          testFilePath: "/a.ts",
          assertionResults: [{ status: "passed" }],
        },
      ],
    } as never);
    expect(run.tests[0]!.name).toBe("<anonymous>");
  });

  it("parseVitest coerces non-number duration to null", () => {
    const run = parseVitest({
      testResults: [
        {
          testFilePath: "/a.ts",
          assertionResults: [{ title: "t", status: "passed", duration: "10" }],
        },
      ],
    } as never);
    expect(run.tests[0]!.durationMs).toBeNull();
  });

  it("parseVitest computes retries from retryReasons when invocations is absent", () => {
    const run = parseVitest({
      testResults: [
        {
          testFilePath: "/a.ts",
          assertionResults: [
            {
              title: "t",
              status: "passed",
              retryReasons: ["timeout", "assertion"],
            },
          ],
        },
      ],
    } as never);
    expect(run.tests[0]!.retries).toBe(2);
  });

  it("parseVitest throws ReporterParseError for non-object input", () => {
    expect(() => parseVitest(null as never)).toThrow(ReporterParseError);
  });

  it("parseVitest clamps negative total duration to zero", () => {
    const run = parseVitest({
      startTime: 2000,
      endTime: 1000,
      testResults: [],
    } as never);
    expect(run.totalDurationMs).toBe(0);
  });

  it("parseVitest maps multi-word statuses to the canonical set", () => {
    const run = parseVitest({
      testResults: [
        {
          testFilePath: "/a.ts",
          assertionResults: [
            { title: "a", status: "SKIP" },
            { title: "b", status: "todo" },
            { title: "c", status: "disabled" },
            { title: "d", status: "wombat" },
          ],
        },
      ],
    } as never);
    expect(run.tests.map((t) => t.status)).toEqual([
      "skipped",
      "skipped",
      "pending",
      "pending",
    ]);
  });

  it("parseVitest coerces non-string status to pending", () => {
    const run = parseVitest({
      testResults: [
        {
          testFilePath: "/a.ts",
          assertionResults: [{ title: "t", status: 42 as unknown as string }],
        },
      ],
    } as never);
    expect(run.tests[0]!.status).toBe("pending");
  });

  it("parsePlaywright walks nested sub-suites", () => {
    const raw = {
      config: { version: "1.0" },
      suites: [
        {
          title: "outer",
          suites: [
            {
              title: "inner",
              specs: [
                {
                  title: "deep spec",
                  file: "/a.spec.ts",
                  tests: [
                    {
                      results: [{ status: "passed", duration: 5 }],
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };
    const run = parsePlaywright(raw as never);
    expect(run.tests).toHaveLength(1);
    expect(run.tests[0]!.name).toContain("outer > inner > deep spec");
  });

  it("parsePlaywright uses startedAt=0 when stats.startTime is missing", () => {
    const raw = {
      config: { version: "1.0" },
      suites: [
        {
          specs: [
            {
              title: "spec",
              file: "/b.spec.ts",
              tests: [{ results: [{ status: "failed" }] }],
            },
          ],
        },
      ],
    };
    const run = parsePlaywright(raw as never);
    expect(run.startedAt).toBe(new Date(0).toISOString());
    expect(run.totalDurationMs).toBe(0);
  });

  it("parsePlaywright skips specs with no results", () => {
    const raw = {
      config: { version: "1.0" },
      suites: [
        {
          specs: [
            {
              title: "empty",
              file: "/c.spec.ts",
              tests: [{ results: [] }],
            },
          ],
        },
      ],
    };
    const run = parsePlaywright(raw as never);
    expect(run.tests).toEqual([]);
  });

  it("parsePlaywright throws ReporterParseError for non-object input", () => {
    expect(() => parsePlaywright("nope" as never)).toThrow(ReporterParseError);
  });

  it("parsePlaywright falls back to <unknown> file when both spec.file and suite.file are missing", () => {
    const raw = {
      config: { version: "1.0" },
      suites: [
        {
          specs: [
            {
              title: "anon",
              tests: [{ results: [{ status: "passed" }] }],
            },
          ],
        },
      ],
    };
    const run = parsePlaywright(raw as never);
    expect(run.tests[0]!.file).toBe("<unknown>");
  });

  it("parsePlaywright reads the last retry result, not the first", () => {
    const raw = {
      config: { version: "1.0" },
      suites: [
        {
          specs: [
            {
              title: "flaky",
              file: "/d.spec.ts",
              tests: [
                {
                  results: [
                    { status: "failed", retry: 0 },
                    { status: "passed", retry: 1 },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };
    const run = parsePlaywright(raw as never);
    expect(run.tests[0]!.status).toBe("passed");
    expect(run.tests[0]!.retries).toBe(1);
  });
});
