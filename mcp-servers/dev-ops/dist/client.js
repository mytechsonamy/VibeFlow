/**
 * CI provider client.
 *
 * The interface is deliberately narrow: every CI we support has to
 * express the same five operations (trigger, status, artifacts, deploy,
 * rollback). Keeping the surface small makes swapping providers or
 * adding new ones cheap, and it lets the MCP tool layer stay
 * provider-agnostic.
 *
 * Token flow is the same as design-bridge: the token comes from
 * `process.env.<PROVIDER>_TOKEN` (never hardcoded, never logged). The
 * plugin.json userConfig binds the user-visible field to the env var
 * via the .mcp.json `env` block. Tests inject a stub provider via
 * `createGithubClient({ fetchImpl, token })`.
 *
 * Only GitHub Actions is implemented in Sprint 3 — the
 * CiProvider interface is here so GitLab CI can land later without
 * touching tools.ts. When the GitLab impl arrives it will drop into
 * `createGitlabClient(...)` and the tool handlers will pick the
 * provider by config.
 */
export function createGithubClient(opts) {
    const token = opts.token ?? process.env.GITHUB_TOKEN ?? "";
    if (!token) {
        throw new CiConfigError("GITHUB_TOKEN is required. Set it via plugin userConfig " +
            "(github_token) or as an environment variable for local dev.");
    }
    if (!opts.owner || !opts.repo) {
        throw new CiConfigError("owner and repo are required for the GitHub client");
    }
    const baseUrl = (opts.baseUrl ?? "https://api.github.com").replace(/\/$/, "");
    const fetchImpl = opts.fetchImpl ?? defaultFetch();
    async function request(path, init = {}) {
        const url = `${baseUrl}${path}`;
        let res;
        try {
            res = await fetchImpl(url, {
                method: init.method ?? "GET",
                headers: {
                    Authorization: `Bearer ${token}`,
                    Accept: "application/vnd.github+json",
                    "X-GitHub-Api-Version": "2022-11-28",
                    "Content-Type": "application/json",
                },
                ...(init.body !== undefined ? { body: JSON.stringify(init.body) } : {}),
            });
        }
        catch (err) {
            throw new CiClientError(`github request failed (transport): ${err.message}`, { status: 0, path });
        }
        if (!res.ok) {
            let snippet = "";
            try {
                snippet = (await res.text()).slice(0, 200);
            }
            catch {
                snippet = "<unreadable response body>";
            }
            throw new CiClientError(`github ${res.status} ${res.statusText} on ${path}: ${snippet}`, { status: res.status, path });
        }
        const body = await res.text();
        // 204 No Content: workflow_dispatch returns an empty body; return
        // a harmless object so the caller can tell "accepted".
        if (body === "")
            return {};
        try {
            return JSON.parse(body);
        }
        catch {
            throw new CiClientError(`github response was not valid JSON on ${path}: ${body.slice(0, 120)}`, { status: res.status, path });
        }
    }
    const { owner, repo } = opts;
    return {
        name: "github",
        async triggerWorkflow(input) {
            if (!input.workflow) {
                throw new CiClientError("workflow is required", { status: 0, path: "" });
            }
            if (!input.ref) {
                throw new CiClientError("ref is required", { status: 0, path: "" });
            }
            // POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches
            // {workflow_id} can be the file name (preferred — stable across renames).
            await request(`/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/actions/workflows/${encodeURIComponent(input.workflow)}/dispatches`, {
                method: "POST",
                body: {
                    ref: input.ref,
                    ...(input.inputs ? { inputs: input.inputs } : {}),
                },
            });
            return {
                accepted: true,
                note: `dispatched ${input.workflow} on ${input.ref}`,
            };
        },
        async getRun(runId) {
            const raw = await request(`/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/actions/runs/${encodeURIComponent(runId)}`);
            return normalizeGithubRun(raw);
        },
        async listArtifacts(runId) {
            const raw = await request(`/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/actions/runs/${encodeURIComponent(runId)}/artifacts`);
            return (raw.artifacts ?? []).map(normalizeGithubArtifact);
        },
    };
}
function normalizeGithubRun(raw) {
    return {
        id: String(raw.id),
        status: normalizeStatus(raw.status),
        conclusion: normalizeConclusion(raw.conclusion),
        url: raw.html_url,
        createdAt: raw.created_at,
        updatedAt: raw.updated_at,
        headSha: raw.head_sha,
        workflow: raw.path ?? raw.name ?? null,
    };
}
function normalizeGithubArtifact(raw) {
    return {
        id: String(raw.id),
        name: raw.name,
        sizeBytes: raw.size_in_bytes,
        downloadUrl: raw.archive_download_url,
        expired: raw.expired,
    };
}
function normalizeStatus(s) {
    if (s === "queued" || s === "in_progress" || s === "completed")
        return s;
    // GitHub occasionally uses "requested", "waiting", "pending" — all map to queued.
    if (s === "requested" || s === "waiting" || s === "pending")
        return "queued";
    return "in_progress";
}
function normalizeConclusion(c) {
    if (c === null)
        return null;
    if (c === "success" ||
        c === "failure" ||
        c === "cancelled" ||
        c === "skipped" ||
        c === "timed_out" ||
        c === "action_required" ||
        c === "neutral") {
        return c;
    }
    // Unknown conclusion values are treated as `neutral` for safety —
    // downstream consumers should never see a raw string they can't
    // pattern-match against.
    return "neutral";
}
export class CiClientError extends Error {
    status;
    path;
    constructor(message, ctx) {
        super(message);
        this.name = "CiClientError";
        this.status = ctx.status;
        this.path = ctx.path;
    }
}
export class CiConfigError extends Error {
    constructor(message) {
        super(message);
        this.name = "CiConfigError";
    }
}
function defaultFetch() {
    const g = globalThis;
    if (typeof g.fetch !== "function") {
        throw new CiConfigError("globalThis.fetch is not available. Node 18+ is required, or pass a fetchImpl.");
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