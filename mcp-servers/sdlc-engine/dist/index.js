#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as fs from "node:fs";
import * as path from "node:path";
import { resolveConfig } from "./config.js";
import { createServer } from "./server.js";
import { SqliteStateStore } from "./state/sqlite.js";
import { PostgresStateStore } from "./state/postgres.js";
async function main() {
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
        }
        finally {
            process.exit(0);
        }
    };
    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);
    process.stderr.write(`[sdlc-engine] started mode=${config.mode} project=${config.project}\n`);
}
async function openStore(config) {
    if (config.mode === "team") {
        const url = config.stateStore.postgresUrl;
        if (!url) {
            throw new Error("Team mode requires VIBEFLOW_POSTGRES_URL or stateStore.postgresUrl");
        }
        return PostgresStateStore.create(url);
    }
    const sqlitePath = config.stateStore.sqlitePath ??
        path.join(process.cwd(), ".vibeflow", "state.db");
    fs.mkdirSync(path.dirname(sqlitePath), { recursive: true });
    return new SqliteStateStore(sqlitePath);
}
main().catch((err) => {
    process.stderr.write(`[sdlc-engine] fatal: ${err instanceof Error ? err.stack ?? err.message : String(err)}\n`);
    process.exit(1);
});
//# sourceMappingURL=index.js.map