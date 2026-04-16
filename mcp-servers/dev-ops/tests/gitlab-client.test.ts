import { describe, expect, it, afterEach } from "vitest";
import {
  createGitlabClient,
  CiClientError,
  CiConfigError,
  FetchImpl,
} from "../src/client.js";

// -----------------------------------------------------------------------------
// Dedicated GitLab client tests (Sprint 5 / S5-02).
//
// Mirror of the GitHub client's test surface. Covers config errors,
// auth header shape, URL shape, trigger / status / artifacts paths,
// status + conclusion normalization, transport failure, invalid JSON,
// and the ECONNREFUSED / ENOTFOUND offline branches the Sprint-4
// S4-08 hardening added for the GitHub client.
// -----------------------------------------------------------------------------

type FetchArgs = { url: string; init?: Parameters<FetchImpl>[1] };

/**
 * Minimal per-test fetch harness. The GitLab mock-fetch is different
 * enough from the GitHub one that sharing the existing _mock-fetch
 * (which is keyed by "METHOD /path") would be more work than a
 * per-test inline implementation.
 */
function mockFetch(responses: Record<string, { status?: number; body: string }>): {
  fetch: FetchImpl;
  calls: FetchArgs[];
} {
  const calls: FetchArgs[] = [];
  const fetch: FetchImpl = async (url, init) => {
    calls.push({ url, init });
    for (const key of Object.keys(responses)) {
      if (url.endsWith(key)) {
        const r = responses[key]!;
        return {
          ok: (r.status ?? 200) < 400,
          status: r.status ?? 200,
          statusText: "OK",
          text: async () => r.body,
        };
      }
    }
    throw new Error(`mockFetch: no response configured for ${url}`);
  };
  return { fetch, calls };
}

describe("createGitlabClient — config", () => {
  const savedGithub = process.env.GITHUB_TOKEN;
  const savedGitlab = process.env.GITLAB_TOKEN;
  afterEach(() => {
    if (savedGithub !== undefined) process.env.GITHUB_TOKEN = savedGithub;
    else delete process.env.GITHUB_TOKEN;
    if (savedGitlab !== undefined) process.env.GITLAB_TOKEN = savedGitlab;
    else delete process.env.GITLAB_TOKEN;
  });

  it("throws CiConfigError when neither GITLAB_TOKEN nor GITHUB_TOKEN is set", () => {
    delete process.env.GITLAB_TOKEN;
    delete process.env.GITHUB_TOKEN;
    expect(() =>
      createGitlabClient({
        projectId: "42",
        fetchImpl: async () => ({
          ok: true, status: 200, statusText: "OK", text: async () => "{}",
        }),
      }),
    ).toThrow(CiConfigError);
  });

  it("throws CiConfigError when projectId is missing", () => {
    expect(() =>
      createGitlabClient({
        projectId: "",
        token: "glpat_x",
        fetchImpl: async () => ({
          ok: true, status: 200, statusText: "OK", text: async () => "{}",
        }),
      }),
    ).toThrow(/projectId is required/);
  });

  it("prefers GITLAB_TOKEN over GITHUB_TOKEN when both are set", async () => {
    process.env.GITLAB_TOKEN = "glpat_gitlab";
    process.env.GITHUB_TOKEN = "ghp_github";
    const mock = mockFetch({
      "/projects/42/pipelines/1": {
        body: JSON.stringify({ id: 1, status: "running" }),
      },
    });
    const client = createGitlabClient({
      projectId: "42",
      fetchImpl: mock.fetch,
    });
    await client.getRun("1");
    const seen = mock.calls[0]!.init?.headers ?? {};
    expect((seen as Record<string, string>)["PRIVATE-TOKEN"]).toBe("glpat_gitlab");
  });

  it("falls back to GITHUB_TOKEN when only it is set (mirrors the shared userConfig.github_token field)", async () => {
    delete process.env.GITLAB_TOKEN;
    process.env.GITHUB_TOKEN = "ghp_shared";
    const mock = mockFetch({
      "/projects/42/pipelines/1": { body: JSON.stringify({ id: 1, status: "running" }) },
    });
    const client = createGitlabClient({ projectId: "42", fetchImpl: mock.fetch });
    await client.getRun("1");
    const seen = (mock.calls[0]!.init?.headers ?? {}) as Record<string, string>;
    expect(seen["PRIVATE-TOKEN"]).toBe("ghp_shared");
  });
});

describe("createGitlabClient — triggerWorkflow", () => {
  it("POSTs a pipeline with WORKFLOW variable and the requested ref", async () => {
    let seenBody: string | undefined;
    const client = createGitlabClient({
      projectId: "o/r",
      token: "glpat_x",
      fetchImpl: async (_url, init) => {
        seenBody = init?.body;
        return {
          ok: true,
          status: 201,
          statusText: "Created",
          text: async () =>
            JSON.stringify({
              id: 42,
              status: "pending",
              web_url: "https://gitlab.com/o/r/-/pipelines/42",
              created_at: "2026-04-13T00:00:00Z",
              ref: "main",
              sha: "abc",
            }),
        };
      },
    });
    const result = await client.triggerWorkflow({
      workflow: "ci-lint",
      ref: "main",
      inputs: { ENVIRONMENT: "staging" },
    });
    expect(result.accepted).toBe(true);
    expect(result.note).toMatch(/pipeline 42/);
    expect(seenBody).toContain('"ref":"main"');
    expect(seenBody).toContain('"WORKFLOW"');
    expect(seenBody).toContain('"ci-lint"');
    expect(seenBody).toContain('"ENVIRONMENT"');
  });

  it("URL-encodes a 'group/name' project path", async () => {
    let seenUrl = "";
    const client = createGitlabClient({
      projectId: "group/sub-group/repo",
      token: "glpat_x",
      fetchImpl: async (url) => {
        seenUrl = url;
        return {
          ok: true, status: 201, statusText: "Created", text: async () =>
            JSON.stringify({ id: 1, status: "created" }),
        };
      },
    });
    await client.triggerWorkflow({ workflow: "w", ref: "main" });
    expect(seenUrl).toContain("/projects/group%2Fsub-group%2Frepo/pipeline");
  });

  it("rejects empty workflow or empty ref at the client layer", async () => {
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async () => ({
        ok: true, status: 200, statusText: "OK", text: async () => "{}",
      }),
    });
    await expect(
      client.triggerWorkflow({ workflow: "", ref: "main" }),
    ).rejects.toBeInstanceOf(CiClientError);
    await expect(
      client.triggerWorkflow({ workflow: "w", ref: "" }),
    ).rejects.toBeInstanceOf(CiClientError);
  });

  it("rejects refs containing whitespace", async () => {
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async () => ({
        ok: true, status: 200, statusText: "OK", text: async () => "{}",
      }),
    });
    await expect(
      client.triggerWorkflow({ workflow: "w", ref: "main branch" }),
    ).rejects.toThrow(/whitespace/);
  });
});

describe("createGitlabClient — getRun normalization", () => {
  it("normalizes a successful pipeline", async () => {
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async () => ({
        ok: true, status: 200, statusText: "OK",
        text: async () =>
          JSON.stringify({
            id: 7,
            status: "success",
            web_url: "https://gitlab.com/o/r/-/pipelines/7",
            created_at: "2026-04-13T00:00:00Z",
            updated_at: "2026-04-13T01:00:00Z",
            ref: "main",
            sha: "beef",
          }),
      }),
    });
    const run = await client.getRun("7");
    expect(run.id).toBe("7");
    expect(run.status).toBe("completed");
    expect(run.conclusion).toBe("success");
    expect(run.url).toBe("https://gitlab.com/o/r/-/pipelines/7");
    expect(run.headSha).toBe("beef");
    expect(run.workflow).toBe("main");
  });

  it("maps transient statuses (waiting_for_resource, manual, scheduled) to queued", async () => {
    const make = (status: string) => async () => ({
      ok: true, status: 200, statusText: "OK",
      text: async () => JSON.stringify({ id: 1, status }),
    });
    for (const s of ["created", "waiting_for_resource", "preparing", "pending", "scheduled", "manual"]) {
      const client = createGitlabClient({
        projectId: "42", token: "glpat_x", fetchImpl: make(s),
      });
      const run = await client.getRun("1");
      expect(run.status).toBe("queued");
      expect(run.conclusion).toBeNull();
    }
  });

  it("maps running to in_progress", async () => {
    const client = createGitlabClient({
      projectId: "42", token: "glpat_x",
      fetchImpl: async () => ({
        ok: true, status: 200, statusText: "OK",
        text: async () => JSON.stringify({ id: 1, status: "running" }),
      }),
    });
    const run = await client.getRun("1");
    expect(run.status).toBe("in_progress");
    expect(run.conclusion).toBeNull();
  });

  it("maps failed / canceled / skipped to completed + respective conclusion", async () => {
    const cases: Array<[string, string]> = [
      ["failed", "failure"],
      ["canceled", "cancelled"],
      ["skipped", "skipped"],
    ];
    for (const [raw, expected] of cases) {
      const client = createGitlabClient({
        projectId: "42", token: "glpat_x",
        fetchImpl: async () => ({
          ok: true, status: 200, statusText: "OK",
          text: async () => JSON.stringify({ id: 1, status: raw }),
        }),
      });
      const run = await client.getRun("1");
      expect(run.status).toBe("completed");
      expect(run.conclusion).toBe(expected);
    }
  });

  it("wraps non-2xx responses in CiClientError", async () => {
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async () => ({
        ok: false, status: 401, statusText: "Unauthorized",
        text: async () => '{"message":"invalid token"}',
      }),
    });
    await expect(client.getRun("1")).rejects.toMatchObject({
      name: "CiClientError", status: 401,
    });
  });

  it("wraps invalid JSON responses", async () => {
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async () => ({
        ok: true, status: 200, statusText: "OK",
        text: async () => "<html>not json</html>",
      }),
    });
    await expect(client.getRun("1")).rejects.toThrow(/not valid JSON/);
  });
});

describe("createGitlabClient — listArtifacts", () => {
  it("collapses the jobs endpoint into PipelineArtifact[]", async () => {
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async () => ({
        ok: true, status: 200, statusText: "OK",
        text: async () =>
          JSON.stringify([
            { id: 100, name: "build", artifacts_file: { filename: "dist.tar.gz", size: 1024 } },
            { id: 101, name: "test", artifacts_file: { filename: "junit.xml", size: 2048 } },
            { id: 102, name: "lint", artifacts_file: null },            // no artifacts
            { id: 103, name: "deploy" },                                 // no field at all
          ]),
      }),
    });
    const artifacts = await client.listArtifacts("42");
    expect(artifacts.map((a) => a.name).sort()).toEqual(["dist.tar.gz", "junit.xml"]);
    expect(artifacts[0]!.sizeBytes).toBe(1024);
    expect(artifacts[0]!.downloadUrl).toMatch(/\/jobs\/100\/artifacts$/);
  });

  it("flags artifacts as expired when artifacts_expire_at is in the past", async () => {
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async () => ({
        ok: true, status: 200, statusText: "OK",
        text: async () =>
          JSON.stringify([
            {
              id: 1,
              name: "build",
              artifacts_file: { filename: "dist.tar.gz", size: 1 },
              artifacts_expire_at: "2000-01-01T00:00:00Z",
            },
          ]),
      }),
    });
    const artifacts = await client.listArtifacts("42");
    expect(artifacts[0]!.expired).toBe(true);
  });

  it("returns empty array when no jobs have artifacts", async () => {
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async () => ({
        ok: true, status: 200, statusText: "OK", text: async () => JSON.stringify([]),
      }),
    });
    expect(await client.listArtifacts("42")).toEqual([]);
  });
});

// Sprint 7 / S7-01 — self-hosted GitLab instances configure a custom
// `baseUrl` via the plugin userConfig (`gitlab_base_url`). The client
// has always accepted the option, but the test suite only exercised
// the default (`https://gitlab.com/api/v4`). This block adds
// real coverage so a future refactor that breaks the baseUrl plumbing
// surfaces immediately.
describe("createGitlabClient — self-hosted baseUrl (S7-01)", () => {
  it("routes requests through a custom baseUrl", async () => {
    let seenUrl = "";
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      baseUrl: "https://gitlab.example.com/api/v4",
      fetchImpl: async (url) => {
        seenUrl = url;
        return {
          ok: true,
          status: 200,
          statusText: "OK",
          text: async () =>
            JSON.stringify({
              id: 1,
              status: "success",
              web_url: "https://gitlab.example.com/o/r/-/pipelines/1",
              created_at: "2026-04-16T00:00:00Z",
            }),
        };
      },
    });
    await client.getRun("1");
    expect(seenUrl.startsWith("https://gitlab.example.com/api/v4/")).toBe(true);
    expect(seenUrl).not.toContain("gitlab.com");
  });

  it("strips a trailing slash from the custom baseUrl", async () => {
    let seenUrl = "";
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      baseUrl: "https://gitlab.example.com/api/v4/",
      fetchImpl: async (url) => {
        seenUrl = url;
        return { ok: true, status: 200, statusText: "OK", text: async () => "{}" };
      },
    });
    await client.getRun("1");
    // No double-slash between the baseUrl and the path.
    expect(seenUrl).not.toMatch(/\/api\/v4\/\/projects\//);
    expect(seenUrl).toContain("/api/v4/projects/");
  });

  it("preserves a non-default port in the baseUrl", async () => {
    let seenUrl = "";
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      baseUrl: "https://gitlab.example.com:8443/api/v4",
      fetchImpl: async (url) => {
        seenUrl = url;
        return { ok: true, status: 200, statusText: "OK", text: async () => "{}" };
      },
    });
    await client.getRun("1");
    expect(seenUrl).toContain(":8443");
  });

  it("supports a sub-path install (reverse-proxied GitLab)", async () => {
    // GitLab can be mounted under a sub-path like
    // https://example.com/gitlab/api/v4 behind a reverse proxy.
    // The baseUrl must pass through unchanged except for the
    // trailing slash strip.
    let seenUrl = "";
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      baseUrl: "https://example.com/gitlab/api/v4",
      fetchImpl: async (url) => {
        seenUrl = url;
        return { ok: true, status: 200, statusText: "OK", text: async () => "{}" };
      },
    });
    await client.getRun("1");
    expect(seenUrl).toContain("/gitlab/api/v4/projects/");
  });

  it("accepts http:// baseUrl (local dev / internal-only installs)", async () => {
    let seenUrl = "";
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      baseUrl: "http://localhost:8080/api/v4",
      fetchImpl: async (url) => {
        seenUrl = url;
        return { ok: true, status: 200, statusText: "OK", text: async () => "{}" };
      },
    });
    await client.getRun("1");
    expect(seenUrl.startsWith("http://localhost:8080/api/v4/")).toBe(true);
  });

  it("triggerWorkflow also routes through the custom baseUrl", async () => {
    let seenUrl = "";
    const client = createGitlabClient({
      projectId: "group/repo",
      token: "glpat_x",
      baseUrl: "https://gitlab.example.com/api/v4",
      fetchImpl: async (url) => {
        seenUrl = url;
        return {
          ok: true,
          status: 201,
          statusText: "Created",
          text: async () =>
            JSON.stringify({ id: 99, status: "created" }),
        };
      },
    });
    await client.triggerWorkflow({ workflow: "ci", ref: "main" });
    expect(seenUrl).toContain("https://gitlab.example.com/api/v4/projects/");
    expect(seenUrl).toContain("/pipeline");
  });

  it("listArtifacts downloadUrl is built from the same custom baseUrl", async () => {
    // Artifacts returned by the API carry a `downloadUrl` the caller
    // can use directly to fetch the artifact bytes. If the baseUrl
    // is custom but downloadUrl still points at gitlab.com, the
    // caller can't actually download anything. Sprint 5 / S5-02's
    // original client.ts already used `${baseUrl}` in the
    // downloadUrl template — this test locks the behavior in.
    const client = createGitlabClient({
      projectId: "group/repo",
      token: "glpat_x",
      baseUrl: "https://gitlab.example.com/api/v4",
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        statusText: "OK",
        text: async () =>
          JSON.stringify([
            {
              id: 1,
              name: "build",
              status: "success",
              artifacts_file: {
                filename: "artifacts.zip",
                size: 1024,
              },
            },
          ]),
      }),
    });
    const artifacts = await client.listArtifacts("42");
    expect(artifacts.length).toBeGreaterThan(0);
    expect(artifacts[0]!.downloadUrl).toContain("https://gitlab.example.com/api/v4/");
    expect(artifacts[0]!.downloadUrl).not.toContain("gitlab.com/api");
  });

  it("falls back to gitlab.com when baseUrl is not provided", async () => {
    let seenUrl = "";
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async (url) => {
        seenUrl = url;
        return { ok: true, status: 200, statusText: "OK", text: async () => "{}" };
      },
    });
    await client.getRun("1");
    expect(seenUrl.startsWith("https://gitlab.com/api/v4/")).toBe(true);
  });

  it("ignores an empty-string baseUrl and falls back to the default", async () => {
    // Undefined and empty-string should both collapse to the
    // default. Passing "" through userConfig is a common footgun
    // when the env var is exported as empty.
    let seenUrl = "";
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      baseUrl: "",
      fetchImpl: async (url) => {
        seenUrl = url;
        return { ok: true, status: 200, statusText: "OK", text: async () => "{}" };
      },
    });
    await client.getRun("1");
    expect(seenUrl.startsWith("https://gitlab.com/api/v4/")).toBe(true);
  });
});

describe("createGitlabClient — offline / network failure", () => {
  it("wraps ECONNREFUSED into CiClientError with transport hint", async () => {
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async () => {
        const err = new Error("connect ECONNREFUSED 172.65.251.78:443");
        (err as { code?: string }).code = "ECONNREFUSED";
        throw err;
      },
    });
    await expect(client.getRun("1")).rejects.toThrow(/transport.*ECONNREFUSED/);
  });

  it("wraps DNS failure (ENOTFOUND) into CiClientError", async () => {
    const client = createGitlabClient({
      projectId: "42",
      token: "glpat_x",
      fetchImpl: async () => {
        const err = new Error("getaddrinfo ENOTFOUND gitlab.com");
        (err as { code?: string }).code = "ENOTFOUND";
        throw err;
      },
    });
    await expect(client.getRun("1")).rejects.toThrow(/transport.*ENOTFOUND/);
  });
});
