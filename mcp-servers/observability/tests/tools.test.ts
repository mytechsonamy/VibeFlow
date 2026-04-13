import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { z } from "zod";
import { buildTools, ToolDefinition } from "../src/tools.js";
import { vitestReport, mkRun, mkTest } from "./_fixtures.js";
import { NormalizedRun, ReporterParseError } from "../src/parsers.js";

function byName(tools: ToolDefinition[], name: string): ToolDefinition {
  const t = tools.find((x) => x.name === name);
  if (!t) throw new Error(`tool ${name} not registered`);
  return t;
}

describe("MCP tool handlers", () => {
  it("registers the expected four tools", () => {
    const tools = buildTools();
    const names = tools.map((t) => t.name).sort();
    expect(names).toEqual([
      "ob_collect_metrics",
      "ob_health_dashboard",
      "ob_perf_trend",
      "ob_track_flaky",
    ]);
  });

  describe("ob_collect_metrics", () => {
    it("accepts an inline payload and returns run + metrics", async () => {
      const tools = buildTools();
      const payload = vitestReport({
        cases: [
          { title: "happy", status: "passed", duration: 10 },
          { title: "sad", status: "failed", duration: 20, message: "boom" },
        ],
      });
      const result = (await byName(tools, "ob_collect_metrics").handler({
        payload,
      })) as { metrics: { passed: number; failed: number } };
      expect(result.metrics.passed).toBe(1);
      expect(result.metrics.failed).toBe(1);
    });

    it("accepts a reporterPath and round-trips through the file", async () => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ob-tools-"));
      try {
        const p = path.join(dir, "report.json");
        fs.writeFileSync(
          p,
          JSON.stringify(
            vitestReport({ cases: [{ title: "t", status: "passed" }] }),
          ),
        );
        const tools = buildTools();
        const r = (await byName(tools, "ob_collect_metrics").handler({
          reporterPath: p,
        })) as { metrics: { passed: number } };
        expect(r.metrics.passed).toBe(1);
      } finally {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    });

    it("rejects input missing both reporterPath and payload via Zod", async () => {
      const tools = buildTools();
      await expect(
        byName(tools, "ob_collect_metrics").handler({}),
      ).rejects.toBeInstanceOf(z.ZodError);
    });
  });

  describe("ob_track_flaky", () => {
    it("accepts an inline runs array and classifies a flaky test", async () => {
      const runs: NormalizedRun[] = [
        mkRun([mkTest({ id: "t1", status: "passed" })]),
        mkRun([mkTest({ id: "t1", status: "failed" })]),
        mkRun([mkTest({ id: "t1", status: "passed" })]),
        mkRun([mkTest({ id: "t1", status: "failed" })]),
      ];
      const tools = buildTools();
      const r = (await byName(tools, "ob_track_flaky").handler({
        runs,
      })) as { flaky: Array<{ id: string }> };
      expect(r.flaky.map((f) => f.id)).toEqual(["t1"]);
    });

    it("rejects missing historyDir + missing runs via Zod", async () => {
      const tools = buildTools();
      await expect(
        byName(tools, "ob_track_flaky").handler({}),
      ).rejects.toBeInstanceOf(z.ZodError);
    });
  });

  describe("ob_perf_trend", () => {
    it("returns insufficient-data for a single run", async () => {
      const tools = buildTools();
      const r = (await byName(tools, "ob_perf_trend").handler({
        runs: [mkRun([mkTest({ id: "t1" })])],
      })) as { overall: { direction: string } };
      expect(r.overall.direction).toBe("insufficient-data");
    });

    it("flags a 2× slowdown as a slowdown regression", async () => {
      const tools = buildTools();
      const runs = [
        mkRun([mkTest({ id: "t1", durationMs: 10 })], { totalDurationMs: 10 }),
        mkRun([mkTest({ id: "t1", durationMs: 10 })], { totalDurationMs: 10 }),
        mkRun([mkTest({ id: "t1", durationMs: 10 })], { totalDurationMs: 10 }),
        mkRun([mkTest({ id: "t1", durationMs: 20 })], { totalDurationMs: 20 }),
      ];
      const r = (await byName(tools, "ob_perf_trend").handler({ runs })) as {
        overall: { direction: string; regression: boolean };
      };
      expect(r.overall.direction).toBe("slowdown");
      expect(r.overall.regression).toBe(true);
    });
  });

  describe("ob_health_dashboard", () => {
    it("returns a compact health grade", async () => {
      const tools = buildTools();
      const runs = [
        mkRun([mkTest({ id: "t1", status: "passed", durationMs: 10 })]),
        mkRun([mkTest({ id: "t1", status: "passed", durationMs: 10 })]),
      ];
      const r = (await byName(tools, "ob_health_dashboard").handler({
        runs,
      })) as { grade: string; totalRuns: number };
      expect(r.grade).toBe("green");
      expect(r.totalRuns).toBe(2);
    });
  });

  // -------------------------------------------------------------------------
  // loadPayload / loadRuns error branches — exercised via the public tool
  // handlers. Driven by coverage-gap analysis in tools.ts (S4-01).
  // -------------------------------------------------------------------------

  describe("ob_collect_metrics error branches", () => {
    it("raises ReporterParseError when reporterPath does not exist", async () => {
      const tools = buildTools();
      await expect(
        byName(tools, "ob_collect_metrics").handler({
          reporterPath: "/does-not-exist-vf.json",
        }),
      ).rejects.toBeInstanceOf(ReporterParseError);
    });

    it("raises ReporterParseError when reporterPath is not valid JSON", async () => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ob-tools-bad-"));
      try {
        const p = path.join(dir, "bad.json");
        fs.writeFileSync(p, "{not-json");
        const tools = buildTools();
        await expect(
          byName(tools, "ob_collect_metrics").handler({ reporterPath: p }),
        ).rejects.toBeInstanceOf(ReporterParseError);
      } finally {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    });
  });

  describe("ob_track_flaky inline run shapes", () => {
    it("trusts pre-normalized runs in the inline array", async () => {
      const tools = buildTools();
      const pre: NormalizedRun[] = [
        mkRun([mkTest({ id: "t1", status: "passed" })]),
        mkRun([mkTest({ id: "t1", status: "failed" })]),
        mkRun([mkTest({ id: "t1", status: "passed" })]),
        mkRun([mkTest({ id: "t1", status: "failed" })]),
      ];
      const r = (await byName(tools, "ob_track_flaky").handler({
        runs: pre,
      })) as { flaky: unknown[] };
      expect(Array.isArray(r.flaky)).toBe(true);
    });

    it("parses raw reporter payloads passed in the inline array", async () => {
      const tools = buildTools();
      const raw = [
        vitestReport({ cases: [{ title: "t1", status: "passed" }] }),
        vitestReport({ cases: [{ title: "t1", status: "failed" }] }),
        vitestReport({ cases: [{ title: "t1", status: "passed" }] }),
        vitestReport({ cases: [{ title: "t1", status: "failed" }] }),
      ];
      const r = (await byName(tools, "ob_track_flaky").handler({
        runs: raw,
      })) as { flaky: unknown[] };
      expect(Array.isArray(r.flaky)).toBe(true);
    });

    it("reads pre-normalized runs from historyDir when inline runs is not supplied", async () => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ob-hist-"));
      try {
        const runs: NormalizedRun[] = [
          mkRun([mkTest({ id: "t1", status: "passed" })]),
          mkRun([mkTest({ id: "t1", status: "failed" })]),
          mkRun([mkTest({ id: "t1", status: "passed" })]),
          mkRun([mkTest({ id: "t1", status: "failed" })]),
        ];
        runs.forEach((r, i) => {
          fs.writeFileSync(
            path.join(dir, `run-${i}.json`),
            JSON.stringify(r),
          );
        });
        const tools = buildTools();
        const r = (await byName(tools, "ob_track_flaky").handler({
          historyDir: dir,
        })) as { flaky: Array<{ id: string }> };
        expect(r.flaky.map((f) => f.id)).toContain("t1");
      } finally {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    });
  });
});
