import { describe, expect, it } from "vitest";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { createServer } from "../src/server.js";
import { vitestReport } from "./_fixtures.js";

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
  it("list_tools returns the four observability tools", async () => {
    const { server } = createServer();
    const r = (await invoke(server, ListToolsRequestSchema, {})) as {
      tools: { name: string }[];
    };
    expect(r.tools.map((t) => t.name).sort()).toEqual([
      "ob_collect_metrics",
      "ob_health_dashboard",
      "ob_perf_trend",
      "ob_track_flaky",
    ]);
  });

  it("call_tool executes ob_collect_metrics with an inline payload", async () => {
    const { server } = createServer();
    const payload = vitestReport({
      cases: [{ title: "t", status: "passed", duration: 10 }],
    });
    const r = (await invoke(server, CallToolRequestSchema, {
      name: "ob_collect_metrics",
      arguments: { payload },
    })) as { content: { type: string; text: string }[] };
    expect(r.content[0]!.type).toBe("text");
    const parsed = JSON.parse(r.content[0]!.text);
    expect(parsed.metrics.passed).toBe(1);
  });

  it("call_tool returns isError=true for an unknown tool", async () => {
    const { server } = createServer();
    const r = (await invoke(server, CallToolRequestSchema, {
      name: "ob_not_a_tool",
      arguments: {},
    })) as { isError: boolean; content: { text: string }[] };
    expect(r.isError).toBe(true);
    expect(r.content[0]!.text).toMatch(/Unknown tool/);
  });

  it("call_tool wraps parser errors in isError=true", async () => {
    const { server } = createServer();
    const r = (await invoke(server, CallToolRequestSchema, {
      name: "ob_collect_metrics",
      arguments: { payload: { not: "a reporter" } },
    })) as { isError: boolean };
    expect(r.isError).toBe(true);
  });

  it("createServer accepts custom name/version", () => {
    const { server } = createServer({ name: "custom", version: "9.9.9" });
    // biome-ignore lint/suspicious/noExplicitAny: SDK internals
    const info = (server as any)._serverInfo;
    expect(info.name).toBe("custom");
    expect(info.version).toBe("9.9.9");
  });
});
