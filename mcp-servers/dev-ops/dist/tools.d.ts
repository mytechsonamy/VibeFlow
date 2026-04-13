import { CiProvider, FetchImpl } from "./client.js";
export interface ToolDefinition {
    name: string;
    description: string;
    inputSchema: Record<string, unknown>;
    handler: (args: unknown) => Promise<unknown>;
}
export interface BuildToolsOptions {
    /** Override provider — tests pass a fake, production reads from env. */
    readonly provider?: CiProvider;
    /** For tests: inject fetch so we never touch the real network. */
    readonly fetchImpl?: FetchImpl;
    /** For tests: explicit token avoids env var pollution. */
    readonly token?: string;
    /** Overrides for the GitHub base URL (local pact tests). */
    readonly baseUrl?: string;
}
export declare function buildTools(opts?: BuildToolsOptions): ToolDefinition[];
