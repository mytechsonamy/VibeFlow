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
