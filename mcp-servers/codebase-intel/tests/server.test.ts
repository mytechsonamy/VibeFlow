import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { createServer } from "../src/server.js";

function invoke(
  // biome-ignore lint/suspicious/noExplicitAny: SDK internals
  server: any,
  // biome-ignore lint/suspicious/noExplicitAny: SDK internals
  schema: any,
  params: unknown,
) {
  const method = schema.shape.method.value;
  const handler = server._requestHandlers.get(method);
  if (!handler) throw new Error(`no handler for ${method}`);
  return handler({ method, params }, { signal: new AbortController().signal });
}

describe("createServer — MCP request dispatch", () => {
  let dir: string;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "ci-srv-"));
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("list_tools returns all four tool names", async () => {
    const { server } = createServer();
    const result = (await invoke(server, ListToolsRequestSchema, {})) as {
      tools: { name: string }[];
    };
    const names = result.tools.map((t) => t.name).sort();
    expect(names).toEqual([
      "ci_analyze_structure",
      "ci_dependency_graph",
      "ci_find_hotspots",
      "ci_tech_debt_scan",
    ]);
  });

  it("call_tool executes analyze_structure and returns JSON text", async () => {
    fs.writeFileSync(
      path.join(dir, "package.json"),
      JSON.stringify({ name: "x" }),
    );
    const { server } = createServer();
    const result = (await invoke(server, CallToolRequestSchema, {
      name: "ci_analyze_structure",
      arguments: { root: dir },
    })) as { content: { type: string; text: string }[] };
    expect(result.content[0]!.type).toBe("text");
    const parsed = JSON.parse(result.content[0]!.text);
    expect(parsed.languages[0]!.name).toBe("javascript");
  });

  it("call_tool returns isError=true for an unknown tool", async () => {
    const { server } = createServer();
    const result = (await invoke(server, CallToolRequestSchema, {
      name: "ci_not_a_tool",
      arguments: {},
    })) as { isError: boolean; content: { text: string }[] };
    expect(result.isError).toBe(true);
    expect(result.content[0]!.text).toMatch(/Unknown tool/);
  });

  it("call_tool wraps Zod validation errors in isError=true", async () => {
    const { server } = createServer();
    const result = (await invoke(server, CallToolRequestSchema, {
      name: "ci_analyze_structure",
      arguments: { root: "" },
    })) as { isError: boolean };
    expect(result.isError).toBe(true);
  });

  it("createServer accepts custom name/version", () => {
    const { server } = createServer({ name: "custom", version: "9.9.9" });
    // biome-ignore lint/suspicious/noExplicitAny: SDK internals
    const info = (server as any)._serverInfo;
    expect(info.name).toBe("custom");
    expect(info.version).toBe("9.9.9");
  });
});
