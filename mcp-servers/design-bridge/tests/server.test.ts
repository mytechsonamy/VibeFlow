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
  it("list_tools returns the four design-bridge tools", async () => {
    const { server } = createServer({
      token: "x",
      fetchImpl: createMockFetch({}).fetch,
    });
    const r = (await invoke(server, ListToolsRequestSchema, {})) as {
      tools: { name: string }[];
    };
    expect(r.tools.map((t) => t.name).sort()).toEqual([
      "db_compare_impl",
      "db_extract_tokens",
      "db_fetch_design",
      "db_generate_styles",
    ]);
  });

  it("call_tool returns isError=true for unknown tool", async () => {
    const { server } = createServer({
      token: "x",
      fetchImpl: createMockFetch({}).fetch,
    });
    const r = (await invoke(server, CallToolRequestSchema, {
      name: "db_nope",
      arguments: {},
    })) as { isError: boolean; content: { text: string }[] };
    expect(r.isError).toBe(true);
    expect(r.content[0]!.text).toMatch(/Unknown tool/);
  });

  it("call_tool wraps Figma transport errors into isError=true", async () => {
    const mock = createMockFetch({
      "/v1/files/K/nodes?ids=1%3A2": { throwTransport: true },
    });
    const { server } = createServer({ token: "x", fetchImpl: mock.fetch });
    const r = (await invoke(server, CallToolRequestSchema, {
      name: "db_fetch_design",
      arguments: { fileKey: "K", nodeId: "1:2" },
    })) as { isError: boolean; content: { text: string }[] };
    expect(r.isError).toBe(true);
    expect(r.content[0]!.text).toMatch(/transport/);
  });

  it("call_tool wraps Figma 4xx into isError=true with status visible", async () => {
    const mock = createMockFetch({
      "/v1/files/K/nodes?ids=1%3A2": {
        status: 401,
        statusText: "Unauthorized",
        rawBody: "bad token",
      },
    });
    const { server } = createServer({ token: "x", fetchImpl: mock.fetch });
    const r = (await invoke(server, CallToolRequestSchema, {
      name: "db_fetch_design",
      arguments: { fileKey: "K", nodeId: "1:2" },
    })) as { isError: boolean; content: { text: string }[] };
    expect(r.isError).toBe(true);
    expect(r.content[0]!.text).toMatch(/401/);
  });

  it("createServer accepts custom name/version", () => {
    const { server } = createServer({
      token: "x",
      fetchImpl: createMockFetch({}).fetch,
      name: "x",
      version: "9.9.9",
    });
    // biome-ignore lint/suspicious/noExplicitAny: SDK internals
    const info = (server as any)._serverInfo;
    expect(info.name).toBe("x");
    expect(info.version).toBe("9.9.9");
  });
});
