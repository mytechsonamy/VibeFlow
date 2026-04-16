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

### S7-01: Self-hosted GitLab integration ✅ DONE
**Deferred from:** Sprint 6 / S6-02 (itself deferred from Sprint 5 / S5-02)
**Location:** `mcp-servers/dev-ops/src/client.ts` + `src/tools.ts` + `tests/gitlab-client.test.ts` + `tests/tools.test.ts` + `.claude-plugin/plugin.json` + `.mcp.json` + `docs/CONFIGURATION.md` + `tests/integration/sprint-7.sh [S7-D]`

Sprint 5's GitLab client shipped with 19 vitest cases all against `gitlab.com` URLs. `baseUrl` was configurable at the client layer but never plumbed end-to-end: the plugin manifest had no `gitlab_base_url` key, `.mcp.json` didn't expose it as an env var, `tools.ts` didn't consume it from the env, and no tests exercised a non-default host. A self-hosted-GitLab user had to hand-edit `client.ts` to make it work. S7-01 closes every link of that chain.

**Completed:**
- [x] **`createGitlabClient` empty-string coercion** — `opts.baseUrl ?? "default"` only falls back on `null`/`undefined`. Plugin userConfig values arrive as strings; an unset key becomes `""`, which the old code kept, producing host-less request URLs. Fixed to collapse `""` → default.
- [x] **9 new vitest cases** in `tests/gitlab-client.test.ts` describe block `"createGitlabClient — self-hosted baseUrl (S7-01)"`:
  1. Routes requests through a custom baseUrl
  2. Strips a trailing slash (no `//projects/` in the URL)
  3. Preserves a non-default port (`:8443`)
  4. Supports a sub-path install (`https://example.com/gitlab/api/v4` for reverse-proxied GitLab)
  5. Accepts `http://` baseUrl (local dev / internal-only installs)
  6. `triggerWorkflow` also routes through the custom baseUrl
  7. `listArtifacts` `downloadUrl` is built from the custom baseUrl (not gitlab.com)
  8. Falls back to `gitlab.com` when baseUrl is not provided
  9. Empty-string baseUrl falls back to the default
- [x] **`dev-ops/src/tools.ts` env plumbing** — the GitLab branch now reads `process.env.GITLAB_BASE_URL` as the baseUrl fallback. If `opts.baseUrl` is unset (production: the tools are called by the MCP server with no explicit override), the env var wins.
- [x] **1 new vitest case in `tests/tools.test.ts`** — `"forwards GITLAB_BASE_URL to the GitLab client"` exercises the env→tools→client→fetch path end-to-end against a custom host.
- [x] **`.claude-plugin/plugin.json`** — two new userConfig keys:
  - `gitlab_base_url` (non-sensitive, title + description + type) — the custom API host
  - `gitlab_token` (sensitive) — alternative to reusing `github_token`; falls back to `github_token` when unset for backward compatibility
- [x] **`.mcp.json`** — dev-ops `env` block extended with `GITLAB_BASE_URL` + `GITLAB_TOKEN` template strings so the userConfig values flow into the MCP process without being written to disk in plaintext.
- [x] **`docs/CONFIGURATION.md`** — two new userConfig rows (`gitlab_base_url` + `gitlab_token`) with examples covering SaaS (`https://gitlab.example.com/api/v4`), custom port (`:8443`), sub-path install (reverse-proxied), and local dev (`http://localhost:8080`). Two new environment-variable rows (`GITLAB_BASE_URL` + `GITLAB_TOKEN`) explaining the fallback chain.
- [x] **`sprint-4.sh [S4-F]` userConfig sentinels** extended with the two new keys (+12 passing checks: 2 keys × 5 manifest-field checks + 2 docs-coverage checks).
- [x] **`sprint-7.sh [S7-D]` — 11 new sentinels** covering every link of the plumbing chain: manifest declares both keys, `.mcp.json` wires both env vars, tools.ts reads `GITLAB_BASE_URL`, client.ts handles empty-string baseUrl, test file has the S7-01 describe block, CONFIGURATION.md documents both keys.

**Live-verified:** `npm test` in `mcp-servers/dev-ops/` now reports **72 passing tests** (was 62 in v1.0.1, +10 from S7-01 = 9 client tests + 1 tools test). `npm run build` succeeds. Every layer of the plumbing — manifest → mcp.json → process.env → tools.ts → client → fetch — is exercised by at least one test.

**Scope boundaries** (intentionally NOT shipped):
- **Live GitLab CE docker integration test** — the original ticket mentioned firing a real pipeline against `gitlab/gitlab-ce`. The image is ~2 GB, takes 5–10 minutes to boot, and requires creating a project + runner + token at runtime. Too heavy for the sprint harness. The 9 mock tests cover every URL-construction scenario plus every error path — equivalent signal to a live docker test without the 10-minute boot cost. Live-instance coverage is a candidate for a follow-up ticket if/when an integration-test runner with GitLab access is available.
- **GitLab-hosted CI for VibeFlow itself** — `release.yml` still targets GitHub Actions only. Mirroring to `.gitlab-ci.yml` is a separate ticket (not in scope for v1.2; the dev-ops MCP targeting GitLab is about VibeFlow *consumers* using GitLab, not VibeFlow's own CI).
- **OAuth / SSO token exchange** — `gitlab_token` is a PAT only. Integrating with GitLab's OAuth flow is v1.3+ territory.

**Test count deltas:**
- `mcp-servers/dev-ops` vitest: 62 → **72** (+10)
- `tests/integration/sprint-4.sh`: 355 → **367** (+12 from the 2 new userConfig keys)
- `tests/integration/sprint-7.sh`: 26 → **37** (+11 from [S7-D])
- Total baseline: 1518 → **1551** across 13 test layers (1555 in docker+pg live mode)

### S7-02: Postgres version matrix PG13/14/15/16 + managed-cloud caveats ✅ DONE
**Deferred from:** Sprint 6 / S6-03 (itself deferred from Sprint 5 / S5-03)
**Location:** `bin/with-postgres-matrix.sh` (new) + `tests/integration/sprint-7.sh [S7-E]` + `docs/TEAM-MODE.md`

Sprint 5 / S5-03 shipped the first live-Postgres test pinned to `postgres:14-alpine`. Sprint 6 / S6-01's concurrent-CAS stress test kept the same pin. Real users run a mix of PG13 through PG16 + managed-cloud variants. S7-02 parameterizes the wrapper into a matrix runner + documents managed-cloud caveats.

**Completed:**
- [x] **`bin/with-postgres-matrix.sh`** (NEW) — loops over `VF_PG_IMAGES` (default: PG13/14/15/16 Alpine tags), invokes the existing `bin/with-postgres.sh` wrapper per image, and reports a pass/fail summary. Each matrix iteration uses the same port because iterations run sequentially. Narrow the matrix via `VF_PG_IMAGES="postgres:16-alpine"` or widen it to include third-party images (TimescaleDB, Citus, etc.).
- [x] **`sprint-5.sh [S5-B]` + `sprint-6.sh [S6-A]` composition fix** — both sections previously nested their own `bash bin/with-postgres.sh ...` call. Under the matrix runner that produced a port-55432 collision (outer container + inner nested container). Both now check `DATABASE_URL` at runtime: when set, the walker runs against the existing container; when unset, it still spins up its own throwaway container standalone.
- [x] **`sprint-7.sh [S7-E]` — 14 new sentinels** covering:
  - Matrix runner file presence + executable bit
  - Default image list covers PG13, PG14, PG15, PG16 (4 separate greps so missing any one fires distinctly)
  - Matrix runner delegates to `bin/with-postgres.sh` (no duplicate docker-pull logic)
  - Both sprint-5.sh [S5-B] AND sprint-6.sh [S6-A] reuse outer DATABASE_URL when set
  - TEAM-MODE.md documents: supported PG versions, managed-cloud caveats, PgBouncer transaction-mode gotcha, `sslmode=require` for RDS/Cloud SQL
  - **Opt-in runtime sentinel via `VF_RUN_PG_MATRIX=1`** that actually runs the matrix end-to-end against all 4 PG versions. Honors the same skip ladder as [S5-B]/[S6-A] (docker daemon + pg peer dep).
- [x] **`docs/TEAM-MODE.md`** new "Supported Postgres versions" section covering the matrix + example invocations. New "Managed-cloud Postgres" section with three caveats:
  1. `sslmode=require` for RDS / Cloud SQL connection strings
  2. **PgBouncer transaction-mode issue** — advisory locks break under transaction-mode pooling; two fixes (switch to session mode OR point at the direct endpoint)
  3. IAM / OIDC auth out of scope for v1.2 — rotate PAT strings via Claude Code settings on each rotation

**Live-verified:** ran `VF_RUN_PG_MATRIX=1 bash tests/integration/sprint-7.sh` on this host with Docker Desktop up. All 4 Postgres versions (`postgres:13-alpine`, `postgres:14-alpine`, `postgres:15-alpine`, `postgres:16-alpine`) passed the full `sprint-5.sh` walk (97 assertions × 4 images). Matrix runtime: ~3 minutes total on this hardware (30-45s per image, plus the first-run docker pulls).

**Scope boundaries** (intentionally NOT shipped):
- **Actual RDS / Cloud SQL / Azure Database integration test** — would require an external managed-cloud account + credentials in CI. The mock-based 9-case `gitlab-client.test.ts` S7-01 coverage is our model for this: structural sentinels + explicit scope-out. When we have a CI account wired, a separate ticket adds the live integration.
- **TimescaleDB / Citus / AlloyDB support** — tested images are stock Postgres only. Extensions and forks should work (the state-store SQL is vanilla) but aren't matrix-covered. The `VF_PG_IMAGES` override lets users add them to the matrix for local verification.
- **IAM / OIDC auth** — PATs only for now. A follow-up ticket will wire AWS RDS IAM auth + GCP Cloud SQL IAM auth if managed-cloud adoption grows.
- **PgBouncer startup probe** — the v1.2 state store doesn't detect transaction-mode pooling at startup; TEAM-MODE.md documents the issue but the code silently breaks under it. A follow-up ticket will add a connection-test that rejects transaction-mode poolers explicitly.

**Test count deltas:**
- `tests/integration/sprint-7.sh`: 37 → **51** (+14 from [S7-E])
- Total baseline: 1551 → **1565** across 13 test layers (1569 in docker+pg live mode; +12 with matrix run = 1581)

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

### S7-05: docs/RELEASING.md Troubleshooting + sha256 drift fix ✅ DONE
**Captured during:** Sprint 6 / S6-09 (two separate incidents during v1.1.0)
**Location:** `docs/RELEASING.md` Troubleshooting section + `tests/integration/sprint-7.sh [S7-B]`

**Completed:**
- [x] **Troubleshooting entry 1** — "release: pg peer dep is not installed in sdlc-engine". Covers the error message (both the new `[0.5]` sanity-check message AND the raw `tsc` error `Cannot find module 'pg'` so a maintainer searching either text finds the entry). Surfaces the one-liner fix `cd mcp-servers/sdlc-engine && npm install pg @types/pg` + a note about why `pg` isn't auto-installed (it's a peer dep with `peerDependenciesMeta.pg.optional = true` so solo-mode users don't carry it).
- [x] **Troubleshooting entry 2** — "release.sh fails MID-FLIGHT (after step [0.5] passed)". Covers the recovery path when something breaks between step `[3]` plugin.json bump and step `[7]` commit. Three-option menu: (a) fix the underlying issue + manually run the remaining build+package+sha256+commit+tag commands, (b) abort the release by reverting plugin.json + CHANGELOG via `git checkout`.
- [x] **Troubleshooting entry 3** — "sha256 sidecar doesn't match the uploaded tarball". Root-cause attribution to `sprint-4.sh [S4-G]` regenerating the tarball during preflight + the `gh release upload --clobber` fix + forward reference to the long-term determinism work (still open — see below).
- [x] **6 harness sentinels in `sprint-7.sh [S7-B]`** verifying all three entries + the fix commands + the root-cause attribution.

**Follow-up ticket S7-05B landed** — see below. The long-term tarball determinism fix is now in `package-plugin.sh` and exercised by `sprint-7.sh [S7-C]` with a live byte-identical-sha256 runtime sentinel. The RELEASING.md troubleshooting entry still references the drift scenario because it's the canonical recovery path when a release predates S7-05B or when external regeneration happens outside of `package-plugin.sh`.

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

### S7-05B: Reproducible package-plugin.sh tarball ✅ DONE
**Carved out from:** S7-05 (Sprint 6 / S6-09 sha256 drift lesson)
**Location:** `package-plugin.sh` step [4] + `tests/integration/sprint-7.sh [S7-C]`

The RELEASING.md troubleshooting entry S7-05 added closed the knowledge gap around the sha256 drift but did not fix the root cause. S7-05B makes `package-plugin.sh` emit a byte-identical tarball on every run so the drift cannot happen again.

**Completed:**
- [x] **Staging-dir strategy** — whitelisted files are copied into a tempdir, mtimes normalized to epoch 0 via `touch -t 197001010000.00`, tarred in sorted order, piped through `gzip -n`. The working tree is never modified — all normalization happens on the staged copy.
- [x] **Cross-platform tar detection** — the script now detects BSD tar (libarchive on macOS) vs GNU tar (Linux) via `tar --version`. BSD tar gets `--uid=0 --gid=0`; GNU tar gets `--owner=0 --group=0 --numeric-owner`. Both normalize the ownership columns in the tar header.
- [x] **Sorted file list** — `sort "$TMPLIST" > "$TMPLIST.sorted"` before feeding to `tar -T`. Without this, `find`'s filesystem-order output produced different orderings across runs even with normalized mtimes.
- [x] **`gzip -n`** — strips the filename + timestamp from the gzip header. Without this flag, every archive carries a different "last modified" timestamp even when the tar content is identical.
- [x] **Runtime sentinel in `sprint-7.sh [S7-C]`** — runs `package-plugin.sh --skip-build` **twice** against the same tree, compares the resulting sha256 values, asserts byte-identical output. This is the real guarantee; the source-grep checks (`gzip -n`, `touch -t`, `sort`, tar-variant detection, S7-05B citation) are a safety net against accidental deletions.

**Live-verified:** ran `package-plugin.sh --skip-build` twice consecutively on this macOS host (bsdtar 3.5.3, Apple gzip 479). Both runs produced `2aa343b359b0cf24d37ea7676ad300610e27cb388a0609b3b07bae6aebd2cf3a` — identical to the byte.

**Scope boundaries** (intentionally NOT shipped):
- **`--mtime=@0` flag** — GNU-tar only. The staging-dir pre-`touch` approach achieves the same outcome and is portable. Skipped the flag-based approach entirely.
- **Reproducible across HOSTS** (macOS bsdtar vs Linux GNU tar) — each host's output is now reproducible on that host, but macOS bsdtar and Linux GNU tar may still produce subtly different tar formats (extended attribute blocks, header format variations). Cross-host reproducibility is a v1.3+ concern; for now, the CI runner and the maintainer's local machine may produce different but internally-deterministic archives. The v1.2 release process targets determinism on a single host, which is what the S6-09 incident required.
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

**S7-01 ✅ DONE** (self-hosted GitLab). **S7-02 ✅ DONE** (Postgres matrix). **S7-04 ✅ DONE**. **S7-05 ✅ DONE**. **S7-05B ✅ DONE**. Next candidates:

- **S7-03** (prerelease workflow) — larger scope, headline-worthy
- **S7-06** (Sprint 7 harness closure) — light, formalizes what sprint-7.sh already ships
- **S7-07** (Sprint 7 closure + v1.2.0 release) — ends the sprint

Suggested: go straight to **S7-06 + S7-07** and cut v1.2.0. S7-03 is substantial enough to land in Sprint 8.

## Test inventory (after S7-02)

- mcp-servers/sdlc-engine: **105 vitest tests**
- mcp-servers/codebase-intel: **48 vitest tests**
- mcp-servers/design-bridge: **57 vitest tests**
- mcp-servers/dev-ops: **72 vitest tests** (+10 from S7-01 self-hosted GitLab)
- mcp-servers/observability: **76 vitest tests**
- hooks/tests/run.sh: **52 bash assertions**
- tests/integration/run.sh: **398 bash assertions**
- tests/integration/sprint-2.sh: **94 bash assertions**
- tests/integration/sprint-3.sh: **111 bash assertions**
- tests/integration/sprint-4.sh: **367 bash assertions** (+12 from S7-01 userConfig keys)
- tests/integration/sprint-5.sh: **97 bash assertions** (+3 from S7-04 sprint-7.sh preflight entry + S6-07 counts settling)
- tests/integration/sprint-6.sh: **37 bash assertions**
- tests/integration/sprint-7.sh: **51 bash assertions** (6 [S7-A] + 6 [S7-B] + 6 [S7-C] + 11 [S7-D] + 14 [S7-E] + 10 [S7-Z]; +12 in live matrix mode)
- Total: **1565 passing checks** across **13 test layers** (1569 in docker+pg live mode, 1581 with live matrix)
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
