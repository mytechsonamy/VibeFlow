import { describe, expect, it } from "vitest";
import { computeMetrics, percentile } from "../src/metrics.js";
import { mkRun, mkTest } from "./_fixtures.js";

describe("percentile", () => {
  it("returns null on an empty array", () => {
    expect(percentile([], 50)).toBeNull();
  });

  it("returns the only element on a single-item array", () => {
    expect(percentile([42], 95)).toBe(42);
  });

  it("interpolates between ranks for uneven distributions", () => {
    // [1,2,3,4,5]; p=50 → rank 2.0 → 3
    expect(percentile([1, 2, 3, 4, 5], 50)).toBe(3);
    // p=25 → rank 1.0 → 2
    expect(percentile([1, 2, 3, 4, 5], 25)).toBe(2);
  });

  it("clamps p<=0 to min and p>=100 to max", () => {
    expect(percentile([1, 2, 3], 0)).toBe(1);
    expect(percentile([1, 2, 3], 100)).toBe(3);
  });
});

describe("computeMetrics", () => {
  it("counts statuses and derives passRate excluding skipped from the denominator", () => {
    const run = mkRun([
      mkTest({ id: "p1", status: "passed", durationMs: 10 }),
      mkTest({ id: "p2", status: "passed", durationMs: 20 }),
      mkTest({ id: "f1", status: "failed", durationMs: 30 }),
      mkTest({ id: "s1", status: "skipped", durationMs: null }),
    ]);
    const m = computeMetrics(run);
    expect(m.passed).toBe(2);
    expect(m.failed).toBe(1);
    expect(m.skipped).toBe(1);
    // 2 / (2 + 1)
    expect(m.passRate).toBeCloseTo(2 / 3, 5);
  });

  it("returns passRate=0 when there are no executable tests", () => {
    const run = mkRun([
      mkTest({ id: "s1", status: "skipped", durationMs: null }),
      mkTest({ id: "s2", status: "skipped", durationMs: null }),
    ]);
    expect(computeMetrics(run).passRate).toBe(0);
  });

  it("surfaces the N slowest tests (sorted desc, respects the limit)", () => {
    const run = mkRun([
      mkTest({ id: "a", status: "passed", durationMs: 10 }),
      mkTest({ id: "b", status: "passed", durationMs: 50 }),
      mkTest({ id: "c", status: "passed", durationMs: 30 }),
      mkTest({ id: "d", status: "passed", durationMs: 80 }),
    ]);
    const m = computeMetrics(run, { slowestLimit: 2 });
    expect(m.slowestTests.map((t) => t.id)).toEqual(["d", "b"]);
  });

  it("rolls metrics up per file (totalTests, passed, failed, total duration)", () => {
    const run = mkRun([
      mkTest({ id: "src/a.ts::1", file: "src/a.ts", status: "passed", durationMs: 10 }),
      mkTest({ id: "src/a.ts::2", file: "src/a.ts", status: "failed", durationMs: 20 }),
      mkTest({ id: "src/b.ts::1", file: "src/b.ts", status: "passed", durationMs: 5 }),
    ]);
    const m = computeMetrics(run);
    const a = m.perFile.find((f) => f.file === "src/a.ts")!;
    const b = m.perFile.find((f) => f.file === "src/b.ts")!;
    expect(a.totalTests).toBe(2);
    expect(a.passed).toBe(1);
    expect(a.failed).toBe(1);
    expect(a.totalDurationMs).toBe(30);
    expect(b.totalTests).toBe(1);
  });

  it("skips tests with null duration when computing percentiles", () => {
    const run = mkRun([
      mkTest({ id: "a", status: "passed", durationMs: 10 }),
      mkTest({ id: "b", status: "passed", durationMs: null }),
      mkTest({ id: "c", status: "passed", durationMs: 20 }),
    ]);
    const m = computeMetrics(run);
    expect(m.durationP50Ms).toBe(15); // [10, 20] p50
  });
});
