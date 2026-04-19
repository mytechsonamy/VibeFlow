import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fsp from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { FilesystemStateStore } from "../src/state/filesystem.js";
import type { ProjectState } from "../src/state/store.js";

const PROJECT_ID = "race-proj";
const ISO = "2026-04-20T00:00:00.000Z";

function bootstrap(): ProjectState {
  return {
    projectId: PROJECT_ID,
    currentPhase: "REQUIREMENTS",
    satisfiedCriteria: [],
    lastConsensus: null,
    updatedAt: ISO,
    revision: 1,
  };
}

describe("FilesystemStateStore — concurrency parity (Bug #6 regression)", () => {
  let dir: string;
  let store: FilesystemStateStore;

  beforeEach(async () => {
    dir = await fsp.mkdtemp(path.join(os.tmpdir(), "vf-race-"));
    store = new FilesystemStateStore(dir);
    await store.init();
    await store.transact(
      PROJECT_ID,
      () => ({ next: bootstrap(), result: null }),
      { context: { actor: "test" } },
    );
  });

  afterEach(async () => {
    await store.close();
    await fsp.rm(dir, { recursive: true, force: true });
  });

  it("50 concurrent satisfyCriterion writes end at revision 51 with all criteria persisted", async () => {
    const writers = Array.from({ length: 50 }, (_, i) =>
      store.transact(
        PROJECT_ID,
        (current) => {
          const criterion = `criterion-${i}`;
          return {
            next: {
              ...current!,
              revision: current!.revision + 1,
              satisfiedCriteria: [...current!.satisfiedCriteria, criterion],
              updatedAt: ISO,
            },
            result: criterion,
          };
        },
        { context: { actor: "test" } },
      ),
    );
    const criteria = await Promise.all(writers);
    const final = await store.read(PROJECT_ID);
    expect(final?.revision).toBe(51);
    expect(final?.satisfiedCriteria.length).toBe(50);
    expect(new Set(final?.satisfiedCriteria)).toEqual(new Set(criteria));
  });

  it("20 concurrent writes produce revisions 2..21 with no gaps", async () => {
    const writers = Array.from({ length: 20 }, (_, i) =>
      store.transact(
        PROJECT_ID,
        (current) => ({
          next: {
            ...current!,
            revision: current!.revision + 1,
            satisfiedCriteria: [
              ...current!.satisfiedCriteria,
              `c-${i}`,
            ],
            updatedAt: ISO,
          },
          result: current!.revision + 1,
        }),
        { context: { actor: "test" } },
      ),
    );
    const revisions = (await Promise.all(writers)).sort((a, b) => a - b);
    expect(revisions).toEqual(
      Array.from({ length: 20 }, (_, i) => i + 2),
    );
  });

  it("transact() rollback on mutator error leaves revision unchanged", async () => {
    const startRevision = (await store.read(PROJECT_ID))!.revision;
    await expect(
      store.transact(
        PROJECT_ID,
        () => {
          throw new Error("intentional");
        },
        { context: { actor: "test" } },
      ),
    ).rejects.toThrowError(/intentional/);
    const end = (await store.read(PROJECT_ID))!.revision;
    expect(end).toBe(startRevision);
  });
});

describe("FilesystemStateStore — cross-process file lock", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await fsp.mkdtemp(path.join(os.tmpdir(), "vf-xproc-"));
    const store = new FilesystemStateStore(dir);
    await store.init();
    await store.transact(
      PROJECT_ID,
      () => ({ next: bootstrap(), result: null }),
      { context: { actor: "test" } },
    );
    await store.close();
  });

  afterEach(async () => {
    await fsp.rm(dir, { recursive: true, force: true });
  });

  it("5 subprocesses writing 5 criteria each produce 25 criteria with revisions 2..26", async () => {
    const workerSource = buildWorkerSource();
    const workerPath = path.join(dir, "worker.mjs");
    await fsp.writeFile(workerPath, workerSource, "utf8");

    const numProcs = 5;
    const writesPerProc = 5;
    const procs = Array.from({ length: numProcs }, (_, idx) =>
      runWorker(workerPath, dir, PROJECT_ID, idx, writesPerProc),
    );
    const exitCodes = await Promise.all(procs);
    expect(exitCodes.every((c) => c === 0)).toBe(true);

    const store = new FilesystemStateStore(dir);
    await store.init();
    const state = await store.read(PROJECT_ID);
    expect(state?.revision).toBe(1 + numProcs * writesPerProc);
    expect(state?.satisfiedCriteria.length).toBe(numProcs * writesPerProc);
    await store.close();
  }, 30_000);
});

function runWorker(
  workerPath: string,
  baseDir: string,
  projectId: string,
  procId: number,
  writes: number,
): Promise<number> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "node",
      [workerPath, baseDir, projectId, String(procId), String(writes)],
      {
        stdio: ["ignore", "pipe", "pipe"],
      },
    );
    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += String(chunk);
    });
    child.on("close", (code) => {
      if (code === 0) resolve(0);
      else reject(new Error(`worker ${procId} exited ${code}: ${stderr}`));
    });
    child.on("error", reject);
  });
}

function buildWorkerSource(): string {
  const here = fileURLToPath(import.meta.url);
  const root = path.resolve(path.dirname(here), "..");
  const fsModule = path
    .join(root, "dist", "state", "filesystem.js")
    .replace(/\\/g, "/");
  return `
import { FilesystemStateStore } from ${JSON.stringify(fsModule)};

const [, , baseDir, projectId, procIdStr, writesStr] = process.argv;
const procId = Number(procIdStr);
const writes = Number(writesStr);

const store = new FilesystemStateStore(baseDir);
await store.init();

for (let i = 0; i < writes; i++) {
  const criterion = \`proc-\${procId}-\${i}\`;
  await store.transact(
    projectId,
    (current) => ({
      next: {
        ...current,
        revision: current.revision + 1,
        satisfiedCriteria: [...current.satisfiedCriteria, criterion],
        updatedAt: new Date().toISOString(),
      },
      result: null,
    }),
    { context: { actor: "race-worker" } },
  );
}

await store.close();
process.exit(0);
`.trimStart();
}
