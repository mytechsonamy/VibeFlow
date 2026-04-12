import { describe, expect, it } from "vitest";
import { z } from "zod";
import { buildTools, ToolDefinition } from "../src/tools.js";
import { createMockFetch } from "./_mock-fetch.js";

function byName(tools: ToolDefinition[], name: string): ToolDefinition {
  const t = tools.find((x) => x.name === name);
  if (!t) throw new Error(`tool ${name} not registered`);
  return t;
}

describe("MCP tool handlers", () => {
  it("registers the expected five tools", () => {
    const tools = buildTools({ token: "x", fetchImpl: createMockFetch({}).fetch });
    const names = tools.map((t) => t.name).sort();
    expect(names).toEqual([
      "do_deploy_staging",
      "do_fetch_artifacts",
      "do_pipeline_status",
      "do_rollback",
      "do_trigger_pipeline",
    ]);
  });

  it("do_trigger_pipeline dispatches through the client and returns a normalized result", async () => {
    const mock = createMockFetch({
      "POST /repos/o/r/actions/workflows/ci.yml/dispatches": { rawBody: "" },
    });
    const tools = buildTools({ token: "x", fetchImpl: mock.fetch });
    const result = (await byName(tools, "do_trigger_pipeline").handler({
      owner: "o",
      repo: "r",
      workflow: "ci.yml",
      ref: "main",
      inputs: { env: "staging" },
    })) as { accepted: boolean; provider: string; workflow: string };
    expect(result.accepted).toBe(true);
    expect(result.provider).toBe("github");
    expect(result.workflow).toBe("ci.yml");
    expect(mock.calls[0]!.method).toBe("POST");
  });

  it("do_trigger_pipeline rejects invalid args via Zod", async () => {
    const tools = buildTools({ token: "x", fetchImpl: createMockFetch({}).fetch });
    await expect(
      byName(tools, "do_trigger_pipeline").handler({
        owner: "",
        repo: "r",
        workflow: "ci.yml",
        ref: "main",
      }),
    ).rejects.toBeInstanceOf(z.ZodError);
  });

  it("do_pipeline_status returns normalized status and durationMs", async () => {
    const mock = createMockFetch({
      "/repos/o/r/actions/runs/42": {
        body: {
          id: 42,
          status: "completed",
          conclusion: "success",
          html_url: "https://example.com/42",
          created_at: "2026-04-13T00:00:00Z",
          updated_at: "2026-04-13T00:03:00Z",
          head_sha: "abc",
          name: "CI",
          path: ".github/workflows/ci.yml",
        },
      },
    });
    const tools = buildTools({ token: "x", fetchImpl: mock.fetch });
    const result = (await byName(tools, "do_pipeline_status").handler({
      owner: "o",
      repo: "r",
      runId: "42",
    })) as { status: string; conclusion: string; durationMs: number };
    expect(result.status).toBe("completed");
    expect(result.conclusion).toBe("success");
    expect(result.durationMs).toBe(3 * 60 * 1000);
  });

  it("do_fetch_artifacts sums totalBytes", async () => {
    const mock = createMockFetch({
      "/repos/o/r/actions/runs/42/artifacts": {
        body: {
          artifacts: [
            {
              id: 1,
              name: "coverage",
              size_in_bytes: 100,
              archive_download_url: "u1",
              expired: false,
            },
            {
              id: 2,
              name: "junit",
              size_in_bytes: 200,
              archive_download_url: "u2",
              expired: false,
            },
          ],
        },
      },
    });
    const tools = buildTools({ token: "x", fetchImpl: mock.fetch });
    const result = (await byName(tools, "do_fetch_artifacts").handler({
      owner: "o",
      repo: "r",
      runId: "42",
    })) as { totalBytes: number; artifacts: unknown[] };
    expect(result.totalBytes).toBe(300);
    expect(result.artifacts).toHaveLength(2);
  });

  it("do_deploy_staging merges environment into inputs", async () => {
    let seenBody: string | undefined;
    const tools = buildTools({
      token: "x",
      fetchImpl: async (_url, init) => {
        seenBody = init?.body;
        return {
          ok: true,
          status: 204,
          statusText: "No Content",
          text: async () => "",
        };
      },
    });
    const result = (await byName(tools, "do_deploy_staging").handler({
      owner: "o",
      repo: "r",
      workflow: "deploy.yml",
      ref: "main",
      environment: "staging",
      inputs: { dry_run: "false" },
    })) as { note: string };
    expect(seenBody).toContain('"environment":"staging"');
    expect(seenBody).toContain('"dry_run":"false"');
    expect(result.note).toMatch(/environment=staging/);
  });

  it("do_deploy_staging defaults environment to staging when omitted", async () => {
    let seenBody: string | undefined;
    const tools = buildTools({
      token: "x",
      fetchImpl: async (_url, init) => {
        seenBody = init?.body;
        return {
          ok: true,
          status: 204,
          statusText: "No Content",
          text: async () => "",
        };
      },
    });
    await byName(tools, "do_deploy_staging").handler({
      owner: "o",
      repo: "r",
      workflow: "deploy.yml",
      ref: "main",
    });
    expect(seenBody).toContain('"environment":"staging"');
  });

  it("do_rollback requires a reason ≥ 3 chars via Zod", async () => {
    const tools = buildTools({ token: "x", fetchImpl: createMockFetch({}).fetch });
    await expect(
      byName(tools, "do_rollback").handler({
        owner: "o",
        repo: "r",
        workflow: "rb.yml",
        targetRef: "v1.0.0",
        reason: "a",
        environment: "production",
      }),
    ).rejects.toBeInstanceOf(z.ZodError);
  });

  it("do_rollback preserves reason in the run note", async () => {
    let seenBody: string | undefined;
    const tools = buildTools({
      token: "x",
      fetchImpl: async (_url, init) => {
        seenBody = init?.body;
        return {
          ok: true,
          status: 204,
          statusText: "No Content",
          text: async () => "",
        };
      },
    });
    const result = (await byName(tools, "do_rollback").handler({
      owner: "o",
      repo: "r",
      workflow: "rb.yml",
      targetRef: "v1.0.0",
      reason: "perf regression",
      environment: "production",
    })) as { note: string };
    expect(seenBody).toContain('"action":"rollback"');
    expect(seenBody).toContain('"reason":"perf regression"');
    expect(result.note).toMatch(/rollback→v1.0.0/);
  });
});
