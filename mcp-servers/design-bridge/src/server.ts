import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { buildTools, BuildToolsOptions, ToolDefinition } from "./tools.js";

export interface CreateServerOptions extends BuildToolsOptions {
  name?: string;
  version?: string;
}

export function createServer(opts: CreateServerOptions = {}): {
  server: Server;
  tools: ToolDefinition[];
} {
  const tools = buildTools(opts);
  const toolMap = new Map(tools.map((t) => [t.name, t] as const));

  const server = new Server(
    {
      name: opts.name ?? "vibeflow-design-bridge",
      version: opts.version ?? "0.1.0",
    },
    {
      capabilities: {
        tools: {},
      },
    },
  );

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
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return {
        isError: true,
        content: [{ type: "text", text: message }],
      };
    }
  });

  return { server, tools };
}
