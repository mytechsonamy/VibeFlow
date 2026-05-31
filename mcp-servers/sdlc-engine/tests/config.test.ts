import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  resolveConfig,
  EngineConfigSchema,
  ConsensusConfigSchema,
  PhaseRunnerConfigSchema,
  LearningLoopConfigSchema,
  ReviewerMemoryConfigSchema,
} from "../src/config.js";

const ENV_KEYS = ["VIBEFLOW_PROJECT", "VIBEFLOW_STATE_DIR"] as const;

describe("resolveConfig", () => {
  let tmpDir: string;
  const saved: Record<string, string | undefined> = {};

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sdlc-engine-config-"));
    for (const k of ENV_KEYS) {
      saved[k] = process.env[k];
      delete process.env[k];
    }
  });

  afterEach(() => {
    for (const k of ENV_KEYS) {
      if (saved[k] === undefined) delete process.env[k];
      else process.env[k] = saved[k];
    }
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("falls back to defaults when nothing is set", () => {
    const cfg = resolveConfig(tmpDir);
    expect(cfg.project).toBe("default");
    expect(cfg.stateStore.dir).toBeUndefined();
  });

  it("reads project from vibeflow.config.json", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({ project: "proj-from-file" }),
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.project).toBe("proj-from-file");
  });

  it("reads stateStore.dir from vibeflow.config.json", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({
        project: "p",
        stateStore: { dir: "/tmp/custom-state" },
      }),
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.stateStore.dir).toBe("/tmp/custom-state");
  });

  it("env vars take precedence over file config", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({
        project: "from-file",
        stateStore: { dir: "/tmp/file-state" },
      }),
    );
    process.env.VIBEFLOW_PROJECT = "from-env";
    process.env.VIBEFLOW_STATE_DIR = "/tmp/env-state";

    const cfg = resolveConfig(tmpDir);
    expect(cfg.project).toBe("from-env");
    expect(cfg.stateStore.dir).toBe("/tmp/env-state");
  });

  it("ignores a malformed config file silently", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      "{ not json",
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.project).toBe("default");
    expect(cfg.stateStore.dir).toBeUndefined();
  });

  it("ignores non-string project in file config", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({ project: 42 }),
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.project).toBe("default");
  });

  it("ignores legacy mode field silently (Sprint 11-E removed it)", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({ project: "p", mode: "team" }),
    );
    // `mode` is not part of EngineConfigSchema anymore — parsing should
    // succeed and produce a config with only project + stateStore.
    const cfg = resolveConfig(tmpDir);
    expect(cfg.project).toBe("p");
    expect((cfg as { mode?: unknown }).mode).toBeUndefined();
  });
});

describe("config schemas", () => {
  it("EngineConfigSchema requires a non-empty project", () => {
    const ok = EngineConfigSchema.safeParse({
      project: "p",
      stateStore: {},
    });
    expect(ok.success).toBe(true);

    const bad = EngineConfigSchema.safeParse({
      project: "",
      stateStore: {},
    });
    expect(bad.success).toBe(false);
  });

  it("EngineConfigSchema defaults stateStore to empty object", () => {
    const parsed = EngineConfigSchema.parse({ project: "p" });
    expect(parsed.stateStore).toEqual({});
  });

  it("EngineConfigSchema accepts stateStore.dir", () => {
    const parsed = EngineConfigSchema.parse({
      project: "p",
      stateStore: { dir: "/tmp/x" },
    });
    expect(parsed.stateStore.dir).toBe("/tmp/x");
  });
});

describe("ConsensusConfigSchema (Sprint 17-F)", () => {
  it("applies defaults when field is omitted", () => {
    const cfg = EngineConfigSchema.parse({ project: "p" });
    expect(cfg.consensus.maxIterations).toBe(5);
    expect(cfg.consensus.approvalThreshold).toBe(0.9);
    expect(cfg.consensus.iteration.enabled).toBe(true);
    expect(cfg.consensus.quorum).toBeUndefined();
  });

  it("accepts a partial consensus object and fills the rest", () => {
    const cfg = EngineConfigSchema.parse({
      project: "p",
      consensus: { maxIterations: 3 },
    });
    expect(cfg.consensus.maxIterations).toBe(3);
    expect(cfg.consensus.approvalThreshold).toBe(0.9);
    expect(cfg.consensus.iteration.enabled).toBe(true);
  });

  it("accepts consensus.iteration.enabled=false as the rollback switch", () => {
    const cfg = EngineConfigSchema.parse({
      project: "p",
      consensus: { iteration: { enabled: false } },
    });
    expect(cfg.consensus.iteration.enabled).toBe(false);
  });

  it("rejects maxIterations outside [1, 20]", () => {
    expect(
      ConsensusConfigSchema.safeParse({ maxIterations: 0 }).success,
    ).toBe(false);
    expect(
      ConsensusConfigSchema.safeParse({ maxIterations: 21 }).success,
    ).toBe(false);
    expect(
      ConsensusConfigSchema.safeParse({ maxIterations: 5 }).success,
    ).toBe(true);
  });

  it("rejects approvalThreshold outside [0, 1]", () => {
    expect(
      ConsensusConfigSchema.safeParse({ approvalThreshold: -0.1 }).success,
    ).toBe(false);
    expect(
      ConsensusConfigSchema.safeParse({ approvalThreshold: 1.01 }).success,
    ).toBe(false);
    expect(
      ConsensusConfigSchema.safeParse({ approvalThreshold: 0.9 }).success,
    ).toBe(true);
  });

  it("rejects quorum < 1 but accepts integers ≥ 1", () => {
    expect(ConsensusConfigSchema.safeParse({ quorum: 0 }).success).toBe(false);
    expect(ConsensusConfigSchema.safeParse({ quorum: 1 }).success).toBe(true);
    expect(ConsensusConfigSchema.safeParse({ quorum: 3 }).success).toBe(true);
  });
});

describe("resolveConfig — consensus (Sprint 17-F)", () => {
  let tmpDir: string;
  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sdlc-engine-consensus-"));
  });
  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("reads partial consensus config from file and fills defaults", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({
        project: "p",
        consensus: { maxIterations: 3, approvalThreshold: 0.85 },
      }),
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.consensus.maxIterations).toBe(3);
    expect(cfg.consensus.approvalThreshold).toBe(0.85);
    expect(cfg.consensus.iteration.enabled).toBe(true);
  });

  it("falls back to defaults when consensus.* is malformed", () => {
    // Negative threshold is not valid — resolver silently falls back
    // to defaults (mirrors Sprint 17-F risk #1 in the plan).
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({
        project: "p",
        consensus: { approvalThreshold: -5 },
      }),
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.consensus.approvalThreshold).toBe(0.9);
    expect(cfg.consensus.maxIterations).toBe(5);
  });
});

describe("PhaseRunnerConfigSchema (Sprint 19-G)", () => {
  it("applies defaults when field is omitted", () => {
    const cfg = EngineConfigSchema.parse({ project: "p" });
    expect(cfg.phaseRunner.autoAdvance).toBe(true);
    expect(cfg.phaseRunner.maxConvergenceAttempts).toBe(3);
  });

  it("accepts a partial phaseRunner object and fills the rest", () => {
    const cfg = EngineConfigSchema.parse({
      project: "p",
      phaseRunner: { autoAdvance: false },
    });
    expect(cfg.phaseRunner.autoAdvance).toBe(false);
    expect(cfg.phaseRunner.maxConvergenceAttempts).toBe(3);
  });

  it("rejects maxConvergenceAttempts outside [1, 10]", () => {
    expect(
      PhaseRunnerConfigSchema.safeParse({ maxConvergenceAttempts: 0 }).success,
    ).toBe(false);
    expect(
      PhaseRunnerConfigSchema.safeParse({ maxConvergenceAttempts: 11 }).success,
    ).toBe(false);
    expect(
      PhaseRunnerConfigSchema.safeParse({ maxConvergenceAttempts: 3 }).success,
    ).toBe(true);
  });
});

describe("LearningLoopConfigSchema (Sprint 20-H)", () => {
  it("applies defaults when field is omitted", () => {
    const cfg = EngineConfigSchema.parse({ project: "p" });
    expect(cfg.learningLoop.enabled).toBe(true);
    expect(cfg.learningLoop.sprintWindow).toBe(3);
    expect(cfg.learningLoop.minObservations).toBe(3);
  });

  it("accepts a partial learningLoop object and fills the rest", () => {
    const cfg = EngineConfigSchema.parse({
      project: "p",
      learningLoop: { sprintWindow: 6 },
    });
    expect(cfg.learningLoop.sprintWindow).toBe(6);
    expect(cfg.learningLoop.minObservations).toBe(3);
    expect(cfg.learningLoop.enabled).toBe(true);
  });

  it("rejects out-of-range sprintWindow and minObservations", () => {
    expect(LearningLoopConfigSchema.safeParse({ sprintWindow: 0 }).success).toBe(
      false,
    );
    expect(
      LearningLoopConfigSchema.safeParse({ sprintWindow: 51 }).success,
    ).toBe(false);
    expect(
      LearningLoopConfigSchema.safeParse({ minObservations: 0 }).success,
    ).toBe(false);
    expect(
      LearningLoopConfigSchema.safeParse({ minObservations: 3 }).success,
    ).toBe(true);
  });
});

describe("ReviewerMemoryConfigSchema (Sprint 20-H)", () => {
  it("applies defaults when field is omitted", () => {
    const cfg = EngineConfigSchema.parse({ project: "p" });
    expect(cfg.reviewerMemory.enabled).toBe(true);
    expect(cfg.reviewerMemory.maxEntriesPerArtifact).toBe(5);
    expect(cfg.reviewerMemory.tokenBudget).toBe(600);
  });

  it("accepts a partial reviewerMemory object and fills the rest", () => {
    const cfg = EngineConfigSchema.parse({
      project: "p",
      reviewerMemory: { enabled: false },
    });
    expect(cfg.reviewerMemory.enabled).toBe(false);
    expect(cfg.reviewerMemory.maxEntriesPerArtifact).toBe(5);
    expect(cfg.reviewerMemory.tokenBudget).toBe(600);
  });

  it("rejects out-of-range maxEntriesPerArtifact and tokenBudget", () => {
    expect(
      ReviewerMemoryConfigSchema.safeParse({ maxEntriesPerArtifact: 0 }).success,
    ).toBe(false);
    expect(
      ReviewerMemoryConfigSchema.safeParse({ tokenBudget: 49 }).success,
    ).toBe(false);
    expect(
      ReviewerMemoryConfigSchema.safeParse({ tokenBudget: 600 }).success,
    ).toBe(true);
  });
});

describe("resolveConfig — learningLoop + reviewerMemory (Sprint 20-H)", () => {
  let tmpDir: string;
  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "vf-cfg-s20-"));
  });
  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("merges partial learningLoop/reviewerMemory from vibeflow.config.json", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({
        project: "merge-test",
        learningLoop: { sprintWindow: 10 },
        reviewerMemory: { tokenBudget: 1200 },
      }),
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.learningLoop.sprintWindow).toBe(10);
    expect(cfg.learningLoop.minObservations).toBe(3);
    expect(cfg.reviewerMemory.tokenBudget).toBe(1200);
    expect(cfg.reviewerMemory.maxEntriesPerArtifact).toBe(5);
  });

  it("falls back to defaults when the config fields are malformed", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({
        project: "bad-test",
        learningLoop: { sprintWindow: -1 },
        reviewerMemory: { tokenBudget: "nope" },
      }),
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.learningLoop.sprintWindow).toBe(3);
    expect(cfg.reviewerMemory.tokenBudget).toBe(600);
  });
});

describe("ConsensusConfigSchema excerption (Sprint 21-E)", () => {
  it("applies excerpt defaults when omitted", () => {
    const cfg = EngineConfigSchema.parse({ project: "p" });
    expect(cfg.consensus.excerptTokenBudget).toBe(30000);
    expect(cfg.consensus.excerptStrategy).toBe("semantic");
  });

  it("accepts a partial consensus object and fills excerpt defaults", () => {
    const cfg = EngineConfigSchema.parse({
      project: "p",
      consensus: { maxIterations: 7 },
    });
    expect(cfg.consensus.maxIterations).toBe(7);
    expect(cfg.consensus.excerptTokenBudget).toBe(30000);
    expect(cfg.consensus.excerptStrategy).toBe("semantic");
  });

  it("rejects an unknown excerptStrategy and out-of-range budget", () => {
    expect(
      ConsensusConfigSchema.safeParse({ excerptStrategy: "magic" }).success,
    ).toBe(false);
    expect(
      ConsensusConfigSchema.safeParse({ excerptTokenBudget: 999 }).success,
    ).toBe(false);
    expect(
      ConsensusConfigSchema.safeParse({ excerptStrategy: "headtail" }).success,
    ).toBe(true);
  });
});

describe("ReviewerMemoryConfigSchema compaction (Sprint 21-E)", () => {
  it("defaults compaction to theme-aware", () => {
    const cfg = EngineConfigSchema.parse({ project: "p" });
    expect(cfg.reviewerMemory.compaction).toBe("theme-aware");
  });

  it("accepts recency and rejects an unknown compaction mode", () => {
    expect(
      ReviewerMemoryConfigSchema.safeParse({ compaction: "recency" }).success,
    ).toBe(true);
    expect(
      ReviewerMemoryConfigSchema.safeParse({ compaction: "lru" }).success,
    ).toBe(false);
  });
});
