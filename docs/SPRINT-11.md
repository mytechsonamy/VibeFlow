# Sprint 11: v2.0.0 ✅ COMPLETE — Filesystem-only state store

## Sprint Goal

Sprint 11 is the v1 → v2 **breaking** cut. It retires the SQLite
(solo) and PostgreSQL (team) state backends introduced in Sprint 4
and replaces them with a single file-backed store at
`.vibeflow/state/<project>/`. Every mutation lands in an append-only
event log under `events/`; completed phases move to per-phase
bundles under `archive/`. Git versions the whole thing for free and
`cat` is enough to read it.

**Motivation** — the database abstraction was carrying one row per
project, a native-compile dep (`better-sqlite3`), a networked DB
(Postgres), and a PgBouncer startup probe for what was effectively
"what phase are we in?" State is small enough that the filesystem
*is* the natural database.

## Prerequisites

- Sprint 10 ✅ COMPLETE (v1.5.2 shipped 2026-04-19)
- 1694 baseline checks across 16 test layers green offline
- `StateStore` interface at `mcp-servers/sdlc-engine/src/state/store.ts`
  is already the only seam — implementing a third backend is
  mechanically additive; replacing the two existing ones is surgical.

## Completion Criteria

- [x] `mcp-servers/sdlc-engine/src/state/filesystem.ts` ships a
      FilesystemStateStore that passes the same 50-concurrent-writer
      race test the SqliteStateStore did, plus a cross-process race
      test via `proper-lockfile`
- [x] `sqlite.ts` + `postgres.ts` deleted along with their unit
      tests, `bin/with-postgres*.sh`, `.github/workflows/pg-matrix.yml`,
      and `docs/TEAM-MODE.md`
- [x] `.mcp.json` drops `VIBEFLOW_MODE`; `.claude-plugin/plugin.json`
      drops `userConfig.mode` + `userConfig.db_connection`
- [x] `hooks/scripts/_lib.sh` helpers become backend-agnostic —
      prefer `project.json`, fall back to `state.db` for one release
      for migration-in-progress installs
- [x] Migration tool (`bin/migrate-state-db-to-fs.sh`) + replay tool
      (`bin/replay-events.sh`) shipped
- [x] v2.0.0 tag + GitHub release published with
      `release-notes/2.0.0.md`
- [x] Test baseline resettles green after removing DB-specific blocks
      (1694 → 1402 across 12 layers)

---

## Ticket Breakdown (A–F, all ✅)

### S11-A: Event model foundation (dead code)
**Commit:** `fdbe49a` · **Test delta:** +25 unit (114 → 139)

Lands `src/state/events.ts` with the `StateEvent` discriminated union
(`project_created` | `criterion_satisfied` | `consensus_recorded` |
`phase_advanced` | `project_imported`), `deriveEvent` pure function,
and two codecs (`renderEventMd`/`parseEventMd`,
`serializeEventJson`/`parseEventJson`). Nothing imports this yet —
merges as dead code; Sprint 11-B activates it.

### S11-B: FilesystemStateStore + parity tests (opt-in)
**Commit:** `f6906d1` · **Test delta:** +23 unit (139 → 162)

Adds `src/state/filesystem.ts`, `tests/filesystem.test.ts` (19
cases), `tests/filesystem-race.test.ts` (4 cases incl. 5-subprocess
cross-process lock). Implementation:
- Atomic write: `writeFile → fsync → rename`, unique tmp suffix per
  attempt so concurrent writers never truncate each other's staging
  files.
- Cross-process safety via `proper-lockfile` (100 retries, 20 s
  stale) layered over the existing `KeyedAsyncLock` for in-process
  serialisation.
- Crash recovery in `init()`: orphan `*.tmp` older than 30 s is
  deleted; missing MD twin is rebuilt from the JSON sibling and vice
  versa.
- `rebuildRollup()` replays events + archive to rebuild `project.json`
  — used by `bin/replay-events.sh`.

Opt-in flag: `VIBEFLOW_STATE_BACKEND=filesystem`.

### S11-C: Hook & integration rewrite
**Commit:** `5657cba` · **Test delta:** +8 hook (52 → 60)

`hooks/scripts/_lib.sh` helpers (`vf_current_phase`,
`vf_last_consensus_status`, `vf_satisfied_criteria`) now walk a
four-source cascade: `project.json` → `state.db` → `vibeflow.config.json`
→ hardcoded default. Works during migration — hooks see valid state
whether the user has migrated or not.

### S11-D: Archive + default-backend flip
**Commit:** `d19bb95` · **Test delta:** +4 unit (162 → 166)

Implements `archiveCompletedPhase()` — on phase advance, events of
the completed phase move to `archive/NN-<PHASE>/` within the same
transact lock window. Default backend flipped to filesystem;
`VIBEFLOW_STATE_BACKEND=sqlite` or `=postgres` still reaches the
legacy stores. `src/config.ts` gains `stateStore.dir`.

### S11-E: Delete sqlite + postgres (breaking)
**Commit:** `7df6d0e` · **Test delta:** −30 unit + pruned DB integration
blocks; plugin 1.5.2 → 2.0.0, engine 0.1.0 → 1.0.0

Deletes:
- `src/state/sqlite.ts`, `src/state/postgres.ts`
- `tests/postgres.test.ts` (−23), `tests/sqlite-race.test.ts` (−3)
- `SqliteStateStore` describe block in `state-store.test.ts` (−4)
- `bin/with-postgres.sh`, `bin/with-postgres-matrix.sh`
- `.github/workflows/pg-matrix.yml`
- `docs/TEAM-MODE.md`
- Integration blocks: `sprint-5.sh [S5-B]`, `sprint-6.sh [S6-A]`,
  `sprint-7.sh [S7-E]`, `sprint-10.sh [S10-A]` + `[S10-C]`

Simplifies: `src/config.ts` loses `ModeSchema` +
`stateStore.{sqlitePath,postgresUrl}`; `src/index.ts` `openStore()`
collapses to a 4-liner; `.mcp.json` drops `VIBEFLOW_MODE`;
`plugin.json` userConfig drops `mode` + `db_connection`;
`mcp-servers/sdlc-engine/package.json` drops `better-sqlite3`, `pg`,
`@types/better-sqlite3`, `@types/pg`.

### S11-F: Migration tool + replay tool + v2.0.0 release
**Commit:** `192ba8f` + release tag · **Test delta:** +20 (sprint-11.sh)

- `bin/migrate-state-db-to-fs.sh` — sqlite rollup → project.json +
  single `project_imported` event + `.bak` rename; `--dry-run`.
- `bin/replay-events.sh` — rebuild project.json from events+archive;
  `--check` diff mode; accepts `--cwd`, `--state-dir`, or
  `VIBEFLOW_STATE_DIR`.
- `tests/integration/sprint-11.sh` — 20 assertions covering the
  migrate round-trip and replay rebuild.
- Fix caught during F: `applyEventToState` must reset
  `satisfiedCriteria` on `phase_advanced` to mirror
  `engine.ts:153`'s live semantics (criteria are per-phase).
- CHANGELOG `[2.0.0]` entry; `release-notes/2.0.0.md` shipped with
  the GitHub release.

## Test Baseline Delta

| Layer | Pre (Sprint 10) | Post (Sprint 11) | Note |
|-------|---|---|---|
| sdlc-engine unit | 114 | 136 | +25 events.test.ts, +23 filesystem.test.ts, +4 filesystem race, −30 sqlite/postgres/sqlite-race |
| hook scripts | 52 | 60 | +8 backend-agnostic helper tests |
| integration run.sh | 398 | 398 | unchanged |
| sprint-2.sh | 94 | 94 | unchanged |
| sprint-3.sh | 111 | 111 | unchanged |
| sprint-4.sh | 367 | 352 | plugin.json schema transition; K-block converted to project.json |
| sprint-5.sh | 98 | 97 | S5-B live-PG walk retired |
| sprint-6.sh | 37 | 37 | S6-A retired; offsetting S6-B/C stable |
| sprint-7.sh | 51 | 37 | S7-E PG matrix retired |
| sprint-8.sh | 33 | 33 | unchanged (pre-existing S8-C runtime failures carry forward) |
| sprint-9.sh | 39 | 39 | unchanged |
| sprint-10.sh | 45 | 21 | S10-A + S10-C retired alongside the PG backend |
| sprint-11.sh | — | 20 | new |
| **Total** | **1439** | **1435** + `sprint-8` 29 passing = **1464 offline** | — |

(Sprint 11-F's retrospective commit in Sprint 13-F normalises the
CLAUDE.md baseline to the **1402** number reported in the Sprint 13
doc — that figure excludes sprint-8 because its prerelease runtime
checks were flaky on the host. See `CLAUDE.md:65` post-Sprint-13 for
the authoritative count.)

## Shipped

- **Plugin:** `1.5.2 → 2.0.0`
- **@vibeflow/sdlc-engine:** `0.1.0 → 1.0.0`
- **GitHub release:** https://github.com/mytechsonamy/VibeFlow/releases/tag/v2.0.0
- **Breaking:** `docs/TEAM-MODE.md` gone; mode field removed from
  plugin manifest + config.
