import { describe, expect, it } from "vitest";
import {
  triggerPipeline,
  getPipelineStatus,
  fetchArtifacts,
  deploy,
  rollback,
} from "../src/pipelines.js";
import { CiProvider, CiClientError } from "../src/client.js";

function fakeProvider(
  overrides: Partial<CiProvider> = {},
): CiProvider {
  return {
    name: "github",
    triggerWorkflow: async () => ({ accepted: true, note: "ok" }),
    getRun: async () => ({
      id: "1",
      status: "completed",
      conclusion: "success",
      url: "",
      createdAt: "2026-04-13T00:00:00Z",
      updatedAt: "2026-04-13T00:01:00Z",
      headSha: "abc",
      workflow: "ci.yml",
    }),
    listArtifacts: async () => [],
    ...overrides,
  };
}

describe("triggerPipeline", () => {
  it("dispatches through the provider and returns a normalized result", async () => {
    let seenInput: unknown;
    const provider = fakeProvider({
      triggerWorkflow: async (input) => {
        seenInput = input;
        return { accepted: true, note: "dispatched ci.yml on main" };
      },
    });
    const result = await triggerPipeline(provider, {
      workflow: "ci.yml",
      ref: "main",
      inputs: { env: "staging" },
    });
    expect(seenInput).toEqual({
      workflow: "ci.yml",
      ref: "main",
      inputs: { env: "staging" },
    });
    expect(result.provider).toBe("github");
    expect(result.accepted).toBe(true);
    expect(result.workflow).toBe("ci.yml");
    expect(result.ref).toBe("main");
    expect(result.dispatchedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it("rejects empty workflow / empty ref / path traversal / whitespace ref", async () => {
    const provider = fakeProvider();
    await expect(
      triggerPipeline(provider, { workflow: "", ref: "main" }),
    ).rejects.toBeInstanceOf(CiClientError);
    await expect(
      triggerPipeline(provider, { workflow: "ci.yml", ref: "" }),
    ).rejects.toBeInstanceOf(CiClientError);
    await expect(
      triggerPipeline(provider, { workflow: "../../../etc/passwd", ref: "main" }),
    ).rejects.toThrowError(/forbidden characters/);
    await expect(
      triggerPipeline(provider, { workflow: "ci.yml", ref: "main\nextra" }),
    ).rejects.toThrowError(/whitespace/);
  });
});

describe("getPipelineStatus", () => {
  it("returns a normalized PipelineStatusResult with derived durationMs", async () => {
    const provider = fakeProvider({
      getRun: async () => ({
        id: "42",
        status: "completed",
        conclusion: "success",
        url: "https://example.com/42",
        createdAt: "2026-04-13T00:00:00Z",
        updatedAt: "2026-04-13T00:02:00Z",
        headSha: "abc",
        workflow: "ci.yml",
      }),
    });
    const result = await getPipelineStatus(provider, "42");
    expect(result.id).toBe("42");
    expect(result.status).toBe("completed");
    expect(result.conclusion).toBe("success");
    expect(result.durationMs).toBe(2 * 60 * 1000);
    expect(result.provider).toBe("github");
  });

  it("sets durationMs to null when timestamps are non-monotonic or unparseable", async () => {
    const provider = fakeProvider({
      getRun: async () => ({
        id: "42",
        status: "in_progress",
        conclusion: null,
        url: "",
        createdAt: "2026-04-13T00:02:00Z",
        updatedAt: "2026-04-13T00:00:00Z",
        headSha: null,
        workflow: null,
      }),
    });
    expect((await getPipelineStatus(provider, "42")).durationMs).toBeNull();
  });

  it("rejects empty runId", async () => {
    await expect(
      getPipelineStatus(fakeProvider(), ""),
    ).rejects.toBeInstanceOf(CiClientError);
  });
});

describe("fetchArtifacts", () => {
  it("returns the artifact list with totalBytes summed", async () => {
    const provider = fakeProvider({
      listArtifacts: async () => [
        {
          id: "a",
          name: "coverage",
          sizeBytes: 100,
          downloadUrl: "u1",
          expired: false,
        },
        {
          id: "b",
          name: "junit",
          sizeBytes: 200,
          downloadUrl: "u2",
          expired: false,
        },
      ],
    });
    const result = await fetchArtifacts(provider, "42");
    expect(result.artifacts).toHaveLength(2);
    expect(result.totalBytes).toBe(300);
  });

  it("returns zero totalBytes for an empty artifact list", async () => {
    const result = await fetchArtifacts(fakeProvider(), "42");
    expect(result.totalBytes).toBe(0);
    expect(result.artifacts).toEqual([]);
  });
});

describe("deploy", () => {
  it("merges environment into inputs and tags the note with env=", async () => {
    let seen: unknown;
    const provider = fakeProvider({
      triggerWorkflow: async (input) => {
        seen = input;
        return { accepted: true, note: "dispatched deploy.yml on main" };
      },
    });
    const result = await deploy(provider, {
      workflow: "deploy.yml",
      ref: "main",
      environment: "staging",
      inputs: { dry_run: "false" },
    });
    expect(seen).toEqual({
      workflow: "deploy.yml",
      ref: "main",
      inputs: { environment: "staging", dry_run: "false" },
    });
    expect(result.note).toMatch(/environment=staging/);
  });
});

describe("rollback", () => {
  it("requires a reason of at least 3 characters", async () => {
    const provider = fakeProvider();
    await expect(
      rollback(provider, {
        workflow: "rb.yml",
        targetRef: "v1.0.0",
        reason: "",
        environment: "production",
      }),
    ).rejects.toThrowError(/reason is required/);
    await expect(
      rollback(provider, {
        workflow: "rb.yml",
        targetRef: "v1.0.0",
        reason: "ab",
        environment: "production",
      }),
    ).rejects.toThrowError(/at least 3 characters/);
  });

  it("dispatches to the target ref with audit fields in the run note", async () => {
    let seen: unknown;
    const provider = fakeProvider({
      triggerWorkflow: async (input) => {
        seen = input;
        return { accepted: true, note: "dispatched rb.yml on v1.0.0" };
      },
    });
    const result = await rollback(provider, {
      workflow: "rb.yml",
      targetRef: "v1.0.0",
      reason: "perf regression in v1.1",
      environment: "production",
    });
    expect(seen).toEqual({
      workflow: "rb.yml",
      ref: "v1.0.0",
      inputs: {
        environment: "production",
        reason: "perf regression in v1.1",
        action: "rollback",
      },
    });
    expect(result.note).toMatch(/rollback→v1.0.0/);
    expect(result.note).toMatch(/reason="perf regression in v1.1"/);
  });
});
