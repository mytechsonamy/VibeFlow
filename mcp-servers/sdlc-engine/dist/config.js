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
    // Sprint 21-A: primary-artifact excerption. `excerptTokenBudget`
    // is the size above which the orchestrator excerpts a primary for
    // the reviewer prompt (the specialist path always gets the full
    // file). `excerptStrategy` picks section-scored selection
    // ("semantic") vs the legacy positional head/tail ("headtail");
    // "semantic" falls back to head/tail when the doc has no detectable
    // section structure, so it is never worse than the legacy path.
    excerptTokenBudget: z.number().int().min(1000).max(200000).default(30000),
    excerptStrategy: z.enum(["semantic", "headtail"]).default("semantic"),
})
    .default({
    maxIterations: 5,
    approvalThreshold: 0.9,
    iteration: { enabled: true },
    excerptTokenBudget: 30000,
    excerptStrategy: "semantic",
});
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
/**
 * Sprint 20-H: learning-loop bounds. Governs the `consensus-history`
 * mode (Sprint 20-B/C) of learning-loop-engine. `sprintWindow` is the
 * default look-back when `--sprint N` is absent; `minObservations` is
 * the evidence floor every detected pattern must clear (mirrors the
 * skill's universal ≥ 3-observation rule); `enabled` is the kill
 * switch. Defaults match the SKILL.md constants so bash + TS agree.
 */
export const LearningLoopConfigSchema = z
    .object({
    enabled: z.boolean().default(true),
    sprintWindow: z.number().int().min(1).max(50).default(3),
    minObservations: z.number().int().min(1).max(20).default(3),
})
    .default({ enabled: true, sprintWindow: 3, minObservations: 3 });
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
export const ReviewerMemoryConfigSchema = z
    .object({
    enabled: z.boolean().default(true),
    maxEntriesPerArtifact: z.number().int().min(1).max(50).default(5),
    tokenBudget: z.number().int().min(50).max(5000).default(600),
    compaction: z.enum(["recency", "theme-aware"]).default("theme-aware"),
})
    .default({
    enabled: true,
    maxEntriesPerArtifact: 5,
    tokenBudget: 600,
    compaction: "theme-aware",
});
export const EngineConfigSchema = z.object({
    project: z.string().min(1),
    stateStore: z
        .object({
        dir: z.string().optional(),
    })
        .default({}),
    consensus: ConsensusConfigSchema,
    phaseRunner: PhaseRunnerConfigSchema,
    learningLoop: LearningLoopConfigSchema,
    reviewerMemory: ReviewerMemoryConfigSchema,
});
/**
 * Resolve runtime config from (in order of precedence):
 *   1. env vars (VIBEFLOW_STATE_DIR, VIBEFLOW_PROJECT)
 *   2. vibeflow.config.json in cwd
 *   3. defaults (.vibeflow/state/)
 */
export function resolveConfig(cwd = process.cwd()) {
    const fileConfig = loadFileConfig(cwd);
    const project = process.env.VIBEFLOW_PROJECT ?? fileConfig.project ?? "default";
    const dir = process.env.VIBEFLOW_STATE_DIR ?? fileConfig.stateStore?.dir;
    return EngineConfigSchema.parse({
        project,
        stateStore: dir ? { dir } : {},
        consensus: fileConfig.consensus ?? {},
        phaseRunner: fileConfig.phaseRunner ?? {},
        learningLoop: fileConfig.learningLoop ?? {},
        reviewerMemory: fileConfig.reviewerMemory ?? {},
    });
}
function loadFileConfig(cwd) {
    const configPath = path.join(cwd, "vibeflow.config.json");
    if (!fs.existsSync(configPath))
        return {};
    try {
        const raw = JSON.parse(fs.readFileSync(configPath, "utf8"));
        const project = raw.project;
        const storeRaw = typeof raw.stateStore === "object" && raw.stateStore !== null
            ? raw.stateStore
            : {};
        const dir = typeof storeRaw.dir === "string" ? storeRaw.dir : undefined;
        // Sprint 17-F: read consensus.* and parse through the schema so
        // partial keys pick up defaults. Malformed fields fall back
        // silently to defaults (no hard fail on a mistyped threshold).
        let consensus;
        if (typeof raw.consensus === "object" && raw.consensus !== null) {
            const parsed = ConsensusConfigSchema.safeParse(raw.consensus);
            if (parsed.success) {
                consensus = parsed.data;
            }
        }
        // Sprint 19-G: phase-runner config, same silent-fallback pattern
        // as consensus — malformed fields keep the schema defaults.
        let phaseRunner;
        if (typeof raw.phaseRunner === "object" && raw.phaseRunner !== null) {
            const parsed = PhaseRunnerConfigSchema.safeParse(raw.phaseRunner);
            if (parsed.success) {
                phaseRunner = parsed.data;
            }
        }
        // Sprint 20-H: learning-loop + reviewer-memory config, same
        // silent-fallback pattern — malformed fields keep schema defaults.
        let learningLoop;
        if (typeof raw.learningLoop === "object" && raw.learningLoop !== null) {
            const parsed = LearningLoopConfigSchema.safeParse(raw.learningLoop);
            if (parsed.success) {
                learningLoop = parsed.data;
            }
        }
        let reviewerMemory;
        if (typeof raw.reviewerMemory === "object" && raw.reviewerMemory !== null) {
            const parsed = ReviewerMemoryConfigSchema.safeParse(raw.reviewerMemory);
            if (parsed.success) {
                reviewerMemory = parsed.data;
            }
        }
        return {
            ...(typeof project === "string" ? { project } : {}),
            ...(dir ? { stateStore: { dir } } : {}),
            ...(consensus ? { consensus } : {}),
            ...(phaseRunner ? { phaseRunner } : {}),
            ...(learningLoop ? { learningLoop } : {}),
            ...(reviewerMemory ? { reviewerMemory } : {}),
        };
    }
    catch {
        return {};
    }
}
//# sourceMappingURL=config.js.map