import { z } from "zod";
export declare const ModeSchema: z.ZodEnum<["solo", "team"]>;
export type Mode = z.infer<typeof ModeSchema>;
export declare const EngineConfigSchema: z.ZodObject<{
    project: z.ZodString;
    mode: z.ZodEnum<["solo", "team"]>;
    stateStore: z.ZodDefault<z.ZodObject<{
        sqlitePath: z.ZodOptional<z.ZodString>;
        postgresUrl: z.ZodOptional<z.ZodString>;
        /**
         * Filesystem backend directory. When set, the engine uses the
         * FilesystemStateStore (Sprint 11) regardless of mode. In Sprint
         * 11-D this becomes the default; in Sprint 11-E the other two
         * fields are deleted.
         */
        dir: z.ZodOptional<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        sqlitePath?: string | undefined;
        postgresUrl?: string | undefined;
        dir?: string | undefined;
    }, {
        sqlitePath?: string | undefined;
        postgresUrl?: string | undefined;
        dir?: string | undefined;
    }>>;
}, "strip", z.ZodTypeAny, {
    project: string;
    mode: "solo" | "team";
    stateStore: {
        sqlitePath?: string | undefined;
        postgresUrl?: string | undefined;
        dir?: string | undefined;
    };
}, {
    project: string;
    mode: "solo" | "team";
    stateStore?: {
        sqlitePath?: string | undefined;
        postgresUrl?: string | undefined;
        dir?: string | undefined;
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
