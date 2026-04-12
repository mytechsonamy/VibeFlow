import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { z } from "zod";
import { buildTools, ToolDefinition } from "../src/tools.js";
import { createMockFetch } from "./_mock-fetch.js";

function byName(tools: ToolDefinition[], name: string): ToolDefinition {
  const t = tools.find((x) => x.name === name);
  if (!t) throw new Error(`tool ${name} not registered`);
  return t;
}

function figmaDocResponse(nodeId: string, doc: Record<string, unknown>): unknown {
  return { nodes: { [nodeId]: { document: doc } } };
}

describe("MCP tool handlers", () => {
  it("registers the expected four tools", () => {
    const tools = buildTools({ token: "x", fetchImpl: createMockFetch({}).fetch });
    const names = tools.map((t) => t.name).sort();
    expect(names).toEqual([
      "db_compare_impl",
      "db_extract_tokens",
      "db_fetch_design",
      "db_generate_styles",
    ]);
  });

  it("db_fetch_design returns flattened frames", async () => {
    const mock = createMockFetch({
      "/v1/files/KEY/nodes?ids=1%3A2": {
        body: figmaDocResponse("1:2", {
          id: "1:2",
          name: "Home",
          type: "FRAME",
          children: [{ id: "3:4", name: "Button", type: "INSTANCE" }],
        }),
      },
    });
    const tools = buildTools({ token: "x", fetchImpl: mock.fetch });
    const r = (await byName(tools, "db_fetch_design").handler({
      fileKey: "KEY",
      nodeId: "1:2",
    })) as { frames: Array<{ id: string }> };
    expect(r.frames.map((f) => f.id)).toEqual(["1:2", "3:4"]);
  });

  it("db_fetch_design rejects missing url/fileKey via Zod", async () => {
    const tools = buildTools({ token: "x", fetchImpl: createMockFetch({}).fetch });
    await expect(byName(tools, "db_fetch_design").handler({})).rejects.toBeInstanceOf(
      z.ZodError,
    );
  });

  it("db_extract_tokens walks the node tree and returns tokens", async () => {
    const mock = createMockFetch({
      "/v1/files/KEY/nodes?ids=1%3A2": {
        body: figmaDocResponse("1:2", {
          id: "1:2",
          type: "FRAME",
          fills: [{ type: "SOLID", color: { r: 1, g: 0, b: 0, a: 1 } }],
          children: [
            {
              id: "3:4",
              style: { fontFamily: "Inter", fontSize: 14 },
            },
          ],
        }),
      },
    });
    const tools = buildTools({ token: "x", fetchImpl: mock.fetch });
    const r = (await byName(tools, "db_extract_tokens").handler({
      fileKey: "KEY",
      nodeId: "1:2",
    })) as {
      colors: Array<{ hex: string }>;
      typography: Array<{ fontFamily: string }>;
    };
    expect(r.colors[0]!.hex).toBe("#ff0000ff");
    expect(r.typography[0]!.fontFamily).toBe("Inter");
  });

  it("db_generate_styles returns tokens + css + tailwind", async () => {
    const mock = createMockFetch({
      "/v1/files/KEY/nodes?ids=1%3A2": {
        body: figmaDocResponse("1:2", {
          id: "1:2",
          type: "FRAME",
          fills: [{ type: "SOLID", color: { r: 0, g: 0, b: 1, a: 1 } }],
        }),
      },
    });
    const tools = buildTools({ token: "x", fetchImpl: mock.fetch });
    const r = (await byName(tools, "db_generate_styles").handler({
      fileKey: "KEY",
      nodeId: "1:2",
    })) as { css: string; tailwind: string; tokens: { colors: unknown[] } };
    expect(r.css).toContain("--color-1: #0000ffff;");
    expect(r.tailwind).toContain("module.exports");
    expect(r.tokens.colors).toHaveLength(1);
  });

  it("db_compare_impl returns a verdict + byte delta", async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "db-tools-"));
    try {
      const p = path.join(dir, "a.bin");
      const q = path.join(dir, "b.bin");
      fs.writeFileSync(p, Buffer.from([1, 2, 3]));
      fs.writeFileSync(q, Buffer.from([1, 2, 3]));
      const tools = buildTools({ token: "x", fetchImpl: createMockFetch({}).fetch });
      const r = (await byName(tools, "db_compare_impl").handler({
        leftPath: p,
        rightPath: q,
      })) as { verdict: string };
      expect(r.verdict).toBe("identical");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("db_compare_impl rejects empty paths via Zod", async () => {
    const tools = buildTools({ token: "x", fetchImpl: createMockFetch({}).fetch });
    await expect(
      byName(tools, "db_compare_impl").handler({ leftPath: "", rightPath: "x" }),
    ).rejects.toBeInstanceOf(z.ZodError);
  });
});
