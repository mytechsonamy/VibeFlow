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
export type StateMutator<T> = (current: ProjectState | null) => {
    next: ProjectState;
    result: T;
};
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
export declare class KeyedAsyncLock {
    private readonly chains;
    acquire<T>(key: string, fn: () => Promise<T>): Promise<T>;
}
export declare function assertRevisionIncrement(current: ProjectState | null, next: ProjectState, projectId: string): void;
