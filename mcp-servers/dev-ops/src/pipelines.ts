import {
  CiProvider,
  PipelineRun,
  PipelineArtifact,
  CiClientError,
} from "./client.js";

/**
 * Pipeline orchestration helpers.
 *
 * Everything in this file is a pure function of a `CiProvider` + input —
 * the module is test-friendly because the provider is injectable and
 * the return shapes are deterministic. No globals, no I/O outside the
 * provider call.
 */

export interface TriggerPipelineInput {
  readonly workflow: string;
  readonly ref: string;
  readonly inputs?: Readonly<Record<string, string>>;
}

export interface TriggerPipelineResult {
  readonly accepted: boolean;
  readonly note: string;
  readonly provider: string;
  readonly workflow: string;
  readonly ref: string;
  readonly dispatchedAt: string;
}

export async function triggerPipeline(
  provider: CiProvider,
  input: TriggerPipelineInput,
): Promise<TriggerPipelineResult> {
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

export interface PipelineStatusResult extends PipelineRun {
  readonly provider: string;
  readonly fetchedAt: string;
  readonly durationMs: number | null;
}

export async function getPipelineStatus(
  provider: CiProvider,
  runId: string,
): Promise<PipelineStatusResult> {
  if (!runId) {
    throw new CiClientError("runId is required", { status: 0, path: "" });
  }
  const run = await provider.getRun(runId);
  const createdMs = Date.parse(run.createdAt);
  const updatedMs = Date.parse(run.updatedAt);
  const durationMs =
    Number.isFinite(createdMs) && Number.isFinite(updatedMs) && updatedMs >= createdMs
      ? updatedMs - createdMs
      : null;
  return {
    ...run,
    provider: provider.name,
    fetchedAt: new Date().toISOString(),
    durationMs,
  };
}

export interface FetchArtifactsResult {
  readonly provider: string;
  readonly runId: string;
  readonly artifacts: readonly PipelineArtifact[];
  readonly totalBytes: number;
  readonly fetchedAt: string;
}

export async function fetchArtifacts(
  provider: CiProvider,
  runId: string,
): Promise<FetchArtifactsResult> {
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

export interface DeployInput {
  readonly workflow: string;
  readonly ref: string;
  readonly environment: "staging" | "production";
  readonly inputs?: Readonly<Record<string, string>>;
}

/**
 * Deploy is a thin wrapper over `triggerPipeline` that enforces an
 * explicit `environment` argument and records it in the run note.
 * The surrounding org is expected to maintain a workflow that reads
 * the environment input and routes accordingly — we do not try to
 * own the deploy topology.
 */
export async function deploy(
  provider: CiProvider,
  input: DeployInput,
): Promise<TriggerPipelineResult> {
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

export interface RollbackInput {
  readonly workflow: string;
  /** The commit SHA or tag to roll back TO — never an empty string. */
  readonly targetRef: string;
  readonly reason: string;
  readonly environment: "staging" | "production";
}

/**
 * Rollback dispatches the caller's rollback workflow with the target
 * ref + human-readable reason. A blank reason is rejected — rollback
 * audit trails are only useful if they record why.
 */
export async function rollback(
  provider: CiProvider,
  input: RollbackInput,
): Promise<TriggerPipelineResult> {
  validateWorkflowName(input.workflow);
  validateRef(input.targetRef);
  if (!input.reason || input.reason.trim().length < 3) {
    throw new CiClientError(
      "rollback reason is required and must be at least 3 characters",
      { status: 0, path: "" },
    );
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

function validateWorkflowName(name: string): void {
  if (!name || name.trim().length === 0) {
    throw new CiClientError("workflow name is required", { status: 0, path: "" });
  }
  // Path traversal would let a caller dispatch any workflow in the repo.
  if (name.includes("..") || name.includes("\\")) {
    throw new CiClientError(
      `workflow name contains forbidden characters: ${name}`,
      { status: 0, path: "" },
    );
  }
}

function validateRef(ref: string): void {
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
