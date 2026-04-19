#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as fs from "node:fs";
import * as path from "node:path";
import { resolveConfig } from "./config.js";
import { createServer } from "./server.js";
import { SqliteStateStore } from "./state/sqlite.js";
import { PostgresStateStore } from "./state/postgres.js";
import { FilesystemStateStore } from "./state/filesystem.js";
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
    // Sprint 11-D: filesystem is the default backend. Legacy stores are
    // still reachable by setting VIBEFLOW_STATE_BACKEND explicitly:
    //   VIBEFLOW_STATE_BACKEND=sqlite    → SqliteStateStore (solo legacy)
    //   VIBEFLOW_STATE_BACKEND=postgres  → PostgresStateStore (team legacy)
    //   VIBEFLOW_STATE_BACKEND=filesystem → FilesystemStateStore (default)
    // Sprint 11-E removes sqlite/postgres entirely and drops this switch.
    const backendOverride = (process.env.VIBEFLOW_STATE_BACKEND ?? "")
        .trim()
        .toLowerCase();
    if (backendOverride === "postgres") {
        const url = config.stateStore.postgresUrl;
        if (!url) {
            throw new Error("VIBEFLOW_STATE_BACKEND=postgres requires VIBEFLOW_POSTGRES_URL " +
                "or stateStore.postgresUrl");
        }
        return PostgresStateStore.create(url);
    }
    if (backendOverride === "sqlite") {
        const sqlitePath = config.stateStore.sqlitePath ??
            path.join(process.cwd(), ".vibeflow", "state.db");
        fs.mkdirSync(path.dirname(sqlitePath), { recursive: true });
        return new SqliteStateStore(sqlitePath);
    }
    const stateDir = config.stateStore.dir ??
        process.env.VIBEFLOW_STATE_DIR ??
        path.join(process.cwd(), ".vibeflow", "state");
    fs.mkdirSync(stateDir, { recursive: true });
    return new FilesystemStateStore(stateDir);
}
main().catch((err) => {
    process.stderr.write(`[sdlc-engine] fatal: ${err instanceof Error ? err.stack ?? err.message : String(err)}\n`);
    process.exit(1);
});
//# sourceMappingURL=index.js.map