import { z } from "zod";
export declare const ModeSchema: z.ZodEnum<["solo", "team"]>;
export type Mode = z.infer<typeof ModeSchema>;
export declare const EngineConfigSchema: z.ZodObject<{
    project: z.ZodString;
    mode: z.ZodEnum<["solo", "team"]>;
    stateStore: z.ZodDefault<z.ZodObject<{
        sqlitePath: z.ZodOptional<z.ZodString>;
        postgresUrl: z.ZodOptional<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        sqlitePath?: string | undefined;
        postgresUrl?: string | undefined;
    }, {
        sqlitePath?: string | undefined;
        postgresUrl?: string | undefined;
    }>>;
}, "strip", z.ZodTypeAny, {
    project: string;
    mode: "solo" | "team";
    stateStore: {
        sqlitePath?: string | undefined;
        postgresUrl?: string | undefined;
    };
}, {
    project: string;
    mode: "solo" | "team";
    stateStore?: {
        sqlitePath?: string | undefined;
        postgresUrl?: string | undefined;
    } | undefined;
}>;
export type EngineConfig = z.infer<typeof EngineConfigSchema>;
/**
 * Resolve runtime config from (in order of precedence):
 *   1. env vars (VIBEFLOW_MODE, VIBEFLOW_SQLITE_PATH, VIBEFLOW_POSTGRES_URL, VIBEFLOW_PROJECT)
 *   2. vibeflow.config.json in cwd
 *   3. defaults (solo / .vibeflow/state.db)
 */
export declare function resolveConfig(cwd?: string): EngineConfig;
