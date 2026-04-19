import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { resolveConfig, EngineConfigSchema } from "../src/config.js";

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
