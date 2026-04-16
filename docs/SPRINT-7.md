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

### S7-04: release.sh pre-step-5 pg sanity check ✅ DONE
**Captured during:** Sprint 6 / S6-09 (the v1.1.0 release hit a mid-flight build failure because `pg` / `@types/pg` had been uninstalled after S6-01 live-verification testing)
**Location:** `bin/release.sh` step [0.5] + `tests/integration/sprint-7.sh [S7-A]`

**Completed:**
- [x] **New step [0.5] in `bin/release.sh`** between `[0]` working-tree cleanliness and `[1]` version argument. Probes both `mcp-servers/sdlc-engine/node_modules/pg` AND `node_modules/@types/pg` — either one missing triggers an abort. Exit happens BEFORE `[1]` version validation, `[2]` preflight gauntlet, `[3]` plugin.json bump, `[4]` CHANGELOG insertion, and `[5]` build. The tree stays untouched.
- [x] **Error message includes the fix** — the script prints `cd mcp-servers/sdlc-engine && npm install pg @types/pg` directly rather than making the maintainer hunt for it.
- [x] **Section comment cites S7-04** — future contributors reading step [0.5] can trace back to this ticket + the S6-09 incident that motivated it.
- [x] **6 harness sentinels in `sprint-7.sh [S7-A]`** covering:
  1. `[0.5]` section header present
  2. Probe checks `mcp-servers/sdlc-engine/node_modules/pg`
  3. Probe ALSO checks `node_modules/@types/pg` (tsc needs both runtime + types)
  4. Error output includes the fix command
  5. `[0.5]` runs before `[1]` (line-number comparison — prevents a future refactor from reordering the checks)
  6. Section comment cites S7-04

**Why the line-number check matters:** a pg-missing release that happens AFTER step `[3]` plugin.json bump would leave the working tree with plugin.json incremented but no commit, no tag, no tarball — exactly the half-released state the ticket is designed to prevent. The `[0.5]` line < `[1]` line assertion catches a refactor that accidentally moved the sanity check past the bump point.

### S7-05: docs/RELEASING.md Troubleshooting + sha256 drift fix ✅ DONE (partial — determinism deferred)
**Captured during:** Sprint 6 / S6-09 (two separate incidents during v1.1.0)
**Location:** `docs/RELEASING.md` Troubleshooting section + `tests/integration/sprint-7.sh [S7-B]`

**Completed:**
- [x] **Troubleshooting entry 1** — "release: pg peer dep is not installed in sdlc-engine". Covers the error message (both the new `[0.5]` sanity-check message AND the raw `tsc` error `Cannot find module 'pg'` so a maintainer searching either text finds the entry). Surfaces the one-liner fix `cd mcp-servers/sdlc-engine && npm install pg @types/pg` + a note about why `pg` isn't auto-installed (it's a peer dep with `peerDependenciesMeta.pg.optional = true` so solo-mode users don't carry it).
- [x] **Troubleshooting entry 2** — "release.sh fails MID-FLIGHT (after step [0.5] passed)". Covers the recovery path when something breaks between step `[3]` plugin.json bump and step `[7]` commit. Three-option menu: (a) fix the underlying issue + manually run the remaining build+package+sha256+commit+tag commands, (b) abort the release by reverting plugin.json + CHANGELOG via `git checkout`.
- [x] **Troubleshooting entry 3** — "sha256 sidecar doesn't match the uploaded tarball". Root-cause attribution to `sprint-4.sh [S4-G]` regenerating the tarball during preflight + the `gh release upload --clobber` fix + forward reference to the long-term determinism work (still open — see below).
- [x] **6 harness sentinels in `sprint-7.sh [S7-B]`** verifying all three entries + the fix commands + the root-cause attribution.

**Scope decision — determinism fix deferred:**

The long-term fix for sha256 drift is making `package-plugin.sh` emit a byte-identical tarball on every run. This requires:
- `tar --mtime=@0` + `--sort=name` + `--owner=0 --group=0 --numeric-owner` (GNU tar flags; BSD tar on macOS has different syntax or no equivalent)
- `gzip -n` to strip the filename + timestamp from the gzip header
- A cross-platform wrapper that normalizes mtimes before tarring (since BSD tar on macOS doesn't have `--mtime`)

That's its own ticket — probably worth a dedicated S7-05B or rolling into a later hardening sprint. For S7-05's v1.2 scope, the doc entry + harness sentinels are enough to close the knowledge gap that bit v1.1.0.

**`docs/RELEASING.md` now has 7 Troubleshooting entries** (up from 4):
1. Dirty working tree
2. Strict SemVer violation
3. Preflight check failed
4. `git tag -s` secret key not available
5. `git tag -s` fails silently (gpg-agent)
6. CHANGELOG insertion failed (S5-07)
7. **pg peer dep not installed** (NEW — S7-04 error)
8. **release.sh fails mid-flight** (NEW — S7-05 lesson 1)
9. **sha256 sidecar doesn't match** (NEW — S7-05 lesson 2)

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

**S7-04 ✅ DONE** (release.sh pg sanity check). **S7-05 ✅ DONE** (RELEASING.md troubleshooting — determinism deferred). Next candidates:

- **S7-01** (self-hosted GitLab) OR **S7-02** (Postgres version matrix) — pick ONE for the next Sprint 7 ticket. Each is a full ticket's worth of work.
- **S7-03** (prerelease workflow) is LARGER — could be the Sprint 7 headline feature OR deferred to Sprint 8.
- **S7-05B** (tarball determinism via `tar --mtime=@0` + `gzip -n` + cross-platform wrapper) was carved out of S7-05 and remains open. Small ticket, can slot in alongside any of the above.

## Test inventory (after S7-04 + S7-05)

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
- tests/integration/sprint-5.sh: **97 bash assertions** (+3 from S7-04 sprint-7.sh preflight entry + S6-07 counts settling)
- tests/integration/sprint-6.sh: **37 bash assertions**
- tests/integration/sprint-7.sh: **19 bash assertions** (NEW — 6 [S7-A] + 6 [S7-B] + 7 [S7-Z])
- Total: **1511 passing checks** across **13 test layers** (1515 in docker+pg live mode)
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
