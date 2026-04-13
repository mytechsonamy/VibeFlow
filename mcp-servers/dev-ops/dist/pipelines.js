import { CiClientError, } from "./client.js";
export async function triggerPipeline(provider, input) {
    validateWorkflowName(input.workflow);
    validateRef(input.ref);
    const result = await provider.triggerWorkflow(input);
    return {
        accepted: result.accepted,
        note: result.note,
        provider: provider.name,
        workflow: input.workflow,
        ref: input.ref,
        dispatchedAt: new Date().toISOString(),
    };
}
export async function getPipelineStatus(provider, runId) {
    if (!runId) {
        throw new CiClientError("runId is required", { status: 0, path: "" });
    }
    const run = await provider.getRun(runId);
    const createdMs = Date.parse(run.createdAt);
    const updatedMs = Date.parse(run.updatedAt);
    const durationMs = Number.isFinite(createdMs) && Number.isFinite(updatedMs) && updatedMs >= createdMs
        ? updatedMs - createdMs
        : null;
    return {
        ...run,
        provider: provider.name,
        fetchedAt: new Date().toISOString(),
        durationMs,
    };
}
export async function fetchArtifacts(provider, runId) {
    if (!runId) {
        throw new CiClientError("runId is required", { status: 0, path: "" });
    }
    const artifacts = await provider.listArtifacts(runId);
    const totalBytes = artifacts.reduce((acc, a) => acc + a.sizeBytes, 0);
    return {
        provider: provider.name,
        runId,
        artifacts,
        totalBytes,
        fetchedAt: new Date().toISOString(),
    };
}
/**
 * Deploy is a thin wrapper over `triggerPipeline` that enforces an
 * explicit `environment` argument and records it in the run note.
 * The surrounding org is expected to maintain a workflow that reads
 * the environment input and routes accordingly — we do not try to
 * own the deploy topology.
 */
export async function deploy(provider, input) {
    validateWorkflowName(input.workflow);
    validateRef(input.ref);
    const merged = {
        environment: input.environment,
        ...(input.inputs ?? {}),
    };
    const result = await triggerPipeline(provider, {
        workflow: input.workflow,
        ref: input.ref,
        inputs: merged,
    });
    return {
        ...result,
        note: `${result.note} (environment=${input.environment})`,
    };
}
/**
 * Rollback dispatches the caller's rollback workflow with the target
 * ref + human-readable reason. A blank reason is rejected — rollback
 * audit trails are only useful if they record why.
 */
export async function rollback(provider, input) {
    validateWorkflowName(input.workflow);
    validateRef(input.targetRef);
    if (!input.reason || input.reason.trim().length < 3) {
        throw new CiClientError("rollback reason is required and must be at least 3 characters", { status: 0, path: "" });
    }
    const result = await triggerPipeline(provider, {
        workflow: input.workflow,
        ref: input.targetRef,
        inputs: {
            environment: input.environment,
            reason: input.reason,
            action: "rollback",
        },
    });
    return {
        ...result,
        note: `${result.note} rollback→${input.targetRef} env=${input.environment} reason="${input.reason}"`,
    };
}
function validateWorkflowName(name) {
    if (!name || name.trim().length === 0) {
        throw new CiClientError("workflow name is required", { status: 0, path: "" });
    }
    // Path traversal would let a caller dispatch any workflow in the repo.
    if (name.includes("..") || name.includes("\\")) {
        throw new CiClientError(`workflow name contains forbidden characters: ${name}`, { status: 0, path: "" });
    }
}
function validateRef(ref) {
    if (!ref || ref.trim().length === 0) {
        throw new CiClientError("ref is required", { status: 0, path: "" });
    }
    // Refs can be branches, tags, or SHAs — anything non-empty is fine,
    // but refs with embedded newlines or whitespace-only entries are
    // almost always accidents.
    if (/\s/.test(ref.trim()) || ref.includes("\n")) {
        throw new CiClientError(`ref contains whitespace: ${JSON.stringify(ref)}`, {
            status: 0,
            path: "",
        });
    }
}
//# sourceMappingURL=pipelines.js.map