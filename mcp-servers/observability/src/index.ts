#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer } from "./server.js";

async function main(): Promise<void> {
  const { server } = createServer({
    name: "vibeflow-observability",
    version: "0.1.0",
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);

  process.stderr.write("[observability] started\n");
}

main().catch((err) => {
  process.stderr.write(
    `[observability] fatal: ${err instanceof Error ? err.stack ?? err.message : String(err)}\n`,
  );
  process.exit(1);
});
