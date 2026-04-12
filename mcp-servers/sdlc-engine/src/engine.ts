import { PhaseId, PhaseRegistry } from "./phases.js";
import {
  ConsensusStatus,
  parseConsensusStatus,
  statusFromScore,
} from "./consensus.js";
import {
  PhaseTransitionValidator,
  TransitionResult,
} from "./validation.js";
import {
  ProjectState,
  StateStore,
  ConsensusRecord,
} from "./state/store.js";

export interface AdvancePhaseInput {
  readonly projectId: string;
  readonly to: PhaseId;
  readonly force?: boolean;
}

export interface RecordConsensusInput {
  readonly projectId: string;
  readonly phase: PhaseId;
  readonly status?: string;
  readonly agreement: number;
  readonly criticalIssues: number;
}

export interface SatisfyCriterionInput {
  readonly projectId: string;
  readonly criterion: string;
}

export class SdlcEngine {
  constructor(
    private readonly store: StateStore,
    private readonly registry: PhaseRegistry,
    private readonly validator: PhaseTransitionValidator = new PhaseTransitionValidator(
      registry,
    ),
  ) {}

  async getOrInit(projectId: string): Promise<ProjectState> {
    return this.store.transact(projectId, (current) => {
      if (current) return { next: current, result: current };
      const now = new Date().toISOString();
      const next: ProjectState = {
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

  async read(projectId: string): Promise<ProjectState | null> {
    return this.store.read(projectId);
  }

  listPhases() {
    return this.registry.all();
  }

  async satisfyCriterion(
    input: SatisfyCriterionInput,
  ): Promise<ProjectState> {
    return this.store.transact(input.projectId, (current) => {
      const base = current ?? this.seed(input.projectId);
      if (base.satisfiedCriteria.includes(input.criterion)) {
        const bumped = bumpRevision(base);
        return { next: bumped, result: bumped };
      }
      const next: ProjectState = {
        ...base,
        satisfiedCriteria: [...base.satisfiedCriteria, input.criterion],
        updatedAt: new Date().toISOString(),
        revision: base.revision + 1,
      };
      return { next, result: next };
    });
  }

  async recordConsensus(
    input: RecordConsensusInput,
  ): Promise<ProjectState> {
    const derivedStatus = input.status
      ? parseConsensusStatus(input.status)
      : statusFromScore(input.agreement, input.criticalIssues);

    return this.store.transact(input.projectId, (current) => {
      const base = current ?? this.seed(input.projectId);
      const record: ConsensusRecord = {
        phase: input.phase,
        status: derivedStatus,
        agreement: input.agreement,
        criticalIssues: input.criticalIssues,
        recordedAt: new Date().toISOString(),
      };
      const next: ProjectState = {
        ...base,
        lastConsensus: record,
        updatedAt: record.recordedAt,
        revision: base.revision + 1,
      };
      return { next, result: next };
    });
  }

  async advancePhase(
    input: AdvancePhaseInput,
  ): Promise<{ state: ProjectState; transition: TransitionResult }> {
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

      const next: ProjectState = {
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

  private seed(projectId: string): ProjectState {
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

function bumpRevision(state: ProjectState): ProjectState {
  return {
    ...state,
    updatedAt: new Date().toISOString(),
    revision: state.revision + 1,
  };
}

export class PhaseTransitionError extends Error {
  constructor(
    public readonly errors: readonly string[],
    public readonly state: ProjectState,
  ) {
    super(`Phase transition blocked: ${errors.join("; ")}`);
    this.name = "PhaseTransitionError";
  }
}
