import { describe, expect, it } from "vitest";
import { buildHealthDashboard } from "../src/dashboard.js";
import { mkRun, mkTest } from "./_fixtures.js";

describe("buildHealthDashboard", () => {
  it("returns red + a note when there are no runs", () => {
    const d = buildHealthDashboard({ runs: [] });
    expect(d.grade).toBe("red");
    expect(d.totalRuns).toBe(0);
    expect(d.notes.some((n) => /no runs available/.test(n))).toBe(true);
  });

  it("returns red when the latest run has failures", () => {
    const d = buildHealthDashboard({
      runs: [
        mkRun([
          mkTest({ id: "t1", status: "passed", durationMs: 10 }),
          mkTest({ id: "t2", status: "failed", durationMs: 20 }),
        ]),
      ],
    });
    expect(d.grade).toBe("red");
    expect(d.failingCount).toBe(1);
    expect(d.notes.some((n) => /1 tests failed/.test(n))).toBe(true);
  });

  it("returns green when everything is passing and the history is stable", () => {
    const pass = () =>
      mkRun([
        mkTest({ id: "t1", status: "passed", durationMs: 10 }),
        mkTest({ id: "t2", status: "passed", durationMs: 15 }),
      ]);
    const d = buildHealthDashboard({ runs: [pass(), pass(), pass()] });
    expect(d.grade).toBe("green");
    expect(d.failingCount).toBe(0);
    expect(d.flakyCount).toBe(0);
    expect(d.regressingCount).toBe(0);
  });

  it("returns yellow when history includes a flaky test but latest is green", () => {
    const runs = [
      mkRun([mkTest({ id: "t1", status: "passed", durationMs: 10 })]),
      mkRun([mkTest({ id: "t1", status: "failed", durationMs: 10 })]),
      mkRun([mkTest({ id: "t1", status: "passed", durationMs: 10 })]),
      mkRun([mkTest({ id: "t1", status: "failed", durationMs: 10 })]),
      mkRun([mkTest({ id: "t1", status: "passed", durationMs: 10 })]),
    ];
    const d = buildHealthDashboard({ runs });
    // Latest is a pass, so no failingCount. Interleaved → flaky.
    expect(d.failingCount).toBe(0);
    expect(d.flakyCount).toBeGreaterThanOrEqual(1);
    expect(d.grade).toBe("yellow");
  });

  it("flags a performance slowdown in the notes", () => {
    const stable = mkRun(
      [mkTest({ id: "t1", status: "passed", durationMs: 100 })],
      { totalDurationMs: 100 },
    );
    const slow = mkRun(
      [mkTest({ id: "t1", status: "passed", durationMs: 300 })],
      { totalDurationMs: 300 },
    );
    const d = buildHealthDashboard({
      runs: [stable, stable, stable, slow],
    });
    expect(d.notes.some((n) => /performance regression/.test(n))).toBe(true);
    // Flakiness + trend → yellow (no failures).
    expect(d.grade).toBe("yellow");
  });
});
