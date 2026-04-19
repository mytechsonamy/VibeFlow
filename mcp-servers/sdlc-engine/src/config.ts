import { z } from "zod";
import * as fs from "node:fs";
import * as path from "node:path";

export const ModeSchema = z.enum(["solo", "team"]);
export type Mode = z.infer<typeof ModeSchema>;

export const EngineConfigSchema = z.object({
  project: z.string().min(1),
  mode: ModeSchema,
  stateStore: z
    .object({
      sqlitePath: z.string().optional(),
      postgresUrl: z.string().optional(),
      /**
       * Filesystem backend directory. When set, the engine uses the
       * FilesystemStateStore (Sprint 11) regardless of mode. In Sprint
       * 11-D this becomes the default; in Sprint 11-E the other two
       * fields are deleted.
       */
      dir: z.string().optional(),
    })
    .default({}),
});

export type EngineConfig = z.infer<typeof EngineConfigSchema>;

/**
 * Resolve runtime config from (in order of precedence):
 *   1. env vars (VIBEFLOW_MODE, VIBEFLOW_SQLITE_PATH, VIBEFLOW_POSTGRES_URL, VIBEFLOW_PROJECT)
 *   2. vibeflow.config.json in cwd
 *   3. defaults (solo / .vibeflow/state.db)
 */
export function resolveConfig(cwd: string = process.cwd()): EngineConfig {
  const fileConfig = loadFileConfig(cwd);
  const mode = (process.env.VIBEFLOW_MODE ?? fileConfig.mode ?? "solo") as Mode;
  const project =
    process.env.VIBEFLOW_PROJECT ?? fileConfig.project ?? "default";

  const sqlitePath =
    process.env.VIBEFLOW_SQLITE_PATH ??
    fileConfig.stateStore?.sqlitePath ??
    path.join(cwd, ".vibeflow", "state.db");

  const postgresUrl =
    process.env.VIBEFLOW_POSTGRES_URL ?? fileConfig.stateStore?.postgresUrl;

  const dir =
    process.env.VIBEFLOW_STATE_DIR ?? fileConfig.stateStore?.dir;

  return EngineConfigSchema.parse({
    project,
    mode,
    stateStore: { sqlitePath, postgresUrl, dir },
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
    const mode = raw.mode;
    const project = raw.project;
    const storeRaw =
      typeof raw.stateStore === "object" && raw.stateStore !== null
        ? (raw.stateStore as Record<string, unknown>)
        : {};
    const dir = typeof storeRaw.dir === "string" ? storeRaw.dir : undefined;
    const sqlitePath =
      typeof storeRaw.sqlitePath === "string" ? storeRaw.sqlitePath : undefined;
    const postgresUrl =
      typeof storeRaw.postgresUrl === "string"
        ? storeRaw.postgresUrl
        : undefined;
    return {
      ...(typeof project === "string" ? { project } : {}),
      ...(typeof mode === "string" && (mode === "solo" || mode === "team")
        ? { mode }
        : {}),
      stateStore: {
        ...(sqlitePath ? { sqlitePath } : {}),
        ...(postgresUrl ? { postgresUrl } : {}),
        ...(dir ? { dir } : {}),
      },
    };
  } catch {
    return {};
  }
}
