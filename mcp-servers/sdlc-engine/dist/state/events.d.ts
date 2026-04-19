import { z } from "zod";
import { ConsensusStatus } from "../consensus.js";
import type { ProjectState } from "./store.js";
/**
 * Event log schema version. Bump on any breaking change to the JSON
 * envelope or payload shapes. FilesystemStateStore refuses to read events
 * with a different schemaVersion.
 */
export declare const EVENT_SCHEMA_VERSION = 1;
/**
 * Canonical event type discriminator. Every state mutation maps to exactly
 * one of these. Adding a new type requires bumping EVENT_SCHEMA_VERSION if
 * older readers would misinterpret the new payload.
 */
export declare const EventTypeSchema: z.ZodEnum<["project_created", "criterion_satisfied", "consensus_recorded", "phase_advanced", "project_imported"]>;
export type EventType = z.infer<typeof EventTypeSchema>;
declare const ProjectCreatedPayloadSchema: z.ZodObject<{
    firstPhase: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
}, "strip", z.ZodTypeAny, {
    firstPhase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
}, {
    firstPhase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
}>;
declare const CriterionSatisfiedPayloadSchema: z.ZodObject<{
    criterion: z.ZodString;
    phase: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
    alreadyPresent: z.ZodBoolean;
}, "strip", z.ZodTypeAny, {
    phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    criterion: string;
    alreadyPresent: boolean;
}, {
    phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    criterion: string;
    alreadyPresent: boolean;
}>;
declare const ConsensusRecordedPayloadSchema: z.ZodObject<{
    consensus: z.ZodObject<{
        phase: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
        status: z.ZodEffects<z.ZodString, ConsensusStatus, string>;
        agreement: z.ZodNumber;
        criticalIssues: z.ZodNumber;
        recordedAt: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        status: ConsensusStatus;
        phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        agreement: number;
        criticalIssues: number;
        recordedAt: string;
    }, {
        status: string;
        phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        agreement: number;
        criticalIssues: number;
        recordedAt: string;
    }>;
}, "strip", z.ZodTypeAny, {
    consensus: {
        status: ConsensusStatus;
        phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        agreement: number;
        criticalIssues: number;
        recordedAt: string;
    };
}, {
    consensus: {
        status: string;
        phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        agreement: number;
        criticalIssues: number;
        recordedAt: string;
    };
}>;
declare const PhaseAdvancedPayloadSchema: z.ZodObject<{
    from: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
    to: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
    force: z.ZodBoolean;
}, "strip", z.ZodTypeAny, {
    to: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    force: boolean;
    from: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
}, {
    to: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    force: boolean;
    from: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
}>;
declare const ProjectImportedPayloadSchema: z.ZodObject<{
    source: z.ZodString;
    importedAt: z.ZodString;
    note: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    source: string;
    importedAt: string;
    note?: string | undefined;
}, {
    source: string;
    importedAt: string;
    note?: string | undefined;
}>;
export type ProjectCreatedPayload = z.infer<typeof ProjectCreatedPayloadSchema>;
export type CriterionSatisfiedPayload = z.infer<typeof CriterionSatisfiedPayloadSchema>;
export type ConsensusRecordedPayload = z.infer<typeof ConsensusRecordedPayloadSchema>;
export type PhaseAdvancedPayload = z.infer<typeof PhaseAdvancedPayloadSchema>;
export type ProjectImportedPayload = z.infer<typeof ProjectImportedPayloadSchema>;
/**
 * Discriminated union across event types. Each variant has a matching
 * payload shape. `seq === revision` by construction (one event per
 * revision bump), stored separately so future compaction can diverge.
 */
export type StateEvent = {
    seq: number;
    revision: number;
    type: "project_created";
    projectId: string;
    recordedAt: string;
    actor: string;
    payload: ProjectCreatedPayload;
    prevRevision: number;
    schemaVersion: typeof EVENT_SCHEMA_VERSION;
} | {
    seq: number;
    revision: number;
    type: "criterion_satisfied";
    projectId: string;
    recordedAt: string;
    actor: string;
    payload: CriterionSatisfiedPayload;
    prevRevision: number;
    schemaVersion: typeof EVENT_SCHEMA_VERSION;
} | {
    seq: number;
    revision: number;
    type: "consensus_recorded";
    projectId: string;
    recordedAt: string;
    actor: string;
    payload: ConsensusRecordedPayload;
    prevRevision: number;
    schemaVersion: typeof EVENT_SCHEMA_VERSION;
} | {
    seq: number;
    revision: number;
    type: "phase_advanced";
    projectId: string;
    recordedAt: string;
    actor: string;
    payload: PhaseAdvancedPayload;
    prevRevision: number;
    schemaVersion: typeof EVENT_SCHEMA_VERSION;
} | {
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
export declare const StateEventSchema: z.ZodDiscriminatedUnion<"type", [z.ZodObject<{
    type: z.ZodLiteral<"project_created">;
    payload: z.ZodObject<{
        firstPhase: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
    }, "strip", z.ZodTypeAny, {
        firstPhase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    }, {
        firstPhase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    }>;
    seq: z.ZodNumber;
    revision: z.ZodNumber;
    projectId: z.ZodString;
    recordedAt: z.ZodString;
    actor: z.ZodString;
    prevRevision: z.ZodNumber;
    schemaVersion: z.ZodLiteral<1>;
}, "strip", z.ZodTypeAny, {
    type: "project_created";
    revision: number;
    projectId: string;
    recordedAt: string;
    payload: {
        firstPhase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    };
    seq: number;
    actor: string;
    prevRevision: number;
    schemaVersion: 1;
}, {
    type: "project_created";
    revision: number;
    projectId: string;
    recordedAt: string;
    payload: {
        firstPhase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    };
    seq: number;
    actor: string;
    prevRevision: number;
    schemaVersion: 1;
}>, z.ZodObject<{
    type: z.ZodLiteral<"criterion_satisfied">;
    payload: z.ZodObject<{
        criterion: z.ZodString;
        phase: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
        alreadyPresent: z.ZodBoolean;
    }, "strip", z.ZodTypeAny, {
        phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        criterion: string;
        alreadyPresent: boolean;
    }, {
        phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        criterion: string;
        alreadyPresent: boolean;
    }>;
    seq: z.ZodNumber;
    revision: z.ZodNumber;
    projectId: z.ZodString;
    recordedAt: z.ZodString;
    actor: z.ZodString;
    prevRevision: z.ZodNumber;
    schemaVersion: z.ZodLiteral<1>;
}, "strip", z.ZodTypeAny, {
    type: "criterion_satisfied";
    revision: number;
    projectId: string;
    recordedAt: string;
    payload: {
        phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        criterion: string;
        alreadyPresent: boolean;
    };
    seq: number;
    actor: string;
    prevRevision: number;
    schemaVersion: 1;
}, {
    type: "criterion_satisfied";
    revision: number;
    projectId: string;
    recordedAt: string;
    payload: {
        phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        criterion: string;
        alreadyPresent: boolean;
    };
    seq: number;
    actor: string;
    prevRevision: number;
    schemaVersion: 1;
}>, z.ZodObject<{
    type: z.ZodLiteral<"consensus_recorded">;
    payload: z.ZodObject<{
        consensus: z.ZodObject<{
            phase: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
            status: z.ZodEffects<z.ZodString, ConsensusStatus, string>;
            agreement: z.ZodNumber;
            criticalIssues: z.ZodNumber;
            recordedAt: z.ZodString;
        }, "strip", z.ZodTypeAny, {
            status: ConsensusStatus;
            phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
            agreement: number;
            criticalIssues: number;
            recordedAt: string;
        }, {
            status: string;
            phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
            agreement: number;
            criticalIssues: number;
            recordedAt: string;
        }>;
    }, "strip", z.ZodTypeAny, {
        consensus: {
            status: ConsensusStatus;
            phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
            agreement: number;
            criticalIssues: number;
            recordedAt: string;
        };
    }, {
        consensus: {
            status: string;
            phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
            agreement: number;
            criticalIssues: number;
            recordedAt: string;
        };
    }>;
    seq: z.ZodNumber;
    revision: z.ZodNumber;
    projectId: z.ZodString;
    recordedAt: z.ZodString;
    actor: z.ZodString;
    prevRevision: z.ZodNumber;
    schemaVersion: z.ZodLiteral<1>;
}, "strip", z.ZodTypeAny, {
    type: "consensus_recorded";
    revision: number;
    projectId: string;
    recordedAt: string;
    payload: {
        consensus: {
            status: ConsensusStatus;
            phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
            agreement: number;
            criticalIssues: number;
            recordedAt: string;
        };
    };
    seq: number;
    actor: string;
    prevRevision: number;
    schemaVersion: 1;
}, {
    type: "consensus_recorded";
    revision: number;
    projectId: string;
    recordedAt: string;
    payload: {
        consensus: {
            status: string;
            phase: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
            agreement: number;
            criticalIssues: number;
            recordedAt: string;
        };
    };
    seq: number;
    actor: string;
    prevRevision: number;
    schemaVersion: 1;
}>, z.ZodObject<{
    type: z.ZodLiteral<"phase_advanced">;
    payload: z.ZodObject<{
        from: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
        to: z.ZodEnum<["REQUIREMENTS", "DESIGN", "ARCHITECTURE", "PLANNING", "DEVELOPMENT", "TESTING", "DEPLOYMENT"]>;
        force: z.ZodBoolean;
    }, "strip", z.ZodTypeAny, {
        to: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        force: boolean;
        from: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    }, {
        to: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        force: boolean;
        from: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    }>;
    seq: z.ZodNumber;
    revision: z.ZodNumber;
    projectId: z.ZodString;
    recordedAt: z.ZodString;
    actor: z.ZodString;
    prevRevision: z.ZodNumber;
    schemaVersion: z.ZodLiteral<1>;
}, "strip", z.ZodTypeAny, {
    type: "phase_advanced";
    revision: number;
    projectId: string;
    recordedAt: string;
    payload: {
        to: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        force: boolean;
        from: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    };
    seq: number;
    actor: string;
    prevRevision: number;
    schemaVersion: 1;
}, {
    type: "phase_advanced";
    revision: number;
    projectId: string;
    recordedAt: string;
    payload: {
        to: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
        force: boolean;
        from: "REQUIREMENTS" | "DESIGN" | "ARCHITECTURE" | "PLANNING" | "DEVELOPMENT" | "TESTING" | "DEPLOYMENT";
    };
    seq: number;
    actor: string;
    prevRevision: number;
    schemaVersion: 1;
}>, z.ZodObject<{
    type: z.ZodLiteral<"project_imported">;
    payload: z.ZodObject<{
        source: z.ZodString;
        importedAt: z.ZodString;
        note: z.ZodOptional<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        source: string;
        importedAt: string;
        note?: string | undefined;
    }, {
        source: string;
        importedAt: string;
        note?: string | undefined;
    }>;
    seq: z.ZodNumber;
    revision: z.ZodNumber;
    projectId: z.ZodString;
    recordedAt: z.ZodString;
    actor: z.ZodString;
    prevRevision: z.ZodNumber;
    schemaVersion: z.ZodLiteral<1>;
}, "strip", z.ZodTypeAny, {
    type: "project_imported";
    revision: number;
    projectId: string;
    recordedAt: string;
    payload: {
        source: string;
        importedAt: string;
        note?: string | undefined;
    };
    seq: number;
    actor: string;
    prevRevision: number;
    schemaVersion: 1;
}, {
    type: "project_imported";
    revision: number;
    projectId: string;
    recordedAt: string;
    payload: {
        source: string;
        importedAt: string;
        note?: string | undefined;
    };
    seq: number;
    actor: string;
    prevRevision: number;
    schemaVersion: 1;
}>]>;
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
export declare function deriveEvent(current: ProjectState | null, next: ProjectState, context: MutatorContext): StateEvent;
/**
 * Serialize an event to a human-readable Markdown file with a YAML
 * front-matter block. The front-matter carries the full envelope (so
 * `parseEventMd` can recover the JSON losslessly) and the body renders
 * a type-specific summary.
 */
export declare function renderEventMd(event: StateEvent): string;
/**
 * Parse a Markdown event file (front-matter + body) back into a typed
 * StateEvent. Round-trips with renderEventMd.
 */
export declare function parseEventMd(md: string): StateEvent;
/**
 * Write a StateEvent to a JSON-safe object (plain JSON, no TypeScript
 * specific values). Inverse of `StateEventSchema.parse`.
 */
export declare function serializeEventJson(event: StateEvent): string;
export declare function parseEventJson(raw: string): StateEvent;
/**
 * Filename stem for an event (e.g. "0007-phase_advanced"). Zero-padded to
 * 4 digits so lexicographic sort matches numeric sort up to 9999 events.
 * Callers append ".json" or ".md".
 */
export declare function eventFileStem(event: Pick<StateEvent, "seq" | "type">): string;
export declare function padSeq(seq: number): string;
/**
 * Ensures ConsensusStatus is retained as a string for JSON I/O even though
 * it's an enum in-memory. No-op at runtime (ConsensusStatus values are
 * already strings) — kept explicit so readers don't grep for "where does
 * the enum get stringified".
 */
export declare function statusToJson(status: ConsensusStatus): string;
export {};
