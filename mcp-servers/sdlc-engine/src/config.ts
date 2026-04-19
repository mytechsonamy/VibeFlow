import { z } from "zod";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Sprint 11-E: state is always file-backed. The legacy `mode` (solo/team)
 * and `stateStore.{sqlitePath,postgresUrl}` fields are gone. The engine
 * reads exactly one location for project state: `stateStore.dir`
 * (default `<cwd>/.vibeflow/state`). `VIBEFLOW_STATE_DIR` overrides.
 */
export const EngineConfigSchema = z.object({
  project: z.string().min(1),
  stateStore: z
    .object({
      dir: z.string().optional(),
    })
    .default({}),
});

export type EngineConfig = z.infer<typeof EngineConfigSchema>;

/**
 * Resolve runtime config from (in order of precedence):
 *   1. env vars (VIBEFLOW_STATE_DIR, VIBEFLOW_PROJECT)
 *   2. vibeflow.config.json in cwd
 *   3. defaults (.vibeflow/state/)
 */
export function resolveConfig(cwd: string = process.cwd()): EngineConfig {
  const fileConfig = loadFileConfig(cwd);
  const project =
    process.env.VIBEFLOW_PROJECT ?? fileConfig.project ?? "default";

  const dir =
    process.env.VIBEFLOW_STATE_DIR ?? fileConfig.stateStore?.dir;

  return EngineConfigSchema.parse({
    project,
    stateStore: dir ? { dir } : {},
  });
}

function loadFileConfig(cwd: string): Partial<EngineConfig> {
  const configPath = path.join(cwd, "vibeflow.config.json");
  if (!fs.existsSync(configPath)) return {};
  try {
    const raw = JSON.parse(fs.readFileSync(configPath, "utf8")) as Record<
      string,
      unknown
    >;
    const project = raw.project;
    const storeRaw =
      typeof raw.stateStore === "object" && raw.stateStore !== null
        ? (raw.stateStore as Record<string, unknown>)
        : {};
    const dir = typeof storeRaw.dir === "string" ? storeRaw.dir : undefined;
    return {
      ...(typeof project === "string" ? { project } : {}),
      ...(dir ? { stateStore: { dir } } : {}),
    };
  } catch {
    return {};
  }
}
