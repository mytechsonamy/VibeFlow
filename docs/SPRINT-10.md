# Sprint 10: v1.5 Scope TBD (Seeded)

## Sprint Goal

Sprint 10 targets **v1.5.0** — the next minor bump after v1.4. The
seeded backlog carries the four deferred tickets from Sprint 9
(S9-02 / S9-03 / S9-04 / S9-06), plus harness + closure tickets
following the established pattern. **Confirm scope with the user
before picking up any ticket.**

## Prerequisites

- Sprint 9 ✅ COMPLETE (v1.4.0 shipped 2026-04-17)
- 1638 baseline checks across 15 test layers held green offline
  (live + `VF_RUN_PG_MATRIX=1` variants unchanged)
- `bin/release.sh` step [1.5] branch guard live (S9-05); must run
  on `main` for stable cuts (or set `VF_RELEASE_ALLOW_BRANCH=1`)
- `package-plugin.sh` prefers `gtar` on macOS when available
  (S9-01); cross-host byte-match still imperfect — Docker build
  option B from S9-01 deferred here as S10-?? if it matters
- `[S4-H]`/`[S4-K]` now select tarball by `plugin.json.version`
  lookup, not alpha-sort (S9-07)
- Autopilot flow proven: Sprint 9 shipped end-to-end via a remote
  Claude Code session + maintainer-gated merge/tag push

## Completion Criteria (DRAFT — confirm with user)

- [ ] Every ticket picked up for Sprint 10 has a stable `S10-*` id
- [ ] Sprint 10 integration harness present
      (`tests/integration/sprint-10.sh`)
- [ ] Baseline test count grows without regression
- [ ] At least one v1.5.0 release ships through `bin/release.sh`
      (stable from `main` per S9-05 guard, or `--prerelease`)
- [ ] No unresolved Sprint 9 deferrals move into
      "forever-deferred" without an explicit decision

---

## Candidate Tickets (draft — confirm scope before starting)

### S10-01: PgBouncer transaction-mode startup probe
**Carried from:** Sprint 9 / S9-02 (originally Sprint 8 / S8-05)
**Location:** `mcp-servers/sdlc-engine/src/state/postgres.ts` +
new unit tests + `docs/TEAM-MODE.md` cross-reference

The v1.4 state store silently breaks under PgBouncer
transaction-mode pooling because `pg_advisory_xact_lock` loses
its serialization guarantee when the pool hands out a different
backend mid-transaction. `docs/TEAM-MODE.md` documents the issue
but the code doesn't detect it.

- [ ] Startup probe that runs `SHOW search_path; SELECT
      pg_backend_pid();` twice in quick succession (across two
      explicit transactions) and checks whether the same backend
      PID is returned both times. Same PID → session mode safe;
      different PID → transaction mode unsafe, abort with clear
      error.
- [ ] Error message points to `docs/TEAM-MODE.md` section + the
      two fix paths (switch to session mode OR point at the
      direct endpoint).
- [ ] Opt-out via `VF_SKIP_POOLER_CHECK=1` for operators who
      have other reasons to run transaction mode + are OK with
      the advisory-lock caveat.
- [ ] Unit test that mocks two distinct backend PIDs, asserts
      the check throws with the TEAM-MODE.md pointer.
- [ ] Harness sentinel in `sprint-10.sh [S10-A]` that structurally
      verifies the probe exists + env opt-out is honoured.

### S10-02: Live RDS / Cloud SQL / Azure Database integration test
**Carried from:** Sprint 9 / S9-03 (originally Sprint 8 / S8-06)
**Location:** `.github/workflows/cloud-postgres.yml` (new) +
`tests/integration/sprint-10.sh [S10-B]`

Sprint 7 / S7-02 added the PG13/14/15/16 matrix using vanilla
Postgres Alpine images. Managed-cloud variants were scoped out —
they need external account credentials in CI. S10-02 wires one
(start with AWS RDS) into a conditional CI path.

- [ ] New GitHub Actions workflow gated on repository secrets
      (`AWS_RDS_HOST` + `AWS_RDS_USER` + `AWS_RDS_PASS`).
- [ ] Skip gracefully when secrets are not set (so external
      contributors' PRs still pass CI without needing the
      managed-cloud path).
- [ ] Workflow runs `bash tests/integration/run.sh` +
      `bash tests/integration/sprint-5.sh` (team-mode walks)
      against the managed endpoint — the engine code treats it
      the same as any other Postgres, so the diff from the
      matrix workflow is only the connection string.
- [ ] Harness sentinel structurally verifies the workflow step +
      secret gating exists.
- [ ] `docs/TEAM-MODE.md` gains a "Running against managed cloud
      Postgres" section citing the secrets + the workflow.

**Prerequisite:** user provisions the AWS RDS instance + sets the
three repo secrets before we can live-verify. Purely structural
ship is possible without the secrets (harness + workflow YAML);
runtime verification waits for the secrets.

### S10-03: Scheduled pg-matrix weekly CI workflow
**Carried from:** Sprint 9 / S9-04 (originally Sprint 8 / S8-03
scope boundaries)
**Location:** new `.github/workflows/pg-matrix.yml` +
`tests/integration/sprint-10.sh [S10-C]`

S8-03 wired `sprint-6.sh` + `sprint-7.sh` + `sprint-8.sh` into
the release preflight but explicitly deferred a scheduled
workflow that runs `VF_RUN_PG_MATRIX=1` weekly. The cost/benefit
was unclear at the time; by Sprint 10 we have enough release
cadence to justify regular PG-version drift detection.

- [ ] New workflow file with `schedule: cron: '0 3 * * 1'`
      (Monday 03:00 UTC) trigger + manual `workflow_dispatch`.
- [ ] Workflow runs `VF_RUN_PG_MATRIX=1 bash
      tests/integration/sprint-7.sh` only (skip the full
      15-layer gauntlet — the main release workflow already
      covers that).
- [ ] Failure opens an issue via `gh issue create` (label:
      `ci-failure`, `pg-matrix`) rather than emailing; silent
      failures are worse than the noise, but email bombs are
      worse than issue pressure.
- [ ] Harness sentinel structurally verifies the workflow YAML +
      cron schedule + issue-creation block.

### S10-04: `release.sh --notes-file` pre-fill
**Carried from:** Sprint 9 / S9-06 (originally Sprint 8 / S8-08)
**Location:** `bin/release.sh` (step [4] + flag parser) +
`docs/RELEASING.md` + `tests/integration/sprint-10.sh [S10-D]`

The current flow creates an empty CHANGELOG stub during step [4]
and relies on the maintainer remembering to fill it in before
pushing. This worked in Sprint 8 because the release happened in
a single session; it worked in Sprint 9 because autopilot filled
the stub before the release commit was even created. But the
single-session assumption is brittle — if a release spans
sessions, the empty stub can ship to GitHub.

- [ ] `bin/release.sh <ver> --notes-file <path>` reads an
      external markdown file and pastes its body into the
      CHANGELOG entry slot, replacing the empty stub sections
      (`### Added`, `### Fixed`, `### Changed`).
- [ ] If `--notes-file` is absent, current behaviour preserved
      (empty stub + "remember to fill in" warning).
- [ ] Cross-validation: if `--notes-file` file doesn't exist or
      is empty, abort with exit 2 + clear error.
- [ ] New post-release warning — if `release.sh` detects that
      the LAST committed CHANGELOG entry has an empty
      `### Added`/`### Fixed`/`### Changed` block when the
      NEXT release is cut, surface a warning ("previous
      release shipped with an empty entry; `git push origin
      <prev-tag>` may have landed without notes").
- [ ] Harness sentinel in `sprint-10.sh [S10-D]` — static
      (flag parsing + help text) + runtime (`--dry-run` with
      a fixture notes file).

### S10-05: Sprint 10 integration harness
**Location:** `tests/integration/sprint-10.sh`

Same pattern as sprint-7.sh through sprint-9.sh: one section per
shipped S10-* ticket + closing `[S10-Z]` self-audit.

### S10-06: Sprint 10 closure + v1.5.0 release
**Location:** `CHANGELOG.md` + `docs/SPRINT-10.md`

- [ ] `CHANGELOG.md` `[1.5.0] — <date>` entry.
- [ ] Mark Sprint 10 ✅ COMPLETE in this file.
- [ ] Update `CLAUDE.md` test layer count.
- [ ] `tests/integration/sprint-4.sh [S4-H]` bump to 1.5.0
      (now SemVer-aware per S9-07, so alpha-sort isn't a
      concern — but the sentinel still reads the string).
- [ ] Run `bin/release.sh 1.5.0` end-to-end from `main`
      (S9-05 guard requires this for stable cuts).

---

## Next Ticket to Work On

**Suggested scope confirmation first.** S10-01 through S10-04
are all direct carry-overs from Sprint 9 deferrals. Pick two or
three that matter most for v1.5 + commit to deferring the rest
explicitly.

**Recommended minimum scope:**

- **S10-04** (`release.sh --notes-file`) — smallest surface,
  fixes the brittle "fill the stub by hand" step directly.
- **S10-01** (pgbouncer probe) — team-mode correctness; low-
  effort since the check is ~20 lines of SQL + a throw.
- **S10-05** + **S10-06** — harness + release closure.

**Defer candidates:**

- **S10-02** (cloud postgres) — needs user-provisioned AWS RDS
  before runtime verification is possible. Structural ship
  is fine but without live verify the sentinel is thin.
- **S10-03** (scheduled pg-matrix) — weekly CI cost vs signal
  tradeoff still unclear; probably worth a "try it for a
  month then decide" experiment but that's a Sprint-11-plus
  conversation.

## Test inventory (baseline from v1.4.0)

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
- tests/integration/sprint-5.sh: **96 bash assertions**
  (+2 from sprint-10 preflight entry once wired)
- tests/integration/sprint-6.sh: **37 bash assertions**
  (41 live with docker + pg)
- tests/integration/sprint-7.sh: **51 bash assertions**
  (+12 with `VF_RUN_PG_MATRIX=1`)
- tests/integration/sprint-8.sh: **33 bash assertions**
- tests/integration/sprint-9.sh: **39 bash assertions**
- Total: **1638 passing checks** across **15 test layers**
- Bonus (not in baseline): demo-app 45 vitest tests +
  nextjs-demo 66 vitest tests

## Sprint 10 vs Sprint 9 differences

- **Two external-dep tickets.** S10-02 (AWS RDS) + S10-03
  (scheduled pg-matrix) both need things outside the repo —
  AWS credentials + longer CI wall time — which pushes them
  to "ship structurally, live-verify later" mode. Plan the
  scope with that caveat.
- **Autopilot now proven.** Sprint 9 was the first sprint
  shipped via the remote autopilot session. If we're in a
  time crunch, Sprint 10 is a good candidate for the same
  flow — the tickets are concrete enough that autopilot can
  make progress without constant checkpoint reviews.
- **Release flow tightened.** S9-05 branch guard + S9-07
  SemVer-aware tarball lookup + S9-01 gtar probe mean the
  v1.5.0 cut itself should be lower-drama than v1.4.0 was.

## Versioning

This sprint targets **v1.5.0**. Patch fixes that surface during
Sprint 10 go into v1.4.x via the same `bin/release.sh` workflow
on a different branch. Prerelease cuts (e.g. `1.5.0-rc.1`) are
available via the S8-01 `--prerelease` flag — use them if the
scope picked up has meaningful uncertainty (S10-01 pgbouncer
probe is a strong candidate for rc bake since pg-connection
edge cases bite late).
