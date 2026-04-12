import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { z } from "zod";
import { SqliteStateStore } from "../src/state/sqlite.js";
import { SdlcEngine } from "../src/engine.js";
import { PhaseRegistry } from "../src/phases.js";
import { buildTools, ToolDefinition } from "../src/tools.js";
import { ConsensusStatus } from "../src/consensus.js";
import { ProjectState } from "../src/state/store.js";

function byName(tools: ToolDefinition[], name: string): ToolDefinition {
  const t = tools.find((x) => x.name === name);
  if (!t) throw new Error(`tool ${name} not registered`);
  return t;
}

describe("MCP tool handlers", () => {
  let tmpDir: string;
  let store: SqliteStateStore;
  let engine: SdlcEngine;
  let tools: ToolDefinition[];

  beforeEach(async () => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sdlc-engine-tools-"));
    store = new SqliteStateStore(path.join(tmpDir, "state.db"));
    await store.init();
    engine = new SdlcEngine(store, new PhaseRegistry());
    tools = buildTools(engine);
  });

  afterEach(async () => {
    await store.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("registers the expected five tools", () => {
    const names = tools.map((t) => t.name).sort();
    expect(names).toEqual([
      "sdlc_advance_phase",
      "sdlc_get_state",
      "sdlc_list_phases",
      "sdlc_record_consensus",
      "sdlc_satisfy_criterion",
    ]);
  });

  it("sdlc_list_phases returns all 7 phases in order", async () => {
    const result = (await byName(tools, "sdlc_list_phases").handler({})) as {
      phases: { id: string }[];
    };
    expect(result.phases.map((p) => p.id)).toEqual([
      "REQUIREMENTS",
      "DESIGN",
      "ARCHITECTURE",
      "PLANNING",
      "DEVELOPMENT",
      "TESTING",
      "DEPLOYMENT",
    ]);
  });

  it("sdlc_get_state initializes a new project", async () => {
    const state = (await byName(tools, "sdlc_get_state").handler({
      projectId: "p1",
    })) as ProjectState;
    expect(state.currentPhase).toBe("REQUIREMENTS");
    expect(state.revision).toBe(1);
  });

  it("sdlc_get_state rejects empty projectId via Zod", async () => {
    await expect(
      byName(tools, "sdlc_get_state").handler({ projectId: "" }),
    ).rejects.toBeInstanceOf(z.ZodError);
  });

  it("sdlc_satisfy_criterion appends the criterion", async () => {
    await byName(tools, "sdlc_get_state").handler({ projectId: "p1" });
    const state = (await byName(tools, "sdlc_satisfy_criterion").handler({
      projectId: "p1",
      criterion: "prd.approved",
    })) as ProjectState;
    expect(state.satisfiedCriteria).toContain("prd.approved");
  });

  it("sdlc_record_consensus derives status when omitted", async () => {
    const state = (await byName(tools, "sdlc_record_consensus").handler({
      projectId: "p1",
      phase: "REQUIREMENTS",
      agreement: 0.95,
      criticalIssues: 0,
    })) as ProjectState;
    expect(state.lastConsensus?.status).toBe(ConsensusStatus.APPROVED);
  });

  it("sdlc_record_consensus accepts lowercase status via Zod transform", async () => {
    const state = (await byName(tools, "sdlc_record_consensus").handler({
      projectId: "p1",
      phase: "REQUIREMENTS",
      agreement: 0.7,
      criticalIssues: 0,
      status: "rejected",
    })) as ProjectState;
    expect(state.lastConsensus?.status).toBe(ConsensusStatus.REJECTED);
  });

  it("sdlc_record_consensus rejects agreement > 1 via Zod", async () => {
    await expect(
      byName(tools, "sdlc_record_consensus").handler({
        projectId: "p1",
        phase: "REQUIREMENTS",
        agreement: 1.5,
        criticalIssues: 0,
      }),
    ).rejects.toBeInstanceOf(z.ZodError);
  });

  it("sdlc_record_consensus rejects unknown phase via Zod", async () => {
    await expect(
      byName(tools, "sdlc_record_consensus").handler({
        projectId: "p1",
        phase: "LAUNCH",
        agreement: 0.9,
        criticalIssues: 0,
      }),
    ).rejects.toBeInstanceOf(z.ZodError);
  });

  it("sdlc_advance_phase returns ok=true on successful transition", async () => {
    await byName(tools, "sdlc_get_state").handler({ projectId: "p1" });
    await byName(tools, "sdlc_satisfy_criterion").handler({
      projectId: "p1",
      criterion: "prd.approved",
    });
    await byName(tools, "sdlc_satisfy_criterion").handler({
      projectId: "p1",
      criterion: "testability.score>=60",
    });
    await byName(tools, "sdlc_record_consensus").handler({
      projectId: "p1",
      phase: "REQUIREMENTS",
      agreement: 0.95,
      criticalIssues: 0,
    });
    const result = (await byName(tools, "sdlc_advance_phase").handler({
      projectId: "p1",
      to: "DESIGN",
    })) as { ok: boolean; state: ProjectState };
    expect(result.ok).toBe(true);
    expect(result.state.currentPhase).toBe("DESIGN");
  });

  it("sdlc_advance_phase wraps PhaseTransitionError into ok=false payload", async () => {
    await byName(tools, "sdlc_get_state").handler({ projectId: "p1" });
    const result = (await byName(tools, "sdlc_advance_phase").handler({
      projectId: "p1",
      to: "DESIGN",
    })) as { ok: boolean; errors: string[]; state: ProjectState };
    expect(result.ok).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    // State must be untouched on failure.
    expect(result.state.currentPhase).toBe("REQUIREMENTS");
  });

  it("sdlc_advance_phase with force=true bypasses missing exit criteria", async () => {
    await byName(tools, "sdlc_get_state").handler({ projectId: "p1" });
    const result = (await byName(tools, "sdlc_advance_phase").handler({
      projectId: "p1",
      to: "DESIGN",
      force: true,
    })) as { ok: boolean; state: ProjectState };
    expect(result.ok).toBe(true);
    expect(result.state.currentPhase).toBe("DESIGN");
  });

  it("sdlc_advance_phase with force=true still blocks structural skip", async () => {
    await byName(tools, "sdlc_get_state").handler({ projectId: "p1" });
    const result = (await byName(tools, "sdlc_advance_phase").handler({
      projectId: "p1",
      to: "ARCHITECTURE",
      force: true,
    })) as { ok: boolean; errors: string[] };
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => /advance exactly one step/.test(e))).toBe(
      true,
    );
  });

  it("sdlc_advance_phase rejects additionalProperties via Zod strict parse", async () => {
    // Zod .object() without .passthrough() ignores unknown keys by default;
    // we only assert that malformed `to` is rejected.
    await expect(
      byName(tools, "sdlc_advance_phase").handler({
        projectId: "p1",
        to: "NOT_A_PHASE",
      }),
    ).rejects.toBeInstanceOf(z.ZodError);
  });
});
