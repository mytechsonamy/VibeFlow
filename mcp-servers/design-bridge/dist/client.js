/**
 * Figma REST client.
 *
 * Two bugs are closed here:
 *  - Bug #3 (missing Figma error handling): every request funnels through
 *    `figmaGet()`, which wraps transport failures, non-2xx responses, and
 *    JSON parse errors in a single `FigmaClientError` that carries enough
 *    context (status, path, snippet) to debug without re-running.
 *  - Bug #7 (Figma token in code): the token is read once at client
 *    construction time from the `FIGMA_TOKEN` env var — never hardcoded,
 *    never logged, never returned from a tool. The `.mcp.json` `env` block
 *    maps plugin `userConfig.figma_token` → `FIGMA_TOKEN` so the value
 *    flows from Claude Code's config, not from files on disk.
 *
 * The `fetch` implementation is injectable so tests can swap in a mock
 * without globals. In production we fall back to `globalThis.fetch` (Node
 * ≥18) so no extra dependency is pulled in.
 */
export class FigmaClient {
    token;
    baseUrl;
    fetchImpl;
    constructor(opts = {}) {
        const token = opts.token ?? process.env.FIGMA_TOKEN ?? "";
        if (!token) {
            throw new FigmaConfigError("FIGMA_TOKEN is required. Set it via plugin userConfig " +
                "(figma_token) or as an environment variable for local dev.");
        }
        this.token = token;
        this.baseUrl = (opts.baseUrl ?? "https://api.figma.com").replace(/\/$/, "");
        this.fetchImpl = opts.fetchImpl ?? defaultFetch();
    }
    /**
     * Fetch `/v1/files/{key}/nodes?ids=...` and return the parsed JSON.
     * A node is Figma's term for a frame, group, text, instance, etc.
     */
    async getNodes(fileKey, nodeIds) {
        if (!fileKey) {
            throw new FigmaClientError("fileKey is required", { status: 0, path: "" });
        }
        if (nodeIds.length === 0) {
            throw new FigmaClientError("at least one node id is required", {
                status: 0,
                path: "",
            });
        }
        const ids = nodeIds.join(",");
        return this.get(`/v1/files/${encodeURIComponent(fileKey)}/nodes?ids=${encodeURIComponent(ids)}`);
    }
    /** Fetch `/v1/files/{key}` — the whole file document. */
    async getFile(fileKey) {
        if (!fileKey) {
            throw new FigmaClientError("fileKey is required", { status: 0, path: "" });
        }
        return this.get(`/v1/files/${encodeURIComponent(fileKey)}`);
    }
    async get(path) {
        const url = `${this.baseUrl}${path}`;
        let res;
        try {
            res = await this.fetchImpl(url, {
                method: "GET",
                headers: {
                    "X-Figma-Token": this.token,
                    Accept: "application/json",
                },
            });
        }
        catch (err) {
            throw new FigmaClientError(`figma request failed (transport): ${err.message}`, { status: 0, path });
        }
        if (!res.ok) {
            let snippet = "";
            try {
                snippet = (await res.text()).slice(0, 200);
            }
            catch {
                snippet = "<unreadable response body>";
            }
            throw new FigmaClientError(`figma ${res.status} ${res.statusText} on ${path}: ${snippet}`, { status: res.status, path });
        }
        const body = await res.text();
        try {
            return JSON.parse(body);
        }
        catch {
            throw new FigmaClientError(`figma response was not valid JSON on ${path}: ${body.slice(0, 120)}`, { status: res.status, path });
        }
    }
}
export class FigmaClientError extends Error {
    status;
    path;
    constructor(message, ctx) {
        super(message);
        this.name = "FigmaClientError";
        this.status = ctx.status;
        this.path = ctx.path;
    }
}
export class FigmaConfigError extends Error {
    constructor(message) {
        super(message);
        this.name = "FigmaConfigError";
    }
}
function defaultFetch() {
    const g = globalThis;
    if (typeof g.fetch !== "function") {
        throw new FigmaConfigError("globalThis.fetch is not available. Node 18+ is required, or pass a fetchImpl.");
    }
    return async (input, init) => {
        const r = (await g.fetch(input, init));
        return {
            ok: r.ok,
            status: r.status,
            statusText: r.statusText,
            text: () => r.text(),
        };
    };
}
//# sourceMappingURL=client.js.map