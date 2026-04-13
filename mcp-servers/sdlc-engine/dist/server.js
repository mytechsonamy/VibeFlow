import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { CallToolRequestSchema, ListToolsRequestSchema, } from "@modelcontextprotocol/sdk/types.js";
import { SdlcEngine } from "./engine.js";
import { PhaseRegistry } from "./phases.js";
import { buildTools } from "./tools.js";
export function createServer(opts) {
    const registry = opts.registry ?? new PhaseRegistry();
    const engine = new SdlcEngine(opts.store, registry);
    const tools = buildTools(engine);
    const toolMap = new Map(tools.map((t) => [t.name, t]));
    const server = new Server({
        name: opts.name ?? "vibeflow-sdlc-engine",
        version: opts.version ?? "0.1.0",
    }, {
        capabilities: {
            tools: {},
        },
    });
    server.setRequestHandler(ListToolsRequestSchema, async () => ({
        tools: tools.map((t) => ({
            name: t.name,
            description: t.description,
            inputSchema: t.inputSchema,
        })),
    }));
    server.setRequestHandler(CallToolRequestSchema, async (request) => {
        const { name, arguments: args } = request.params;
        const tool = toolMap.get(name);
        if (!tool) {
            return {
                isError: true,
                content: [{ type: "text", text: `Unknown tool: ${name}` }],
            };
        }
        try {
            const result = await tool.handler(args ?? {});
            return {
                content: [
                    {
                        type: "text",
                        text: JSON.stringify(result, null, 2),
                    },
                ],
            };
        }
        catch (err) {
            const message = err instanceof Error ? err.message : String(err);
            return {
                isError: true,
                content: [{ type: "text", text: message }],
            };
        }
    });
    return { server, engine, tools };
}
//# sourceMappingURL=server.js.map