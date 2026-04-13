import { z } from "zod";
import {
  CiProvider,
  createGithubClient,
  FetchImpl,
  CiConfigError,
} from "./client.js";
import {
  triggerPipeline,
  getPipelineStatus,
  fetchArtifacts,
  deploy,
  rollback,
} from "./pipelines.js";

export interface ToolDefinition {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  handler: (args: unknown) => Promise<unknown>;
}

export interface BuildToolsOptions {
  /** Override provider — tests pass a fake, production reads from env. */
  readonly provider?: CiProvider;
  /** For tests: inject fetch so we never touch the real network. */
  readonly fetchImpl?: FetchImpl;
  /** For tests: explicit token avoids env var pollution. */
  readonly token?: string;
  /** Overrides for the GitHub base URL (local pact tests). */
  readonly baseUrl?: string;
}

const KvObject = z.record(z.string());

const TriggerPipelineInput = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
  workflow: z.string().min(1),
  ref: z.string().min(1),
  inputs: KvObject.optional(),
});

const PipelineStatusInput = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
  runId: z.string().min(1),
});

const FetchArtifactsInput = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
  runId: z.string().min(1),
});

const DeployStagingInput = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
  workflow: z.string().min(1),
  ref: z.string().min(1),
  environment: z.enum(["staging", "production"]).default("staging"),
  inputs: KvObject.optional(),
});

const RollbackInput = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
  workflow: z.string().min(1),
  targetRef: z.string().min(1),
  reason: z.string().min(3),
  environment: z.enum(["staging", "production"]).default("production"),
});

export function buildTools(opts: BuildToolsOptions = {}): ToolDefinition[] {
  /**
   * Resolve the provider lazily so the tool list can be enumerated
   * (and the server can start) without a valid token. Token errors
   * only surface when a tool that needs the provider is actually
   * called.
   *
   * The CI_PROVIDER environment variable (sourced from the
   * `ci_provider` userConfig key via .mcp.json template substitution)
   * selects between the supported backends. Unknown values raise a
   * loud CiConfigError rather than silently falling back to GitHub —
   * a misconfigured provider is a worse failure mode than no provider.
   */
  const getProvider = (owner: string, repo: string): CiProvider => {
    if (opts.provider) return opts.provider;
    const requested = (process.env.CI_PROVIDER ?? "github").toLowerCase();
    if (requested === "github" || requested === "") {
      try {
        return createGithubClient({
          owner,
          repo,
          token: opts.token,
          baseUrl: opts.baseUrl,
          fetchImpl: opts.fetchImpl,
        });
      } catch (err) {
        if (err instanceof CiConfigError) throw err;
        throw err;
      }
    }
    if (requested === "gitlab") {
      throw new CiConfigError(
        "ci_provider 'gitlab' is declared but the GitLab client is not implemented yet. " +
          "Set ci_provider to 'github' or remove the override.",
      );
    }
    throw new CiConfigError(
      `unknown ci_provider '${requested}'. Supported values: 'github', 'gitlab'.`,
    );
  };

  return [
    {
      name: "do_trigger_pipeline",
      description:
        "Dispatch a CI workflow (GitHub Actions) on a given ref with " +
        "optional workflow_dispatch inputs. Accepts workflow file name " +
        "(preferred) or workflow id.",
      inputSchema: {
        type: "object",
        properties: {
          owner: { type: "string", minLength: 1 },
          repo: { type: "string", minLength: 1 },
          workflow: { type: "string", minLength: 1 },
          ref: { type: "string", minLength: 1 },
          inputs: { type: "object", additionalProperties: { type: "string" } },
        },
        required: ["owner", "repo", "workflow", "ref"],
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = TriggerPipelineInput.parse(raw);
        const provider = getProvider(args.owner, args.repo);
        return triggerPipeline(provider, {
          workflow: args.workflow,
          ref: args.ref,
          inputs: args.inputs,
        });
      },
    },
    {
      name: "do_pipeline_status",
      description:
        "Fetch the status + conclusion of a CI run. Returns a normalized " +
        "shape that never exposes provider-specific string enums (queued/" +
        "in_progress/completed only). Computes a derived durationMs.",
      inputSchema: {
        type: "object",
        properties: {
          owner: { type: "string", minLength: 1 },
          repo: { type: "string", minLength: 1 },
          runId: { type: "string", minLength: 1 },
        },
        required: ["owner", "repo", "runId"],
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = PipelineStatusInput.parse(raw);
        const provider = getProvider(args.owner, args.repo);
        return getPipelineStatus(provider, args.runId);
      },
    },
    {
      name: "do_fetch_artifacts",
      description:
        "List artifacts for a CI run — returns download URLs, never " +
        "downloads the blobs. Caller is responsible for fetching the " +
        "archive (which requires the same auth).",
      inputSchema: {
        type: "object",
        properties: {
          owner: { type: "string", minLength: 1 },
          repo: { type: "string", minLength: 1 },
          runId: { type: "string", minLength: 1 },
        },
        required: ["owner", "repo", "runId"],
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = FetchArtifactsInput.parse(raw);
        const provider = getProvider(args.owner, args.repo);
        return fetchArtifacts(provider, args.runId);
      },
    },
    {
      name: "do_deploy_staging",
      description:
        "Dispatch a deploy workflow with an explicit environment input. " +
        "Thin wrapper over do_trigger_pipeline; exists so audit logs " +
        "clearly record 'deploy' vs generic 'dispatch'.",
      inputSchema: {
        type: "object",
        properties: {
          owner: { type: "string", minLength: 1 },
          repo: { type: "string", minLength: 1 },
          workflow: { type: "string", minLength: 1 },
          ref: { type: "string", minLength: 1 },
          environment: { type: "string", enum: ["staging", "production"] },
          inputs: { type: "object", additionalProperties: { type: "string" } },
        },
        required: ["owner", "repo", "workflow", "ref"],
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = DeployStagingInput.parse(raw);
        const provider = getProvider(args.owner, args.repo);
        return deploy(provider, {
          workflow: args.workflow,
          ref: args.ref,
          environment: args.environment,
          inputs: args.inputs,
        });
      },
    },
    {
      name: "do_rollback",
      description:
        "Dispatch a rollback workflow with the target ref + a required " +
        "human-readable reason (min 3 chars). Reason is preserved in the " +
        "run note for audit.",
      inputSchema: {
        type: "object",
        properties: {
          owner: { type: "string", minLength: 1 },
          repo: { type: "string", minLength: 1 },
          workflow: { type: "string", minLength: 1 },
          targetRef: { type: "string", minLength: 1 },
          reason: { type: "string", minLength: 3 },
          environment: { type: "string", enum: ["staging", "production"] },
        },
        required: ["owner", "repo", "workflow", "targetRef", "reason"],
        additionalProperties: false,
      },
      handler: async (raw) => {
        const args = RollbackInput.parse(raw);
        const provider = getProvider(args.owner, args.repo);
        return rollback(provider, {
          workflow: args.workflow,
          targetRef: args.targetRef,
          reason: args.reason,
          environment: args.environment,
        });
      },
    },
  ];
}
