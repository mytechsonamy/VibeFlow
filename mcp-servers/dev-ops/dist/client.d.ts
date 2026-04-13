/**
 * CI provider client.
 *
 * The interface is deliberately narrow: every CI we support has to
 * express the same five operations (trigger, status, artifacts, deploy,
 * rollback). Keeping the surface small makes swapping providers or
 * adding new ones cheap, and it lets the MCP tool layer stay
 * provider-agnostic.
 *
 * Token flow is the same as design-bridge: the token comes from
 * `process.env.<PROVIDER>_TOKEN` (never hardcoded, never logged). The
 * plugin.json userConfig binds the user-visible field to the env var
 * via the .mcp.json `env` block. Tests inject a stub provider via
 * `createGithubClient({ fetchImpl, token })`.
 *
 * Only GitHub Actions is implemented in Sprint 3 — the
 * CiProvider interface is here so GitLab CI can land later without
 * touching tools.ts. When the GitLab impl arrives it will drop into
 * `createGitlabClient(...)` and the tool handlers will pick the
 * provider by config.
 */
export type FetchImpl = (input: string, init?: {
    method?: string;
    headers?: Record<string, string>;
    body?: string;
}) => Promise<FetchResponse>;
export interface FetchResponse {
    readonly ok: boolean;
    readonly status: number;
    readonly statusText: string;
    readonly text: () => Promise<string>;
}
export interface PipelineRun {
    readonly id: string;
    readonly status: "queued" | "in_progress" | "completed";
    readonly conclusion: "success" | "failure" | "cancelled" | "skipped" | "timed_out" | "action_required" | "neutral" | null;
    readonly url: string;
    readonly createdAt: string;
    readonly updatedAt: string;
    readonly headSha: string | null;
    readonly workflow: string | null;
}
export interface PipelineArtifact {
    readonly id: string;
    readonly name: string;
    readonly sizeBytes: number;
    readonly downloadUrl: string;
    readonly expired: boolean;
}
export interface CiTriggerInput {
    readonly workflow: string;
    readonly ref: string;
    readonly inputs?: Readonly<Record<string, string>>;
}
export interface CiProvider {
    readonly name: "github" | "gitlab";
    triggerWorkflow(input: CiTriggerInput): Promise<{
        accepted: boolean;
        note: string;
    }>;
    getRun(runId: string): Promise<PipelineRun>;
    listArtifacts(runId: string): Promise<readonly PipelineArtifact[]>;
}
export interface GithubClientOptions {
    readonly owner: string;
    readonly repo: string;
    readonly token?: string;
    readonly baseUrl?: string;
    readonly fetchImpl?: FetchImpl;
}
export declare function createGithubClient(opts: GithubClientOptions): CiProvider;
export interface CiErrorContext {
    readonly status: number;
    readonly path: string;
}
export declare class CiClientError extends Error {
    readonly status: number;
    readonly path: string;
    constructor(message: string, ctx: CiErrorContext);
}
export declare class CiConfigError extends Error {
    constructor(message: string);
}
