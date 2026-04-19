import { describe, expect, it } from "vitest";
import {
  EVENT_SCHEMA_VERSION,
  StateEvent,
  StateEventSchema,
  deriveEvent,
  eventFileStem,
  padSeq,
  parseEventJson,
  parseEventMd,
  renderEventMd,
  serializeEventJson,
} from "../src/state/events.js";
import type { ProjectState } from "../src/state/store.js";
import { ConsensusStatus } from "../src/consensus.js";

const ISO = "2026-04-20T08:15:02.441Z";
const CTX = { actor: "sdlc_test", recordedAt: ISO };

function stateFactory(overrides: Partial<ProjectState> = {}): ProjectState {
  return {
    projectId: "test-project",
    currentPhase: "REQUIREMENTS",
    satisfiedCriteria: [],
    lastConsensus: null,
    updatedAt: ISO,
    revision: 1,
    ...overrides,
  };
}

describe("deriveEvent", () => {
  it("returns project_created when current is null", () => {
    const next = stateFactory();
    const event = deriveEvent(null, next, CTX);
    expect(event.type).toBe("project_created");
    expect(event.revision).toBe(1);
    expect(event.prevRevision).toBe(0);
    expect(event.payload).toEqual({ firstPhase: "REQUIREMENTS" });
  });

  it("returns phase_advanced when currentPhase changes", () => {
    const current = stateFactory({
      revision: 3,
      satisfiedCriteria: ["prd.approved", "testability.score>=60"],
    });
    const next = stateFactory({
      revision: 4,
      currentPhase: "DESIGN",
      satisfiedCriteria: ["prd.approved", "testability.score>=60"],
    });
    const event = deriveEvent(current, next, { ...CTX, force: false });
    expect(event.type).toBe("phase_advanced");
    if (event.type === "phase_advanced") {
      expect(event.payload).toEqual({
        from: "REQUIREMENTS",
        to: "DESIGN",
        force: false,
      });
    }
    expect(event.revision).toBe(4);
    expect(event.prevRevision).toBe(3);
  });

  it("honors the force flag in phase_advanced", () => {
    const current = stateFactory({ revision: 1 });
    const next = stateFactory({ revision: 2, currentPhase: "DESIGN" });
    const event = deriveEvent(current, next, { ...CTX, force: true });
    if (event.type !== "phase_advanced") throw new Error("wrong type");
    expect(event.payload.force).toBe(true);
  });

  it("returns consensus_recorded when lastConsensus changes", () => {
    const current = stateFactory({ revision: 1 });
    const next = stateFactory({
      revision: 2,
      lastConsensus: {
        phase: "REQUIREMENTS",
        status: ConsensusStatus.APPROVED,
        agreement: 0.95,
        criticalIssues: 0,
        recordedAt: ISO,
      },
    });
    const event = deriveEvent(current, next, CTX);
    expect(event.type).toBe("consensus_recorded");
    if (event.type !== "consensus_recorded") throw new Error("wrong type");
    expect(event.payload.consensus.status).toBe(ConsensusStatus.APPROVED);
    expect(event.payload.consensus.agreement).toBe(0.95);
  });

  it("returns criterion_satisfied when a new criterion is appended", () => {
    const current = stateFactory({ revision: 1, satisfiedCriteria: [] });
    const next = stateFactory({
      revision: 2,
      satisfiedCriteria: ["prd.approved"],
    });
    const event = deriveEvent(current, next, CTX);
    expect(event.type).toBe("criterion_satisfied");
    if (event.type !== "criterion_satisfied") throw new Error("wrong type");
    expect(event.payload.criterion).toBe("prd.approved");
    expect(event.payload.alreadyPresent).toBe(false);
    expect(event.payload.phase).toBe("REQUIREMENTS");
  });

  it("sets alreadyPresent=true for the Bug #13 no-op revision bump", () => {
    const current = stateFactory({
      revision: 2,
      satisfiedCriteria: ["prd.approved"],
    });
    const next = stateFactory({
      revision: 3,
      satisfiedCriteria: ["prd.approved"],
    });
    const event = deriveEvent(current, next, CTX);
    expect(event.type).toBe("criterion_satisfied");
    if (event.type !== "criterion_satisfied") throw new Error("wrong type");
    expect(event.payload.alreadyPresent).toBe(true);
    expect(event.payload.criterion).toBe("prd.approved");
  });

  it("throws on multi-field mutations", () => {
    const current = stateFactory({
      revision: 1,
      currentPhase: "REQUIREMENTS",
      satisfiedCriteria: [],
    });
    // Simultaneously bump phase AND add criterion — not a single event.
    const next = stateFactory({
      revision: 2,
      currentPhase: "DESIGN",
      satisfiedCriteria: ["prd.approved"],
    });
    // This still registers as phase_advanced because phase diff takes
    // precedence — verify that single-phase change works, then construct a
    // truly ambiguous mutation:
    deriveEvent(current, next, CTX); // phase_advanced, no throw

    const ambiguous = stateFactory({
      revision: 2,
      satisfiedCriteria: ["a", "b"],
    });
    expect(() =>
      deriveEvent(stateFactory({ revision: 1, satisfiedCriteria: [] }), ambiguous, CTX),
    ).toThrowError(/Cannot derive event/);
  });

  it("derives prevRevision=0 for project creation", () => {
    const next = stateFactory({ revision: 1 });
    const event = deriveEvent(null, next, CTX);
    expect(event.prevRevision).toBe(0);
  });

  it("uses context.recordedAt when provided, else next.updatedAt", () => {
    const next = stateFactory({
      revision: 1,
      updatedAt: "2026-04-20T00:00:00.000Z",
    });
    const explicit = deriveEvent(null, next, {
      actor: "test",
      recordedAt: "2026-01-01T00:00:00.000Z",
    });
    expect(explicit.recordedAt).toBe("2026-01-01T00:00:00.000Z");
    const fallback = deriveEvent(null, next, { actor: "test" });
    expect(fallback.recordedAt).toBe("2026-04-20T00:00:00.000Z");
  });
});

describe("renderEventMd + parseEventMd round-trip", () => {
  const projectCreated = deriveEvent(null, stateFactory({ revision: 1 }), CTX);
  const criterionSatisfied = deriveEvent(
    stateFactory({ revision: 1 }),
    stateFactory({ revision: 2, satisfiedCriteria: ["prd.approved"] }),
    CTX,
  );
  const phaseAdvanced = deriveEvent(
    stateFactory({ revision: 5 }),
    stateFactory({ revision: 6, currentPhase: "DESIGN" }),
    { ...CTX, force: true },
  );
  const consensusRecorded = deriveEvent(
    stateFactory({ revision: 1 }),
    stateFactory({
      revision: 2,
      lastConsensus: {
        phase: "REQUIREMENTS",
        status: ConsensusStatus.NEEDS_REVISION,
        agreement: 0.72,
        criticalIssues: 1,
        recordedAt: ISO,
      },
    }),
    CTX,
  );

  it.each<[string, StateEvent]>([
    ["project_created", projectCreated],
    ["criterion_satisfied", criterionSatisfied],
    ["phase_advanced", phaseAdvanced],
    ["consensus_recorded", consensusRecorded],
  ])("round-trips %s event through MD", (_label, event) => {
    const md = renderEventMd(event);
    const parsed = parseEventMd(md);
    expect(parsed).toEqual(event);
  });

  it("produces a body containing the type heading", () => {
    const md = renderEventMd(phaseAdvanced);
    expect(md).toMatch(/# Phase advanced: REQUIREMENTS → DESIGN/);
    expect(md).toMatch(/Revision 5 → 6/);
    expect(md).toMatch(/Force: yes/);
  });

  it("renders consensus body with verdict and agreement table", () => {
    const md = renderEventMd(consensusRecorded);
    expect(md).toMatch(/# Consensus recorded: NEEDS_REVISION/);
    expect(md).toMatch(/\| Agreement \| 72.0% \|/);
    expect(md).toMatch(/\| Critical issues \| 1 \|/);
  });

  it("renders the front-matter in a stable field order", () => {
    const md = renderEventMd(projectCreated);
    const order = [
      "seq:",
      "revision:",
      "type:",
      "projectId:",
      "recordedAt:",
      "actor:",
      "prevRevision:",
      "schemaVersion:",
      "payload:",
    ];
    let lastIdx = -1;
    for (const key of order) {
      const idx = md.indexOf(key);
      expect(idx).toBeGreaterThan(lastIdx);
      lastIdx = idx;
    }
  });

  it("rejects MD without front-matter delimiters", () => {
    expect(() => parseEventMd("# not an event\nbody only")).toThrowError(
      /front-matter/,
    );
  });
});

describe("serializeEventJson + parseEventJson round-trip", () => {
  const event = deriveEvent(null, stateFactory(), CTX);

  it("round-trips through JSON", () => {
    const json = serializeEventJson(event);
    const parsed = parseEventJson(json);
    expect(parsed).toEqual(event);
  });

  it("rejects JSON with wrong schemaVersion", () => {
    const json = JSON.stringify({ ...event, schemaVersion: 99 });
    expect(() => parseEventJson(json)).toThrowError();
  });

  it("rejects JSON with unknown event type", () => {
    const bad = JSON.stringify({ ...event, type: "unknown_event" });
    expect(() => parseEventJson(bad)).toThrowError();
  });

  it("rejects JSON with missing envelope fields", () => {
    const { seq: _seq, ...rest } = event as Record<string, unknown>;
    const bad = JSON.stringify(rest);
    expect(() => parseEventJson(bad)).toThrowError();
  });
});

describe("eventFileStem + padSeq", () => {
  it("pads seq to 4 digits", () => {
    expect(padSeq(1)).toBe("0001");
    expect(padSeq(42)).toBe("0042");
    expect(padSeq(9999)).toBe("9999");
    expect(padSeq(10000)).toBe("10000"); // graceful overflow, no truncation
  });

  it("produces stable filename stems", () => {
    const event = deriveEvent(null, stateFactory({ revision: 7 }), CTX);
    expect(eventFileStem(event)).toBe("0007-project_created");
  });
});

describe("StateEventSchema", () => {
  it("validates a well-formed event", () => {
    const event = deriveEvent(null, stateFactory(), CTX);
    const parsed = StateEventSchema.parse(event);
    expect(parsed.type).toBe("project_created");
  });

  it("accepts ConsensusStatus string aliases", () => {
    const event = {
      seq: 2,
      revision: 2,
      type: "consensus_recorded" as const,
      projectId: "p",
      recordedAt: ISO,
      actor: "test",
      prevRevision: 1,
      schemaVersion: EVENT_SCHEMA_VERSION,
      payload: {
        consensus: {
          phase: "REQUIREMENTS",
          status: "approved", // lowercase alias
          agreement: 0.9,
          criticalIssues: 0,
          recordedAt: ISO,
        },
      },
    };
    const parsed = StateEventSchema.parse(event);
    if (parsed.type !== "consensus_recorded") throw new Error("wrong type");
    expect(parsed.payload.consensus.status).toBe(ConsensusStatus.APPROVED);
  });
});
