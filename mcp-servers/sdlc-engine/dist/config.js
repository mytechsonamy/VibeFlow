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
 *
 * Sprint 24: `demoteAfterReverts` makes auto-apply self-correcting — a
 * key auto-reverted this many times (in the consensus history window) is
 * demoted back to propose-only even while it stays allowlisted, a
 * longer-horizon guard than the per-sprint cooldown. `transactional`
 * makes a run's auto-applies one unit: a single pre-batch snapshot + one
 * watch over `keys[]` that reverts/holds the whole set atomically.
 */
export const AutoApplyConfigSchema = z
    .object({
    enabled: z.boolean().default(false),
    keys: z.array(z.string()).default([]),
    revertOnRegression: z.boolean().default(true),
    regressionDelta: z.number().min(0).max(1).default(0.05),
    demoteAfterReverts: z.number().int().min(1).max(100).default(3),
    transactional: z.boolean().default(true),
})
    .default({
    enabled: false,
    keys: [],
    revertOnRegression: true,
    regressionDelta: 0.05,
    demoteAfterReverts: 3,
    transactional: true,
});
export const LearningApplyConfigSchema = z
    .object({
    enabled: z.boolean().default(true),
    maxRelativeStep: z.number().min(0).max(1).default(0.5),
    minObservations: z.number().int().min(1).max(20).default(3),
    autoApply: AutoApplyConfigSchema,
    // Sprint 27-A: template-route autonomy. When true, a
    // `recurring-suggestion-theme` finding auto-forks the matching phase
    // specialist to produce a diff-first patch (propose-only — the
    // operator still applies it via apply-arbiter-patch). Default OFF ⇒
    // template-route stays recommend-only (Sprint 22-C).
    autoForkSpecialist: z.boolean().default(false),
})
    .default({
    enabled: true,
    maxRelativeStep: 0.5,
    minObservations: 3,
    autoApply: {
        enabled: false,
        keys: [],
        revertOnRegression: true,
        regressionDelta: 0.05,
    },
    autoForkSpecialist: false,
});
/**
 * Sprint 25-C: bounds for the autonomous-loop audit reader
 * (`hooks/scripts/loop-audit.sh`, surfaced by `/vibeflow:status`).
 * `window` is how many recent `auto-*` rows of `history.jsonl` the
 * per-key tally summarizes — bounds the audit to recent activity.
 */
export const LoopAuditConfigSchema = z
    .object({
    window: z.number().int().min(1).max(1000).default(20),
})
    .default({ window: 20 });
/**
 * Sprint 26-B: phase-gate strictness. `enforceEntryCriteria` is an
 * opt-in (default OFF) that makes `sdlc_advance_phase` also require the
 * TARGET phase's `entryCriteria` to be satisfied — e.g. no entering
 * DEPLOYMENT without a recorded `release.decision.go`. Default off keeps
 * existing advances unchanged; consumers that want the stricter gate
 * turn it on.
 */
export const GatesConfigSchema = z
    .object({
    enforceEntryCriteria: z.boolean().default(false),
})
    .default({ enforceEntryCriteria: false });
/**
 * Sprint 28-A: cross-project meta-learning. `enabled` (default OFF) opts
 * a project into mirroring its auto-tune *outcomes* (key + outcome +
 * phase + one-way projectHash — never code/content/file names) to a
 * shared `~/.vibeflow/global-learning.jsonl` store, and into reading that
 * store for cross-project recommendations. Read-only: it never
 * auto-allowlists or auto-applies — one repo's record can't change
 * another's behaviour. Off by default so nothing leaves a project.
 */
export const GlobalLearningConfigSchema = z
    .object({
    enabled: z.boolean().default(false),
})
    .default({ enabled: false });
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
    learningApply: LearningApplyConfigSchema,
    loopAudit: LoopAuditConfigSchema,
    gates: GatesConfigSchema,
    globalLearning: GlobalLearningConfigSchema,
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
        learningApply: fileConfig.learningApply ?? {},
        loopAudit: fileConfig.loopAudit ?? {},
        gates: fileConfig.gates ?? {},
        globalLearning: fileConfig.globalLearning ?? {},
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
        // Sprint 22-D: learning-apply bounds, same silent-fallback pattern.
        let learningApply;
        if (typeof raw.learningApply === "object" && raw.learningApply !== null) {
            const parsed = LearningApplyConfigSchema.safeParse(raw.learningApply);
            if (parsed.success) {
                learningApply = parsed.data;
            }
        }
        // Sprint 25-C: loop-audit window, same silent-fallback pattern.
        let loopAudit;
        if (typeof raw.loopAudit === "object" && raw.loopAudit !== null) {
            const parsed = LoopAuditConfigSchema.safeParse(raw.loopAudit);
            if (parsed.success) {
                loopAudit = parsed.data;
            }
        }
        // Sprint 26-B: phase-gate strictness, same silent-fallback pattern.
        let gates;
        if (typeof raw.gates === "object" && raw.gates !== null) {
            const parsed = GatesConfigSchema.safeParse(raw.gates);
            if (parsed.success) {
                gates = parsed.data;
            }
        }
        // Sprint 28-A: cross-project meta-learning opt-in, same fallback.
        let globalLearning;
        if (typeof raw.globalLearning === "object" && raw.globalLearning !== null) {
            const parsed = GlobalLearningConfigSchema.safeParse(raw.globalLearning);
            if (parsed.success) {
                globalLearning = parsed.data;
            }
        }
        return {
            ...(typeof project === "string" ? { project } : {}),
            ...(dir ? { stateStore: { dir } } : {}),
            ...(consensus ? { consensus } : {}),
            ...(phaseRunner ? { phaseRunner } : {}),
            ...(learningLoop ? { learningLoop } : {}),
            ...(reviewerMemory ? { reviewerMemory } : {}),
            ...(learningApply ? { learningApply } : {}),
            ...(loopAudit ? { loopAudit } : {}),
            ...(gates ? { gates } : {}),
            ...(globalLearning ? { globalLearning } : {}),
        };
    }
    catch {
        return {};
    }
}
//# sourceMappingURL=config.js.map