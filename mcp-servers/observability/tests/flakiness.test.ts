import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  analyzeHistory,
  analyzeHistoryDir,
  loadHistoryDir,
} from "../src/flakiness.js";
import { NormalizedRun } from "../src/parsers.js";
import { mkRun, mkTest } from "./_fixtures.js";

function runWith(
  testDefs: Array<{
    id: string;
    status: "passed" | "failed" | "skipped";
  }>,
): NormalizedRun {
  return mkRun(
    testDefs.map((t) =>
      mkTest({ id: t.id, name: t.id, status: t.status, durationMs: 1 }),
    ),
  );
}

describe("analyzeHistory", () => {
  it("marks a pure regression (all fails) as regressing, not flaky", () => {
    const runs: NormalizedRun[] = [
      runWith([{ id: "t1", status: "failed" }]),
      runWith([{ id: "t1", status: "failed" }]),
      runWith([{ id: "t1", status: "failed" }]),
    ];
    const r = analyzeHistory(runs);
    expect(r.regressing.map((f) => f.id)).toEqual(["t1"]);
    expect(r.flaky).toEqual([]);
  });

  it("marks pass-then-fail (no subsequent pass) as regressing", () => {
    const runs = [
      runWith([{ id: "t1", status: "passed" }]),
      runWith([{ id: "t1", status: "passed" }]),
      runWith([{ id: "t1", status: "failed" }]),
      runWith([{ id: "t1", status: "failed" }]),
    ];
    const r = analyzeHistory(runs);
    expect(r.regressing.map((f) => f.id)).toEqual(["t1"]);
    expect(r.flaky).toEqual([]);
  });

  it("marks interleaved pass/fail as flaky", () => {
    const runs = [
      runWith([{ id: "t1", status: "passed" }]),
      runWith([{ id: "t1", status: "failed" }]),
      runWith([{ id: "t1", status: "passed" }]),
      runWith([{ id: "t1", status: "failed" }]),
    ];
    const r = analyzeHistory(runs);
    expect(r.flaky.map((f) => f.id)).toEqual(["t1"]);
    expect(r.regressing).toEqual([]);
    expect(r.flaky[0]!.score).toBeGreaterThan(0.4);
  });

  it("counts all-pass tests as stable", () => {
    const runs = [
      runWith([{ id: "t1", status: "passed" }]),
      runWith([{ id: "t1", status: "passed" }]),
      runWith([{ id: "t1", status: "passed" }]),
    ];
    const r = analyzeHistory(runs);
    expect(r.stableCount).toBe(1);
    expect(r.flaky).toEqual([]);
  });

  it("ignores tests with fewer observations than minObservations", () => {
    const runs = [
      runWith([{ id: "t1", status: "passed" }]),
      runWith([{ id: "t1", status: "failed" }]),
    ];
    const r = analyzeHistory(runs, { minObservations: 3 });
    expect(r.flaky).toEqual([]);
    expect(r.regressing).toEqual([]);
  });

  it("respects the flakinessThreshold — low mix falls below threshold", () => {
    // 9 passes + 1 fail. base = 1/10 = 0.1; interleave = 1 transition /
    // 9 max = 0.111; score = 0.1 * (0.5 + 0.5 * 0.111) ≈ 0.0556.
    // Default threshold 0.15 → NOT flagged.
    const runs = [
      ...Array.from({ length: 9 }, () =>
        runWith([{ id: "t1", status: "passed" as const }]),
      ),
      runWith([{ id: "t1", status: "failed" }]),
    ];
    expect(analyzeHistory(runs).regressing.map((r) => r.id)).toEqual(["t1"]);

    // Move the failure earlier so it's not at the tail — interleave path:
    const runsMixed: NormalizedRun[] = [
      runWith([{ id: "t1", status: "passed" }]),
      runWith([{ id: "t1", status: "failed" }]),
      ...Array.from({ length: 8 }, () =>
        runWith([{ id: "t1", status: "passed" as const }]),
      ),
    ];
    const r = analyzeHistory(runsMixed);
    // 1 fail out of 10 observations; score is below default threshold 0.15
    // → classified as stable (not flaky, not regressing).
    expect(r.flaky).toEqual([]);
    expect(r.regressing).toEqual([]);
    expect(r.stableCount).toBeGreaterThanOrEqual(1);
  });
});

describe("loadHistoryDir + analyzeHistoryDir", () => {
  let dir: string;
  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "ob-flaky-"));
  });
  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  function writeRun(name: string, run: NormalizedRun, mtimeMs: number): void {
    const p = path.join(dir, name);
    fs.writeFileSync(p, JSON.stringify(run));
    fs.utimesSync(p, mtimeMs / 1000, mtimeMs / 1000);
  }

  it("reads JSON files in mtime order", () => {
    writeRun(
      "old.json",
      runWith([{ id: "t1", status: "passed" }]),
      1000,
    );
    writeRun(
      "new.json",
      runWith([{ id: "t1", status: "failed" }]),
      2000,
    );

    const runs = loadHistoryDir(dir);
    expect(runs).toHaveLength(2);
    expect(runs[0]!.tests[0]!.status).toBe("passed"); // oldest first
    expect(runs[1]!.tests[0]!.status).toBe("failed");
  });

  it("analyzeHistoryDir runs end-to-end", () => {
    writeRun("r1.json", runWith([{ id: "t1", status: "passed" }]), 1000);
    writeRun("r2.json", runWith([{ id: "t1", status: "failed" }]), 2000);
    writeRun("r3.json", runWith([{ id: "t1", status: "passed" }]), 3000);
    writeRun("r4.json", runWith([{ id: "t1", status: "failed" }]), 4000);

    const r = analyzeHistoryDir(dir);
    expect(r.flaky.map((f) => f.id)).toEqual(["t1"]);
  });

  it("skips malformed history files with a stderr note", () => {
    writeRun("good.json", runWith([{ id: "t1", status: "passed" }]), 1000);
    fs.writeFileSync(path.join(dir, "bad.json"), "{ not json");
    const runs = loadHistoryDir(dir);
    expect(runs).toHaveLength(1);
  });

  it("throws for a missing directory", () => {
    expect(() => loadHistoryDir(path.join(dir, "nope"))).toThrow(/does not exist/);
  });
});
