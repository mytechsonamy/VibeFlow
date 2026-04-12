import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { z } from "zod";
import { buildTools, ToolDefinition } from "../src/tools.js";

function byName(tools: ToolDefinition[], name: string): ToolDefinition {
  const t = tools.find((x) => x.name === name);
  if (!t) throw new Error(`tool ${name} not registered`);
  return t;
}

function write(file: string, content: string): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}

describe("MCP tool handlers", () => {
  let dir: string;
  let tools: ToolDefinition[];

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "ci-tools-"));
    tools = buildTools();
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("registers the expected four tools", () => {
    const names = tools.map((t) => t.name).sort();
    expect(names).toEqual([
      "ci_analyze_structure",
      "ci_dependency_graph",
      "ci_find_hotspots",
      "ci_tech_debt_scan",
    ]);
  });

  it("ci_analyze_structure returns a ScanResult for a package.json project", async () => {
    write(
      path.join(dir, "package.json"),
      JSON.stringify({ name: "x", dependencies: { fastify: "^4.0.0" } }),
    );
    const res = (await byName(tools, "ci_analyze_structure").handler({
      root: dir,
    })) as { frameworks: { name: string }[] };
    expect(res.frameworks.some((f) => f.name === "fastify")).toBe(true);
  });

  it("ci_analyze_structure rejects empty root via Zod", async () => {
    await expect(
      byName(tools, "ci_analyze_structure").handler({ root: "" }),
    ).rejects.toBeInstanceOf(z.ZodError);
  });

  it("ci_find_hotspots returns an empty file list for a non-git directory", async () => {
    const res = (await byName(tools, "ci_find_hotspots").handler({
      root: dir,
    })) as { files: unknown[] };
    expect(res.files).toEqual([]);
  });

  it("ci_find_hotspots rejects sinceDays=0 via Zod", async () => {
    await expect(
      byName(tools, "ci_find_hotspots").handler({ root: dir, sinceDays: 0 }),
    ).rejects.toBeInstanceOf(z.ZodError);
  });

  it("ci_dependency_graph returns a graph and (when requested) cycles", async () => {
    write(path.join(dir, "a.ts"), 'import "./b";');
    write(path.join(dir, "b.ts"), 'import "./a";');

    const base = (await byName(tools, "ci_dependency_graph").handler({
      root: dir,
    })) as { edges: unknown[]; cycles?: unknown };
    expect(base.edges.length).toBe(2);
    expect(base.cycles).toBeUndefined();

    const withCycles = (await byName(tools, "ci_dependency_graph").handler({
      root: dir,
      detectCycles: true,
    })) as { cycles: string[][] };
    expect(withCycles.cycles.length).toBe(1);
  });

  it("ci_tech_debt_scan returns findings with a plain-object totals map", async () => {
    write(path.join(dir, "a.ts"), "// TODO: one\n// FIXME: two\n");
    const res = (await byName(tools, "ci_tech_debt_scan").handler({
      root: dir,
    })) as { findings: unknown[]; totals: Record<string, number> };
    expect(res.findings.length).toBe(2);
    expect(res.totals.TODO).toBe(1);
    expect(res.totals.FIXME).toBe(1);
  });

  it("ci_tech_debt_scan rejects limit=0 via Zod", async () => {
    await expect(
      byName(tools, "ci_tech_debt_scan").handler({ root: dir, limit: 0 }),
    ).rejects.toBeInstanceOf(z.ZodError);
  });
});
