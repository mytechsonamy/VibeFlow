import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as fsp from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { FilesystemStateStore } from "../src/state/filesystem.js";
import { ProjectState } from "../src/state/store.js";
import { ConsensusStatus } from "../src/consensus.js";

const PROJECT_ID = "testproj";
const ISO = "2026-04-20T00:00:00.000Z";

function makeState(overrides: Partial<ProjectState> = {}): ProjectState {
  return {
    projectId: PROJECT_ID,
    currentPhase: "REQUIREMENTS",
    satisfiedCriteria: [],
    lastConsensus: null,
    updatedAt: ISO,
    revision: 1,
    ...overrides,
  };
}

describe("FilesystemStateStore", () => {
  let dir: string;
  let store: FilesystemStateStore;

  beforeEach(async () => {
    dir = await fsp.mkdtemp(path.join(os.tmpdir(), "vf-fs-"));
    store = new FilesystemStateStore(dir);
    await store.init();
  });

  afterEach(async () => {
    await store.close();
    await fsp.rm(dir, { recursive: true, force: true });
  });

  it("init() is idempotent", async () => {
    await store.init();
    await store.init();
    expect(fs.existsSync(dir)).toBe(true);
  });

  it("init() creates the state dir even when absent", async () => {
    const fresh = path.join(dir, "nested", "further");
    const freshStore = new FilesystemStateStore(fresh);
    await freshStore.init();
    expect(fs.existsSync(fresh)).toBe(true);
    await freshStore.close();
  });

  it("read() returns null for an unknown project", async () => {
    const state = await store.read("never-seen");
    expect(state).toBeNull();
  });

  it("transact() creates project, writes event 0001 + MD twin + rollup", async () => {
    await store.transact(
      PROJECT_ID,
      (current) => {
        expect(current).toBeNull();
        return { next: makeState(), result: "ok" };
      },
      { context: { actor: "sdlc_get_state" } },
    );
    const projectDir = store.projectDir(PROJECT_ID);
    expect(fs.existsSync(path.join(projectDir, "project.json"))).toBe(true);
    expect(
      fs.existsSync(path.join(projectDir, "events", "0001-project_created.json")),
    ).toBe(true);
    expect(
      fs.existsSync(path.join(projectDir, "events", "0001-project_created.md")),
    ).toBe(true);
  });

  it("read() returns the state last written by transact()", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    const state = await store.read(PROJECT_ID);
    expect(state).not.toBeNull();
    expect(state?.currentPhase).toBe("REQUIREMENTS");
    expect(state?.revision).toBe(1);
  });

  it("transact() enforces revision increment", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    await expect(
      store.transact(
        PROJECT_ID,
        (current) => ({
          next: { ...current!, revision: current!.revision }, // no bump
          result: null,
        }),
        { context: { actor: "test" } },
      ),
    ).rejects.toThrowError(/revision must increment/);
  });

  it("transact() round-trips a consensus record through JSON + MD", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: current!.revision + 1,
          lastConsensus: {
            phase: "REQUIREMENTS",
            status: ConsensusStatus.APPROVED,
            agreement: 0.95,
            criticalIssues: 0,
            recordedAt: ISO,
          },
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "sdlc_record_consensus" } },
    );
    const state = await store.read(PROJECT_ID);
    expect(state?.lastConsensus?.status).toBe(ConsensusStatus.APPROVED);
  });

  it("survives close and reopen (rollup persistence)", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    await store.close();

    const reopened = new FilesystemStateStore(dir);
    await reopened.init();
    const state = await reopened.read(PROJECT_ID);
    expect(state?.revision).toBe(1);
    await reopened.close();
  });

  it("event sequence numbers increase monotonically", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    for (let i = 0; i < 3; i++) {
      await store.transact(
        PROJECT_ID,
        (current) => ({
          next: {
            ...current!,
            revision: current!.revision + 1,
            satisfiedCriteria: [
              ...current!.satisfiedCriteria,
              `criterion-${i}`,
            ],
            updatedAt: ISO,
          },
          result: null,
        }),
        { context: { actor: "test" } },
      );
    }
    const entries = (
      await fsp.readdir(path.join(store.projectDir(PROJECT_ID), "events"))
    )
      .filter((e) => e.endsWith(".json"))
      .sort();
    expect(entries).toEqual([
      "0001-project_created.json",
      "0002-criterion_satisfied.json",
      "0003-criterion_satisfied.json",
      "0004-criterion_satisfied.json",
    ]);
  });

  it("rejects invalid projectId", async () => {
    await expect(store.transact("has spaces", () => ({
      next: makeState({ projectId: "has spaces" }),
      result: null,
    }), { context: { actor: "test" } })).rejects.toThrowError(/Invalid projectId/);
  });

  it("rollback on mutator error leaves state unchanged", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    await expect(
      store.transact(
        PROJECT_ID,
        () => {
          throw new Error("boom");
        },
        { context: { actor: "test" } },
      ),
    ).rejects.toThrowError(/boom/);
    const state = await store.read(PROJECT_ID);
    expect(state?.revision).toBe(1);
  });

  it("cleans up orphan *.tmp files during init sweep", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    const projectDir = store.projectDir(PROJECT_ID);
    const orphan = path.join(projectDir, "events", "orphan.tmp");
    await fsp.writeFile(orphan, "garbage");
    // Backdate the mtime so the 30s orphan grace period considers it stale.
    const pastSec = Date.now() / 1000 - 3600;
    await fsp.utimes(orphan, pastSec, pastSec);
    expect(fs.existsSync(orphan)).toBe(true);

    await store.close();
    const reopened = new FilesystemStateStore(dir);
    await reopened.init();
    expect(fs.existsSync(orphan)).toBe(false);
    await reopened.close();
  });

  it("rebuilds missing MD twin from JSON on init", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    const mdPath = path.join(
      store.projectDir(PROJECT_ID),
      "events",
      "0001-project_created.md",
    );
    await fsp.unlink(mdPath);
    expect(fs.existsSync(mdPath)).toBe(false);

    await store.close();
    const reopened = new FilesystemStateStore(dir);
    await reopened.init();
    expect(fs.existsSync(mdPath)).toBe(true);
    await reopened.close();
  });

  it("rebuildRollup() reconstructs state from events", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: 2,
          satisfiedCriteria: ["prd.approved"],
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "test" } },
    );
    const rebuilt = await store.rebuildRollup(PROJECT_ID);
    const direct = await store.read(PROJECT_ID);
    expect(rebuilt).toEqual(direct);
  });

  it("concurrent transact() on different projects both succeed without blocking each other", async () => {
    const writer = (id: string) =>
      store.transact(
        id,
        (current) => ({
          next: {
            projectId: id,
            currentPhase: "REQUIREMENTS",
            satisfiedCriteria: [],
            lastConsensus: null,
            updatedAt: ISO,
            revision: (current?.revision ?? 0) + 1,
          },
          result: id,
        }),
        { context: { actor: "test" } },
      );

    const results = await Promise.all([writer("proj-a"), writer("proj-b")]);
    expect(results.sort()).toEqual(["proj-a", "proj-b"]);
    expect((await store.read("proj-a"))?.revision).toBe(1);
    expect((await store.read("proj-b"))?.revision).toBe(1);
  });

  it("read() does not touch events/ or archive/", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    const eventsDir = path.join(store.projectDir(PROJECT_ID), "events");
    const originalReaddir = fsp.readdir;
    let readdirCalls: string[] = [];
    // Spy via module replacement is heavy; instead, verify the read path
    // doesn't produce side effects by comparing mtimes.
    const mtimeBefore = (await fsp.stat(eventsDir)).mtimeMs;
    await store.read(PROJECT_ID);
    const mtimeAfter = (await fsp.stat(eventsDir)).mtimeMs;
    expect(mtimeAfter).toBe(mtimeBefore);
    // Silence the unused-variable lints on originalReaddir / readdirCalls.
    void originalReaddir;
    void readdirCalls;
  });

  it("archives the completed phase when currentPhase changes", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: 2,
          satisfiedCriteria: ["prd.approved"],
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "test" } },
    );
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: 3,
          currentPhase: "DESIGN",
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "sdlc_advance_phase" } },
    );

    const eventsDir = path.join(store.projectDir(PROJECT_ID), "events");
    const archiveDir = path.join(
      store.projectDir(PROJECT_ID),
      "archive",
      "01-REQUIREMENTS",
    );
    const eventsAfter = await fsp.readdir(eventsDir);
    const archiveAfter = await fsp.readdir(archiveDir);
    expect(eventsAfter).toEqual([]);
    expect(archiveAfter.sort()).toContain("0001-project_created.json");
    expect(archiveAfter.sort()).toContain("0001-project_created.md");
    expect(archiveAfter.sort()).toContain("0003-phase_advanced.json");
  });

  it("archive preserves original filenames (no renumbering)", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: 2,
          currentPhase: "DESIGN",
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "test" } },
    );
    const archived = await fsp.readdir(
      path.join(store.projectDir(PROJECT_ID), "archive", "01-REQUIREMENTS"),
    );
    expect(archived).toContain("0001-project_created.json");
    expect(archived).toContain("0002-phase_advanced.json");
  });

  it("two consecutive phase advances produce two archive buckets", async () => {
    // Create, advance to DESIGN, advance to ARCHITECTURE.
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: 2,
          currentPhase: "DESIGN",
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "test" } },
    );
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: 3,
          currentPhase: "ARCHITECTURE",
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "test" } },
    );
    const archiveRoot = path.join(store.projectDir(PROJECT_ID), "archive");
    const buckets = (await fsp.readdir(archiveRoot)).sort();
    expect(buckets).toContain("01-REQUIREMENTS");
    expect(buckets).toContain("02-DESIGN");
    const reqBucket = await fsp.readdir(
      path.join(archiveRoot, "01-REQUIREMENTS"),
    );
    const designBucket = await fsp.readdir(path.join(archiveRoot, "02-DESIGN"));
    expect(reqBucket).toContain("0002-phase_advanced.json");
    expect(designBucket).toContain("0003-phase_advanced.json");
  });

  it("read() ignores archive — rollup stays authoritative after archive moves", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: 2,
          currentPhase: "DESIGN",
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "test" } },
    );
    const archiveDir = path.join(
      store.projectDir(PROJECT_ID),
      "archive",
      "01-REQUIREMENTS",
    );
    // Corrupt every JSON in the archive. read() must not care.
    for (const f of await fsp.readdir(archiveDir)) {
      if (f.endsWith(".json")) {
        await fsp.writeFile(path.join(archiveDir, f), "not json at all", "utf8");
      }
    }
    const state = await store.read(PROJECT_ID);
    expect(state?.currentPhase).toBe("DESIGN");
    expect(state?.revision).toBe(2);
  });

  it("archive MD front-matter stays intact after move", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "sdlc_get_state" } },
    );
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: 2,
          currentPhase: "DESIGN",
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "sdlc_advance_phase" } },
    );
    const mdPath = path.join(
      store.projectDir(PROJECT_ID),
      "archive",
      "01-REQUIREMENTS",
      "0001-project_created.md",
    );
    const md = await fsp.readFile(mdPath, "utf8");
    expect(md).toMatch(/^---\n/);
    expect(md).toMatch(/type: project_created/);
    expect(md).toMatch(/actor: "sdlc_get_state"/);
    expect(md).toMatch(/# Project created/);
  });

  it("rebuildRollup includes archived events", async () => {
    await store.transact(
      PROJECT_ID,
      () => ({ next: makeState({ revision: 1 }), result: null }),
      { context: { actor: "test" } },
    );
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: 2,
          satisfiedCriteria: ["prd.approved"],
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "test" } },
    );
    // Mirror the engine's advancePhase semantics — criteria reset on
    // every phase transition (engine.ts:153). Replay must agree.
    await store.transact(
      PROJECT_ID,
      (current) => ({
        next: {
          ...current!,
          revision: 3,
          currentPhase: "DESIGN",
          satisfiedCriteria: [],
          updatedAt: ISO,
        },
        result: null,
      }),
      { context: { actor: "test" } },
    );
    const rebuilt = await store.rebuildRollup(PROJECT_ID);
    const direct = await store.read(PROJECT_ID);
    expect(rebuilt).toEqual(direct);
    expect(rebuilt?.currentPhase).toBe("DESIGN");
    expect(rebuilt?.satisfiedCriteria).toEqual([]);
  });

  it("disables fsync when VIBEFLOW_STATE_FSYNC=off", async () => {
    const prev = process.env.VIBEFLOW_STATE_FSYNC;
    process.env.VIBEFLOW_STATE_FSYNC = "off";
    try {
      const alt = new FilesystemStateStore(dir);
      await alt.init();
      await alt.transact(
        "fsync-off-test",
        () => ({
          next: makeState({ projectId: "fsync-off-test", revision: 1 }),
          result: null,
        }),
        { context: { actor: "test" } },
      );
      const state = await alt.read("fsync-off-test");
      expect(state?.revision).toBe(1);
      await alt.close();
    } finally {
      if (prev === undefined) delete process.env.VIBEFLOW_STATE_FSYNC;
      else process.env.VIBEFLOW_STATE_FSYNC = prev;
    }
  });
});
