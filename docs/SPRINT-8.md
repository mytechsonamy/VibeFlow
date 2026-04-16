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

### S8-02: Fix sprint-7.sh [S7-C] multi-tarball save/restore bug
**Captured during:** Sprint 7 / S7-07 (v1.2.0 release)
**Location:** `tests/integration/sprint-7.sh [S7-C]`

The [S7-C] determinism runtime sentinel saves only the FIRST
pre-existing tarball via `ls vibeflow-plugin-*.tar.gz | head -1`
and then deletes ALL tarballs via `rm -f vibeflow-plugin-*.tar.gz`.
When the harness runs with multiple version tarballs on disk (e.g.
right after a fresh `release.sh` run produced
`vibeflow-plugin-1.2.0.tar.gz` while an older
`vibeflow-plugin-1.1.0.tar.gz` lingered), only the older one is
restored and the fresh release artifact gets clobbered.

The fix is small but worth doing explicitly because the current
behavior bit the v1.2.0 release:

- [ ] Change the save strategy to `mv vibeflow-plugin-*.tar.gz
      $DETERMINISM_TMPDIR/saved/` so EVERY pre-existing tarball
      is preserved
- [ ] Change the restore strategy to `mv $DETERMINISM_TMPDIR/saved/*.tar.gz
      $REPO_ROOT/` so every saved tarball is put back
- [ ] Add a regression sentinel: set up a fixture with two
      pre-existing tarballs, run [S7-C], assert both are still
      present after
- [ ] Update the [S7-C] section comment to call out the
      multi-tarball case

### S8-03: Consolidate deferred CI workflow changes
**Captured during:** Sprint 6 / S6-01 + Sprint 7 / S7-06
**Location:** `.github/workflows/release.yml`

Sprint 6's S6-01 ticket wanted to add sprint-6.sh to the CI
release workflow but the token lacked `workflow` scope. Sprint 7's
S7-06 hit the same issue with sprint-7.sh. Both are local-only
changes waiting for a user-gated push.

S8-03 consolidates both deferred updates into a single
user-authored commit the maintainer pushes with an elevated
token:

- [ ] Add `VF_SKIP_LIVE_POSTGRES=1 bash tests/integration/sprint-6.sh`
      after the existing sprint-5.sh CI run
- [ ] Add `bash tests/integration/sprint-7.sh` after that
      (no skip needed — sprint-7.sh's [S7-E] already defaults to
      opt-in via `VF_RUN_PG_MATRIX=1` which CI won't set)
- [ ] Optionally add a CI-only step that runs with
      `VF_RUN_PG_MATRIX=1` on a schedule (weekly) rather than on
      every tag push, so the 4-image matrix exercises in CI
      without slowing every release

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

**Confirm Sprint 8 scope with the user first.** Good first-pass
candidates:

- **S8-02** (sprint-7.sh [S7-C] fix) — smallest ticket,
  closes a known bug, good warmup
- **S8-03** (CI workflow consolidation) — needs user push with
  workflow-scoped token, but the diff is tiny
- **S8-01** (prerelease workflow) — the Sprint 8 headline
  feature if you want a real v1.3 deliverable

S8-04 / S8-05 / S8-06 are LARGER and can move to Sprint 9 if
Sprint 8 stays narrow.

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
