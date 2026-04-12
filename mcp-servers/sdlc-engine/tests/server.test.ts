import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { SqliteStateStore } from "../src/state/sqlite.js";
import { createServer } from "../src/server.js";

// The MCP SDK Server doesn't expose a public request-dispatch method, so we
// reach into the internal handler map. This keeps the test focused on the
// dispatch logic in server.ts without spinning up a full stdio transport.
function invoke(
  // biome-ignore lint/suspicious/noExplicitAny: reaching into SDK internals
  server: any,
  // biome-ignore lint/suspicious/noExplicitAny: reaching into SDK internals
  schema: any,
  params: unknown,
) {
  const method = schema.shape.method.value;
  const handler = server._requestHandlers.get(method);
  if (!handler) throw new Error(`no handler for ${method}`);
  return handler({ method, params }, { signal: new AbortController().signal });
}

describe("createServer — MCP request dispatch", () => {
  let tmpDir: string;
  let store: SqliteStateStore;

  beforeEach(async () => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sdlc-engine-srv-"));
    store = new SqliteStateStore(path.join(tmpDir, "state.db"));
    await store.init();
  });

  afterEach(async () => {
    await store.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("list_tools returns the registered tool names", async () => {
    const { server } = createServer({ store });
    const result = (await invoke(server, ListToolsRequestSchema, {})) as {
      tools: { name: string }[];
    };
    const names = result.tools.map((t) => t.name).sort();
    expect(names).toEqual([
      "sdlc_advance_phase",
      "sdlc_get_state",
      "sdlc_list_phases",
      "sdlc_record_consensus",
      "sdlc_satisfy_criterion",
    ]);
  });

  it("call_tool executes a valid tool and returns JSON text content", async () => {
    const { server } = createServer({ store });
    const result = (await invoke(server, CallToolRequestSchema, {
      name: "sdlc_get_state",
      arguments: { projectId: "p1" },
    })) as { content: { type: string; text: string }[] };
    expect(result.content[0]!.type).toBe("text");
    const parsed = JSON.parse(result.content[0]!.text);
    expect(parsed.currentPhase).toBe("REQUIREMENTS");
  });

  it("call_tool returns isError=true for an unknown tool name", async () => {
    const { server } = createServer({ store });
    const result = (await invoke(server, CallToolRequestSchema, {
      name: "not_a_tool",
      arguments: {},
    })) as { isError: boolean; content: { text: string }[] };
    expect(result.isError).toBe(true);
    expect(result.content[0]!.text).toMatch(/Unknown tool/);
  });

  it("call_tool wraps Zod validation errors in isError=true", async () => {
    const { server } = createServer({ store });
    const result = (await invoke(server, CallToolRequestSchema, {
      name: "sdlc_get_state",
      arguments: { projectId: "" },
    })) as { isError: boolean; content: { text: string }[] };
    expect(result.isError).toBe(true);
    expect(typeof result.content[0]!.text).toBe("string");
  });

  it("createServer accepts a custom name/version", () => {
    const { server } = createServer({
      store,
      name: "custom-name",
      version: "9.9.9",
    });
    // biome-ignore lint/suspicious/noExplicitAny: SDK internals
    const info = (server as any)._serverInfo;
    expect(info.name).toBe("custom-name");
    expect(info.version).toBe("9.9.9");
  });
});
