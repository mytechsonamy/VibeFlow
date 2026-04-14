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
 * Sprint 3 shipped the GitHub client; Sprint 5 adds the GitLab
 * client. Both implement the same narrow CiProvider interface so
 * tools.ts stays provider-agnostic and routes requests through the
 * CI_PROVIDER environment variable (sourced from the `ci_provider`
 * userConfig key).
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
export interface GitlabClientOptions {
    /**
     * Project identifier. Accepts either the numeric project id ("42")
     * or the URL-path-encoded full path ("group/subgroup/repo"). The
     * client URL-encodes the value automatically.
     */
    readonly projectId: string;
    readonly token?: string;
    /** Defaults to `https://gitlab.com/api/v4`. Trailing slash stripped. */
    readonly baseUrl?: string;
    readonly fetchImpl?: FetchImpl;
}
export declare function createGitlabClient(opts: GitlabClientOptions): CiProvider;
