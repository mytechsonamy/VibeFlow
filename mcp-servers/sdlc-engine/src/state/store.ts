import { PhaseId } from "../phases.js";
import { ConsensusStatus } from "../consensus.js";

export interface ConsensusRecord {
  readonly phase: PhaseId;
  readonly status: ConsensusStatus;
  readonly agreement: number;
  readonly criticalIssues: number;
  readonly recordedAt: string;
}

export interface ProjectState {
  readonly projectId: string;
  readonly currentPhase: PhaseId;
  readonly satisfiedCriteria: readonly string[];
  readonly lastConsensus: ConsensusRecord | null;
  readonly updatedAt: string;
  /** Monotonically increasing revision, incremented on every write. */
  readonly revision: number;
}

export type StateMutator<T> = (
  current: ProjectState | null,
) => { next: ProjectState; result: T };

/**
 * Transactional state store interface.
 *
 * `transact()` runs its mutator inside an exclusive critical section per
 * `projectId` — both in-process (async mutex) AND cross-process (DB row
 * lock). This is what fixes Bug #6, where two concurrent writers could
 * read the same revision and clobber each other's changes.
 */
export interface StateStore {
  init(): Promise<void>;
  read(projectId: string): Promise<ProjectState | null>;
  transact<T>(projectId: string, mutator: StateMutator<T>): Promise<T>;
  close(): Promise<void>;
}

/**
 * In-process serialization primitive used by every backend to chain
 * `transact()` calls on the same project. Independent of DB-level locks,
 * which protect against *other* processes.
 */
export class KeyedAsyncLock {
  private readonly chains = new Map<string, Promise<void>>();

  async acquire<T>(key: string, fn: () => Promise<T>): Promise<T> {
    const previous = this.chains.get(key) ?? Promise.resolve();
    let release!: () => void;
    const current = new Promise<void>((resolve) => {
      release = resolve;
    });
    this.chains.set(
      key,
      previous.then(() => current),
    );

    try {
      await previous;
      return await fn();
    } finally {
      release();
      // Only clear if we're still the tail — otherwise a later waiter is
      // queued behind us and needs the chain to stay intact.
      if (this.chains.get(key) === current) {
        this.chains.delete(key);
      }
    }
  }
}

export function assertRevisionIncrement(
  current: ProjectState | null,
  next: ProjectState,
  projectId: string,
): void {
  if (next.projectId !== projectId) {
    throw new Error(
      `State mutator cannot change projectId (expected ${projectId}, got ${next.projectId})`,
    );
  }
  const expected = (current?.revision ?? 0) + 1;
  if (next.revision !== expected) {
    throw new Error(
      `revision must increment by exactly 1 ` +
        `(expected ${expected}, got ${next.revision})`,
    );
  }
}
