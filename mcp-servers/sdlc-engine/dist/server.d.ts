import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { SdlcEngine } from "./engine.js";
import { PhaseRegistry } from "./phases.js";
import { ToolDefinition } from "./tools.js";
import { StateStore } from "./state/store.js";
export interface CreateServerOptions {
    store: StateStore;
    registry?: PhaseRegistry;
    name?: string;
    version?: string;
    /** Sprint 26-B: phase-gate strictness, threaded to the advance tool. */
    gates?: {
        enforceEntryCriteria: boolean;
    };
}
export declare function createServer(opts: CreateServerOptions): {
    server: Server;
    engine: SdlcEngine;
    tools: ToolDefinition[];
};
