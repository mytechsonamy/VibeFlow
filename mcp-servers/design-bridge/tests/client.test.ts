import { describe, expect, it } from "vitest";
import {
  FigmaClient,
  FigmaClientError,
  FigmaConfigError,
} from "../src/client.js";
import { createMockFetch } from "./_mock-fetch.js";

describe("FigmaClient — config", () => {
  it("throws FigmaConfigError when no token is provided and FIGMA_TOKEN is unset", () => {
    const saved = process.env.FIGMA_TOKEN;
    delete process.env.FIGMA_TOKEN;
    try {
      expect(() => new FigmaClient({ fetchImpl: async () => ({
        ok: true, status: 200, statusText: "OK", text: async () => "{}",
      }) })).toThrow(FigmaConfigError);
    } finally {
      if (saved !== undefined) process.env.FIGMA_TOKEN = saved;
    }
  });

  it("reads token from env when no explicit token is passed", async () => {
    const saved = process.env.FIGMA_TOKEN;
    process.env.FIGMA_TOKEN = "env-token";
    try {
      const mock = createMockFetch({
        "/v1/files/abc": { body: { name: "ok" } },
      });
      const client = new FigmaClient({ fetchImpl: mock.fetch });
      await client.getFile("abc");
      expect(mock.calls).toEqual(["/v1/files/abc"]);
    } finally {
      if (saved === undefined) delete process.env.FIGMA_TOKEN;
      else process.env.FIGMA_TOKEN = saved;
    }
  });
});

describe("FigmaClient — getNodes", () => {
  it("sends the X-Figma-Token header (via injected fetch)", async () => {
    let seenToken: string | undefined;
    const client = new FigmaClient({
      token: "secret",
      fetchImpl: async (_url, init) => {
        seenToken = init?.headers?.["X-Figma-Token"];
        return {
          ok: true,
          status: 200,
          statusText: "OK",
          text: async () => JSON.stringify({ nodes: {} }),
        };
      },
    });
    await client.getNodes("abc", ["1:2"]);
    expect(seenToken).toBe("secret");
  });

  it("wraps non-2xx responses in FigmaClientError with status and path", async () => {
    const mock = createMockFetch({
      "/v1/files/abc/nodes?ids=1%3A2": {
        status: 403,
        statusText: "Forbidden",
        rawBody: "Invalid token",
      },
    });
    const client = new FigmaClient({ token: "x", fetchImpl: mock.fetch });
    await expect(client.getNodes("abc", ["1:2"])).rejects.toMatchObject({
      name: "FigmaClientError",
      status: 403,
    });
  });

  it("wraps transport failures in FigmaClientError", async () => {
    const mock = createMockFetch({
      "/v1/files/abc/nodes?ids=1%3A2": { throwTransport: true },
    });
    const client = new FigmaClient({ token: "x", fetchImpl: mock.fetch });
    await expect(client.getNodes("abc", ["1:2"])).rejects.toBeInstanceOf(
      FigmaClientError,
    );
  });

  it("wraps invalid JSON responses", async () => {
    const mock = createMockFetch({
      "/v1/files/abc/nodes?ids=1%3A2": { rawBody: "not json" },
    });
    const client = new FigmaClient({ token: "x", fetchImpl: mock.fetch });
    await expect(client.getNodes("abc", ["1:2"])).rejects.toThrowError(
      /not valid JSON/,
    );
  });

  it("rejects empty fileKey or empty node list", async () => {
    const client = new FigmaClient({
      token: "x",
      fetchImpl: async () => ({
        ok: true, status: 200, statusText: "OK", text: async () => "{}",
      }),
    });
    await expect(client.getNodes("", ["1:2"])).rejects.toBeInstanceOf(
      FigmaClientError,
    );
    await expect(client.getNodes("abc", [])).rejects.toBeInstanceOf(
      FigmaClientError,
    );
  });

  // -----------------------------------------------------------------------
  // Offline / network-failure paths (S4-08).
  // The Figma MCP must produce a clear, classified error when the
  // network layer fails (ECONNREFUSED, DNS failure, transport reset)
  // — NOT a generic TypeError leaking through the fetch boundary.
  // -----------------------------------------------------------------------

  describe("offline / network failure", () => {
    it("wraps ECONNREFUSED into FigmaClientError with transport hint", async () => {
      const client = new FigmaClient({
        token: "x",
        fetchImpl: async () => {
          const err = new Error("connect ECONNREFUSED 127.0.0.1:443");
          (err as { code?: string }).code = "ECONNREFUSED";
          throw err;
        },
      });
      await expect(client.getNodes("abc", ["1:2"])).rejects.toThrow(
        /transport|ECONNREFUSED/,
      );
    });

    it("wraps DNS failure (ENOTFOUND) into FigmaClientError", async () => {
      const client = new FigmaClient({
        token: "x",
        fetchImpl: async () => {
          const err = new Error("getaddrinfo ENOTFOUND api.figma.com");
          (err as { code?: string }).code = "ENOTFOUND";
          throw err;
        },
      });
      await expect(client.getNodes("abc", ["1:2"])).rejects.toThrow(
        /transport|ENOTFOUND/,
      );
    });

    it("wraps abrupt connection reset into FigmaClientError", async () => {
      const client = new FigmaClient({
        token: "x",
        fetchImpl: async () => {
          throw new Error("socket hang up");
        },
      });
      await expect(client.getNodes("abc", ["1:2"])).rejects.toThrow(
        /transport|socket/,
      );
    });
  });
});
