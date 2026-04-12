import { describe, expect, it } from "vitest";
import {
  parseFigmaUrl,
  normalizeNodeId,
  flattenFrames,
  fetchDesign,
  FigmaNode,
} from "../src/frames.js";
import { FigmaClient } from "../src/client.js";
import { createMockFetch } from "./_mock-fetch.js";

describe("parseFigmaUrl", () => {
  it("parses /file/<KEY>/<title>?node-id=", () => {
    const r = parseFigmaUrl("https://www.figma.com/file/ABC123/MyFile?node-id=12-345");
    expect(r).toEqual({ fileKey: "ABC123", nodeId: "12:345" });
  });

  it("parses the newer /design/<KEY>/ path", () => {
    const r = parseFigmaUrl("https://www.figma.com/design/XYZ789/Title?node-id=7-8");
    expect(r).toEqual({ fileKey: "XYZ789", nodeId: "7:8" });
  });

  it("returns null node id when the URL has no ?node-id=", () => {
    const r = parseFigmaUrl("https://figma.com/file/KEY/Title");
    expect(r.fileKey).toBe("KEY");
    expect(r.nodeId).toBeNull();
  });

  it("rejects non-figma hosts", () => {
    expect(() => parseFigmaUrl("https://example.com/file/KEY/T")).toThrow();
  });

  it("rejects unknown path kinds", () => {
    expect(() => parseFigmaUrl("https://figma.com/community/KEY/T")).toThrow(
      /must start with \/file\/ or \/design\//,
    );
  });

  it("rejects URLs without a file key", () => {
    expect(() => parseFigmaUrl("https://figma.com/file/")).toThrow(/missing a file key/);
  });
});

describe("normalizeNodeId", () => {
  it("converts dashes to colons", () => {
    expect(normalizeNodeId("12-345")).toBe("12:345");
  });

  it("leaves already-normalized ids alone", () => {
    expect(normalizeNodeId("12:345")).toBe("12:345");
  });
});

describe("flattenFrames", () => {
  it("BFS flattens nested children with depth labels", () => {
    const root: FigmaNode = {
      id: "0:0",
      name: "Root",
      type: "FRAME",
      absoluteBoundingBox: { width: 100, height: 200 },
      children: [
        {
          id: "1:1",
          name: "Child",
          type: "FRAME",
          absoluteBoundingBox: { width: 50, height: 50 },
          children: [
            { id: "2:2", name: "Grandchild", type: "TEXT" },
          ],
        },
      ],
    };
    const flat = flattenFrames(root, 0);
    expect(flat).toHaveLength(3);
    expect(flat[0]!.depth).toBe(0);
    expect(flat[1]!.depth).toBe(1);
    expect(flat[2]!.depth).toBe(2);
    expect(flat[0]!.childCount).toBe(1);
  });

  it("records absolute bounding box dimensions when present", () => {
    const root: FigmaNode = {
      id: "0:0",
      absoluteBoundingBox: { width: 42, height: 24 },
    };
    const flat = flattenFrames(root, 0);
    expect(flat[0]!.width).toBe(42);
    expect(flat[0]!.height).toBe(24);
  });
});

describe("fetchDesign (integration with mocked client)", () => {
  it("resolves (fileKey, nodeId) from a URL and flattens the document", async () => {
    const mock = createMockFetch({
      "/v1/files/FKEY/nodes?ids=1%3A2": {
        body: {
          nodes: {
            "1:2": {
              document: {
                id: "1:2",
                name: "Frame",
                type: "FRAME",
                children: [{ id: "3:4", name: "Text", type: "TEXT" }],
              },
            },
          },
        },
      },
    });
    const client = new FigmaClient({ token: "t", fetchImpl: mock.fetch });
    const r = await fetchDesign(client, {
      url: "https://figma.com/file/FKEY/T?node-id=1-2",
    });
    expect(r.fileKey).toBe("FKEY");
    expect(r.nodeId).toBe("1:2");
    expect(r.frames.map((f) => f.id)).toEqual(["1:2", "3:4"]);
  });

  it("errors clearly when figma returns no document for the requested node", async () => {
    const mock = createMockFetch({
      "/v1/files/FKEY/nodes?ids=9%3A9": {
        body: { nodes: { "9:9": { err: "not found" } } },
      },
    });
    const client = new FigmaClient({ token: "t", fetchImpl: mock.fetch });
    await expect(
      fetchDesign(client, { fileKey: "FKEY", nodeId: "9:9" }),
    ).rejects.toThrowError(/no document for node 9:9.*not found/);
  });

  it("requires either url or fileKey", async () => {
    const mock = createMockFetch({});
    const client = new FigmaClient({ token: "t", fetchImpl: mock.fetch });
    await expect(fetchDesign(client, {})).rejects.toThrowError(
      /url or a fileKey/,
    );
  });
});
