import { parseConsensusStatus, statusFromScore, } from "./consensus.js";
import { PhaseTransitionValidator, } from "./validation.js";
export class SdlcEngine {
    store;
    registry;
    validator;
    constructor(store, registry, validator = new PhaseTransitionValidator(registry)) {
        this.store = store;
        this.registry = registry;
        this.validator = validator;
    }
    async getOrInit(projectId) {
        // Fast path: if the project already exists, return it without
        // entering the mutator transaction. The mutator path requires
        // `next.revision === current.revision + 1`, so a no-op return of
        // `{ next: current, result: current }` always fails validation
        // — which used to make sdlc_get_state crash on any project that
        // had been written to before. (Bug #13, S4-09 fix.)
        const existing = await this.store.read(projectId);
        if (existing)
            return existing;
        return this.store.transact(projectId, (current) => {
            // Race: another writer may have inserted the row between our
            // read and this transact callback. Bump the revision so the
            // mutator validation passes — the state is otherwise unchanged.
            if (current) {
                const bumped = bumpRevision(current);
                return { next: bumped, result: bumped };
            }
            const now = new Date().toISOString();
            const next = {
                projectId,
                currentPhase: this.registry.first().id,
                satisfiedCriteria: [],
                lastConsensus: null,
                updatedAt: now,
                revision: 1,
            };
            return { next, result: next };
        });
    }
    async read(projectId) {
        return this.store.read(projectId);
    }
    listPhases() {
        return this.registry.all();
    }
    async satisfyCriterion(input) {
        return this.store.transact(input.projectId, (current) => {
            const base = current ?? this.seed(input.projectId);
            if (base.satisfiedCriteria.includes(input.criterion)) {
                const bumped = bumpRevision(base);
                return { next: bumped, result: bumped };
            }
            const next = {
                ...base,
                satisfiedCriteria: [...base.satisfiedCriteria, input.criterion],
                updatedAt: new Date().toISOString(),
                revision: base.revision + 1,
            };
            return { next, result: next };
        });
    }
    async recordConsensus(input) {
        const derivedStatus = input.status
            ? parseConsensusStatus(input.status)
            : statusFromScore(input.agreement, input.criticalIssues);
        return this.store.transact(input.projectId, (current) => {
            const base = current ?? this.seed(input.projectId);
            const record = {
                phase: input.phase,
                status: derivedStatus,
                agreement: input.agreement,
                criticalIssues: input.criticalIssues,
                recordedAt: new Date().toISOString(),
            };
            const next = {
                ...base,
                lastConsensus: record,
                updatedAt: record.recordedAt,
                revision: base.revision + 1,
            };
            return { next, result: next };
        });
    }
    async advancePhase(input) {
        return this.store.transact(input.projectId, (current) => {
            const base = current ?? this.seed(input.projectId);
            const transition = this.validator.validate({
                from: base.currentPhase,
                to: input.to,
                satisfiedCriteria: base.satisfiedCriteria,
                lastConsensus: base.lastConsensus?.status ?? null,
                force: input.force ?? false,
            });
            if (!transition.ok) {
                // Do not mutate on failure: return the current state with bumped
                // revision-less identity (no-op write would be wasteful, so we
                // short-circuit by throwing and letting the caller handle it).
                throw new PhaseTransitionError(transition.errors, base);
            }
            const next = {
                ...base,
                currentPhase: input.to,
                // Fresh phase starts with an empty criterion set.
                satisfiedCriteria: [],
                updatedAt: new Date().toISOString(),
                revision: base.revision + 1,
            };
            return { next, result: { state: next, transition } };
        });
    }
    seed(projectId) {
        return {
            projectId,
            currentPhase: this.registry.first().id,
            satisfiedCriteria: [],
            lastConsensus: null,
            updatedAt: new Date(0).toISOString(),
            revision: 0,
        };
    }
}
function bumpRevision(state) {
    return {
        ...state,
        updatedAt: new Date().toISOString(),
        revision: state.revision + 1,
    };
}
export class PhaseTransitionError extends Error {
    errors;
    state;
    constructor(errors, state) {
        super(`Phase transition blocked: ${errors.join("; ")}`);
        this.errors = errors;
        this.state = state;
        this.name = "PhaseTransitionError";
    }
}
//# sourceMappingURL=engine.js.map