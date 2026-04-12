import { describe, expect, it } from "vitest";
import { analyzeTrend } from "../src/trends.js";
import { mkRun, mkTest } from "./_fixtures.js";
import { NormalizedRun } from "../src/parsers.js";

function withDuration(totalDurationMs: number, tests = 1): NormalizedRun {
  return mkRun(
    Array.from({ length: tests }, (_, i) =>
      mkTest({
        id: `t${i}`,
        durationMs: Math.round(totalDurationMs / tests),
      }),
    ),
    { totalDurationMs },
  );
}

describe("analyzeTrend — overall", () => {
  it("reports insufficient-data for a single run", () => {
    const r = analyzeTrend([withDuration(1000)]);
    expect(r.overall.direction).toBe("insufficient-data");
    expect(r.overall.regression).toBe(false);
    expect(r.overall.latestDurationMs).toBe(1000);
  });

  it("marks a 2× slowdown as a slowdown regression", () => {
    const runs = [
      withDuration(1000),
      withDuration(1000),
      withDuration(1000),
      withDuration(1000),
      withDuration(2000), // latest
    ];
    const r = analyzeTrend(runs);
    expect(r.overall.direction).toBe("slowdown");
    expect(r.overall.regression).toBe(true);
    expect(r.overall.latestDeltaRatio).toBeCloseTo(2, 1);
  });

  it("marks a 2× speedup as a speedup (not a regression)", () => {
    const runs = [
      withDuration(1000),
      withDuration(1000),
      withDuration(1000),
      withDuration(500), // latest
    ];
    const r = analyzeTrend(runs);
    expect(r.overall.direction).toBe("speedup");
    expect(r.overall.regression).toBe(false);
  });

  it("respects the windowSize when computing the baseline", () => {
    const runs = [
      withDuration(100),
      withDuration(100),
      withDuration(100),
      withDuration(1000), // only this previous run should be in the window
      withDuration(1000),
    ];
    const r = analyzeTrend(runs, { windowSize: 1 });
    expect(r.overall.baselineAvgDurationMs).toBe(1000);
    expect(r.overall.direction).toBe("stable");
  });
});

describe("analyzeTrend — per test", () => {
  it("ranks the largest regressions first", () => {
    const runs = [
      mkRun([
        mkTest({ id: "a", durationMs: 10 }),
        mkTest({ id: "b", durationMs: 20 }),
      ]),
      mkRun([
        mkTest({ id: "a", durationMs: 12 }),
        mkTest({ id: "b", durationMs: 22 }),
      ]),
      mkRun([
        mkTest({ id: "a", durationMs: 11 }),
        mkTest({ id: "b", durationMs: 80 }),
      ]),
    ];
    const r = analyzeTrend(runs);
    expect(r.perTest[0]!.id).toBe("b");
    expect(r.perTest[0]!.regression).toBe(true);
    expect(r.perTest[1]!.regression).toBe(false);
  });

  it("skips tests with too few observations", () => {
    const runs = [
      mkRun([mkTest({ id: "a", durationMs: 10 })]),
      mkRun([mkTest({ id: "a", durationMs: 12 })]),
    ];
    const r = analyzeTrend(runs, { minObservationsPerTest: 3 });
    expect(r.perTest).toEqual([]);
  });
});
