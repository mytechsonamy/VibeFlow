import { StateStore, ProjectState, StateMutator } from "./store.js";
export declare class SqliteStateStore implements StateStore {
    private readonly db;
    private readonly locks;
    constructor(filename: string);
    init(): Promise<void>;
    read(projectId: string): Promise<ProjectState | null>;
    transact<T>(projectId: string, mutator: StateMutator<T>): Promise<T>;
    private runTransaction;
    close(): Promise<void>;
}
