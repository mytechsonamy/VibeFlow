# Sprint 9: v1.4 Scope TBD (Seeded)

## Sprint Goal

Sprint 9 targets **v1.4.0** — the next minor bump after v1.3.
The seeded backlog below carries the three deferred tickets from
Sprint 8 (S8-04 / S8-05 / S8-06), one lift-out from Sprint 8 /
S8-03 (scheduled pg-matrix), plus lessons captured during the
v1.3.0 cut. **Confirm scope with the user before picking up any
ticket.**

## Prerequisites

- Sprint 8 ✅ COMPLETE (v1.3.0 shipped 2026-04-17)
- 1599 baseline checks across 14 test layers held green offline
  (1603 live; 1615 with `VF_RUN_PG_MATRIX=1`)
- `bin/release.sh` now supports `--prerelease` (S8-01), byte-
  reproducible tarballs (S7-05B), and a `VF_SKIP_GAUNTLET=1`
  escape hatch for harness self-tests (S8-01)
- CI release workflow exercises `sprint-6.sh` + `sprint-7.sh` +
  `sprint-8.sh` preflight (S8-03)

## Completion Criteria (DRAFT — confirm with user)

- [ ] Every ticket picked up for Sprint 9 has a stable `S9-*` id
- [ ] Sprint 9 integration harness present
      (`tests/integration/sprint-9.sh`)
- [ ] Baseline test count grows without regression
- [ ] At least one v1.4.0 release ships through `bin/release.sh`
      (stable or prerelease — the S8-01 path is now available)
- [ ] No unresolved Sprint 8 deferrals move into
      "forever-deferred" without an explicit decision

---

## Candidate Tickets (draft — confirm scope before starting)

### S9-01: Cross-host deterministic tarballs
**Carried from:** Sprint 8 / S8-04
**Location:** `package-plugin.sh` + `docs/RELEASING.md` + possibly
`.github/workflows/release.yml`

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
      means "same host, same input" for v1.4 and hedge for v1.5

Recommendation: start with Option 1 (gtar detection + warn
fallback) — smallest surface change, preserves the "works out of
the box on macOS" property.

### S9-02: PgBouncer transaction-mode startup probe
**Carried from:** Sprint 8 / S8-05
**Location:** `mcp-servers/sdlc-engine/src/state/postgres.ts`

The v1.3 state store silently breaks under PgBouncer
transaction-mode pooling because `pg_advisory_xact_lock` loses
its serialization guarantee when the pool hands out a different
backend mid-transaction. `docs/TEAM-MODE.md` documents the issue
but the code doesn't detect it.

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

### S9-03: Live RDS / Cloud SQL / Azure Database integration test
**Carried from:** Sprint 8 / S8-06
**Location:** `tests/integration/sprint-9.sh [S9-?]` + new
`.github/workflows/` step

S7-02 added the PG13/14/15/16 matrix using vanilla Postgres
Alpine images. Managed-cloud variants were scoped out — they
need external account credentials in CI. S9-03 wires one (start
with AWS RDS) into a conditional CI path.

- [ ] New GitHub Actions workflow step gated on repository
      secrets (`AWS_RDS_HOST` + `AWS_RDS_USER` + `AWS_RDS_PASS`)
- [ ] Skip gracefully when secrets are not set (so external
      contributors' PRs still pass CI)
- [ ] Harness sentinel structurally verifies the workflow step
      exists

### S9-04: Scheduled pg-matrix weekly CI workflow
**Captured from:** Sprint 8 / S8-03 scope boundaries
**Location:** new `.github/workflows/pg-matrix.yml`

S8-03 wired `sprint-6.sh` + `sprint-7.sh` + `sprint-8.sh` into
the release preflight but explicitly deferred a scheduled
workflow that runs `VF_RUN_PG_MATRIX=1` weekly. The cost/benefit
was unclear: the matrix adds ~12 assertions but runs 4 Postgres
containers (13/14/15/16), which is noticeable CI minutes.

- [ ] New workflow file with `schedule: cron: '0 3 * * 1'`
      (Monday 03:00 UTC) trigger + manual `workflow_dispatch`
- [ ] Workflow runs `VF_RUN_PG_MATRIX=1 bash
      tests/integration/sprint-7.sh [S7-E]` only (skip the full
      14-layer gauntlet — the main release workflow already
      covers that)
- [ ] Failure opens an issue via `gh issue create` rather than
      emailing (silent failures are worse than the noise)
- [ ] Harness sentinel verifies workflow YAML + cron schedule

### S9-05: Release workflow — stop clobbering main
**Captured during:** Sprint 8 / S8-08 (v1.3.0 cut)
**Location:** `bin/release.sh` + `docs/RELEASING.md`

During the v1.3.0 cut we noticed `origin/main` had been stale
since Sprint 6 (last updated 2026-04 by `docs/SPRINT-7.md:
S7-05 expanded with sha256 drift lesson`). `release.sh`'s
Next-Steps hint says `git push origin main` but the actual
practice has been to cut tags from feature branches without
touching main. That works until:

- A contributor clones a fresh repo and runs `release.sh`
  expecting main to be the source of truth.
- The `plugin.json` version on main drifts from the latest
  release tag, confusing anyone running `claude plugin install`
  from a cloned repo rather than a tarball.

- [ ] Decide the canonical model — either:
  - (a) Require release commits land on `main` (open a PR from
    the feature branch → merge → cut the tag from `main`).
    `release.sh` refuses to run unless `HEAD` is on `main`
    (or an allowlisted release branch).
  - (b) Accept that feature branches carry release tags,
    document it in `RELEASING.md`, and stop printing
    `git push origin main` in the Next-Steps block when the
    tag doesn't actually come from `main`.
- [ ] Reconcile `main` once — fast-forward to whatever branch
      `v1.3.0` lives on so future reasoning isn't confused by
      the legacy drift (done manually during Sprint 8 / S8-08).

Recommendation: option (a). Feature branches ship, but the
main branch should always reflect the latest released state.

### S9-06: `release.sh --notes-file` pre-fill
**Captured during:** Sprint 8 / S8-08 (v1.3.0 cut)
**Location:** `bin/release.sh` + `docs/RELEASING.md`

The current flow creates an empty CHANGELOG stub during step [4]
and relies on the maintainer remembering to fill it in before
pushing. This worked in Sprint 8 because the release happened in
a single session, but for a longer cycle (cut a tag, come back
tomorrow, push the release) the empty stub can make it all the
way to GitHub.

- [ ] `bin/release.sh <ver> --notes-file <path>` reads an
      external markdown file and pastes its body into the
      CHANGELOG entry slot, replacing the empty stub sections
      (`### Added`, `### Fixed`, `### Changed`).
- [ ] If `--notes-file` is absent, current behaviour preserved
      (empty stub + "remember to fill in" warning).
- [ ] New warning if `release.sh` detects an empty stub in the
      LAST committed CHANGELOG entry when the next release is
      cut — "previous release has an empty entry; push may have
      shipped without notes".

### S9-07: `[S4-K]` tarball selection — SemVer-aware sort
**Captured during:** Sprint 8 / S8-08 (v1.3.0 cut)
**Location:** `tests/integration/sprint-4.sh [S4-K]`

The fresh-install simulation picks the tarball via
`ls vibeflow-plugin-*.tar.gz | head -1` which sorts
alphabetically. That works fine for 1.2.0 vs 1.3.0 but will
pick 1.10.0 before 1.9.0 (string sort: "1.10.0" < "1.9.0"). The
Sprint 8 cut hit a related edge case — a stale 1.2.0 tarball
left over from the previous release was picked over the
freshly-built 1.3.0 — and we worked around it by deleting the
stale tarball. The fix is a SemVer-aware sort or explicit
plugin.json-version lookup.

- [ ] Replace `ls | head -1` with a `jq` lookup: parse
      `plugin.json.version` and select `vibeflow-plugin-${VERSION}.tar.gz`
      directly.
- [ ] Fail with a clear error if the expected tarball isn't
      present (instead of silently picking the wrong one).
- [ ] Add a regression sentinel that seeds two fake tarballs
      (9.9.9 + 1.9.0, where alpha-sort would pick 1.9.0 and
      SemVer-sort would pick 9.9.9) and asserts the correct one
      is selected.

### S9-08: Sprint 9 integration harness
**Location:** `tests/integration/sprint-9.sh`

Same pattern as sprint-7.sh / sprint-8.sh: one section per
shipped S9-* ticket + closing `[S9-Z]` self-audit.

### S9-09: Sprint 9 closure + v1.4.0 release
**Location:** `CHANGELOG.md` + `docs/SPRINT-9.md`

- [ ] CHANGELOG.md `[1.4.0] — <date>` entry
- [ ] Mark Sprint 9 ✅ COMPLETE in this file
- [ ] Update CLAUDE.md test layer count
- [ ] `tests/integration/sprint-4.sh [S4-H]` bump to 1.4.0
      (see S9-07 for a longer-term fix)
- [ ] Run `bin/release.sh 1.4.0` end-to-end

---

## Next Ticket to Work On

**Suggested scope confirmation first.** S9-01 through S9-04 are
direct carry-overs from Sprint 8 deferrals; S9-05 through S9-07
are new items captured during Sprint 8 / S8-08. Pick the two or
three that matter most for v1.4 + commit to deferring the rest
explicitly to keep Sprint 9 narrow.

Recommended minimum:

- **S9-05** (stop clobbering main) — process hygiene, blocks
  future confusion.
- **S9-01** (cross-host deterministic tarballs) — completes the
  S7-05B reproducibility story.
- **S9-07** (SemVer-aware tarball sort) — tiny fix, prevents a
  subtle bug at v1.10.0.
- **S9-08** + **S9-09** — harness + release closure.

Defer candidates: S9-02 (pgbouncer probe), S9-03 (cloud
postgres), S9-04 (scheduled pg-matrix), S9-06 (release.sh
`--notes-file`).

## Test inventory (baseline from v1.3.0)

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
- tests/integration/sprint-5.sh: **98 bash assertions**
- tests/integration/sprint-6.sh: **37 bash assertions**
  (41 live with docker + pg)
- tests/integration/sprint-7.sh: **51 bash assertions**
  (+12 with `VF_RUN_PG_MATRIX=1`)
- tests/integration/sprint-8.sh: **33 bash assertions**
- Total: **1599 passing checks** across **14 test layers**
  (1603 live; 1615 with `VF_RUN_PG_MATRIX=1`)
- Bonus (not in baseline): demo-app 45 vitest tests +
  nextjs-demo 66 vitest tests

## Sprint 9 vs Sprint 8 differences

- **First sprint without a release headline.** Sprint 8 had
  S8-01 (prerelease workflow) as a clear marquee feature.
  Sprint 9's candidate list is a mix of carry-overs and
  release-cycle polish — no single headline. Deciding the scope
  needs a product conversation, not just a ticket list.
- **More CI-heavy tickets.** S9-03 (cloud postgres) + S9-04
  (scheduled pg-matrix) both need workflow-scoped PAT pushes,
  which has historically been friction (Sprint 8 / S8-03 had to
  refresh the gh auth mid-sprint). Cluster them into a single
  workflow-PAT session.
- **Process hygiene item.** S9-05 is about how we release, not
  what we release. Worth picking up first so the v1.4.0 cut
  itself is cleaner than v1.3.0's was.

## Versioning

This sprint targets **v1.4.0**. Patch fixes that surface during
Sprint 9 go into v1.3.x via the same `bin/release.sh` workflow
on a different branch. Prerelease cuts (e.g. `1.4.0-rc.1`) are
now available via the S8-01 `--prerelease` flag — use them if
the scope picked up has meaningful uncertainty.
