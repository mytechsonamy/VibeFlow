# Sprint 6: v1.1 Hardening + Deferred Items (Scope TBD)

## Sprint Goal

Sprint 6 targets **v1.1.0** — the first minor bump after v1.0.x. The
seeded backlog below is a candidate list drawn from Sprint 5 scope
decisions + the one bug surfaced during S5-07. **Confirm scope with
the user before picking up any ticket** — not all of these will fit
in a single sprint and some may be deferred further.

## Prerequisites

- Sprint 5 ✅ COMPLETE (v1.0.1 shipped 2026-04-14)
- 1445 baseline checks across 11 test layers held green
- `bin/release.sh` discipline established + verified end-to-end

## Completion Criteria (DRAFT — confirm with user)

- [ ] Every ticket picked up for Sprint 6 has a stable `S6-*` id
- [ ] Sprint 6 integration harness present (`tests/integration/sprint-6.sh`)
- [ ] Baseline test count grows without regression
- [ ] At least one v1.1.0 release ships through `bin/release.sh` once
      the sprint's picked tickets are closed
- [ ] No unresolved Sprint 5 deferrals move into "forever-deferred"
      without an explicit decision

---

## Candidate Tickets (draft — confirm scope before starting)

### S6-01: Concurrent-advance CAS stress test against real Postgres
**Location:** `tests/integration/sprint-6.sh` + new `mcp-servers/sdlc-engine/tests/postgres-stress.test.ts`
**Deferred from:** S5-03 scope decision

Sprint 1's 14 `FakePool` unit tests cover the CAS logic at the unit
layer. Sprint 5's `sprint-5.sh [S5-B]` walks one fresh engine process
against a real Postgres. Neither exercises **concurrent** advance
attempts — the revision-mismatch loser path is still only covered
by mocks. S6-01 spins up two engine processes under
`bin/with-postgres.sh` + drives them at the same project with a
deterministic interleave, asserting the loser sees the CAS mismatch
and retries correctly.

- [ ] Stress test wrapper (bash or Node) driving N concurrent
      `sdlc_advance_phase` calls at the same project
- [ ] Loser process sees a `"revision mismatch"` error envelope and
      retries via `sdlc_get_state` + re-advance
- [ ] State ends at a consistent phase (whichever process won)
- [ ] Harness sentinel in `sprint-6.sh [S6-A]`

### S6-02: Self-hosted GitLab integration
**Location:** `mcp-servers/dev-ops/tests/gitlab-client.test.ts` + `docs/CONFIGURATION.md`
**Deferred from:** S5-02 scope decision

Sprint 5's GitLab client ships with 19 vitest cases all against
`gitlab.com` URLs. `baseUrl` is configurable but never exercised.
S6-02 adds test coverage for self-hosted instances + updates the
docs to spell out the `userConfig.gitlab_base_url` override.

- [ ] Mock tests for custom `baseUrl` (e.g. `https://gitlab.example.com`)
- [ ] Real-instance test against a `gitlab/gitlab-ce` docker image
      (conditional skip on docker + `VF_SKIP_LIVE_GITLAB=1`)
- [ ] `docs/CONFIGURATION.md` `ci_provider` row extended with the
      self-hosted override documentation
- [ ] Harness sentinel in `sprint-6.sh [S6-B]`

### S6-03: Postgres version matrix (PG13 / PG15 / PG16 / managed)
**Location:** `bin/with-postgres.sh` + `sprint-6.sh [S6-C]`
**Deferred from:** S5-03 scope decision

Sprint 5 only tests against `postgres:14-alpine`. Real users will
run a mix of PG13, PG15, PG16, AWS RDS, GCP Cloud SQL. S6-03
parameterizes `with-postgres.sh` to accept multiple `VF_PG_IMAGE`
values and loops the S5-B walk across each.

- [ ] Matrix runner wrapping `with-postgres.sh`
- [ ] PG13 + PG14 + PG15 + PG16 all exercise the REQUIREMENTS →
      DESIGN walk
- [ ] Document managed-cloud caveats (RDS-specific config) in
      `docs/TEAM-MODE.md`

### S6-04: Next.js demo — `next build` coverage + `"use client"` surface
**Location:** `examples/nextjs-demo/` + `sprint-6.sh [S6-D]`
**Deferred from:** S5-05 scope decision

The v1.0.1 Next.js demo is 100% RSC + server actions. S6-04 adds:

- [ ] A `"use client"` component (e.g. a rating picker) + its tests
- [ ] A CI-optional `next build` step (gated on `VF_SKIP_NEXT_BUILD=1`)
- [ ] Harness sentinel verifying the `"use client"` directive + the
      client/server boundary
- [ ] Updated `NEXTJS-DEMO-WALKTHROUGH.md` covering the new surface

### S6-05: GPG-signed release tags + marketplace publish API
**Location:** `bin/release.sh` + `.github/workflows/release.yml` + `docs/RELEASING.md` (new)
**Deferred from:** S5-04 scope decision

S5-04's release.sh creates unsigned annotated tags. S6-05 wires GPG
signing (via `git tag -s`) + documents the key management. Also
hooks into Claude Code's plugin marketplace API (if/when it exists
by v1.1) or documents the manual publish flow.

- [ ] `git tag -s v$VERSION -m v$VERSION` when a signing key is
      configured, fallback to annotated-only otherwise
- [ ] Release workflow verifies the tag signature
- [ ] New `docs/RELEASING.md` walkthrough covering the full workflow

### S6-06: Automated prerelease / beta-channel workflow
**Location:** `bin/release.sh` (new `--prerelease` mode) + docs
**Deferred from:** S5-04 scope decision

S5-04's release.sh rejects `1.0.1-beta` and other prerelease
suffixes by design. S6-06 adds a dedicated prerelease path with its
own SemVer rules + GitHub Releases `prerelease: true` flag.

- [ ] `bin/release.sh <version>-<tag>.<n> --prerelease` accepts
      SemVer prerelease identifiers
- [ ] Separate release track that doesn't update the
      `## [latest]` CHANGELOG pointer
- [ ] Harness sentinel for the prerelease path

### S6-07: release.sh CHANGELOG insertion runtime sentinel
**Location:** `tests/integration/sprint-5.sh [S5-C]` (extend) or
new `tests/integration/sprint-6.sh [S6-G]`
**Discovered during:** S5-07 (CHANGELOG BSD awk bug)

S5-07 uncovered a BSD awk portability bug in `release.sh` that
caused a silent broken-release (CHANGELOG never updated, release
commit claimed success). The current `sprint-5.sh [S5-C]` sentinels
only grep release.sh source — they cannot catch a runtime insertion
failure. S6-07 adds a runtime test that exercises the CHANGELOG
insertion step against a tempfile fixture.

- [ ] Fixture CHANGELOG (minimal — header + one `## [1.0.0]` entry)
- [ ] Harness extracts release.sh's CHANGELOG-insertion block (or
      calls release.sh with a new `--check-changelog-insert` flag)
      against the fixture
- [ ] Asserts the fixture now has a `## [<new-version>]` header at
      the top AND the post-insertion verification step fires on a
      deliberately-broken fixture
- [ ] Lives in sprint-5.sh (closing a Sprint 5 regression window) OR
      sprint-6.sh if it grows into something larger

### S6-08: Sprint 6 integration harness
**Location:** `tests/integration/sprint-6.sh`

Mirror the pattern from `sprint-5.sh`: one section per S6-* ticket,
with structural checks for the files/signals each ticket produces.
This ticket closes last once every other S6 ticket lands its
sentinel.

### S6-09: Sprint 6 closure + v1.1.0 release notes
**Location:** `CHANGELOG.md` + `docs/SPRINT-6.md`

- [ ] CHANGELOG.md `[1.1.0] — <date>` entry covering the picked
      tickets
- [ ] Mark Sprint 6 ✅ COMPLETE in this file
- [ ] Update CLAUDE.md test layer count
- [ ] Run `bin/release.sh 1.1.0` end-to-end (push gated on user
      authorization, same discipline as v1.0.0 / v1.0.1)

---

## Next Ticket to Work On

**Confirm Sprint 6 scope with the user first.** The candidate list
above is seeded from Sprint 5's deferrals + the S5-07 bug. It is
almost certainly too much for a single sprint. Pick a subset,
re-number if needed, and remove the un-picked items from this file
before starting work.

## Test inventory (baseline from v1.0.1)

- mcp-servers/sdlc-engine: **105 vitest tests**
- mcp-servers/codebase-intel: **48 vitest tests**
- mcp-servers/design-bridge: **57 vitest tests**
- mcp-servers/dev-ops: **62 vitest tests**
- mcp-servers/observability: **76 vitest tests**
- hooks/tests/run.sh: **52 bash assertions**
- tests/integration/run.sh: **398 bash assertions**
- tests/integration/sprint-2.sh: **94 bash assertions**
- tests/integration/sprint-3.sh: **111 bash assertions**
- tests/integration/sprint-4.sh: **355 bash assertions**
- tests/integration/sprint-5.sh: **87 bash assertions**
- Total: **1445 passing checks** across **11 test layers**
- Bonus (not in baseline): demo-app 45 vitest tests + nextjs-demo 41 vitest tests

## Sprint 6 vs Sprint 5 differences

- **Minor bump, not patch.** v1.1 may include breaking changes to
  internal APIs (not user-facing config). Document any in CHANGELOG.
- **Scope picked, not seeded.** Sprint 5 shipped all 7 of its seeded
  tickets because the scope was narrow (close v1.0 stubs). Sprint 6
  starts with a wider candidate list and picks from it — don't try
  to land everything.

## Versioning

This sprint targets **v1.1.0**. Patch fixes that surface during
Sprint 6 go into v1.0.2 via the same `bin/release.sh` workflow
(Sprint 6 work stays on a different branch from the v1.0.2 branch).
