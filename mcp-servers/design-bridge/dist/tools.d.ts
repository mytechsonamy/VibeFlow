import { FetchImpl } from "./client.js";
export interface ToolDefinition {
    name: string;
    description: string;
    inputSchema: Record<string, unknown>;
    handler: (args: unknown) => Promise<unknown>;
}
export interface BuildToolsOptions {
    /** Injected so tests can stub the HTTP layer without touching globals. */
    readonly fetchImpl?: FetchImpl;
    /** Override the token lookup — tests pass "test-token"; prod reads env. */
    readonly token?: string;
    /** Override base URL — tests point at a fake. */
    readonly baseUrl?: string;
}
export declare function buildTools(opts?: BuildToolsOptions): ToolDefinition[];
