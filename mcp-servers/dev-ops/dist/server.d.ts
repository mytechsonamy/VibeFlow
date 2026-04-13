import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { BuildToolsOptions, ToolDefinition } from "./tools.js";
export interface CreateServerOptions extends BuildToolsOptions {
    name?: string;
    version?: string;
}
export declare function createServer(opts?: CreateServerOptions): {
    server: Server;
    tools: ToolDefinition[];
};
