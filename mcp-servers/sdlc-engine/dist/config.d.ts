import { z } from "zod";
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
export declare const ConsensusConfigSchema: z.ZodDefault<z.ZodObject<{
    quorum: z.ZodOptional<z.ZodNumber>;
    maxIterations: z.ZodDefault<z.ZodNumber>;
    approvalThreshold: z.ZodDefault<z.ZodNumber>;
    iteration: z.ZodDefault<z.ZodObject<{
        enabled: z.ZodDefault<z.ZodBoolean>;
    }, "strip", z.ZodTypeAny, {
        enabled: boolean;
    }, {
        enabled?: boolean | undefined;
    }>>;
}, "strip", z.ZodTypeAny, {
    maxIterations: number;
    approvalThreshold: number;
    iteration: {
        enabled: boolean;
    };
    quorum?: number | undefined;
}, {
    quorum?: number | undefined;
    maxIterations?: number | undefined;
    approvalThreshold?: number | undefined;
    iteration?: {
        enabled?: boolean | undefined;
    } | undefined;
}>>;
export type ConsensusConfig = z.infer<typeof ConsensusConfigSchema>;
/**
 * Sprint 19-G: phase-runner bounds. `autoAdvance` gates whether
 * the runner calls `sdlc_advance_phase` automatically on APPROVED;
 * `maxConvergenceAttempts` bounds the specialist-apply cycles on
 * top of `consensus.maxIterations` (each attempt runs a full
 * reviewer-round loop).
 */
export declare const PhaseRunnerConfigSchema: z.ZodDefault<z.ZodObject<{
    autoAdvance: z.ZodDefault<z.ZodBoolean>;
    maxConvergenceAttempts: z.ZodDefault<z.ZodNumber>;
}, "strip", z.ZodTypeAny, {
    autoAdvance: boolean;
    maxConvergenceAttempts: number;
}, {
    autoAdvance?: boolean | undefined;
    maxConvergenceAttempts?: number | undefined;
}>>;
export type PhaseRunnerConfig = z.infer<typeof PhaseRunnerConfigSchema>;
export declare const EngineConfigSchema: z.ZodObject<{
    project: z.ZodString;
    stateStore: z.ZodDefault<z.ZodObject<{
        dir: z.ZodOptional<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        dir?: string | undefined;
    }, {
        dir?: string | undefined;
    }>>;
    consensus: z.ZodDefault<z.ZodObject<{
        quorum: z.ZodOptional<z.ZodNumber>;
        maxIterations: z.ZodDefault<z.ZodNumber>;
        approvalThreshold: z.ZodDefault<z.ZodNumber>;
        iteration: z.ZodDefault<z.ZodObject<{
            enabled: z.ZodDefault<z.ZodBoolean>;
        }, "strip", z.ZodTypeAny, {
            enabled: boolean;
        }, {
            enabled?: boolean | undefined;
        }>>;
    }, "strip", z.ZodTypeAny, {
        maxIterations: number;
        approvalThreshold: number;
        iteration: {
            enabled: boolean;
        };
        quorum?: number | undefined;
    }, {
        quorum?: number | undefined;
        maxIterations?: number | undefined;
        approvalThreshold?: number | undefined;
        iteration?: {
            enabled?: boolean | undefined;
        } | undefined;
    }>>;
    phaseRunner: z.ZodDefault<z.ZodObject<{
        autoAdvance: z.ZodDefault<z.ZodBoolean>;
        maxConvergenceAttempts: z.ZodDefault<z.ZodNumber>;
    }, "strip", z.ZodTypeAny, {
        autoAdvance: boolean;
        maxConvergenceAttempts: number;
    }, {
        autoAdvance?: boolean | undefined;
        maxConvergenceAttempts?: number | undefined;
    }>>;
}, "strip", z.ZodTypeAny, {
    project: string;
    stateStore: {
        dir?: string | undefined;
    };
    consensus: {
        maxIterations: number;
        approvalThreshold: number;
        iteration: {
            enabled: boolean;
        };
        quorum?: number | undefined;
    };
    phaseRunner: {
        autoAdvance: boolean;
        maxConvergenceAttempts: number;
    };
}, {
    project: string;
    stateStore?: {
        dir?: string | undefined;
    } | undefined;
    consensus?: {
        quorum?: number | undefined;
        maxIterations?: number | undefined;
        approvalThreshold?: number | undefined;
        iteration?: {
            enabled?: boolean | undefined;
        } | undefined;
    } | undefined;
    phaseRunner?: {
        autoAdvance?: boolean | undefined;
        maxConvergenceAttempts?: number | undefined;
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
