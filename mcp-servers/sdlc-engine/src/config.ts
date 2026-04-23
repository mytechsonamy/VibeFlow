import { z } from "zod";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Sprint 11-E: state is always file-backed. The legacy `mode` (solo/team)
 * and `stateStore.{sqlitePath,postgresUrl}` fields are gone. The engine
 * reads exactly one location for project state: `stateStore.dir`
 * (default `<cwd>/.vibeflow/state`). `VIBEFLOW_STATE_DIR` overrides.
 *
 * Sprint 17-F: typed consensus config. Governs the iterative
 * negotiation loop (maxIterations, approvalThreshold) and the
 * rollback switch (iteration.enabled). Defaults match the
 * orchestrator SKILL.md constants so bash + TS read the same
 * numbers.
 */
export const ConsensusConfigSchema = z
  .object({
    quorum: z.number().int().min(1).optional(),
    maxIterations: z.number().int().min(1).max(20).default(5),
    approvalThreshold: z.number().min(0).max(1).default(0.9),
    iteration: z
      .object({
        enabled: z.boolean().default(true),
      })
      .default({ enabled: true }),
  })
  .default({
    maxIterations: 5,
    approvalThreshold: 0.9,
    iteration: { enabled: true },
  });

export type ConsensusConfig = z.infer<typeof ConsensusConfigSchema>;

/**
 * Sprint 19-G: phase-runner bounds. `autoAdvance` gates whether
 * the runner calls `sdlc_advance_phase` automatically on APPROVED;
 * `maxConvergenceAttempts` bounds the specialist-apply cycles on
 * top of `consensus.maxIterations` (each attempt runs a full
 * reviewer-round loop).
 */
export const PhaseRunnerConfigSchema = z
  .object({
    autoAdvance: z.boolean().default(true),
    maxConvergenceAttempts: z.number().int().min(1).max(10).default(3),
  })
  .default({
    autoAdvance: true,
    maxConvergenceAttempts: 3,
  });

export type PhaseRunnerConfig = z.infer<typeof PhaseRunnerConfigSchema>;

export const EngineConfigSchema = z.object({
  project: z.string().min(1),
  stateStore: z
    .object({
      dir: z.string().optional(),
    })
    .default({}),
  consensus: ConsensusConfigSchema,
  phaseRunner: PhaseRunnerConfigSchema,
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
    consensus: fileConfig.consensus ?? {},
    phaseRunner: fileConfig.phaseRunner ?? {},
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
    // Sprint 17-F: read consensus.* and parse through the schema so
    // partial keys pick up defaults. Malformed fields fall back
    // silently to defaults (no hard fail on a mistyped threshold).
    let consensus: ConsensusConfig | undefined;
    if (typeof raw.consensus === "object" && raw.consensus !== null) {
      const parsed = ConsensusConfigSchema.safeParse(raw.consensus);
      if (parsed.success) {
        consensus = parsed.data;
      }
    }
    // Sprint 19-G: phase-runner config, same silent-fallback pattern
    // as consensus — malformed fields keep the schema defaults.
    let phaseRunner: PhaseRunnerConfig | undefined;
    if (typeof raw.phaseRunner === "object" && raw.phaseRunner !== null) {
      const parsed = PhaseRunnerConfigSchema.safeParse(raw.phaseRunner);
      if (parsed.success) {
        phaseRunner = parsed.data;
      }
    }
    return {
      ...(typeof project === "string" ? { project } : {}),
      ...(dir ? { stateStore: { dir } } : {}),
      ...(consensus ? { consensus } : {}),
      ...(phaseRunner ? { phaseRunner } : {}),
    };
  } catch {
    return {};
  }
}
