import { z } from "zod";
import { PhaseIdSchema, type PhaseId } from "../phases.js";
import { ConsensusStatus, ConsensusStatusSchema } from "../consensus.js";
import type { ConsensusRecord, ProjectState } from "./store.js";

/**
 * Event log schema version. Bump on any breaking change to the JSON
 * envelope or payload shapes. FilesystemStateStore refuses to read events
 * with a different schemaVersion.
 */
export const EVENT_SCHEMA_VERSION = 1;

/**
 * Canonical event type discriminator. Every state mutation maps to exactly
 * one of these. Adding a new type requires bumping EVENT_SCHEMA_VERSION if
 * older readers would misinterpret the new payload.
 */
export const EventTypeSchema = z.enum([
  "project_created",
  "criterion_satisfied",
  "consensus_recorded",
  "phase_advanced",
  "project_imported",
]);
export type EventType = z.infer<typeof EventTypeSchema>;

const ConsensusRecordSchema = z.object({
  phase: PhaseIdSchema,
  status: ConsensusStatusSchema,
  agreement: z.number().min(0).max(1),
  criticalIssues: z.number().int().min(0),
  recordedAt: z.string(),
});

const ProjectCreatedPayloadSchema = z.object({
  firstPhase: PhaseIdSchema,
});

const CriterionSatisfiedPayloadSchema = z.object({
  criterion: z.string().min(1),
  phase: PhaseIdSchema,
  alreadyPresent: z.boolean(),
});

const ConsensusRecordedPayloadSchema = z.object({
  consensus: ConsensusRecordSchema,
});

const PhaseAdvancedPayloadSchema = z.object({
  from: PhaseIdSchema,
  to: PhaseIdSchema,
  force: z.boolean(),
});

const ProjectImportedPayloadSchema = z.object({
  source: z.string(),
  importedAt: z.string(),
  note: z.string().optional(),
});

export type ProjectCreatedPayload = z.infer<typeof ProjectCreatedPayloadSchema>;
export type CriterionSatisfiedPayload = z.infer<
  typeof CriterionSatisfiedPayloadSchema
>;
export type ConsensusRecordedPayload = z.infer<
  typeof ConsensusRecordedPayloadSchema
>;
export type PhaseAdvancedPayload = z.infer<typeof PhaseAdvancedPayloadSchema>;
export type ProjectImportedPayload = z.infer<
  typeof ProjectImportedPayloadSchema
>;

/**
 * Discriminated union across event types. Each variant has a matching
 * payload shape. `seq === revision` by construction (one event per
 * revision bump), stored separately so future compaction can diverge.
 */
export type StateEvent =
  | {
      seq: number;
      revision: number;
      type: "project_created";
      projectId: string;
      recordedAt: string;
      actor: string;
      payload: ProjectCreatedPayload;
      prevRevision: number;
      schemaVersion: typeof EVENT_SCHEMA_VERSION;
    }
  | {
      seq: number;
      revision: number;
      type: "criterion_satisfied";
      projectId: string;
      recordedAt: string;
      actor: string;
      payload: CriterionSatisfiedPayload;
      prevRevision: number;
      schemaVersion: typeof EVENT_SCHEMA_VERSION;
    }
  | {
      seq: number;
      revision: number;
      type: "consensus_recorded";
      projectId: string;
      recordedAt: string;
      actor: string;
      payload: ConsensusRecordedPayload;
      prevRevision: number;
      schemaVersion: typeof EVENT_SCHEMA_VERSION;
    }
  | {
      seq: number;
      revision: number;
      type: "phase_advanced";
      projectId: string;
      recordedAt: string;
      actor: string;
      payload: PhaseAdvancedPayload;
      prevRevision: number;
      schemaVersion: typeof EVENT_SCHEMA_VERSION;
    }
  | {
      seq: number;
      revision: number;
      type: "project_imported";
      projectId: string;
      recordedAt: string;
      actor: string;
      payload: ProjectImportedPayload;
      prevRevision: number;
      schemaVersion: typeof EVENT_SCHEMA_VERSION;
    };

const baseEnvelope = {
  seq: z.number().int().positive(),
  revision: z.number().int().positive(),
  projectId: z.string().min(1),
  recordedAt: z.string(),
  actor: z.string().min(1),
  prevRevision: z.number().int().min(0),
  schemaVersion: z.literal(EVENT_SCHEMA_VERSION),
};

export const StateEventSchema = z.discriminatedUnion("type", [
  z.object({
    ...baseEnvelope,
    type: z.literal("project_created"),
    payload: ProjectCreatedPayloadSchema,
  }),
  z.object({
    ...baseEnvelope,
    type: z.literal("criterion_satisfied"),
    payload: CriterionSatisfiedPayloadSchema,
  }),
  z.object({
    ...baseEnvelope,
    type: z.literal("consensus_recorded"),
    payload: ConsensusRecordedPayloadSchema,
  }),
  z.object({
    ...baseEnvelope,
    type: z.literal("phase_advanced"),
    payload: PhaseAdvancedPayloadSchema,
  }),
  z.object({
    ...baseEnvelope,
    type: z.literal("project_imported"),
    payload: ProjectImportedPayloadSchema,
  }),
]);

export interface MutatorContext {
  /** MCP tool name that triggered the mutation (e.g. "sdlc_advance_phase"). */
  actor: string;
  /** When the mutation was recorded. Falls back to next.updatedAt. */
  recordedAt?: string;
  /** Optional hint — only read for phase_advanced to record force flag. */
  force?: boolean;
}

/**
 * Compare current → next ProjectState and produce the single StateEvent
 * that describes the transition. Throws if the two states differ in ways
 * that can't be expressed as exactly one event (caller contract violation).
 */
export function deriveEvent(
  current: ProjectState | null,
  next: ProjectState,
  context: MutatorContext,
): StateEvent {
  const recordedAt = context.recordedAt ?? next.updatedAt;
  const base = {
    seq: next.revision,
    revision: next.revision,
    projectId: next.projectId,
    recordedAt,
    actor: context.actor,
    prevRevision: current?.revision ?? 0,
    schemaVersion: EVENT_SCHEMA_VERSION as typeof EVENT_SCHEMA_VERSION,
  };

  if (current === null) {
    return {
      ...base,
      type: "project_created",
      payload: { firstPhase: next.currentPhase },
    };
  }

  if (current.currentPhase !== next.currentPhase) {
    return {
      ...base,
      type: "phase_advanced",
      payload: {
        from: current.currentPhase,
        to: next.currentPhase,
        force: context.force ?? false,
      },
    };
  }

  const consensusChanged = consensusRecordsDiffer(
    current.lastConsensus,
    next.lastConsensus,
  );
  if (consensusChanged && next.lastConsensus !== null) {
    return {
      ...base,
      type: "consensus_recorded",
      payload: { consensus: next.lastConsensus },
    };
  }

  const added = diffCriteria(current.satisfiedCriteria, next.satisfiedCriteria);
  if (added.length === 1) {
    return {
      ...base,
      type: "criterion_satisfied",
      payload: {
        criterion: added[0]!,
        phase: next.currentPhase,
        alreadyPresent: current.satisfiedCriteria.includes(added[0]!),
      },
    };
  }
  if (added.length === 0 && next.revision > current.revision) {
    // Bug #13 fast-path: no-op revision bump (getOrInit on existing row).
    // Record a criterion_satisfied event with alreadyPresent=true and the
    // most recent criterion as the payload so the log stays faithful.
    const lastCriterion =
      next.satisfiedCriteria[next.satisfiedCriteria.length - 1] ?? "";
    return {
      ...base,
      type: "criterion_satisfied",
      payload: {
        criterion: lastCriterion,
        phase: next.currentPhase,
        alreadyPresent: true,
      },
    };
  }

  throw new Error(
    `Cannot derive event: state transition between revision ` +
      `${current.revision} → ${next.revision} does not match any known ` +
      `event type (phase unchanged, consensus unchanged, ${added.length} ` +
      `new criteria). Multi-field updates must be split into separate ` +
      `transact() calls.`,
  );
}

function consensusRecordsDiffer(
  a: ConsensusRecord | null,
  b: ConsensusRecord | null,
): boolean {
  if (a === null && b === null) return false;
  if (a === null || b === null) return true;
  return (
    a.phase !== b.phase ||
    a.status !== b.status ||
    a.agreement !== b.agreement ||
    a.criticalIssues !== b.criticalIssues ||
    a.recordedAt !== b.recordedAt
  );
}

function diffCriteria(
  before: readonly string[],
  after: readonly string[],
): string[] {
  const beforeSet = new Set(before);
  return after.filter((c) => !beforeSet.has(c));
}

/**
 * Serialize an event to a human-readable Markdown file with a YAML
 * front-matter block. The front-matter carries the full envelope (so
 * `parseEventMd` can recover the JSON losslessly) and the body renders
 * a type-specific summary.
 */
export function renderEventMd(event: StateEvent): string {
  const frontMatter = renderFrontMatter(event);
  const body = renderEventBody(event);
  return `---\n${frontMatter}---\n\n${body}\n`;
}

function renderFrontMatter(event: StateEvent): string {
  // Keep the ordering stable so git diffs are minimal.
  const lines: string[] = [];
  lines.push(`seq: ${event.seq}`);
  lines.push(`revision: ${event.revision}`);
  lines.push(`type: ${event.type}`);
  lines.push(`projectId: ${yamlString(event.projectId)}`);
  lines.push(`recordedAt: ${yamlString(event.recordedAt)}`);
  lines.push(`actor: ${yamlString(event.actor)}`);
  lines.push(`prevRevision: ${event.prevRevision}`);
  lines.push(`schemaVersion: ${event.schemaVersion}`);
  lines.push(`payload: ${JSON.stringify(event.payload)}`);
  return lines.map((l) => l + "\n").join("");
}

function yamlString(value: string): string {
  // Quote to dodge YAML's special characters (colons, dashes, etc.).
  return JSON.stringify(value);
}

function renderEventBody(event: StateEvent): string {
  switch (event.type) {
    case "project_created":
      return (
        `# Project created\n\n` +
        `Project \`${event.projectId}\` initialised at phase ` +
        `**${event.payload.firstPhase}** (revision 1).`
      );
    case "criterion_satisfied":
      return (
        `# Criterion satisfied\n\n` +
        `Criterion \`${event.payload.criterion}\` satisfied during phase ` +
        `**${event.payload.phase}**` +
        (event.payload.alreadyPresent
          ? ` (already present — revision bump only).`
          : `.`)
      );
    case "consensus_recorded": {
      const c = event.payload.consensus;
      return (
        `# Consensus recorded: ${c.status}\n\n` +
        `| Field | Value |\n` +
        `|-------|-------|\n` +
        `| Phase | ${c.phase} |\n` +
        `| Status | ${c.status} |\n` +
        `| Agreement | ${formatAgreement(c.agreement)} |\n` +
        `| Critical issues | ${c.criticalIssues} |\n` +
        `| Recorded at | ${c.recordedAt} |\n`
      );
    }
    case "phase_advanced":
      return (
        `# Phase advanced: ${event.payload.from} → ${event.payload.to}\n\n` +
        `Revision ${event.prevRevision} → ${event.revision}. ` +
        `Force: ${event.payload.force ? "yes" : "no"}.`
      );
    case "project_imported":
      return (
        `# Project imported from ${event.payload.source}\n\n` +
        `Imported at ${event.payload.importedAt}.` +
        (event.payload.note ? `\n\n${event.payload.note}` : "")
      );
  }
}

function formatAgreement(value: number): string {
  return `${(value * 100).toFixed(1)}%`;
}

/**
 * Parse a Markdown event file (front-matter + body) back into a typed
 * StateEvent. Round-trips with renderEventMd.
 */
export function parseEventMd(md: string): StateEvent {
  const match = md.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) {
    throw new Error("Event MD missing YAML front-matter delimiters");
  }
  const frontMatter = match[1]!;
  const envelope: Record<string, unknown> = {};
  for (const line of frontMatter.split("\n")) {
    if (!line.trim()) continue;
    const sep = line.indexOf(":");
    if (sep < 0) {
      throw new Error(`Malformed front-matter line: ${line}`);
    }
    const key = line.slice(0, sep).trim();
    const rawValue = line.slice(sep + 1).trim();
    envelope[key] = parseFrontMatterValue(key, rawValue);
  }
  return StateEventSchema.parse(envelope);
}

function parseFrontMatterValue(key: string, raw: string): unknown {
  if (key === "payload") {
    return JSON.parse(raw);
  }
  if (
    key === "seq" ||
    key === "revision" ||
    key === "prevRevision" ||
    key === "schemaVersion"
  ) {
    return Number(raw);
  }
  if (raw.startsWith('"') && raw.endsWith('"')) {
    return JSON.parse(raw);
  }
  return raw;
}

/**
 * Write a StateEvent to a JSON-safe object (plain JSON, no TypeScript
 * specific values). Inverse of `StateEventSchema.parse`.
 */
export function serializeEventJson(event: StateEvent): string {
  return JSON.stringify(event, null, 2) + "\n";
}

export function parseEventJson(raw: string): StateEvent {
  const parsed = JSON.parse(raw);
  return StateEventSchema.parse(parsed);
}

/**
 * Filename stem for an event (e.g. "0007-phase_advanced"). Zero-padded to
 * 4 digits so lexicographic sort matches numeric sort up to 9999 events.
 * Callers append ".json" or ".md".
 */
export function eventFileStem(event: Pick<StateEvent, "seq" | "type">): string {
  return `${padSeq(event.seq)}-${event.type}`;
}

export function padSeq(seq: number): string {
  return String(seq).padStart(4, "0");
}

/**
 * Ensures ConsensusStatus is retained as a string for JSON I/O even though
 * it's an enum in-memory. No-op at runtime (ConsensusStatus values are
 * already strings) — kept explicit so readers don't grep for "where does
 * the enum get stringified".
 */
export function statusToJson(status: ConsensusStatus): string {
  return status;
}
