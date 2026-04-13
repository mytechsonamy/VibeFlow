import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { ToolDefinition } from "./tools.js";
export interface CreateServerOptions {
    name?: string;
    version?: string;
}
export declare function createServer(opts?: CreateServerOptions): {
    server: Server;
    tools: ToolDefinition[];
};
