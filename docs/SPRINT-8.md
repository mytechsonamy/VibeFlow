# Sprint 8: v1.3 Scope TBD (Seeded)

## Sprint Goal

Sprint 8 targets **v1.3.0** — the next minor bump after v1.2. The
seeded backlog below picks up the one deferred ticket from Sprint 7
(S7-03 prerelease workflow) + the two lessons captured during the
v1.2.0 release cycle (Sprint 7 / S7-07). **Confirm scope with the
user before picking up any ticket.**

## Prerequisites

- Sprint 7 ✅ COMPLETE (v1.2.0 shipped 2026-04-16)
- 1565 baseline checks across 13 test layers held green
  (1581 with `VF_RUN_PG_MATRIX=1`)
- `bin/release.sh` now covers 7 steps + pg sanity check (S7-04)
  and produces byte-reproducible tarballs (S7-05B)

## Completion Criteria (DRAFT — confirm with user)

- [ ] Every ticket picked up for Sprint 8 has a stable `S8-*` id
- [ ] Sprint 8 integration harness present (`tests/integration/sprint-8.sh`)
- [ ] Baseline test count grows without regression
- [ ] At least one v1.3.0 release ships through `bin/release.sh`
- [ ] No unresolved Sprint 7 deferrals move into
      "forever-deferred" without an explicit decision

---

## Candidate Tickets (draft — confirm scope before starting)

### S8-01: Automated prerelease / beta-channel workflow
**Deferred from:** Sprint 7 / S7-03 (itself deferred from Sprint 6 / S6-06)
**Location:** `bin/release.sh` (new `--prerelease` mode) + `docs/RELEASING.md`

Sprint 5's `bin/release.sh` rejects prerelease SemVer suffixes
(`1.2.1-beta`) by design. S8-01 adds a dedicated prerelease path
with its own validation rules + the GitHub Releases
`prerelease: true` flag.

- [ ] `bin/release.sh <version>-<tag>.<n> --prerelease` accepts
      SemVer prerelease identifiers (e.g. `1.3.0-rc.1`,
      `1.3.0-beta.2`)
- [ ] Separate release track that does NOT update the
      `## [latest]` CHANGELOG pointer — the prerelease entry
      sits below the latest stable entry
- [ ] `gh release create` invocation adds `--prerelease` flag
- [ ] `docs/RELEASING.md` gains a "Prereleases" section covering
      when to cut one vs a normal release + promotion path
      (prerelease → stable when confident)
- [ ] Harness sentinel in `sprint-8.sh [S8-?]` with an opt-in
      runtime check (invoke `release.sh 1.3.0-rc.1 --prerelease
      --dry-run` and assert the expected dry-run output)

### S8-02: Fix sprint-7.sh [S7-C] multi-tarball save/restore bug ✅ DONE
**Captured during:** Sprint 7 / S7-07 (v1.2.0 release)
**Location:** `tests/integration/sprint-7.sh [S7-C]` rewrite + `tests/integration/sprint-8.sh [S8-A]` regression sentinel

The [S7-C] determinism runtime sentinel used to save only the FIRST pre-existing tarball via `ls vibeflow-plugin-*.tar.gz | head -1` and then delete ALL tarballs via `rm -f vibeflow-plugin-*.tar.gz`. When the harness ran with multiple version tarballs on disk — exactly what happens right after a fresh `release.sh <newer>` produces a new tarball alongside a stale older one — the new release artifact got clobbered and only the older one survived. This bit the v1.2.0 release during S7-07.

**Completed:**
- [x] **Save strategy rewritten** to a `for` loop that `mv`s every match into `$DETERMINISM_TMPDIR/saved/`. Both `.tar.gz` and `.tar.gz.sha256` patterns covered. `[[ -e "$f" ]]` guard handles the no-pre-existing-tarball case (glob expands to a non-existent literal, loop body skips).
- [x] **Restore strategy rewritten** to a matching `for` loop that `mv`s every saved file back to `$REPO_ROOT/`. Symmetrical to the save loop.
- [x] **`mkdir -p "$SAVED_DIR"`** added so the save loop's `mv` has a destination — without this the first `mv` would fail with "No such file or directory".
- [x] **Section comment cites S8-02** + the v1.2.0 incident + the rationale for `[[ -e ]]` over `shopt -s nullglob` (the latter would leak into later harness sections).
- [x] **`tests/integration/sprint-8.sh [S8-A]` — 6 new sentinels**:
  1. Save loop iterates every match (grep for `for f in.*vibeflow-plugin-\*\.tar\.gz`)
  2. Old `ls | head -1` single-tarball pattern is gone
  3. `mkdir -p "$SAVED_DIR"` precedes the save loop
  4. Restore loop iterates every saved match
  5. S8-02 ticket reference present in [S7-C] comment
  6. **RUNTIME** — seeds two distinct fixture tarballs (`vibeflow-plugin-0.0.1.tar.gz` + `vibeflow-plugin-0.0.2.tar.gz`) with random bytes via `dd if=/dev/urandom`, captures sha256 for each, runs `sprint-7.sh` (which exercises [S7-C]), and asserts BOTH fixtures survive with bytes unchanged. Skip via `VF_SKIP_S8A_RUNTIME=1` for environments that can't write to repo root.

**Live-verified:** with `vibeflow-plugin-1.2.0.tar.gz` (real release) + `vibeflow-plugin-0.9.9.tar.gz` (fake fixture) on disk, ran `sprint-7.sh` and confirmed both files still present afterward with sha256 unchanged. Without the fix, the 1.2.0 tarball would have been clobbered.

### S8-03: Consolidate deferred CI workflow changes ✅ DONE (pending user push)
**Captured during:** Sprint 6 / S6-01 + Sprint 7 / S7-06
**Location:** `.github/workflows/release.yml` + `tests/integration/sprint-8.sh [S8-B]`

Sprint 6's S6-01, Sprint 7's S7-06, and Sprint 8's S8-02 all wanted to wire their respective harness into the CI release workflow, but my PAT consistently lacks the `workflow` scope. S8-03 consolidates all three deferred updates into one commit the maintainer can push with a workflow-scoped token.

**Completed:**
- [x] `.github/workflows/release.yml` preflight step extended with three new harness runs:
  - `VF_SKIP_LIVE_POSTGRES=1 VF_SKIP_NEXT_BUILD=1 bash tests/integration/sprint-6.sh` — sprint-6.sh [S6-A] concurrent-CAS walk + [S6-B] next-build gate BOTH skip in CI (no docker-in-docker, no Next installed on a fresh runner)
  - `bash tests/integration/sprint-7.sh` — runs unconditionally; [S7-E] Postgres matrix is already opt-in via `VF_RUN_PG_MATRIX=1` which CI doesn't set, so it takes the structural-only path
  - `bash tests/integration/sprint-8.sh` — runs unconditionally; no external infra dependencies
- [x] `sprint-5.sh`'s existing CI line preserved verbatim (we only added three harnesses, didn't rewrite the existing sprint-5 preflight)
- [x] Preflight `run:` block now has a big comment block citing S8-03 + the three originating tickets so a future contributor reading the workflow can trace the history
- [x] **`tests/integration/sprint-8.sh [S8-B]` — 6 new sentinels** that grep the workflow YAML and verify each harness + each skip env var is still wired. If a future refactor drops any of them, the sentinel fires at the next preflight run.

**User action required:** commit `0cc6657...` (S8-02) is already pushed via `feature/sprint8`, but the follow-up commit that modifies `.github/workflows/release.yml` needs a workflow-scoped PAT to push. The commit is staged locally — push with:

```bash
# Option A — use gh CLI which has the right scopes by default
gh auth login
git push origin feature/sprint8

# Option B — refresh your PAT with workflow scope
# https://github.com/settings/tokens → edit/regenerate with 'workflow' scope
git push origin feature/sprint8
```

Once the workflow change is pushed, CI release runs will exercise sprint-6.sh + sprint-7.sh + sprint-8.sh alongside the existing sprint-2..5 layers. Before that push, CI still runs the pre-Sprint-8 gauntlet (sprint-5.sh only for the newer harnesses).

**Scope not shipped** (moved to future tickets):
- **Scheduled workflow that runs `VF_RUN_PG_MATRIX=1` weekly** — mentioned as a nice-to-have in the Sprint 8 seed draft. Deferred because it's a separate workflow file (`.github/workflows/pg-matrix.yml`) that needs the same PAT workflow scope to push + adds a cron trigger to consider. Better handled as its own Sprint 9 ticket if/when CI matrix signal is worth the monthly-CI cost.

### S8-04: Cross-host deterministic tarballs
**Captured during:** Sprint 7 / S7-05B scope boundaries
**Location:** `package-plugin.sh` + `docs/RELEASING.md`

S7-05B made `package-plugin.sh` produce byte-identical tarballs
on the SAME host across consecutive runs. Cross-host (macOS
bsdtar vs Linux GNU tar) was explicitly out of scope — the two
tar variants write subtly different headers (extended attribute
blocks, PAX headers). This means the CI-generated tarball may
differ from the maintainer's locally-generated tarball even
though both are internally deterministic.

Options for making cross-host reproducible:

- [ ] Require GNU tar (`gtar`) on macOS via `brew install
      gnu-tar` + detect + use if available; fall back to
      bsdtar with a WARN (document the non-reproducibility
      implication in RELEASING.md)
- [ ] Use a Docker-based build (run `package-plugin.sh` inside
      a fixed container so the host tar doesn't matter)
- [ ] Accept the host variance + document that "reproducible"
      means "same host, same input" for v1.3 and hedge for v1.4

### S8-05: PgBouncer transaction-mode startup probe
**Captured during:** Sprint 7 / S7-02 (TEAM-MODE.md doc)
**Location:** `mcp-servers/sdlc-engine/src/state/postgres.ts`

The v1.2 state store silently breaks under PgBouncer
transaction-mode pooling because `pg_advisory_xact_lock` loses
its serialization guarantee when the pool hands out a different
backend mid-transaction. TEAM-MODE.md documents the issue but
the code doesn't detect it.

- [ ] Startup probe that runs `SHOW search_path; SELECT
      pg_backend_pid();` twice in quick succession and checks
      whether the same backend PID is returned both times
      (same PID → session mode safe; different PID →
      transaction mode unsafe, abort with clear error)
- [ ] Error message points to TEAM-MODE.md section + the two
      fix paths (switch to session mode OR point at direct
      endpoint)
- [ ] Opt-out via `VF_SKIP_POOLER_CHECK=1` for operators who
      have other reasons to run transaction mode + are OK with
      the advisory-lock caveat

### S8-06: Live RDS / Cloud SQL / Azure Database integration test
**Captured during:** Sprint 7 / S7-02 scope boundaries
**Location:** `tests/integration/sprint-8.sh [S8-?]`

S7-02 added the PG13/14/15/16 matrix using vanilla Postgres
Alpine images. Managed-cloud variants were scoped out — they
need external account credentials in CI. S8-06 wires one (start
with AWS RDS) into a conditional CI path.

- [ ] New GitHub Actions workflow step gated on repository
      secrets (`AWS_RDS_HOST` + `AWS_RDS_USER` + `AWS_RDS_PASS`)
- [ ] Skip gracefully when secrets are not set (so external
      contributors' PRs still pass CI)
- [ ] Harness sentinel structurally verifies the workflow step
      exists

### S8-07: Sprint 8 integration harness
**Location:** `tests/integration/sprint-8.sh`

Same pattern as sprint-6.sh / sprint-7.sh: one section per
shipped S8-* ticket + closing [S8-Z] self-audit.

### S8-08: Sprint 8 closure + v1.3.0 release
**Location:** `CHANGELOG.md` + `docs/SPRINT-8.md`

- [ ] CHANGELOG.md `[1.3.0] — <date>` entry
- [ ] Mark Sprint 8 ✅ COMPLETE in this file
- [ ] Update CLAUDE.md test layer count
- [ ] `tests/integration/sprint-4.sh [S4-H]` bump to 1.3.0
- [ ] Run `bin/release.sh 1.3.0` end-to-end

---

## Next Ticket to Work On

**S8-02 ✅ DONE**. **S8-03 ✅ DONE** (workflow change staged, pending user push with workflow-scoped PAT). Suggested next:

- **S8-01** (prerelease workflow) — Sprint 8 headline feature
- **S8-07** + **S8-08** — harness + release closure, cuts v1.3.0

S8-04 / S8-05 / S8-06 stay deferred.

## Test inventory (after S8-02 + S8-03)

- mcp-servers/sdlc-engine: **105 vitest tests**
- mcp-servers/codebase-intel: **48 vitest tests**
- mcp-servers/design-bridge: **57 vitest tests**
- mcp-servers/dev-ops: **72 vitest tests**
- mcp-servers/observability: **76 vitest tests**
- hooks/tests/run.sh: **52 bash assertions**
- tests/integration/run.sh: **398 bash assertions**
- tests/integration/sprint-2.sh: **94 bash assertions**
- tests/integration/sprint-3.sh: **111 bash assertions**
- tests/integration/sprint-4.sh: **367 bash assertions**
- tests/integration/sprint-5.sh: **98 bash assertions** (+1 from sprint-8.sh preflight entry)
- tests/integration/sprint-6.sh: **37 bash assertions**
- tests/integration/sprint-7.sh: **51 bash assertions**
- tests/integration/sprint-8.sh: **19 bash assertions** (6 [S8-A] + 6 [S8-B] + 7 [S8-Z])
- Total: **1585 passing checks** across **14 test layers**
- Bonus (not in baseline): demo-app 45 vitest tests + nextjs-demo 66 vitest tests

## Test inventory (baseline from v1.2.0)

- mcp-servers/sdlc-engine: **105 vitest tests**
- mcp-servers/codebase-intel: **48 vitest tests**
- mcp-servers/design-bridge: **57 vitest tests**
- mcp-servers/dev-ops: **72 vitest tests**
- mcp-servers/observability: **76 vitest tests**
- hooks/tests/run.sh: **52 bash assertions**
- tests/integration/run.sh: **398 bash assertions**
- tests/integration/sprint-2.sh: **94 bash assertions**
- tests/integration/sprint-3.sh: **111 bash assertions**
- tests/integration/sprint-4.sh: **367 bash assertions**
- tests/integration/sprint-5.sh: **97 bash assertions**
- tests/integration/sprint-6.sh: **37 bash assertions**
- tests/integration/sprint-7.sh: **51 bash assertions**
- Total: **1565 passing checks** across **13 test layers**
  (1581 with `VF_RUN_PG_MATRIX=1`)
- Bonus (not in baseline): demo-app 45 vitest tests +
  nextjs-demo 66 vitest tests

## Sprint 8 vs Sprint 7 differences

- **Smaller scope, more polish.** Sprint 7 was a feature-heavy
  minor bump. Sprint 8 can afford to be narrow — bug-fixes
  from S7-07 (S8-02) + one headline (S8-01 prerelease) is a
  reasonable minimum.
- **First ticket that needs user-gated CI commits** — S8-03
  consolidates two deferred workflow changes that my PAT can't
  push. Plan the workflow PAT refresh before picking up S8-03.

## Versioning

This sprint targets **v1.3.0**. Patch fixes that surface during
Sprint 8 go into v1.2.x via the same `bin/release.sh` workflow
on a different branch.
