import { CiProvider, PipelineRun, PipelineArtifact } from "./client.js";
/**
 * Pipeline orchestration helpers.
 *
 * Everything in this file is a pure function of a `CiProvider` + input —
 * the module is test-friendly because the provider is injectable and
 * the return shapes are deterministic. No globals, no I/O outside the
 * provider call.
 */
export interface TriggerPipelineInput {
    readonly workflow: string;
    readonly ref: string;
    readonly inputs?: Readonly<Record<string, string>>;
}
export interface TriggerPipelineResult {
    readonly accepted: boolean;
    readonly note: string;
    readonly provider: string;
    readonly workflow: string;
    readonly ref: string;
    readonly dispatchedAt: string;
}
export declare function triggerPipeline(provider: CiProvider, input: TriggerPipelineInput): Promise<TriggerPipelineResult>;
export interface PipelineStatusResult extends PipelineRun {
    readonly provider: string;
    readonly fetchedAt: string;
    readonly durationMs: number | null;
}
export declare function getPipelineStatus(provider: CiProvider, runId: string): Promise<PipelineStatusResult>;
export interface FetchArtifactsResult {
    readonly provider: string;
    readonly runId: string;
    readonly artifacts: readonly PipelineArtifact[];
    readonly totalBytes: number;
    readonly fetchedAt: string;
}
export declare function fetchArtifacts(provider: CiProvider, runId: string): Promise<FetchArtifactsResult>;
export interface DeployInput {
    readonly workflow: string;
    readonly ref: string;
    readonly environment: "staging" | "production";
    readonly inputs?: Readonly<Record<string, string>>;
}
/**
 * Deploy is a thin wrapper over `triggerPipeline` that enforces an
 * explicit `environment` argument and records it in the run note.
 * The surrounding org is expected to maintain a workflow that reads
 * the environment input and routes accordingly — we do not try to
 * own the deploy topology.
 */
export declare function deploy(provider: CiProvider, input: DeployInput): Promise<TriggerPipelineResult>;
export interface RollbackInput {
    readonly workflow: string;
    /** The commit SHA or tag to roll back TO — never an empty string. */
    readonly targetRef: string;
    readonly reason: string;
    readonly environment: "staging" | "production";
}
/**
 * Rollback dispatches the caller's rollback workflow with the target
 * ref + human-readable reason. A blank reason is rejected — rollback
 * audit trails are only useful if they record why.
 */
export declare function rollback(provider: CiProvider, input: RollbackInput): Promise<TriggerPipelineResult>;
