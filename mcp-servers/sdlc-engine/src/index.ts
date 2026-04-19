#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as fs from "node:fs";
import * as path from "node:path";
import { resolveConfig } from "./config.js";
import { createServer } from "./server.js";
import { FilesystemStateStore } from "./state/filesystem.js";
import { StateStore } from "./state/store.js";

async function main(): Promise<void> {
  const config = resolveConfig();
  const store = await openStore(config);
  await store.init();

  const { server } = createServer({
    store,
    name: "vibeflow-sdlc-engine",
    version: "0.1.0",
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);

  const shutdown = async () => {
    try {
      await store.close();
    } finally {
      process.exit(0);
    }
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  process.stderr.write(
    `[sdlc-engine] started project=${config.project} stateDir=${config.stateStore.dir ?? "<default>"}\n`,
  );
}

async function openStore(
  config: ReturnType<typeof resolveConfig>,
): Promise<StateStore> {
  const stateDir =
    config.stateStore.dir ??
    process.env.VIBEFLOW_STATE_DIR ??
    path.join(process.cwd(), ".vibeflow", "state");
  fs.mkdirSync(stateDir, { recursive: true });
  return new FilesystemStateStore(stateDir);
}

main().catch((err) => {
  process.stderr.write(
    `[sdlc-engine] fatal: ${err instanceof Error ? err.stack ?? err.message : String(err)}\n`,
  );
  process.exit(1);
});
