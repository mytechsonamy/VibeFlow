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
    // Opt-in filesystem backend. When VIBEFLOW_STATE_BACKEND=filesystem is
    // set, or stateStore.dir is configured, use FilesystemStateStore
    // regardless of mode. This is the Sprint 11 migration path — Sprint
    // 11-D will flip the default; Sprint 11-E will remove sqlite/postgres.
    const backendOverride = (process.env.VIBEFLOW_STATE_BACKEND ?? "").trim();
    if (backendOverride === "filesystem" || config.stateStore.dir) {
        const stateDir = config.stateStore.dir ??
            process.env.VIBEFLOW_STATE_DIR ??
            path.join(process.cwd(), ".vibeflow", "state");
        fs.mkdirSync(stateDir, { recursive: true });
        return new FilesystemStateStore(stateDir);
    }
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