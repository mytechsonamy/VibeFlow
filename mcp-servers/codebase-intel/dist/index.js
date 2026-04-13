#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer } from "./server.js";
async function main() {
    const { server } = createServer({
        name: "vibeflow-codebase-intel",
        version: "0.1.0",
    });
    const transport = new StdioServerTransport();
    await server.connect(transport);
    process.stderr.write("[codebase-intel] started\n");
}
main().catch((err) => {
    process.stderr.write(`[codebase-intel] fatal: ${err instanceof Error ? err.stack ?? err.message : String(err)}\n`);
    process.exit(1);
});
//# sourceMappingURL=index.js.map