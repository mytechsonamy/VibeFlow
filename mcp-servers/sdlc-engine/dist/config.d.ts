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
    excerptTokenBudget: z.ZodDefault<z.ZodNumber>;
    excerptStrategy: z.ZodDefault<z.ZodEnum<["semantic", "headtail"]>>;
}, "strip", z.ZodTypeAny, {
    maxIterations: number;
    approvalThreshold: number;
    iteration: {
        enabled: boolean;
    };
    excerptTokenBudget: number;
    excerptStrategy: "semantic" | "headtail";
    quorum?: number | undefined;
}, {
    quorum?: number | undefined;
    maxIterations?: number | undefined;
    approvalThreshold?: number | undefined;
    iteration?: {
        enabled?: boolean | undefined;
    } | undefined;
    excerptTokenBudget?: number | undefined;
    excerptStrategy?: "semantic" | "headtail" | undefined;
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
/**
 * Sprint 20-H: learning-loop bounds. Governs the `consensus-history`
 * mode (Sprint 20-B/C) of learning-loop-engine. `sprintWindow` is the
 * default look-back when `--sprint N` is absent; `minObservations` is
 * the evidence floor every detected pattern must clear (mirrors the
 * skill's universal ≥ 3-observation rule); `enabled` is the kill
 * switch. Defaults match the SKILL.md constants so bash + TS agree.
 */
export declare const LearningLoopConfigSchema: z.ZodDefault<z.ZodObject<{
    enabled: z.ZodDefault<z.ZodBoolean>;
    sprintWindow: z.ZodDefault<z.ZodNumber>;
    minObservations: z.ZodDefault<z.ZodNumber>;
}, "strip", z.ZodTypeAny, {
    enabled: boolean;
    sprintWindow: number;
    minObservations: number;
}, {
    enabled?: boolean | undefined;
    sprintWindow?: number | undefined;
    minObservations?: number | undefined;
}>>;
export type LearningLoopConfig = z.infer<typeof LearningLoopConfigSchema>;
/**
 * Sprint 20-H: cross-session reviewer-memory bounds. `enabled` is the
 * kill switch (false ⇒ orchestrator omits the PRIOR REVIEW MEMORY
 * block and the aggregator stops appending memory entries);
 * `maxEntriesPerArtifact` caps the per-(reviewer, artifact) store;
 * `tokenBudget` bounds the injected memory block (chars ≈ tokens × 4).
 * `compaction` (Sprint 21-B) picks what happens when the cap is hit:
 * "recency" silently drops the oldest entry; "theme-aware" folds the
 * dropped entry's criticals into a rolling recurrence summary so a
 * long-standing objection keeps its "this keeps coming back" signal.
 * Defaults match consensus-aggregator.sh + consensus-orchestrator.
 */
export declare const ReviewerMemoryConfigSchema: z.ZodDefault<z.ZodObject<{
    enabled: z.ZodDefault<z.ZodBoolean>;
    maxEntriesPerArtifact: z.ZodDefault<z.ZodNumber>;
    tokenBudget: z.ZodDefault<z.ZodNumber>;
    compaction: z.ZodDefault<z.ZodEnum<["recency", "theme-aware"]>>;
}, "strip", z.ZodTypeAny, {
    enabled: boolean;
    maxEntriesPerArtifact: number;
    tokenBudget: number;
    compaction: "recency" | "theme-aware";
}, {
    enabled?: boolean | undefined;
    maxEntriesPerArtifact?: number | undefined;
    tokenBudget?: number | undefined;
    compaction?: "recency" | "theme-aware" | undefined;
}>>;
export type ReviewerMemoryConfig = z.infer<typeof ReviewerMemoryConfigSchema>;
/**
 * Sprint 22-D: bounds for the `learning-apply` skill, which turns
 * learning-loop recommendations into diff-first, operator-confirmed
 * `vibeflow.config.json` patches. `enabled` is the kill switch;
 * `maxRelativeStep` caps how far a single numeric tune may move from the
 * current value (0.5 = ±50%, then clamped to each field's schema range);
 * `minObservations` is the evidence floor a finding must clear before it
 * is eligible to propose a change.
 *
 * Sprint 23-A: the nested `autoApply` block opts a project into bounded
 * autonomous tuning. It is **OFF by default** — the framework stays
 * propose-only unless a project turns it on. `keys` is an allowlist:
 * only config keys listed here may auto-apply (and only ones in the
 * config-tune key map); everything else stays operator-confirmed.
 * `revertOnRegression` arms the aggregator's auto-revert watch, which
 * restores the pre-change snapshot if the next consensus round's
 * agreement drops by more than `regressionDelta`.
 */
export declare const AutoApplyConfigSchema: z.ZodDefault<z.ZodObject<{
    enabled: z.ZodDefault<z.ZodBoolean>;
    keys: z.ZodDefault<z.ZodArray<z.ZodString, "many">>;
    revertOnRegression: z.ZodDefault<z.ZodBoolean>;
    regressionDelta: z.ZodDefault<z.ZodNumber>;
}, "strip", z.ZodTypeAny, {
    enabled: boolean;
    keys: string[];
    revertOnRegression: boolean;
    regressionDelta: number;
}, {
    enabled?: boolean | undefined;
    keys?: string[] | undefined;
    revertOnRegression?: boolean | undefined;
    regressionDelta?: number | undefined;
}>>;
export type AutoApplyConfig = z.infer<typeof AutoApplyConfigSchema>;
export declare const LearningApplyConfigSchema: z.ZodDefault<z.ZodObject<{
    enabled: z.ZodDefault<z.ZodBoolean>;
    maxRelativeStep: z.ZodDefault<z.ZodNumber>;
    minObservations: z.ZodDefault<z.ZodNumber>;
    autoApply: z.ZodDefault<z.ZodObject<{
        enabled: z.ZodDefault<z.ZodBoolean>;
        keys: z.ZodDefault<z.ZodArray<z.ZodString, "many">>;
        revertOnRegression: z.ZodDefault<z.ZodBoolean>;
        regressionDelta: z.ZodDefault<z.ZodNumber>;
    }, "strip", z.ZodTypeAny, {
        enabled: boolean;
        keys: string[];
        revertOnRegression: boolean;
        regressionDelta: number;
    }, {
        enabled?: boolean | undefined;
        keys?: string[] | undefined;
        revertOnRegression?: boolean | undefined;
        regressionDelta?: number | undefined;
    }>>;
}, "strip", z.ZodTypeAny, {
    enabled: boolean;
    minObservations: number;
    maxRelativeStep: number;
    autoApply: {
        enabled: boolean;
        keys: string[];
        revertOnRegression: boolean;
        regressionDelta: number;
    };
}, {
    enabled?: boolean | undefined;
    minObservations?: number | undefined;
    maxRelativeStep?: number | undefined;
    autoApply?: {
        enabled?: boolean | undefined;
        keys?: string[] | undefined;
        revertOnRegression?: boolean | undefined;
        regressionDelta?: number | undefined;
    } | undefined;
}>>;
export type LearningApplyConfig = z.infer<typeof LearningApplyConfigSchema>;
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
        excerptTokenBudget: z.ZodDefault<z.ZodNumber>;
        excerptStrategy: z.ZodDefault<z.ZodEnum<["semantic", "headtail"]>>;
    }, "strip", z.ZodTypeAny, {
        maxIterations: number;
        approvalThreshold: number;
        iteration: {
            enabled: boolean;
        };
        excerptTokenBudget: number;
        excerptStrategy: "semantic" | "headtail";
        quorum?: number | undefined;
    }, {
        quorum?: number | undefined;
        maxIterations?: number | undefined;
        approvalThreshold?: number | undefined;
        iteration?: {
            enabled?: boolean | undefined;
        } | undefined;
        excerptTokenBudget?: number | undefined;
        excerptStrategy?: "semantic" | "headtail" | undefined;
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
    learningLoop: z.ZodDefault<z.ZodObject<{
        enabled: z.ZodDefault<z.ZodBoolean>;
        sprintWindow: z.ZodDefault<z.ZodNumber>;
        minObservations: z.ZodDefault<z.ZodNumber>;
    }, "strip", z.ZodTypeAny, {
        enabled: boolean;
        sprintWindow: number;
        minObservations: number;
    }, {
        enabled?: boolean | undefined;
        sprintWindow?: number | undefined;
        minObservations?: number | undefined;
    }>>;
    reviewerMemory: z.ZodDefault<z.ZodObject<{
        enabled: z.ZodDefault<z.ZodBoolean>;
        maxEntriesPerArtifact: z.ZodDefault<z.ZodNumber>;
        tokenBudget: z.ZodDefault<z.ZodNumber>;
        compaction: z.ZodDefault<z.ZodEnum<["recency", "theme-aware"]>>;
    }, "strip", z.ZodTypeAny, {
        enabled: boolean;
        maxEntriesPerArtifact: number;
        tokenBudget: number;
        compaction: "recency" | "theme-aware";
    }, {
        enabled?: boolean | undefined;
        maxEntriesPerArtifact?: number | undefined;
        tokenBudget?: number | undefined;
        compaction?: "recency" | "theme-aware" | undefined;
    }>>;
    learningApply: z.ZodDefault<z.ZodObject<{
        enabled: z.ZodDefault<z.ZodBoolean>;
        maxRelativeStep: z.ZodDefault<z.ZodNumber>;
        minObservations: z.ZodDefault<z.ZodNumber>;
        autoApply: z.ZodDefault<z.ZodObject<{
            enabled: z.ZodDefault<z.ZodBoolean>;
            keys: z.ZodDefault<z.ZodArray<z.ZodString, "many">>;
            revertOnRegression: z.ZodDefault<z.ZodBoolean>;
            regressionDelta: z.ZodDefault<z.ZodNumber>;
        }, "strip", z.ZodTypeAny, {
            enabled: boolean;
            keys: string[];
            revertOnRegression: boolean;
            regressionDelta: number;
        }, {
            enabled?: boolean | undefined;
            keys?: string[] | undefined;
            revertOnRegression?: boolean | undefined;
            regressionDelta?: number | undefined;
        }>>;
    }, "strip", z.ZodTypeAny, {
        enabled: boolean;
        minObservations: number;
        maxRelativeStep: number;
        autoApply: {
            enabled: boolean;
            keys: string[];
            revertOnRegression: boolean;
            regressionDelta: number;
        };
    }, {
        enabled?: boolean | undefined;
        minObservations?: number | undefined;
        maxRelativeStep?: number | undefined;
        autoApply?: {
            enabled?: boolean | undefined;
            keys?: string[] | undefined;
            revertOnRegression?: boolean | undefined;
            regressionDelta?: number | undefined;
        } | undefined;
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
        excerptTokenBudget: number;
        excerptStrategy: "semantic" | "headtail";
        quorum?: number | undefined;
    };
    phaseRunner: {
        autoAdvance: boolean;
        maxConvergenceAttempts: number;
    };
    learningLoop: {
        enabled: boolean;
        sprintWindow: number;
        minObservations: number;
    };
    reviewerMemory: {
        enabled: boolean;
        maxEntriesPerArtifact: number;
        tokenBudget: number;
        compaction: "recency" | "theme-aware";
    };
    learningApply: {
        enabled: boolean;
        minObservations: number;
        maxRelativeStep: number;
        autoApply: {
            enabled: boolean;
            keys: string[];
            revertOnRegression: boolean;
            regressionDelta: number;
        };
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
        excerptTokenBudget?: number | undefined;
        excerptStrategy?: "semantic" | "headtail" | undefined;
    } | undefined;
    phaseRunner?: {
        autoAdvance?: boolean | undefined;
        maxConvergenceAttempts?: number | undefined;
    } | undefined;
    learningLoop?: {
        enabled?: boolean | undefined;
        sprintWindow?: number | undefined;
        minObservations?: number | undefined;
    } | undefined;
    reviewerMemory?: {
        enabled?: boolean | undefined;
        maxEntriesPerArtifact?: number | undefined;
        tokenBudget?: number | undefined;
        compaction?: "recency" | "theme-aware" | undefined;
    } | undefined;
    learningApply?: {
        enabled?: boolean | undefined;
        minObservations?: number | undefined;
        maxRelativeStep?: number | undefined;
        autoApply?: {
            enabled?: boolean | undefined;
            keys?: string[] | undefined;
            revertOnRegression?: boolean | undefined;
            regressionDelta?: number | undefined;
        } | undefined;
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
