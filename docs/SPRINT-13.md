# Sprint 13: v2.1.0 ✅ COMPLETE — Generic phase enforcement

## Sprint Goal

Sprint 13 generalises `commit-guard.sh` to every file-producing tool
call. Before this sprint the only hard phase gate was at
`git commit` time — `Write` and `Edit` tool calls were unrestricted,
so a skill could silently produce code in the wrong SDLC phase.
Concretely, `/vibeflow:init` in REQUIREMENTS was scaffolding test
projects (`src/`, `.cs` files, `dotnet sln add`) even though
REQUIREMENTS is supposed to be analysis-only.

Sprint 13 ships a `phase-write-guard.sh` hook that reads
`hooks/scripts/phase-policy.json` and rejects any Write/Edit call
that targets a path outside the current phase's allow list. Five
high-risk skills also grow "Phase Contract" sections so they refuse
to run outside their allowed phases even before reaching for a
write. Escape hatch: per-call `VF_ALLOW_PHASE_WRITE=1`.

**Motivation** — a user observed VibeFlow skip phase boundaries
during a live FlowBridge_TR session, asked whether the framework
"shouldn't have prevented this", and the honest answer was "yes —
the gating was always intended to cover writes, not just commits."

## Prerequisites

- Sprint 12 ✅ COMPLETE (v2.0.2 shipped 2026-04-20)
- 1402 baseline checks across 12 test layers green
- `hooks/scripts/_lib.sh` backend-agnostic helpers (Sprint 11-C)
  still wired — the new guard reuses `vf_current_phase` + `vf_cwd`
- `python3` on PATH (used for glob matching in the guard)

## Completion Criteria

- [x] `hooks/scripts/phase-policy.json` covers all seven phases
      with `allow` + `warn` glob arrays; `.vibeflow/**` +
      `vibeflow.config.json` always writable
- [x] `hooks/scripts/phase-write-guard.sh` installed as
      PreToolUse/`Write|Edit` hook in `hooks/hooks.json`
- [x] `skills/init/SKILL.md` fixed — no more `codebase-explorer`
      invocation, no more stale `mode: solo/team` prompt, Phase
      Contract at the top
- [x] Four other high-risk skills carry Phase Contracts
      (component-test-writer, release-decision-engine,
      test-strategy-planner, coverage-analyzer)
- [x] `skills/phase-policy.json` advisory registry ships for all
      31 skills
- [x] `docs/PHASE-BOUNDARIES.md` user-facing reference lands
- [x] `docs/SPRINT-11.md` + `docs/SPRINT-12.md` retrospective
      docs filled (user observed they were missing)
- [x] `tests/integration/sprint-13.sh` harness added
- [x] `CLAUDE.md` baseline bumped
- [x] v2.1.0 tag + GitHub release shipped

---

## Ticket Breakdown (A–F, all ✅)

### S13-A: Policy registry + hook scaffold (dead code)
Lands `hooks/scripts/phase-policy.json` (path policy for the hook)
and `skills/phase-policy.json` (advisory skill→phases mapping). The
guard script exists but is not yet wired; it always allows.

### S13-B: Guard implementation + hook tests
`hooks/scripts/_lib.sh` gains four helpers:
- `vf_policy_path()` → path to the hook policy JSON.
- `vf_relpath(abs)` → strips `$(vf_cwd)` prefix so policy globs
  match against repo-relative paths.
- `vf_phase_decision(phase, rel, policy)` → prints `allow` / `warn` /
  `block` after parsing the policy JSON and glob-matching both the
  allow and warn lists via a single `python3` invocation.

Glob semantics: `**/` → `(?:.*/)?`, `/**` → `(?:/.*)?`, `**` →
`.*`, `*` → `[^/]*`, `?` → `[^/]`. Literal chars escape regex
metas. Same shape as gitignore.

`hooks/tests/run.sh` `[S13-A]` section: 15 assertions covering
REQUIREMENTS block (`.ts` denied, `docs/`, `.vibeflow/`, config
allowed), DESIGN parity, DEVELOPMENT full-allow, TESTING warn-only
on `src/` non-test, escape hatch, missing-policy fail-safe.

### S13-C: Wire hook into hooks.json (flag flip)
Third PreToolUse entry next to commit-guard + test-optimizer.
`matcher: "Write|Edit"`, no `if:` predicate — the script itself
filters by `file_path`.

Regression check: hook 75/75, integration run.sh 398/398, sprint
harnesses unchanged.

### S13-D: init skill fix + Phase Contracts
`skills/init/SKILL.md` rewritten:
- Step 1 no longer asks about `mode`.
- Step 2 config template no longer carries a `"mode"` field.
- Step 4 ("Detect Existing Codebase") now explicitly:
  - Produces exactly one file: `.vibeflow/reports/codebase-fingerprint.md`
  - Forbids writes outside `.vibeflow/` / `vibeflow.config.json`
  - Forbids test scaffolding, `mkdir src/`, `dotnet sln add`,
    `git add` / `git commit`
- Step 5 closes with `"Now run /vibeflow:prd-quality-analyzer"`.
- New Phase Contract section (REQUIREMENTS only) at the top of the
  skill body.

Phase Contract boilerplate added to four other skills:
component-test-writer, release-decision-engine,
test-strategy-planner, coverage-analyzer. Each reads
`vibeflow.config.json.currentPhase`, compares to the allowed list,
and stops with a named error if mismatched.

### S13-E: Integration harness + user docs
`tests/integration/sprint-13.sh` — ~50 assertions across seven
sections (`[S13-A]` policy structure, `[S13-B]` guard surface,
`[S13-C]` hooks.json wire, `[S13-D]` init regression + four Phase
Contracts + registry coverage, `[S13-E]` PHASE-BOUNDARIES.md,
`[S13-F]` retrospective-doc presence sentinel, `[S13-Z]` self-audit).

`docs/PHASE-BOUNDARIES.md` — allow/warn/deny table per phase, block
message walkthrough, escape hatches, skill self-check explainer,
troubleshooting section.

### S13-F: Retrospective docs + v2.1.0 release
- `docs/SPRINT-11.md` (back-filled retrospective for v2.0.0)
- `docs/SPRINT-12.md` (back-filled retrospective for v2.0.1 + v2.0.2)
- `docs/SPRINT-13.md` (this doc)
- `CLAUDE.md` — test-layer count 12 → 13, baseline bumped to 1486,
  sprint-13.sh entry added
- `release-notes/2.1.0.md` published with the v2.1.0 GitHub release
- Version bumps: plugin `2.0.2 → 2.1.0`, engine `1.0.1 → 1.1.0`,
  marketplace entry version synced, `sprint-4.sh`
  `EXPECTED_PLUGIN_VERSION` synced
- `vibeflow-plugin-2.1.0.tar.gz` regenerated + attached to release

## Test Baseline Delta

| Layer | Pre (post-Sprint-12) | Post (Sprint 13) | Note |
|-------|---|---|---|
| sdlc-engine unit | 136 | 136 | unchanged |
| hook scripts | 60 | 75 | +15 `[S13-A]` assertions |
| integration run.sh | 398 | 398 | unchanged |
| sprint-2..11.sh (combined) | 808 | 808 | unchanged |
| sprint-13.sh | — | ~55 | new |
| **Total** | **1402** | **~1472** | net +70 |

## Risks & Mitigations

1. **Hook latency.** `python3` + file read per Write/Edit ≈ 5 ms.
   Negligible for a short policy file (<1 KB). If it becomes a
   bottleneck, Sprint 14 can cache the parsed policy in
   `$TMPDIR/vf-policy-cache`.
2. **False positives.** `.vibeflow/**` + `vibeflow.config.json`
   explicit allows in every phase stop the framework from
   self-blocking. Integration `[S13-A]` pins this.
3. **Escape hatch abuse.** `VF_ALLOW_PHASE_WRITE=1` is documented as
   per-call only. Sprint 14 may add a SessionStart warning if the
   env var is exported.
4. **Policy/python missing.** Guard fails safe to allow — framework
   never bricks a user's install. Integration assertions catch
   missing-file regressions in CI.

## Shipped

- **Plugin:** `2.0.2 → 2.1.0`
- **@vibeflow/sdlc-engine:** `1.0.1 → 1.1.0`
- **GitHub release:** v2.1.0 with `release-notes/2.1.0.md` and
  `vibeflow-plugin-2.1.0.tar.gz`
