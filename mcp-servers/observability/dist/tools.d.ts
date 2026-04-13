export interface ToolDefinition {
    name: string;
    description: string;
    inputSchema: Record<string, unknown>;
    handler: (args: unknown) => Promise<unknown>;
}
export declare function buildTools(): ToolDefinition[];
