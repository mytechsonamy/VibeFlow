import { z } from "zod";
/**
 * Sprint 11-E: state is always file-backed. The legacy `mode` (solo/team)
 * and `stateStore.{sqlitePath,postgresUrl}` fields are gone. The engine
 * reads exactly one location for project state: `stateStore.dir`
 * (default `<cwd>/.vibeflow/state`). `VIBEFLOW_STATE_DIR` overrides.
 */
export declare const EngineConfigSchema: z.ZodObject<{
    project: z.ZodString;
    stateStore: z.ZodDefault<z.ZodObject<{
        dir: z.ZodOptional<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        dir?: string | undefined;
    }, {
        dir?: string | undefined;
    }>>;
}, "strip", z.ZodTypeAny, {
    project: string;
    stateStore: {
        dir?: string | undefined;
    };
}, {
    project: string;
    stateStore?: {
        dir?: string | undefined;
    } | undefined;
}>;
export type EngineConfig = z.infer<typeof EngineConfigSchema>;
/**
 * Resolve runtime config from (in order of precedence):
 *   1. env vars (VIBEFLOW_STATE_DIR, VIBEFLOW_PROJECT)
 *   2. vibeflow.config.json in cwd
 *   3. defaults (.vibeflow/state/)
 */
export declare function resolveConfig(cwd?: string): EngineConfig;
