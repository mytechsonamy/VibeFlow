import { StateStore, StateMutator, ProjectState } from "./store.js";
import { MutatorContext, StateEvent } from "./events.js";
export interface TransactOptions {
    /** Pass to `deriveEvent` for richer event metadata. */
    context?: Omit<MutatorContext, "actor"> & {
        actor?: string;
    };
}
/**
 * File-system backed state store. Layout per project:
 *
 *   <stateDir>/<projectId>/
 *     project.json                   rollup (authoritative read target)
 *     project.json.lock              proper-lockfile sidecar
 *     events/NNNN-<type>.json        append-only audit log
 *     events/NNNN-<type>.md          human-readable twin
 *     archive/NN-<PHASE>/            moved once a phase completes
 *
 * Concurrency model:
 *   - `KeyedAsyncLock` (reused from store.ts) serialises transact() calls
 *     in the same process.
 *   - `proper-lockfile` serialises transact() calls across processes.
 *   - Every write goes through a temp file + atomic rename to avoid
 *     torn writes. fsyncDir is called on the parent directory so Linux
 *     ext4 durability holds under crash.
 */
export declare class FilesystemStateStore implements StateStore {
    private readonly baseDir;
    private readonly keyedLock;
    private readonly fsyncEnabled;
    private readonly tmpGraceMs;
    private initialized;
    constructor(baseDir: string, options?: {
        fsync?: boolean;
        tmpGraceMs?: number;
    });
    init(): Promise<void>;
    read(projectId: string): Promise<ProjectState | null>;
    transact<T>(projectId: string, mutator: StateMutator<T>, options?: TransactOptions): Promise<T>;
    close(): Promise<void>;
    /** Reconstruct rollup from event log. Used by bin/replay-events.sh. */
    rebuildRollup(projectId: string): Promise<ProjectState | null>;
    projectDir(projectId: string): string;
    private eventsDir;
    private archiveDir;
    private rollupPath;
    private lockPath;
    private ensureProjectDirs;
    private acquireFileLock;
    private writeEvent;
    private writeRollup;
    private writeAtomic;
    private fsyncDir;
    private archiveCompletedPhase;
    private sweepCrashRecovery;
    private cleanupTmpFiles;
    private rebuildMissingMdTwins;
    private loadAllEvents;
}
declare function bucketForPhase(phase: string): string;
declare function applyEventToState(state: ProjectState | null, event: StateEvent): ProjectState;
export declare const __testing__: {
    EVENT_SCHEMA_VERSION: number;
    ROLLUP_SCHEMA_VERSION: 1;
    bucketForPhase: typeof bucketForPhase;
    applyEventToState: typeof applyEventToState;
};
export {};
