/**
 * Figma REST client.
 *
 * Two bugs are closed here:
 *  - Bug #3 (missing Figma error handling): every request funnels through
 *    `figmaGet()`, which wraps transport failures, non-2xx responses, and
 *    JSON parse errors in a single `FigmaClientError` that carries enough
 *    context (status, path, snippet) to debug without re-running.
 *  - Bug #7 (Figma token in code): the token is read once at client
 *    construction time from the `FIGMA_TOKEN` env var — never hardcoded,
 *    never logged, never returned from a tool. The `.mcp.json` `env` block
 *    maps plugin `userConfig.figma_token` → `FIGMA_TOKEN` so the value
 *    flows from Claude Code's config, not from files on disk.
 *
 * The `fetch` implementation is injectable so tests can swap in a mock
 * without globals. In production we fall back to `globalThis.fetch` (Node
 * ≥18) so no extra dependency is pulled in.
 */
export type FetchImpl = (input: string, init?: {
    headers?: Record<string, string>;
    method?: string;
}) => Promise<FetchResponse>;
export interface FetchResponse {
    readonly ok: boolean;
    readonly status: number;
    readonly statusText: string;
    readonly text: () => Promise<string>;
}
export interface FigmaClientOptions {
    readonly token?: string;
    readonly baseUrl?: string;
    readonly fetchImpl?: FetchImpl;
}
export declare class FigmaClient {
    private readonly token;
    private readonly baseUrl;
    private readonly fetchImpl;
    constructor(opts?: FigmaClientOptions);
    /**
     * Fetch `/v1/files/{key}/nodes?ids=...` and return the parsed JSON.
     * A node is Figma's term for a frame, group, text, instance, etc.
     */
    getNodes(fileKey: string, nodeIds: readonly string[]): Promise<unknown>;
    /** Fetch `/v1/files/{key}` — the whole file document. */
    getFile(fileKey: string): Promise<unknown>;
    private get;
}
export interface FigmaErrorContext {
    readonly status: number;
    readonly path: string;
}
export declare class FigmaClientError extends Error {
    readonly status: number;
    readonly path: string;
    constructor(message: string, ctx: FigmaErrorContext);
}
export declare class FigmaConfigError extends Error {
    constructor(message: string);
}
