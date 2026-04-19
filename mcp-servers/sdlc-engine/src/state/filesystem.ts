import * as fs from "node:fs";
import * as fsp from "node:fs/promises";
import * as path from "node:path";
import lockfile from "proper-lockfile";
import {
  KeyedAsyncLock,
  StateStore,
  StateMutator,
  ProjectState,
  assertRevisionIncrement,
} from "./store.js";
import {
  EVENT_SCHEMA_VERSION,
  MutatorContext,
  StateEvent,
  deriveEvent,
  eventFileStem,
  parseEventJson,
  parseEventMd,
  renderEventMd,
  serializeEventJson,
} from "./events.js";

const ROLLUP_SCHEMA_VERSION = 1 as const;
const TMP_ORPHAN_GRACE_MS = 30_000;

interface RollupFile extends ProjectState {
  schemaVersion: typeof ROLLUP_SCHEMA_VERSION;
}

export interface TransactOptions {
  /** Pass to `deriveEvent` for richer event metadata. */
  context?: Omit<MutatorContext, "actor"> & { actor?: string };
}

/**
 * File-system backed state store. Layout per project:
 *
 *   <stateDir>/<projectId>/
 *     project.json                   rollup (authoritative read target)
 *     project.json.lock              proper-lockfile sidecar
 *     events/NNNN-<type>.json        append-only audit log
 *     events/NNNN-<type>.md          human-readable twin
 *     archive/NN-<PHASE>/            moved once a phase completes
 *
 * Concurrency model:
 *   - `KeyedAsyncLock` (reused from store.ts) serialises transact() calls
 *     in the same process.
 *   - `proper-lockfile` serialises transact() calls across processes.
 *   - Every write goes through a temp file + atomic rename to avoid
 *     torn writes. fsyncDir is called on the parent directory so Linux
 *     ext4 durability holds under crash.
 */
export class FilesystemStateStore implements StateStore {
  private readonly baseDir: string;
  private readonly keyedLock = new KeyedAsyncLock();
  private readonly fsyncEnabled: boolean;
  private readonly tmpGraceMs: number;
  private initialized = false;

  constructor(
    baseDir: string,
    options: { fsync?: boolean; tmpGraceMs?: number } = {},
  ) {
    this.baseDir = path.resolve(baseDir);
    this.fsyncEnabled = options.fsync ?? fsyncEnabledFromEnv();
    this.tmpGraceMs = options.tmpGraceMs ?? TMP_ORPHAN_GRACE_MS;
  }

  async init(): Promise<void> {
    if (this.initialized) return;
    await fsp.mkdir(this.baseDir, { recursive: true });
    await this.sweepCrashRecovery();
    this.initialized = true;
  }

  async read(projectId: string): Promise<ProjectState | null> {
    validateProjectId(projectId);
    const rollupPath = this.rollupPath(projectId);
    try {
      const raw = await fsp.readFile(rollupPath, "utf8");
      const parsed = JSON.parse(raw) as RollupFile;
      if (parsed.schemaVersion !== ROLLUP_SCHEMA_VERSION) {
        throw new Error(
          `Rollup schemaVersion ${parsed.schemaVersion} not supported ` +
            `(expected ${ROLLUP_SCHEMA_VERSION}) at ${rollupPath}`,
        );
      }
      const { schemaVersion: _sv, ...state } = parsed;
      return state;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw err;
    }
  }

  async transact<T>(
    projectId: string,
    mutator: StateMutator<T>,
    options: TransactOptions = {},
  ): Promise<T> {
    validateProjectId(projectId);
    return this.keyedLock.acquire(projectId, async () => {
      await this.ensureProjectDirs(projectId);
      const release = await this.acquireFileLock(projectId);
      try {
        const current = await this.read(projectId);
        const { next, result } = mutator(current);
        assertRevisionIncrement(current, next, projectId);

        const ctx: MutatorContext = {
          actor: options.context?.actor ?? "unknown",
          recordedAt: options.context?.recordedAt ?? next.updatedAt,
          force: options.context?.force,
        };
        const event = deriveEvent(current, next, ctx);

        await this.writeEvent(projectId, event);
        await this.writeRollup(projectId, next);
        await this.fsyncDir(this.projectDir(projectId));

        // Archive the completed phase. The archive step lives inside the
        // lock window on purpose — a later transact() might enqueue more
        // events for the (new) phase and we must not mix them into the
        // archive bucket of the phase we just left.
        if (current && current.currentPhase !== next.currentPhase) {
          await this.archiveCompletedPhase(
            projectId,
            current.currentPhase,
            current.revision,
          );
        }

        return result;
      } finally {
        try {
          await release();
        } catch {
          // Best-effort release — the next transact() will re-acquire.
        }
      }
    });
  }

  async close(): Promise<void> {
    // proper-lockfile instances are released per-call; nothing process-wide
    // to close. Flush in-process queue by acquiring a no-op lock on the
    // empty string (which is never a valid projectId) — skipped because
    // the keyedLock auto-drains when the last waiter resolves.
  }

  /** Reconstruct rollup from event log. Used by bin/replay-events.sh. */
  async rebuildRollup(projectId: string): Promise<ProjectState | null> {
    validateProjectId(projectId);
    const events = await this.loadAllEvents(projectId);
    if (events.length === 0) return null;
    let state: ProjectState | null = null;
    for (const event of events) {
      state = applyEventToState(state, event);
    }
    return state;
  }

  // ---------- internals ----------

  projectDir(projectId: string): string {
    return path.join(this.baseDir, projectId);
  }

  private eventsDir(projectId: string): string {
    return path.join(this.projectDir(projectId), "events");
  }

  private archiveDir(projectId: string): string {
    return path.join(this.projectDir(projectId), "archive");
  }

  private rollupPath(projectId: string): string {
    return path.join(this.projectDir(projectId), "project.json");
  }

  private lockPath(projectId: string): string {
    return path.join(this.projectDir(projectId), "project.json.lock");
  }

  private async ensureProjectDirs(projectId: string): Promise<void> {
    await fsp.mkdir(this.projectDir(projectId), { recursive: true });
    await fsp.mkdir(this.eventsDir(projectId), { recursive: true });
    await fsp.mkdir(this.archiveDir(projectId), { recursive: true });
    // proper-lockfile treats the given path as a target and creates a
    // sibling `<path>.lock/` directory as the cross-process sentinel.
    // Our target is a sentinel file we own; it's created once and never
    // rewritten.  proper-lockfile will only create `<target>.lock/`
    // alongside it.
    const lockTarget = this.lockPath(projectId);
    if (!fs.existsSync(lockTarget)) {
      await fsp.writeFile(lockTarget, "");
    }
  }

  private async acquireFileLock(projectId: string): Promise<() => Promise<void>> {
    const lockTarget = this.lockPath(projectId);
    return lockfile.lock(lockTarget, {
      retries: {
        retries: 100,
        factor: 1.2,
        minTimeout: 50,
        maxTimeout: 1000,
        randomize: true,
      },
      stale: 20000,
      realpath: false,
    });
  }

  private async writeEvent(
    projectId: string,
    event: StateEvent,
  ): Promise<void> {
    const stem = eventFileStem(event);
    const jsonPath = path.join(this.eventsDir(projectId), `${stem}.json`);
    const mdPath = path.join(this.eventsDir(projectId), `${stem}.md`);
    await this.writeAtomic(jsonPath, serializeEventJson(event));
    await this.writeAtomic(mdPath, renderEventMd(event));
  }

  private async writeRollup(
    projectId: string,
    state: ProjectState,
  ): Promise<void> {
    const rollup: RollupFile = { ...state, schemaVersion: ROLLUP_SCHEMA_VERSION };
    const body = JSON.stringify(rollup, null, 2) + "\n";
    await this.writeAtomic(this.rollupPath(projectId), body);
  }

  private async writeAtomic(
    finalPath: string,
    body: string,
  ): Promise<void> {
    // Use a unique tmp suffix per attempt so two racing processes (both
    // legitimately holding the file lock on different schedulers, or a
    // slow fsync that overlaps with the next writer) never truncate each
    // other's in-flight tmp file. Once rename succeeds, the tmp vanishes
    // and the crash-recovery sweep treats any leftover `*.tmp` as orphan.
    const tmpPath = `${finalPath}.${process.pid}-${randomSuffix()}.tmp`;
    const handle = await fsp.open(tmpPath, "wx");
    try {
      await handle.writeFile(body);
      if (this.fsyncEnabled) {
        await handle.sync();
      }
    } finally {
      await handle.close();
    }
    await fsp.rename(tmpPath, finalPath);
  }

  private async fsyncDir(dirPath: string): Promise<void> {
    if (!this.fsyncEnabled) return;
    // Windows fsync on directories throws EPERM/EACCES. Skip there; on
    // POSIX we want the parent directory entry durable.
    if (process.platform === "win32") return;
    let fd: number | null = null;
    try {
      fd = fs.openSync(dirPath, fs.constants.O_RDONLY);
      fs.fsyncSync(fd);
    } catch {
      // Some FSs disallow directory fsync (FAT32). Non-fatal.
    } finally {
      if (fd !== null) fs.closeSync(fd);
    }
  }

  private async archiveCompletedPhase(
    projectId: string,
    phase: string,
    _lastRevision: number,
  ): Promise<void> {
    const archiveBucket = path.join(
      this.archiveDir(projectId),
      `${bucketForPhase(phase)}-${phase}`,
    );
    await fsp.mkdir(archiveBucket, { recursive: true });
    const eventsDir = this.eventsDir(projectId);
    const entries = await fsp.readdir(eventsDir);
    // Pass 1: inspect every JSON, collect stems whose event belongs to the
    // completed phase. The MD twin is moved with the JSON in pass 2 so we
    // never miss it just because its sibling has already been renamed.
    const stemsToArchive = new Set<string>();
    for (const entry of entries) {
      if (!entry.endsWith(".json")) continue;
      const jsonPath = path.join(eventsDir, entry);
      if (await eventJsonMatchesPhase(jsonPath, phase)) {
        stemsToArchive.add(entry.replace(/\.json$/, ""));
      }
    }
    // Pass 2: move JSON + MD pairs. MD twin may be absent on disk (e.g.
    // mid-crash state); if so, only the JSON moves and the init sweep
    // will rebuild the missing MD inside the archive bucket next boot.
    for (const stem of stemsToArchive) {
      for (const ext of [".json", ".md"]) {
        const src = path.join(eventsDir, `${stem}${ext}`);
        if (!fs.existsSync(src)) continue;
        await fsp.rename(src, path.join(archiveBucket, `${stem}${ext}`));
      }
    }
    await this.fsyncDir(archiveBucket);
    await this.fsyncDir(eventsDir);
  }

  private async sweepCrashRecovery(): Promise<void> {
    let projects: string[];
    try {
      projects = await fsp.readdir(this.baseDir);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return;
      throw err;
    }
    for (const project of projects) {
      const pdir = path.join(this.baseDir, project);
      const stat = await fsp.stat(pdir).catch(() => null);
      if (!stat?.isDirectory()) continue;
      await this.cleanupTmpFiles(pdir);
      await this.rebuildMissingMdTwins(project);
    }
  }

  private async cleanupTmpFiles(dir: string): Promise<void> {
    // Only delete tmp files older than the grace period. Active tmps
    // from an in-flight writeAtomic() are sub-second; orphans from a
    // crashed previous run are minutes or hours old. A 30s cutoff keeps
    // concurrent start-ups from wiping each other's pending writes.
    const now = Date.now();
    const graceMs = this.tmpGraceMs;
    const walk = async (root: string): Promise<void> => {
      const entries = await fsp.readdir(root, { withFileTypes: true }).catch(
        () => [],
      );
      for (const entry of entries) {
        const full = path.join(root, entry.name);
        if (entry.isDirectory()) {
          await walk(full);
        } else if (entry.name.endsWith(".tmp")) {
          try {
            const stat = await fsp.stat(full);
            if (now - stat.mtimeMs >= graceMs) {
              await fsp.unlink(full).catch(() => undefined);
            }
          } catch {
            // stat failed (maybe unlinked by a sibling sweep) — no-op.
          }
        }
      }
    };
    await walk(dir);
  }

  private async rebuildMissingMdTwins(projectId: string): Promise<void> {
    const eventsDir = this.eventsDir(projectId);
    const entries = await fsp.readdir(eventsDir).catch(() => []);
    const jsonNames = new Set(entries.filter((e) => e.endsWith(".json")));
    const mdNames = new Set(entries.filter((e) => e.endsWith(".md")));
    for (const jsonName of jsonNames) {
      const mdTwin = jsonName.replace(/\.json$/, ".md");
      if (!mdNames.has(mdTwin)) {
        try {
          const jsonBody = await fsp.readFile(
            path.join(eventsDir, jsonName),
            "utf8",
          );
          const event = parseEventJson(jsonBody);
          await fsp.writeFile(
            path.join(eventsDir, mdTwin),
            renderEventMd(event),
          );
        } catch {
          // Skip unparseable; manual intervention needed.
        }
      }
    }
    for (const mdName of mdNames) {
      const jsonTwin = mdName.replace(/\.md$/, ".json");
      if (!jsonNames.has(jsonTwin)) {
        try {
          const mdBody = await fsp.readFile(
            path.join(eventsDir, mdName),
            "utf8",
          );
          const event = parseEventMd(mdBody);
          await fsp.writeFile(
            path.join(eventsDir, jsonTwin),
            serializeEventJson(event),
          );
        } catch {
          // Skip unparseable.
        }
      }
    }
  }

  private async loadAllEvents(projectId: string): Promise<StateEvent[]> {
    const events: StateEvent[] = [];
    const readDir = async (dir: string): Promise<void> => {
      let entries: string[];
      try {
        entries = await fsp.readdir(dir);
      } catch {
        return;
      }
      for (const entry of entries.sort()) {
        if (!entry.endsWith(".json")) continue;
        const full = path.join(dir, entry);
        try {
          const body = await fsp.readFile(full, "utf8");
          events.push(parseEventJson(body));
        } catch {
          // Skip unreadable.
        }
      }
    };
    await readDir(this.eventsDir(projectId));
    const archiveBuckets = await fsp
      .readdir(this.archiveDir(projectId))
      .catch(() => []);
    for (const bucket of archiveBuckets.sort()) {
      await readDir(path.join(this.archiveDir(projectId), bucket));
    }
    events.sort((a, b) => a.seq - b.seq);
    return events;
  }
}

const PHASE_ORDER: readonly string[] = [
  "REQUIREMENTS",
  "DESIGN",
  "ARCHITECTURE",
  "PLANNING",
  "DEVELOPMENT",
  "TESTING",
  "DEPLOYMENT",
];

function bucketForPhase(phase: string): string {
  const idx = PHASE_ORDER.indexOf(phase);
  const ordinal = idx >= 0 ? idx + 1 : PHASE_ORDER.length + 1;
  return String(ordinal).padStart(2, "0");
}

function randomSuffix(): string {
  return Math.random().toString(36).slice(2, 10);
}

function fsyncEnabledFromEnv(): boolean {
  const raw = process.env.VIBEFLOW_STATE_FSYNC;
  if (raw === undefined) return true;
  return !["0", "off", "false", "no"].includes(raw.toLowerCase());
}

function validateProjectId(projectId: string): void {
  if (!/^[a-z0-9_-]{1,64}$/i.test(projectId)) {
    throw new Error(
      `Invalid projectId "${projectId}": must match [a-zA-Z0-9_-]{1,64}`,
    );
  }
}

async function eventJsonMatchesPhase(
  jsonPath: string,
  phase: string,
): Promise<boolean> {
  try {
    const body = await fsp.readFile(jsonPath, "utf8");
    const event = parseEventJson(body);
    const eventPhase = phaseOf(event);
    return eventPhase === phase;
  } catch {
    return false;
  }
}

function phaseOf(event: StateEvent): string | null {
  switch (event.type) {
    case "project_created":
      return event.payload.firstPhase;
    case "criterion_satisfied":
      return event.payload.phase;
    case "consensus_recorded":
      return event.payload.consensus.phase;
    case "phase_advanced":
      // Phase_advanced events are logically part of the OUTGOING phase —
      // they describe leaving it. Keep them in the completed phase bucket.
      return event.payload.from;
    case "project_imported":
      return null;
  }
}

function applyEventToState(
  state: ProjectState | null,
  event: StateEvent,
): ProjectState {
  switch (event.type) {
    case "project_created":
      return {
        projectId: event.projectId,
        currentPhase: event.payload.firstPhase,
        satisfiedCriteria: [],
        lastConsensus: null,
        updatedAt: event.recordedAt,
        revision: event.revision,
      };
    case "criterion_satisfied": {
      if (!state) throw new Error("criterion_satisfied requires existing state");
      const criteria = event.payload.alreadyPresent
        ? state.satisfiedCriteria
        : [...state.satisfiedCriteria, event.payload.criterion];
      return {
        ...state,
        satisfiedCriteria: criteria,
        updatedAt: event.recordedAt,
        revision: event.revision,
      };
    }
    case "consensus_recorded":
      if (!state) throw new Error("consensus_recorded requires existing state");
      return {
        ...state,
        lastConsensus: event.payload.consensus,
        updatedAt: event.recordedAt,
        revision: event.revision,
      };
    case "phase_advanced":
      if (!state) throw new Error("phase_advanced requires existing state");
      return {
        ...state,
        currentPhase: event.payload.to,
        updatedAt: event.recordedAt,
        revision: event.revision,
      };
    case "project_imported":
      if (!state) {
        // imported as the first event — bootstrap with REQUIREMENTS.
        return {
          projectId: event.projectId,
          currentPhase: "REQUIREMENTS",
          satisfiedCriteria: [],
          lastConsensus: null,
          updatedAt: event.recordedAt,
          revision: event.revision,
        };
      }
      return { ...state, updatedAt: event.recordedAt, revision: event.revision };
  }
}

export const __testing__ = {
  EVENT_SCHEMA_VERSION,
  ROLLUP_SCHEMA_VERSION,
  bucketForPhase,
  applyEventToState,
};
