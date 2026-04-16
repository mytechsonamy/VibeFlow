# Sprint 7: v1.2 Scope TBD (Seeded)

## Sprint Goal

Sprint 7 targets **v1.2.0** — the next minor bump after v1.1. The
seeded backlog below picks up items deferred from Sprint 6's scope
decisions + the two lessons learned during the v1.1.0 release
(Sprint 6 / S6-09). **Confirm scope with the user before picking
up any ticket** — not all of these will fit in a single sprint, and
some may move to v1.3 or be dropped entirely.

## Prerequisites

- Sprint 6 ✅ COMPLETE (v1.1.0 shipped 2026-04-16)
- 1489 baseline checks across 12 test layers held green
- `bin/release.sh` + `docs/RELEASING.md` discipline established + exercised end-to-end across v1.0.0, v1.0.1, v1.1.0

## Completion Criteria (DRAFT — confirm with user)

- [ ] Every ticket picked up for Sprint 7 has a stable `S7-*` id
- [ ] Sprint 7 integration harness present (`tests/integration/sprint-7.sh`) OR extended sections on sprint-6.sh (depending on scope)
- [ ] Baseline test count grows without regression
- [ ] At least one v1.2.0 release ships through `bin/release.sh`
- [ ] No unresolved Sprint 6 deferrals move into "forever-deferred"
      without an explicit decision

---

## Candidate Tickets (draft — confirm scope before starting)

### S7-01: Self-hosted GitLab integration
**Deferred from:** Sprint 6 / S6-02 (itself deferred from Sprint 5 / S5-02)
**Location:** `mcp-servers/dev-ops/tests/gitlab-client.test.ts` + `docs/CONFIGURATION.md`

Sprint 5's GitLab client ships with 19 vitest cases all against
`gitlab.com` URLs. `baseUrl` is configurable but never exercised.
S7-01 adds test coverage for self-hosted instances + updates the
docs to spell out the `userConfig.gitlab_base_url` override.

- [ ] Mock tests for custom `baseUrl` (e.g. `https://gitlab.example.com`)
- [ ] Real-instance test against a `gitlab/gitlab-ce` docker image
      (conditional skip on docker + `VF_SKIP_LIVE_GITLAB=1`)
- [ ] `docs/CONFIGURATION.md` `ci_provider` row extended with the
      self-hosted override documentation
- [ ] Harness sentinel in `sprint-7.sh [S7-?]`

### S7-02: Postgres version matrix (PG13 / PG15 / PG16 / managed)
**Deferred from:** Sprint 6 / S6-03 (itself deferred from Sprint 5 / S5-03)
**Location:** `bin/with-postgres.sh` + `sprint-7.sh [S7-?]`

Sprint 5 only tests against `postgres:14-alpine`. Sprint 6's
[S6-A] concurrent-CAS stress test also pins `postgres:14-alpine`.
Real users will run a mix of PG13, PG15, PG16, AWS RDS, GCP Cloud
SQL. S7-02 parameterizes `bin/with-postgres.sh` to accept multiple
`VF_PG_IMAGE` values and loops the S5-B + S6-A walks across each.

- [ ] Matrix runner wrapping `with-postgres.sh`
- [ ] PG13 + PG14 + PG15 + PG16 all exercise the REQUIREMENTS →
      DESIGN walk + the concurrent-advance CAS stress test
- [ ] Document managed-cloud caveats (RDS-specific config) in
      `docs/TEAM-MODE.md`

### S7-03: Automated prerelease / beta-channel workflow
**Deferred from:** Sprint 6 / S6-06 (itself deferred from Sprint 5 / S5-04)
**Location:** `bin/release.sh` (new `--prerelease` mode) + `docs/RELEASING.md`

Sprint 5's release.sh rejects `1.0.1-beta` and other prerelease
suffixes by design. S7-03 adds a dedicated prerelease path with
its own SemVer rules + GitHub Releases `prerelease: true` flag.

- [ ] `bin/release.sh <version>-<tag>.<n> --prerelease` accepts
      SemVer prerelease identifiers
- [ ] Separate release track that does NOT update the
      `## [latest]` CHANGELOG pointer
- [ ] `docs/RELEASING.md` gains a "Prereleases" section covering
      when to cut one vs a normal release
- [ ] Harness sentinel for the prerelease path

### S7-04: release.sh pre-step-5 pg sanity check
**Captured during:** Sprint 6 / S6-09 (the v1.1.0 release hit a mid-flight build failure because `pg` / `@types/pg` had been uninstalled after S6-01 live-verification testing)
**Location:** `bin/release.sh` step [0.5] (new, between cleanliness and version-arg)

Before running the preflight gauntlet, release.sh should probe
that the sdlc-engine MCP has its `pg` peer dep installed — without
it, `build-all.sh` fails with `Cannot find module 'pg'` halfway
through the release. Catching this pre-flight keeps the release
atomic: the tree stays clean until the build actually runs.

- [ ] New step [0.5] in release.sh: if `mcp-servers/sdlc-engine/node_modules/pg` is missing, print a clear error + exit non-zero
- [ ] Error message includes the fix: `cd mcp-servers/sdlc-engine && npm install pg @types/pg`
- [ ] Harness sentinel asserting the check exists

### S7-05: docs/RELEASING.md Troubleshooting + sha256 drift fix
**Captured during:** Sprint 6 / S6-09 (two separate incidents during v1.1.0)
**Location:** `docs/RELEASING.md` Troubleshooting section (extend) + `bin/release.sh` step [6] sha256 regen

Two lessons captured during the v1.1.0 release:

**Lesson 1: mid-release build failure recovery.** release.sh fails
mid-flight at step [5] (or any step after the plugin.json bump):

- [ ] Entry: "release.sh fails at step 5 with `Cannot find module 'pg'`"
- [ ] Recovery steps: reinstall pg, manually run `bash build-all.sh + bash package-plugin.sh --skip-build + shasum -a 256 ...`, then manually `git add + git commit + git tag -a`
- [ ] Note that the release commit can fold in the recovery without amending because release.sh's steps 5-7 are all re-runnable from a dirty-tree state (the cleanliness check only runs at step 0)

**Lesson 2: sha256 sidecar drift when preflight regenerates the tarball.**
Between release.sh's step [6] (sha256 generation) and the eventual
`gh release upload`, the harness preflight that runs elsewhere
(or a manual re-run of `package-plugin.sh`) can regenerate the
tarball. Tar + gzip bake timestamps into the archive so each
regen produces a slightly different byte-for-byte output → a
different sha256. If the sidecar on disk was generated BEFORE
the regen, it will not match the uploaded tarball.

- [ ] `bin/release.sh` should re-generate the sha256 sidecar as the
      LAST step before the commit, right after the final build, so
      it cannot be out of sync with the tarball.
- [ ] Alternative: make `package-plugin.sh` deterministic (tar `--mtime=@0` or similar) so two consecutive runs produce identical bytes. This is the right long-term fix.
- [ ] `docs/RELEASING.md` Troubleshooting entry: "sha256 doesn't match the tarball" → regenerate with `shasum -a 256 vibeflow-plugin-X.Y.Z.tar.gz > vibeflow-plugin-X.Y.Z.tar.gz.sha256` then `gh release upload vX.Y.Z ... --clobber`.

### S7-06: Sprint 7 integration harness OR sprint-6.sh extension
**Location:** `tests/integration/sprint-7.sh` (new) OR `tests/integration/sprint-6.sh` (extend)

Sprint 5 / S5-06 and Sprint 6 / S6-08 established the pattern:
one harness file per sprint, with sections `[SN-A]`, `[SN-B]`, …
for each ticket. Sprint 7 can follow the same pattern with a new
`sprint-7.sh`, OR extend the existing `sprint-6.sh` with new
sections. Decide early — cross-sprint harness sharing makes the
release.sh preflight list longer but avoids fragmentation.

- [ ] One section per shipped S7-* ticket
- [ ] Closing `[S7-Z]` self-audit mirroring `[S6-Z]`
- [ ] Wired into `bin/release.sh` preflight gauntlet if new file
- [ ] Wired into `.github/workflows/release.yml` if new file

### S7-07: Sprint 7 closure + v1.2.0 release notes
**Location:** `CHANGELOG.md` + `docs/SPRINT-7.md`

- [ ] CHANGELOG.md `[1.2.0] — <date>` entry covering picked tickets
- [ ] Mark Sprint 7 ✅ COMPLETE in this file
- [ ] Update CLAUDE.md test layer count
- [ ] `tests/integration/sprint-4.sh [S4-H]` EXPECTED_PLUGIN_VERSION bumped to `1.2.0`
- [ ] Run `bin/release.sh 1.2.0` end-to-end (push gated on user authorization, same discipline as v1.0.0 / v1.0.1 / v1.1.0)

---

## Next Ticket to Work On

**Confirm Sprint 7 scope with the user first.** The candidate list
above is seeded from Sprint 6's deferrals + the two S6-09 lessons.
Pick a subset, re-number if needed, and remove the un-picked items
from this file before starting work. Good candidates for a
scope-narrow first-pass Sprint 7:

- **S7-04** + **S7-05** (release.sh hardening + docs) — small,
  high-value, closes the gap revealed by S6-09
- **S7-01** (self-hosted GitLab) OR **S7-02** (Postgres version
  matrix) — pick ONE, not both; each is a full ticket's worth of
  work

S7-03 (prerelease workflow) is LARGER and could either be the
single Sprint 7 headline feature or deferred to a later sprint.

## Test inventory (baseline from v1.1.0)

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
- tests/integration/sprint-5.sh: **94 bash assertions**
- tests/integration/sprint-6.sh: **37 bash assertions**
- Total: **1489 passing checks** across **12 test layers** (1493 in live mode)
- Bonus (not in baseline): demo-app 45 vitest tests + nextjs-demo 66 vitest tests

## Sprint 7 vs Sprint 6 differences

- **Minor bump, not patch.** v1.2 may include API surface additions
  but should maintain drop-in compatibility with v1.1. Any internal
  refactor that changes observable behavior deserves a CHANGELOG
  "Changed" entry.
- **Scope picked, not seeded.** Same discipline as Sprint 6 —
  don't try to land every candidate.
- **Lessons from Sprint 6 feed forward.** S7-04 + S7-05 directly
  capture pain points from the v1.1.0 release process.

## Versioning

This sprint targets **v1.2.0**. Patch fixes that surface during
Sprint 7 go into v1.1.x via the same `bin/release.sh` workflow on
a different branch. The signing probe (S6-05) handles both paths
without modification.
