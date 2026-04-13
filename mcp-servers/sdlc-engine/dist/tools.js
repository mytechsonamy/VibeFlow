import { z } from "zod";
import { PhaseTransitionError } from "./engine.js";
import { PhaseIdSchema } from "./phases.js";
import { ConsensusStatusSchema } from "./consensus.js";
const GetStateInput = z.object({
    projectId: z.string().min(1),
});
const AdvancePhaseInput = z.object({
    projectId: z.string().min(1),
    to: PhaseIdSchema,
    force: z.boolean().optional(),
});
const RecordConsensusInput = z.object({
    projectId: z.string().min(1),
    phase: PhaseIdSchema,
    agreement: z.number().min(0).max(1),
    criticalIssues: z.number().int().min(0),
    status: ConsensusStatusSchema.optional(),
});
const SatisfyCriterionInput = z.object({
    projectId: z.string().min(1),
    criterion: z.string().min(1),
});
export function buildTools(engine) {
    return [
        {
            name: "sdlc_list_phases",
            description: "List the ordered SDLC phases with entry/exit criteria. " +
                "Phase order is data-driven — read this instead of hardcoding.",
            inputSchema: {
                type: "object",
                properties: {},
                additionalProperties: false,
            },
            handler: async () => ({
                phases: engine.listPhases(),
            }),
        },
        {
            name: "sdlc_get_state",
            description: "Fetch the current SDLC state for a project. Initializes state at " +
                "the first phase if the project has never been seen before.",
            inputSchema: {
                type: "object",
                properties: {
                    projectId: { type: "string", minLength: 1 },
                },
                required: ["projectId"],
                additionalProperties: false,
            },
            handler: async (raw) => {
                const args = GetStateInput.parse(raw);
                return engine.getOrInit(args.projectId);
            },
        },
        {
            name: "sdlc_satisfy_criterion",
            description: "Mark an exit criterion as satisfied for the project's current phase.",
            inputSchema: {
                type: "object",
                properties: {
                    projectId: { type: "string", minLength: 1 },
                    criterion: { type: "string", minLength: 1 },
                },
                required: ["projectId", "criterion"],
                additionalProperties: false,
            },
            handler: async (raw) => {
                const args = SatisfyCriterionInput.parse(raw);
                return engine.satisfyCriterion(args);
            },
        },
        {
            name: "sdlc_record_consensus",
            description: "Record a multi-AI consensus outcome. `status` accepts any case " +
                "(APPROVED/approved/Approved). If omitted, derived from agreement " +
                "and criticalIssues.",
            inputSchema: {
                type: "object",
                properties: {
                    projectId: { type: "string", minLength: 1 },
                    phase: { type: "string" },
                    agreement: { type: "number", minimum: 0, maximum: 1 },
                    criticalIssues: { type: "integer", minimum: 0 },
                    status: { type: "string" },
                },
                required: ["projectId", "phase", "agreement", "criticalIssues"],
                additionalProperties: false,
            },
            handler: async (raw) => {
                const args = RecordConsensusInput.parse(raw);
                return engine.recordConsensus(args);
            },
        },
        {
            name: "sdlc_advance_phase",
            description: "Advance the project to the next phase. Validates phase order, " +
                "exit criteria, and last consensus status. Use force=true to " +
                "bypass gate criteria (structural rules are still enforced).",
            inputSchema: {
                type: "object",
                properties: {
                    projectId: { type: "string", minLength: 1 },
                    to: { type: "string" },
                    force: { type: "boolean" },
                },
                required: ["projectId", "to"],
                additionalProperties: false,
            },
            handler: async (raw) => {
                const args = AdvancePhaseInput.parse(raw);
                try {
                    const { state, transition } = await engine.advancePhase(args);
                    return { ok: true, state, transition };
                }
                catch (err) {
                    if (err instanceof PhaseTransitionError) {
                        return {
                            ok: false,
                            errors: err.errors,
                            state: err.state,
                        };
                    }
                    throw err;
                }
            },
        },
    ];
}
//# sourceMappingURL=tools.js.map