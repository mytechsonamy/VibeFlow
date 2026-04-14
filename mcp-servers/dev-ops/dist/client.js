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
 * Sprint 3 shipped the GitHub client; Sprint 5 adds the GitLab
 * client. Both implement the same narrow CiProvider interface so
 * tools.ts stays provider-agnostic and routes requests through the
 * CI_PROVIDER environment variable (sourced from the `ci_provider`
 * userConfig key).
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
export function createGitlabClient(opts) {
    const token = opts.token ?? process.env.GITLAB_TOKEN ?? process.env.GITHUB_TOKEN ?? "";
    if (!token) {
        throw new CiConfigError("GITLAB_TOKEN is required. Set it via plugin userConfig " +
            "(github_token is reused when you set ci_provider=gitlab, or " +
            "export GITLAB_TOKEN for local dev).");
    }
    if (!opts.projectId) {
        throw new CiConfigError("projectId is required for the GitLab client (either the " +
            "numeric project id or the 'group/name' path).");
    }
    const baseUrl = (opts.baseUrl ?? "https://gitlab.com/api/v4").replace(/\/$/, "");
    const fetchImpl = opts.fetchImpl ?? defaultFetch();
    const projectPath = encodeURIComponent(opts.projectId);
    async function request(path, init = {}) {
        const url = `${baseUrl}${path}`;
        let res;
        try {
            res = await fetchImpl(url, {
                method: init.method ?? "GET",
                headers: {
                    "PRIVATE-TOKEN": token,
                    Accept: "application/json",
                    "Content-Type": "application/json",
                },
                ...(init.body !== undefined ? { body: JSON.stringify(init.body) } : {}),
            });
        }
        catch (err) {
            throw new CiClientError(`gitlab request failed (transport): ${err.message}`, { status: 0, path });
        }
        if (!res.ok) {
            let snippet = "";
            try {
                snippet = (await res.text()).slice(0, 200);
            }
            catch {
                snippet = "<unreadable response body>";
            }
            throw new CiClientError(`gitlab ${res.status} ${res.statusText} on ${path}: ${snippet}`, { status: res.status, path });
        }
        const body = await res.text();
        if (body === "")
            return {};
        try {
            return JSON.parse(body);
        }
        catch {
            throw new CiClientError(`gitlab response was not valid JSON on ${path}: ${body.slice(0, 120)}`, { status: res.status, path });
        }
    }
    return {
        name: "gitlab",
        async triggerWorkflow(input) {
            if (!input.workflow) {
                throw new CiClientError("workflow is required", { status: 0, path: "" });
            }
            if (!input.ref) {
                throw new CiClientError("ref is required", { status: 0, path: "" });
            }
            if (/\s/.test(input.ref)) {
                throw new CiClientError(`ref contains whitespace: ${JSON.stringify(input.ref)}`, {
                    status: 0,
                    path: "",
                });
            }
            // GitLab has no "workflow file" concept like GitHub Actions;
            // pipelines are defined by .gitlab-ci.yml in the repo. We use
            // the `variables` payload to let callers inject a WORKFLOW
            // selector plus any additional inputs — consumers should
            // gate their jobs on `$WORKFLOW == "<name>"` in .gitlab-ci.yml.
            const variables = [
                { key: "WORKFLOW", value: input.workflow },
            ];
            if (input.inputs) {
                for (const [k, v] of Object.entries(input.inputs)) {
                    variables.push({ key: k, value: String(v) });
                }
            }
            const result = await request(`/projects/${projectPath}/pipeline`, {
                method: "POST",
                body: { ref: input.ref, variables },
            });
            const runId = result.id ?? "unknown";
            return {
                accepted: true,
                note: `created pipeline ${runId} on ${input.ref} with WORKFLOW=${input.workflow}`,
            };
        },
        async getRun(runId) {
            const raw = await request(`/projects/${projectPath}/pipelines/${encodeURIComponent(runId)}`);
            return normalizeGitlabRun(raw);
        },
        async listArtifacts(runId) {
            const jobs = await request(`/projects/${projectPath}/pipelines/${encodeURIComponent(runId)}/jobs`);
            const out = [];
            for (const job of jobs ?? []) {
                if (!job.artifacts_file || !job.artifacts_file.filename)
                    continue;
                out.push({
                    id: String(job.id),
                    name: job.artifacts_file.filename,
                    sizeBytes: job.artifacts_file.size ?? 0,
                    downloadUrl: `${baseUrl}/projects/${projectPath}/jobs/${encodeURIComponent(String(job.id))}/artifacts`,
                    expired: job.artifacts_expire_at
                        ? Date.parse(job.artifacts_expire_at) < Date.now()
                        : false,
                });
            }
            return out;
        },
    };
}
function normalizeGitlabRun(raw) {
    const rawStatus = raw.status ?? "";
    const status = normalizeGitlabStatus(rawStatus);
    const conclusion = status === "completed" ? normalizeGitlabConclusion(rawStatus) : null;
    return {
        id: String(raw.id ?? "0"),
        status,
        conclusion,
        url: raw.web_url ?? "",
        createdAt: raw.created_at ?? "",
        updatedAt: raw.updated_at ?? raw.created_at ?? "",
        headSha: raw.sha ?? null,
        workflow: raw.ref ?? null,
    };
}
function normalizeGitlabStatus(s) {
    if (s === "created" ||
        s === "waiting_for_resource" ||
        s === "preparing" ||
        s === "pending" ||
        s === "scheduled" ||
        s === "manual") {
        return "queued";
    }
    if (s === "running")
        return "in_progress";
    if (s === "success" || s === "failed" || s === "canceled" || s === "skipped") {
        return "completed";
    }
    // Unknown status — treat as queued so downstream consumers don't
    // mistakenly interpret it as a terminal verdict.
    return "queued";
}
function normalizeGitlabConclusion(s) {
    if (s === "success")
        return "success";
    if (s === "failed")
        return "failure";
    if (s === "canceled")
        return "cancelled";
    if (s === "skipped")
        return "skipped";
    // Terminal status we don't know yet — default to neutral so
    // downstream consumers can pattern-match.
    return "neutral";
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