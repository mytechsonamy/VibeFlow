import { describe, expect, it } from "vitest";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { createServer } from "../src/server.js";
import { createMockFetch } from "./_mock-fetch.js";

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
  it("list_tools returns the five dev-ops tools", async () => {
    const { server } = createServer({
      token: "x",
      fetchImpl: createMockFetch({}).fetch,
    });
    const r = (await invoke(server, ListToolsRequestSchema, {})) as {
      tools: { name: string }[];
    };
    expect(r.tools.map((t) => t.name).sort()).toEqual([
      "do_deploy_staging",
      "do_fetch_artifacts",
      "do_pipeline_status",
      "do_rollback",
      "do_trigger_pipeline",
    ]);
  });

  it("call_tool executes a valid tool and returns JSON text content", async () => {
    const mock = createMockFetch({
      "POST /repos/o/r/actions/workflows/ci.yml/dispatches": { rawBody: "" },
    });
    const { server } = createServer({
      token: "x",
      fetchImpl: mock.fetch,
    });
    const r = (await invoke(server, CallToolRequestSchema, {
      name: "do_trigger_pipeline",
      arguments: {
        owner: "o",
        repo: "r",
        workflow: "ci.yml",
        ref: "main",
      },
    })) as { content: { type: string; text: string }[] };
    expect(r.content[0]!.type).toBe("text");
    const parsed = JSON.parse(r.content[0]!.text);
    expect(parsed.accepted).toBe(true);
    expect(parsed.provider).toBe("github");
  });

  it("call_tool returns isError=true for an unknown tool", async () => {
    const { server } = createServer({
      token: "x",
      fetchImpl: createMockFetch({}).fetch,
    });
    const r = (await invoke(server, CallToolRequestSchema, {
      name: "do_not_a_tool",
      arguments: {},
    })) as { isError: boolean; content: { text: string }[] };
    expect(r.isError).toBe(true);
    expect(r.content[0]!.text).toMatch(/Unknown tool/);
  });

  it("call_tool wraps CI transport errors into isError=true", async () => {
    const mock = createMockFetch({
      "POST /repos/o/r/actions/workflows/ci.yml/dispatches": {
        throwTransport: true,
      },
    });
    const { server } = createServer({ token: "x", fetchImpl: mock.fetch });
    const r = (await invoke(server, CallToolRequestSchema, {
      name: "do_trigger_pipeline",
      arguments: {
        owner: "o",
        repo: "r",
        workflow: "ci.yml",
        ref: "main",
      },
    })) as { isError: boolean; content: { text: string }[] };
    expect(r.isError).toBe(true);
    expect(r.content[0]!.text).toMatch(/transport/);
  });

  it("call_tool wraps GitHub 4xx into isError=true with status visible", async () => {
    const mock = createMockFetch({
      "POST /repos/o/r/actions/workflows/ci.yml/dispatches": {
        status: 404,
        statusText: "Not Found",
        rawBody: "no such workflow",
      },
    });
    const { server } = createServer({ token: "x", fetchImpl: mock.fetch });
    const r = (await invoke(server, CallToolRequestSchema, {
      name: "do_trigger_pipeline",
      arguments: {
        owner: "o",
        repo: "r",
        workflow: "ci.yml",
        ref: "main",
      },
    })) as { isError: boolean; content: { text: string }[] };
    expect(r.isError).toBe(true);
    expect(r.content[0]!.text).toMatch(/404/);
  });

  it("createServer accepts custom name/version", () => {
    const { server } = createServer({
      token: "x",
      fetchImpl: createMockFetch({}).fetch,
      name: "custom",
      version: "9.9.9",
    });
    // biome-ignore lint/suspicious/noExplicitAny: SDK internals
    const info = (server as any)._serverInfo;
    expect(info.name).toBe("custom");
    expect(info.version).toBe("9.9.9");
  });
});
