import { describe, expect, it } from "vitest";
import {
  createGithubClient,
  CiClientError,
  CiConfigError,
} from "../src/client.js";
import { createMockFetch } from "./_mock-fetch.js";

describe("createGithubClient — config", () => {
  it("throws CiConfigError when no token is provided and GITHUB_TOKEN is unset", () => {
    const saved = process.env.GITHUB_TOKEN;
    delete process.env.GITHUB_TOKEN;
    try {
      expect(() =>
        createGithubClient({
          owner: "o",
          repo: "r",
          fetchImpl: async () => ({
            ok: true,
            status: 200,
            statusText: "OK",
            text: async () => "{}",
          }),
        }),
      ).toThrow(CiConfigError);
    } finally {
      if (saved !== undefined) process.env.GITHUB_TOKEN = saved;
    }
  });

  it("throws CiConfigError when owner or repo is missing", () => {
    expect(() =>
      createGithubClient({
        owner: "",
        repo: "r",
        token: "t",
      }),
    ).toThrow(CiConfigError);
    expect(() =>
      createGithubClient({
        owner: "o",
        repo: "",
        token: "t",
      }),
    ).toThrow(CiConfigError);
  });

  it("reads token from env when no explicit token is passed", async () => {
    const saved = process.env.GITHUB_TOKEN;
    process.env.GITHUB_TOKEN = "env-token";
    try {
      const mock = createMockFetch({
        "POST /repos/o/r/actions/workflows/ci.yml/dispatches": { rawBody: "" },
      });
      const client = createGithubClient({
        owner: "o",
        repo: "r",
        fetchImpl: mock.fetch,
      });
      await client.triggerWorkflow({ workflow: "ci.yml", ref: "main" });
      expect(mock.calls).toHaveLength(1);
    } finally {
      if (saved === undefined) delete process.env.GITHUB_TOKEN;
      else process.env.GITHUB_TOKEN = saved;
    }
  });
});

describe("createGithubClient — triggerWorkflow", () => {
  it("sends a POST with Bearer auth and workflow_dispatch body", async () => {
    let seenAuth: string | undefined;
    let seenBody: string | undefined;
    const client = createGithubClient({
      owner: "o",
      repo: "r",
      token: "secret",
      fetchImpl: async (_url, init) => {
        seenAuth = init?.headers?.Authorization;
        seenBody = init?.body;
        return {
          ok: true,
          status: 204,
          statusText: "No Content",
          text: async () => "",
        };
      },
    });
    const result = await client.triggerWorkflow({
      workflow: "ci.yml",
      ref: "main",
      inputs: { env: "staging" },
    });
    expect(seenAuth).toBe("Bearer secret");
    expect(seenBody).toContain('"ref":"main"');
    expect(seenBody).toContain('"env":"staging"');
    expect(result.accepted).toBe(true);
  });

  it("wraps non-2xx responses in CiClientError", async () => {
    const mock = createMockFetch({
      "POST /repos/o/r/actions/workflows/ci.yml/dispatches": {
        status: 401,
        statusText: "Unauthorized",
        rawBody: "bad credentials",
      },
    });
    const client = createGithubClient({
      owner: "o",
      repo: "r",
      token: "t",
      fetchImpl: mock.fetch,
    });
    await expect(
      client.triggerWorkflow({ workflow: "ci.yml", ref: "main" }),
    ).rejects.toMatchObject({ name: "CiClientError", status: 401 });
  });

  it("wraps transport failures in CiClientError", async () => {
    const mock = createMockFetch({
      "POST /repos/o/r/actions/workflows/ci.yml/dispatches": {
        throwTransport: true,
      },
    });
    const client = createGithubClient({
      owner: "o",
      repo: "r",
      token: "t",
      fetchImpl: mock.fetch,
    });
    await expect(
      client.triggerWorkflow({ workflow: "ci.yml", ref: "main" }),
    ).rejects.toBeInstanceOf(CiClientError);
  });

  it("wraps invalid JSON responses", async () => {
    const mock = createMockFetch({
      "/repos/o/r/actions/runs/42": {
        rawBody: "not json",
      },
    });
    const client = createGithubClient({
      owner: "o",
      repo: "r",
      token: "t",
      fetchImpl: mock.fetch,
    });
    await expect(client.getRun("42")).rejects.toThrowError(/not valid JSON/);
  });

  it("rejects empty workflow or empty ref at the client layer", async () => {
    const client = createGithubClient({
      owner: "o",
      repo: "r",
      token: "t",
      fetchImpl: async () => ({
        ok: true,
        status: 204,
        statusText: "No Content",
        text: async () => "",
      }),
    });
    await expect(
      client.triggerWorkflow({ workflow: "", ref: "main" }),
    ).rejects.toBeInstanceOf(CiClientError);
    await expect(
      client.triggerWorkflow({ workflow: "ci.yml", ref: "" }),
    ).rejects.toBeInstanceOf(CiClientError);
  });
});

describe("createGithubClient — getRun + listArtifacts", () => {
  it("normalizes a completed GitHub run payload", async () => {
    const mock = createMockFetch({
      "/repos/o/r/actions/runs/42": {
        body: {
          id: 42,
          status: "completed",
          conclusion: "success",
          html_url: "https://example.com/runs/42",
          created_at: "2026-04-13T00:00:00Z",
          updated_at: "2026-04-13T00:02:00Z",
          head_sha: "abc123",
          name: "CI",
          path: ".github/workflows/ci.yml",
        },
      },
    });
    const client = createGithubClient({
      owner: "o",
      repo: "r",
      token: "t",
      fetchImpl: mock.fetch,
    });
    const run = await client.getRun("42");
    expect(run.id).toBe("42");
    expect(run.status).toBe("completed");
    expect(run.conclusion).toBe("success");
    expect(run.workflow).toBe(".github/workflows/ci.yml");
  });

  it("collapses unusual status strings (requested/waiting/pending) to queued", async () => {
    for (const raw of ["requested", "waiting", "pending"]) {
      const mock = createMockFetch({
        "/repos/o/r/actions/runs/1": {
          body: {
            id: 1,
            status: raw,
            conclusion: null,
            html_url: "",
            created_at: "2026-04-13T00:00:00Z",
            updated_at: "2026-04-13T00:00:00Z",
            head_sha: null,
            name: null,
          },
        },
      });
      const client = createGithubClient({
        owner: "o",
        repo: "r",
        token: "t",
        fetchImpl: mock.fetch,
      });
      const run = await client.getRun("1");
      expect(run.status).toBe("queued");
    }
  });

  it("remaps unknown conclusions to 'neutral' so downstream consumers can pattern-match", async () => {
    const mock = createMockFetch({
      "/repos/o/r/actions/runs/1": {
        body: {
          id: 1,
          status: "completed",
          conclusion: "strange-new-value",
          html_url: "",
          created_at: "2026-04-13T00:00:00Z",
          updated_at: "2026-04-13T00:00:00Z",
          head_sha: null,
          name: null,
        },
      },
    });
    const client = createGithubClient({
      owner: "o",
      repo: "r",
      token: "t",
      fetchImpl: mock.fetch,
    });
    expect((await client.getRun("1")).conclusion).toBe("neutral");
  });

  it("listArtifacts returns normalized shape + empty list when none", async () => {
    const mock = createMockFetch({
      "/repos/o/r/actions/runs/1/artifacts": {
        body: {
          artifacts: [
            {
              id: 100,
              name: "coverage",
              size_in_bytes: 512,
              archive_download_url: "https://example.com/100",
              expired: false,
            },
          ],
        },
      },
      "/repos/o/r/actions/runs/2/artifacts": { body: { artifacts: [] } },
    });
    const client = createGithubClient({
      owner: "o",
      repo: "r",
      token: "t",
      fetchImpl: mock.fetch,
    });
    const one = await client.listArtifacts("1");
    expect(one).toHaveLength(1);
    expect(one[0]!.name).toBe("coverage");
    expect(one[0]!.downloadUrl).toBe("https://example.com/100");

    const none = await client.listArtifacts("2");
    expect(none).toEqual([]);
  });
});
