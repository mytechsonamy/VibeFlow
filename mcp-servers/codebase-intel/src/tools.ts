import { z } from "zod";
import { scanRepo } from "./scanner.js";
import { findHotspots } from "./hotspots.js";
import { buildImportGraph, findCycles } from "./imports.js";
import { scanDebt } from "./debtscan.js";

export interface ToolDefinition {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  handler: (args: unknown) => Promise<unknown>;
}

const AnalyzeStructureInput = z.object({
  root: z.string().min(1),
});

const FindHotspotsInput = z.object({
  root: z.string().min(1),
  sinceDays: z.number().int().positive().max(3650).optional(),
  limit: z.number().int().positive().max(500).optional(),
});

const DependencyGraphInput = z.object({
  root: z.string().min(1),
  detectCycles: z.boolean().optional(),
});

const TechDebtScanInput = z.object({
  root: z.string().min(1),
  limit: z.number().int().positive().max(5000).optional(),
});

export function buildTools(): ToolDefinition[] {
  return [
    {
      name: "ci_analyze_structure",
      description:
        "Detect languages, frameworks, test runners, and build tools for a " +
        "project root. Every finding carries evidence files; never guess.",
      inputSchema: {
        type: "object",
        properties: {
          root: { type: "string", minLength: 1 },
        },
        required: ["root"],
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = AnalyzeStructureInput.parse(raw);
        return scanRepo(args.root);
      },
    },
    {
      name: "ci_find_hotspots",
      description:
        "Rank files by git churn (commits × lines changed) over a window. " +
        "Returns an empty list for non-git directories rather than failing.",
      inputSchema: {
        type: "object",
        properties: {
          root: { type: "string", minLength: 1 },
          sinceDays: { type: "integer", minimum: 1, maximum: 3650 },
          limit: { type: "integer", minimum: 1, maximum: 500 },
        },
        required: ["root"],
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = FindHotspotsInput.parse(raw);
        return findHotspots(args);
      },
    },
    {
      name: "ci_dependency_graph",
      description:
        "Build the import graph for TS/JS files under a project root. " +
        "Includes internal edges, external package imports, and optional " +
        "cycle detection (Tarjan SCC).",
      inputSchema: {
        type: "object",
        properties: {
          root: { type: "string", minLength: 1 },
          detectCycles: { type: "boolean" },
        },
        required: ["root"],
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = DependencyGraphInput.parse(raw);
        const graph = buildImportGraph(args.root);
        if (args.detectCycles) {
          return { ...graph, cycles: findCycles(graph) };
        }
        return graph;
      },
    },
    {
      name: "ci_tech_debt_scan",
      description:
        "Grep the source tree for TODO/FIXME/HACK/XXX/@deprecated markers. " +
        "Returns findings in the explainability contract shape plus a " +
        "per-marker total.",
      inputSchema: {
        type: "object",
        properties: {
          root: { type: "string", minLength: 1 },
          limit: { type: "integer", minimum: 1, maximum: 5000 },
        },
        required: ["root"],
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = TechDebtScanInput.parse(raw);
        const result = scanDebt(args);
        // Maps aren't JSON-serializable by default; flatten to an object.
        const totalsObj: Record<string, number> = {};
        for (const [k, v] of result.totals) totalsObj[k] = v;
        return { ...result, totals: totalsObj };
      },
    },
  ];
}
