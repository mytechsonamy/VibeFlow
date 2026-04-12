import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { resolveConfig, EngineConfigSchema, ModeSchema } from "../src/config.js";

const ENV_KEYS = [
  "VIBEFLOW_MODE",
  "VIBEFLOW_PROJECT",
  "VIBEFLOW_SQLITE_PATH",
  "VIBEFLOW_POSTGRES_URL",
] as const;

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
    expect(cfg.mode).toBe("solo");
    expect(cfg.project).toBe("default");
    expect(cfg.stateStore.sqlitePath).toBe(
      path.join(tmpDir, ".vibeflow", "state.db"),
    );
    expect(cfg.stateStore.postgresUrl).toBeUndefined();
  });

  it("reads mode and project from vibeflow.config.json", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({ mode: "team", project: "proj-from-file" }),
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.mode).toBe("team");
    expect(cfg.project).toBe("proj-from-file");
  });

  it("env vars take precedence over file config", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({ mode: "solo", project: "from-file" }),
    );
    process.env.VIBEFLOW_MODE = "team";
    process.env.VIBEFLOW_PROJECT = "from-env";
    process.env.VIBEFLOW_SQLITE_PATH = "/tmp/custom.db";
    process.env.VIBEFLOW_POSTGRES_URL = "postgres://x/y";

    const cfg = resolveConfig(tmpDir);
    expect(cfg.mode).toBe("team");
    expect(cfg.project).toBe("from-env");
    expect(cfg.stateStore.sqlitePath).toBe("/tmp/custom.db");
    expect(cfg.stateStore.postgresUrl).toBe("postgres://x/y");
  });

  it("ignores invalid mode in file config (falls back to default)", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({ mode: "turbo" }),
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.mode).toBe("solo");
  });

  it("ignores a malformed config file silently", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      "{ not json",
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.mode).toBe("solo");
    expect(cfg.project).toBe("default");
  });

  it("ignores non-string project in file config", () => {
    fs.writeFileSync(
      path.join(tmpDir, "vibeflow.config.json"),
      JSON.stringify({ project: 42 }),
    );
    const cfg = resolveConfig(tmpDir);
    expect(cfg.project).toBe("default");
  });
});

describe("config schemas", () => {
  it("ModeSchema accepts only solo or team", () => {
    expect(ModeSchema.parse("solo")).toBe("solo");
    expect(ModeSchema.parse("team")).toBe("team");
    expect(ModeSchema.safeParse("turbo").success).toBe(false);
  });

  it("EngineConfigSchema requires a non-empty project", () => {
    const ok = EngineConfigSchema.safeParse({
      project: "p",
      mode: "solo",
      stateStore: {},
    });
    expect(ok.success).toBe(true);

    const bad = EngineConfigSchema.safeParse({
      project: "",
      mode: "solo",
      stateStore: {},
    });
    expect(bad.success).toBe(false);
  });

  it("EngineConfigSchema defaults stateStore to empty object", () => {
    const parsed = EngineConfigSchema.parse({ project: "p", mode: "solo" });
    expect(parsed.stateStore).toEqual({});
  });
});
