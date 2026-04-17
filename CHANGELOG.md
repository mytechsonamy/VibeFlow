# Changelog

All notable changes to VibeFlow are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.3.0] — 2026-04-17

Third minor release. Sprint 8 delivered the long-deferred
prerelease / beta-channel workflow (originally scoped for Sprint 6
/ S6-06, twice punted to Sprint 7 / S7-03) plus two release-cycle
hardening items captured during the v1.2.0 cut. 14 new commits,
14 new [S8-C] sentinels, and the first release cut on a branch
other than `main` — exercising the prerelease-aware promotion
path end-to-end.

### Added

- **`bin/release.sh --prerelease`** — opt-in mode that accepts
  SemVer 2.0.0 prerelease identifiers (`1.3.0-rc.1`,
  `1.3.0-beta.2`, `1.3.0-alpha`, `1.3.0-dev`). Strict
  cross-validation refuses `--prerelease` + strict X.Y.Z and
  prerelease X.Y.Z-id without `--prerelease`, each with a
  specific remediation hint. (S8-01)
- **CHANGELOG `## Pre-releases` footer** — prerelease entries
  land under this section at the bottom of `CHANGELOG.md`
  instead of the top. Stable releases continue to become
  "latest"; prereleases never do. (S8-01)
- **Two-mode `insert_changelog_entry`** — second positional arg
  (`is_prerelease`) switches between prepending at the top
  (stable) and inserting under the footer (prerelease). Post-
  insert verify guards both paths. (S8-01)
- **Conditional `gh release create --prerelease` hint** —
  the Next-Steps block surfaces the `--prerelease` flag when the
  release mode is prerelease, plus a warning line about GitHub's
  "latest" semantics and package-manager default filtering.
  Dry-run mode also prints a preview of the hint block. (S8-01)
- **`VF_SKIP_GAUNTLET=1` escape hatch** — env-only (no CLI flag
  so a human can't mis-skip the gauntlet) knob that short-
  circuits `release.sh` step [2] when the S8-C runtime sentinels
  recursively invoke `release.sh` from inside its own preflight.
  Without this, running `release.sh` would infinitely recurse
  through sprint-8.sh. (S8-01)
- **`docs/RELEASING.md` Prereleases H2** — covers when-to-cut,
  command syntax, CHANGELOG convention, rc → stable promotion
  path, tag + tarball naming, GitHub release effect. (S8-01)
- **`tests/integration/sprint-8.sh [S8-C]`** — 13 new sentinels
  (9 static + 4 runtime dry-run probes) covering the full
  prerelease surface. Runtime opt-out via `VF_SKIP_S8C_RUNTIME=1`
  for environments with dirty trees or missing pg peer dep. (S8-01)

### Fixed

- **`tests/integration/sprint-7.sh [S7-C]` multi-tarball
  save/restore** — the determinism runtime sentinel used to save
  only the FIRST pre-existing tarball (`ls … | head -1`) but
  delete ALL of them (`rm -f vibeflow-plugin-*.tar.gz`). When
  the harness ran with multiple version tarballs on disk — exactly
  what happens right after a fresh `release.sh <newer>` produces
  a new tarball alongside a stale older one — the new release
  artifact got clobbered. This bit the v1.2.0 release during
  Sprint 7 / S7-07. Rewritten save + restore loops that iterate
  every match + matching `.sha256` sidecar; `mkdir -p` for the
  save destination. Six new `[S8-A]` regression sentinels
  including a runtime fixture test that seeds two fake tarballs
  and verifies both survive. (S8-02)

### Changed

- **`.github/workflows/release.yml` preflight** — now runs
  `sprint-6.sh` + `sprint-7.sh` + `sprint-8.sh` alongside the
  existing `sprint-5.sh` step. CI release runs exercise the full
  14-layer gauntlet. `sprint-6.sh [S6-A]` concurrent-CAS walk
  and `[S6-B]` next-build gate both skip in CI (no docker-in-
  docker, no Next installed on fresh runners) via the existing
  opt-out env vars. (S8-03)
- **Baseline test count** — **1585 → 1599 offline / 1589 → 1603
  live / 1601 → 1615** with `VF_RUN_PG_MATRIX=1`. New `sprint-
  8.sh` layer contributes **33 assertions** (6 [S8-A] + 6 [S8-B] +
  13 [S8-C] + 8 [S8-Z]).

### Breaking changes

None. `bin/release.sh <ver>` continues to reject prerelease
identifiers without `--prerelease` — a v1.2 consumer that doesn't
use prereleases sees no behavioural change.

### Migration

N/A. Existing stable-release muscle memory is untouched:

```bash
bash bin/release.sh 1.4.0   # same as before — stable release
```

For prereleases, opt in explicitly:

```bash
bash bin/release.sh 1.4.0-rc.1 --prerelease
```

## [1.2.0] — 2026-04-16

Second minor release. Sprint 7 delivered v1.1's deferrals
(self-hosted GitLab, Postgres version matrix) + captured two
release-workflow lessons from the v1.1.0 cut (the "pg missing
mid-release" incident + the sha256 sidecar drift). All shipped
tickets tighten release discipline and expand the supported
infrastructure surface.

**No breaking changes.** Drop-in replacement for v1.1.0.

### Added

- **Self-hosted GitLab support — `createGitlabClient` plumbed
  end-to-end.** Sprint 5 / S5-02 shipped the client with a
  configurable `baseUrl` option, but the plugin manifest had no
  `gitlab_base_url` key, `.mcp.json` did not expose it as an env
  var, `dev-ops/src/tools.ts` never consumed it from env, and the
  19 vitest cases all hit gitlab.com. A self-hosted-GitLab user had
  to hand-edit `client.ts` to make it work. S7-01 closes every link
  of the chain: new `gitlab_base_url` + `gitlab_token` userConfig
  keys, `.mcp.json` plumbs both, `tools.ts` reads
  `process.env.GITLAB_BASE_URL` as the baseUrl fallback,
  `client.ts` coerces empty-string `baseUrl` to the default,
  9 new vitest cases + 1 tools-layer case, `docs/CONFIGURATION.md`
  gains four new rows with worked examples (SaaS, custom port,
  sub-path install, local dev). (S7-01)
- **Postgres version matrix — PG13 / PG14 / PG15 / PG16.** Sprint
  5 / S5-03 pinned the first live-Postgres test to
  `postgres:14-alpine`; Sprint 6 / S6-01 kept the pin. S7-02 ships
  `bin/with-postgres-matrix.sh` which loops `VF_PG_IMAGES` (default:
  PG13 through PG16 Alpine) and invokes the existing
  `bin/with-postgres.sh` wrapper per image. `sprint-5.sh [S5-B]`
  and `sprint-6.sh [S6-A]` taught to reuse an outer `DATABASE_URL`
  so nested wrapper calls don't collide on port 55432. Opt-in
  runtime sentinel via `VF_RUN_PG_MATRIX=1` in `sprint-7.sh [S7-E]`
  runs the full matrix end-to-end. Live-verified: all 4 PG versions
  pass the full sprint-5 walk. `docs/TEAM-MODE.md` gains a
  "Supported Postgres versions" section + a "Managed-cloud Postgres
  (AWS RDS, GCP Cloud SQL, Azure)" section covering
  `sslmode=require`, the PgBouncer transaction-mode advisory-lock
  gotcha, and IAM-auth scope. (S7-02)
- **`bin/release.sh` step [0.5] — pg peer-dep sanity check.** The
  v1.1.0 release failed mid-flight at step [5] because `pg` had
  been uninstalled during S6-01 testing and `tsc` couldn't find
  the module. plugin.json had already been bumped, leaving the
  tree in a half-released state. The new step [0.5] probes both
  `mcp-servers/sdlc-engine/node_modules/pg` AND
  `node_modules/@types/pg` before any tree mutation and surfaces
  the fix command in the error output. (S7-04)
- **`docs/RELEASING.md` Troubleshooting expanded from 6 to 9
  entries.** Three new entries capture the v1.1.0 release lessons:
  "pg peer dep is not installed", "release.sh fails MID-FLIGHT",
  and "sha256 sidecar doesn't match the uploaded tarball" (with
  the `gh release upload --clobber` recovery). (S7-05)
- **Reproducible `package-plugin.sh` tarballs.** The v1.1.0 sha256
  drift incident had a root cause: `tar -cz` bakes timestamps into
  the gzip header, and `find`'s filesystem-order output produced
  different tar orderings across runs. S7-05B rewrites step [4] to
  stage files into a tempdir, normalize mtimes to epoch 0 via
  `touch -t 197001010000.00`, sort the file list, detect BSD-vs-GNU
  tar for ownership flags, and pipe uncompressed tar through
  `gzip -n`. Two consecutive runs now produce byte-identical
  archives. `sprint-7.sh [S7-C]` includes a runtime sentinel that
  actually runs packaging twice and asserts sha256 equality.
  (S7-05B)
- **`tests/integration/sprint-7.sh`** — new 51-assertion harness
  covering all five Sprint 7 shipped tickets plus a closing
  [S7-Z] self-audit that mirrors sprint-6.sh's [S6-Z]. (S7-01 /
  S7-02 / S7-04 / S7-05 / S7-05B / S7-06)

### Changed

- **`bin/release.sh` preflight gauntlet** now runs 13 harnesses
  (was 12 in v1.1.0) — sprint-7.sh added alongside the existing
  layers.
- **`tests/integration/sprint-4.sh [S4-F]` userConfig key list**
  extended with `gitlab_token` + `gitlab_base_url` (+12
  assertions).
- **`tests/integration/sprint-4.sh [S4-H]` EXPECTED_PLUGIN_VERSION**
  bumped 1.1.0 → 1.2.0 via the parameterized variable introduced
  in S5-07.
- **`mcp-servers/dev-ops/src/client.ts`** — `createGitlabClient`
  now treats empty-string `baseUrl` the same as unset (userConfig
  values arrive as `""` for unset keys).

### Fixed

- **sha256 sidecar drift during release** — see S7-05B under Added.
  The v1.1.0 release briefly uploaded a sidecar that didn't match
  the tarball; the root cause is fixed in v1.2.0 so future releases
  produce byte-identical tarballs across runs on the same host.
- **Nested `with-postgres.sh` port collision** — sprint-5.sh
  [S5-B] and sprint-6.sh [S6-A] used to always invoke their own
  wrapper. Under the S7-02 matrix runner that caused a port-55432
  collision. Both sections now detect `DATABASE_URL` from an outer
  context and reuse the running container.

### Test baseline growth

| Version | Test layers | Baseline checks | Bonus suites |
|---------|-------------|-----------------|--------------|
| v1.0.0  | 10          | 1255            | demo-app (45) |
| v1.0.1  | 11          | 1445            | demo-app (45) + nextjs-demo (41) |
| v1.1.0  | 12          | 1489            | demo-app (45) + nextjs-demo (66) |
| v1.2.0  | **13**      | **1565**        | demo-app (45) + nextjs-demo (66) |

76-check growth v1.1.0 → v1.2.0 split:
- `sprint-7.sh` (new harness): 51 assertions across
  [S7-A/B/C/D/E/Z]
- `sprint-4.sh`: 355 → 367 (+12 from the two new userConfig keys)
- `sprint-5.sh`: 94 → 97 (+3 from preflight list + counter
  settling)
- `dev-ops` vitest: 62 → 72 (+10 from S7-01 self-hosted GitLab
  coverage)

Opt-in `VF_RUN_PG_MATRIX=1` adds +12 assertions for the 4-image
live matrix run → **1581** total.

### Breaking changes

None.

### Migration

N/A — v1.2.0 is a drop-in replacement for v1.1.0. New optional
env vars default to "do nothing":
- `VF_RUN_PG_MATRIX=1` — opt IN to the 4-image Postgres matrix
- `VF_PG_IMAGES` — override the default matrix image list
- `GITLAB_BASE_URL` — self-hosted GitLab API URL (unset = gitlab.com)
- `GITLAB_TOKEN` — GitLab PAT (unset = fall back to `GITHUB_TOKEN`)

Self-hosted GitLab users can now set `userConfig.gitlab_base_url`
directly in Claude Code plugin settings — no more hand-editing
`client.ts`.

### Distribution

- **Tarball**: `./package-plugin.sh` produces
  `vibeflow-plugin-1.2.0.tar.gz`. **Now byte-reproducible** across
  consecutive runs on the same host thanks to S7-05B.
- **Local install**: `claude --plugin-dir ~/Projects/VibeFlow`
- **Marketplace**: `claude plugin install vibeflow@vibeflow-marketplace`
- **Tag/release push**: user-gated. v1.2.0 uses the annotated
  fall-back (no `user.signingkey` on the release host).

### Documentation

- [Releasing](./docs/RELEASING.md) — now 9 troubleshooting entries
- [Team Mode](./docs/TEAM-MODE.md) — new "Supported Postgres
  versions" + "Managed-cloud Postgres" sections
- [Configuration](./docs/CONFIGURATION.md) — four new rows
  (`gitlab_base_url`, `gitlab_token`, `GITLAB_BASE_URL`,
  `GITLAB_TOKEN`)

[1.2.0]: https://github.com/mytechsonamy/VibeFlow/releases/tag/v1.2.0

## [1.1.0] — 2026-04-16

First minor release after v1.0. Sprint 6 picks up items deferred
from Sprint 5's scope decisions + the one bug surfaced during v1.0.1
(the BSD awk silent CHANGELOG break). No new SDLC skills — Sprint 6
is hardening + v1.1 polish. Real skill work lands in v1.2+.

**No breaking changes.** Drop-in replacement for v1.0.1.

### Added

- **Concurrent-advance CAS stress test on real PostgreSQL** —
  `tests/integration/sprint-6.sh [S6-A]` spins up 5 engine
  processes under `bin/with-postgres.sh` and races them all on the
  same `sdlc_advance_phase` call. Asserts exactly 1 winner + 4
  losers + final state consistency. Sprint 1's 14 `FakePool` unit
  tests covered the CAS logic at the unit layer; Sprint 5's `[S5-B]`
  walked one fresh engine against a real Postgres; neither
  exercised concurrent writers against the real wire protocol.
  `[S6-A]` closes that gap. The advisory lock + `FOR UPDATE` row
  lock serializes the writes so tightly that the revision CAS
  never has to fire — losers hit the phase validator with "Cannot
  transition to the same phase (DESIGN)" instead. (S6-01)
- **Next.js demo `"use client"` component surface** —
  `examples/nextjs-demo/components/rating-picker.tsx` is the first
  client component in the demo, backed by pure helpers in
  `lib/rating.ts` (`computeDisplay`, `clampRating`, `renderStars`,
  `isValidSubmittedRating`). 25 new vitest cases cover every branch
  in the node environment without mounting React. The detail page
  (`app/products/[id]/page.tsx`) imports the picker — this is where
  the RSC/client boundary runs. Total `examples/nextjs-demo` vitest
  count: 41 → 66. (S6-04)
- **Optional `next build` gate in the harness** —
  `sprint-6.sh [S6-B]` auto-runs `npm run build` in the Next.js demo
  when `examples/nextjs-demo/node_modules/next` is present and
  `VF_SKIP_NEXT_BUILD=1` is unset. Produces a real production build
  alongside the vitest suite, catching type/lint regressions the
  pure-logic tests cannot. Skipped gracefully when Next is not
  installed. (S6-04)
- **GPG-signed release tags** — `bin/release.sh [7]` teaches the
  release workflow to sign the tag when a key is configured, with
  a three-step graceful fall-back ladder:
  1. `VF_SKIP_GPG_SIGN=1` → annotated tag (opt-out)
  2. `user.signingkey` unset → annotated tag + configuration hint
  3. `git tag -s` fails at runtime → half-tag cleanup + annotated
     fall-back + `WARN` line surfacing the gpg error
  `TAG_MODE` is recorded and surfaced in the "Release prepared
  locally" hint block. Dry-run prints the probe result without
  creating anything. (S6-05)
- **`docs/RELEASING.md`** — new 210+ line end-to-end release
  walkthrough. Covers `bin/release.sh`'s seven steps, the tag
  signing ladder, one-time GPG key setup, `git tag -v` verification,
  a 5-step Quickstart checklist, a three-scenario Rollback guide,
  and a troubleshooting table with 5 common errors. (S6-05)
- **`tests/integration/sprint-6.sh`** — new 37-assertion harness
  covering S6-01 ([S6-A]), S6-04 ([S6-B]), S6-05 ([S6-C]), and the
  S6-08 self-audit ([S6-Z]). Skip gracefully when docker / pg /
  next are not installed. (S6-01 / S6-04 / S6-05 / S6-08)
- **`sprint-6.sh [S6-Z]` harness self-audit** — 8 sentinels that
  catch regressions a future refactor might silently introduce:
  section header presence, executable bit, release.sh preflight
  reference, shebang, `set -uo pipefail` discipline. (S6-08)

### Fixed

- **`bin/release.sh` CHANGELOG insertion — BSD awk portability.**
  The v1.0.0 implementation passed the new version entry through
  `awk -v entry="$NEW_ENTRY"` which BSD awk on macOS rejected with a
  "newline in string" runtime error on multiline values. awk exited
  non-zero, the `&& mv tmp CHANGELOG.md` short-circuited, and
  `release.sh` reported success even though CHANGELOG.md was never
  updated. First run on the v1.0.1 release session produced a
  commit with ONLY `plugin.json` bumped — a silent broken-release
  path. The insertion step is now a standalone
  `insert_changelog_entry()` helper using portable
  `head`/`tail`/`grep` + post-insertion verification. (v1.0.1
  shipped the initial patch; v1.1.0 / S6-07 adds the runtime-sentinel
  that catches this bug class at build time.)
- **`release.sh --test-changelog-insert <version>`** — new mode
  that runs ONLY the CHANGELOG insertion step against CHANGELOG.md
  in `cwd`, skipping every other release step. Called from
  isolated tempdir fixtures by `sprint-5.sh [S5-C]` with happy-path
  + header-less negative path + source-grep sentinels. Closes the
  runtime-verification gap that let the BSD awk bug slip past
  every static source-grep check. (S6-07)
- **`sprint-5.sh [S5-B]` and `sprint-6.sh [S6-A]` docker-daemon
  skip probe.** The old `command -v docker` check only verified
  the binary, not the daemon. macOS contributors with docker
  installed but Docker Desktop not running would see the walks
  fire and fail instead of skip. Added `docker info >/dev/null`
  to both skip ladders. (S6-01)

### Changed

- **`bin/release.sh` preflight gauntlet** now runs
  `tests/integration/sprint-6.sh` alongside sprint-5 and earlier
  harnesses. 11 total preflight commands.
- **`package-plugin.sh` whitelist** extended with
  `examples/nextjs-demo/components/` so the new client component
  ships in the tarball.
- **`tests/integration/sprint-4.sh [S4-H]` expected plugin version**
  parameterized via `EXPECTED_PLUGIN_VERSION` and bumped to
  `1.1.0`. Future releases bump this single variable.

### Test baseline growth

| Version | Test layers | Baseline checks | Bonus suites |
|---------|-------------|-----------------|--------------|
| v1.0.0  | 10          | 1255            | demo-app (45) |
| v1.0.1  | 11 (+ sprint-5.sh) | 1445 | demo-app (45) + nextjs-demo (41) |
| v1.1.0  | **12** (+ sprint-6.sh) | **1489** | demo-app (45) + nextjs-demo (66) |

44-check growth v1.0.1 → v1.1.0 split:
- `sprint-6.sh` (new harness): 37 assertions — [S6-A] 5 + [S6-B] 16
  + [S6-C] 12 + [S6-Z] 8 (some counted with different prerequisites
  — totals reflect the normal-dev path; live mode with docker + pg
  adds 4 more for [S6-A])
- `sprint-5.sh`: 93 → 94 (+1 for the new sprint-6.sh preflight
  entry in [S5-C])
- `nextjs-demo` vitest: 41 → 66 (+25 rating helpers in tests/rating.test.ts)

### Breaking changes

None.

### Migration

N/A — v1.1.0 is a drop-in replacement for v1.0.1. Existing
`ci_provider: github` and `ci_provider: gitlab` configurations are
unchanged. `VIBEFLOW_POSTGRES_URL` team-mode setups are unchanged.

New optional environment variables (all default to "do nothing"):
- `VF_SKIP_GPG_SIGN=1` — opt out of tag signing in `bin/release.sh`
- `VF_SKIP_NEXT_BUILD=1` — opt out of the optional `next build`
  step in `sprint-6.sh [S6-B]`

### Distribution

- **Tarball**: `./package-plugin.sh` produces
  `vibeflow-plugin-1.1.0.tar.gz` (grown slightly by the new Next.js
  demo client component + `docs/RELEASING.md`).
- **Local install**: `claude --plugin-dir ~/Projects/VibeFlow`
- **Marketplace**: `claude plugin install vibeflow@vibeflow-marketplace`
- **Tag/release push**: user-gated — `bin/release.sh` stops at a
  local commit + local tag; `git push` + `gh release create` require
  explicit authorization. The signing probe is purely opt-in — all
  maintainers can still cut a release without configuring a key.

### Documentation

- [Releasing](./docs/RELEASING.md) — new
- [Getting Started](./docs/GETTING-STARTED.md)
- [Next.js Demo Walkthrough](./examples/nextjs-demo/docs/NEXTJS-DEMO-WALKTHROUGH.md) — updated for `"use client"` boundary + `next build` gate
- [Demo Walkthrough](./examples/demo-app/docs/DEMO-WALKTHROUGH.md) — unchanged

[1.1.0]: https://github.com/mytechsonamy/VibeFlow/releases/tag/v1.1.0

## [1.0.1] — 2026-04-14

Post-v1.0 maintenance release. Closes the forward-looking stubs that
landed in v1.0.0, adds real-world coverage the original release did
not have time for, and ships the marketplace-publish workflow so
future v1.0.x releases are reproducible without hand surgery.

**No breaking changes.** No new SDLC skills — this sprint is
maintenance + missing-piece closure. Skill work returns in v1.1
(Sprint 6+).

### Added

- **GitLab CI provider** — `dev-ops` MCP server now supports
  `ci_provider: gitlab` end-to-end. New `createGitlabClient` in
  `mcp-servers/dev-ops/src/client.ts` (155 LoC) with `PRIVATE-TOKEN`
  auth, status normalization (10+ GitLab states → 3-value
  `queued`/`in_progress`/`completed`), URL-encoded `namespace/name`
  project paths, `artifacts_expire_at` expiry detection, and lazy
  construction parity with the GitHub client. Token resolution order:
  explicit → `GITLAB_TOKEN` → `GITHUB_TOKEN`. The "not yet
  implemented" stub is removed from `tools.ts`. 19 new vitest cases
  in `tests/gitlab-client.test.ts`. (S5-02)
- **Live PostgreSQL team-mode integration test** — new
  `bin/with-postgres.sh` wrapper spins up a throwaway
  `postgres:14-alpine` container, exports `DATABASE_URL` +
  `VIBEFLOW_POSTGRES_URL`, and tears down on exit/error/interrupt.
  Configurable via `VF_PG_*` env vars. `sprint-5.sh [S5-B]` drives
  the engine through a phase-1-writes / phase-2-read-in-fresh-process
  walk against the real `pg` wire protocol — the hand-rolled
  `FakePool` unit tests from Sprint 1 never exercised this path. `pg`
  moved from `optionalDependencies` to regular `dependencies` in
  `sdlc-engine/package.json` (dynamic import path preserved, so
  solo-mode users are not forced to carry it). Gracefully skips when
  docker / pg / `VF_SKIP_LIVE_POSTGRES=1`. (S5-03)
- **`bin/release.sh`** — 7-step release-prep script (working-tree
  cleanliness → strict SemVer validation → preflight gauntlet across
  all 11 layers → `plugin.json` bump → CHANGELOG stub insertion →
  `build-all.sh` + `package-plugin.sh` → sha256 manifest → local
  commit + annotated tag). **Does not push** — tag/release push is
  user-gated (same discipline as v1.0.0 in Sprint 4 / S4-07).
  `--check-clean` exit-code-only mode for CI / harness use.
  `--dry-run` walks the pipeline without writing any files. Strict
  SemVer (rejects `1.0.1-beta` and build-metadata suffixes). (S5-04)
- **`.github/workflows/release.yml`** — tag-push-triggered GitHub
  Actions workflow (`v*.*.*`). Rebuilds dists, runs the full test
  gauntlet with `VF_SKIP_LIVE_POSTGRES=1`, packages the tarball,
  verifies `plugin.json` version matches the tag, generates sha256,
  extracts release notes from CHANGELOG via awk, and uploads via
  `softprops/action-gh-release@v2`. (S5-04)
- **Second demo — `examples/nextjs-demo/`** — parallel to the
  existing TypeScript-only demo. Next.js 14 app-router project with
  two React Server Component pages, one `"use server"` action, and
  14 numbered requirements across `PROD-*` / `REV-*` / `ACT-*` /
  `PAGE-*` families. 41 vitest tests (14 catalog + 18 reviews + 9
  action) covering every branch without booting Next.js. Pre-baked
  VibeFlow artifacts: `prd-quality-report.md` (APPROVED, testability
  86), `scenario-set.md` (14 scenarios), `test-strategy.md`,
  `release-decision.md` (**GO 91/100**). `docs/NEXTJS-DEMO-WALKTHROUGH.md`
  parallels the existing demo's walkthrough. `package-plugin.sh`
  whitelist extended to ship the new demo; `.next/` added to the
  `find -prune` list so a future `next build` does not leak build
  artifacts into the tarball. (S5-05)
- **Bug #13 cross-process reproducer in the platform baseline** —
  `tests/integration/run.sh [4]` now drives two engine invocations
  against the same `state.db`: a writer (REQUIREMENTS → DESIGN) and
  a fresh reader that calls `sdlc_get_state`. Before the Sprint 4
  fix to `engine.getOrInit()` this path crashed with "revision must
  increment by exactly 1". The new reproducer fires exactly the two
  expected failures when the fix is reverted — gold-standard
  verified. (S5-01) The same reproducer is **mirrored in
  `sprint-5.sh [S5-E]`** so contributors who only run the Sprint 5
  harness still catch the regression. (S5-06)

### Changed

- **`mcp-servers/sdlc-engine/package.json`** — `pg` moved from
  `optionalDependencies` to `dependencies` so team-mode users do not
  need to manually install the peer. Solo-mode users are still
  unaffected (`openStore` dynamic-imports pg only when team mode is
  requested).
- **`package-plugin.sh`** — whitelist extended to include
  `examples/nextjs-demo/{app,lib,actions,docs,tests,.vibeflow/reports}`
  plus the standard manifest files. `find -prune` list grew to
  include `.next/` alongside `node_modules`, `__pycache__`, `.git`.
- **`docs/CONFIGURATION.md`** — `ci_provider` row updated to note
  GitLab is now implemented (v1.0.1 / Sprint 5 / S5-02).

### Fixed

- **`bin/release.sh` CHANGELOG insertion — BSD awk portability.**
  The original v1.0.0 implementation passed the new version entry
  through `awk -v entry="$NEW_ENTRY"` which BSD awk on macOS rejects
  with a "newline in string" runtime error whenever the value
  contains embedded newlines. awk then exited non-zero, the
  `&& mv tmp CHANGELOG.md` short-circuited, and release.sh reported
  success even though CHANGELOG.md was never updated — the v1.0.1
  release commit would have landed with a stale changelog. The
  insertion step is rewritten to use `head`/`tail`/`grep` (POSIX,
  no multiline-variable gotchas) with a post-insertion verification
  step that refuses to continue if the new version header is not at
  the top of CHANGELOG.md after the rewrite.

### Test baseline growth

| Version | Test layers | Baseline checks | Bonus suites |
|---------|-------------|-----------------|--------------|
| v1.0.0  | 10          | 1255            | demo-app (45) |
| v1.0.1  | **11** (+ `sprint-5.sh`) | **1445** | demo-app (45) + nextjs-demo (41) |

190-check growth split:
- `sprint-5.sh` (new harness): 87 assertions — [S5-A] GitLab 23 +
  [S5-B] Postgres 4 + [S5-C] release 14 + [S5-D] Next.js 41 +
  [S5-E] Bug #13 mirror 5
- `run.sh`: +4 (Bug #13 cross-process reproducer)
- `dev-ops` vitest: +19 (GitLab client)
- The rest of the delta reflects the test inventory refresh captured
  across the 5 MCP servers between Sprint 4 and Sprint 5.

### Breaking changes

None.

### Migration

N/A — v1.0.1 is a drop-in replacement for v1.0.0. Users of
`ci_provider: github` see no change. Users setting
`ci_provider: gitlab` who previously hit the "not yet implemented"
error can now configure a real GitLab project via the standard
`userConfig` key.

### Distribution

- **Tarball**: `./package-plugin.sh` produces
  `vibeflow-plugin-1.0.1.tar.gz` (grown by the `nextjs-demo` directory).
- **Local install**: `claude --plugin-dir ~/Projects/VibeFlow`
- **Marketplace**: `claude plugin install vibeflow@vibeflow-marketplace`
- **Tag/release push**: user-gated (`bin/release.sh` stops at a
  local commit + local annotated tag; `git push` + `gh release create`
  require explicit authorization).

### Documentation

- [Next.js Demo Walkthrough](./examples/nextjs-demo/docs/NEXTJS-DEMO-WALKTHROUGH.md) — new
- [Getting Started](./docs/GETTING-STARTED.md)
- [Demo Walkthrough](./examples/demo-app/docs/DEMO-WALKTHROUGH.md) — TypeScript-only, unchanged

[1.0.1]: https://github.com/mustiyildirim/vibeflow/releases/tag/v1.0.1

---

## [1.0.0] — 2026-04-13

First public release. Production-ready Claude Code plugin orchestrating
the full SDLC through multi-AI consensus and truth validation.

### Highlights

- **5 MCP servers** with stdio JSON-RPC interfaces, all built and shipped pre-compiled
- **26 skills** across 4 layers (L0 Truth Creation → L3 Truth Evolution)
- **7 hooks** with shared `_lib.sh` defensive helper surface
- **7 canonical pipelines** covering new feature → release decision → production feedback
- **8 user-facing docs** + a working sample project
- **1255 passing checks across 10 test layers** (5 vitest suites, 1 hook test runner, 4 integration harness scripts) — every commit since Sprint 1 has cleared this baseline

### Added — Sprint 1 (Foundations)

- **`sdlc-engine` MCP server** — authoritative SQLite/PostgreSQL state store for SDLC phase tracking, consensus verdicts, and satisfied criteria. 104 vitest cases.
- **7-phase SDLC model** — REQUIREMENTS → DESIGN → ARCHITECTURE → PLANNING → DEVELOPMENT → TESTING → DEPLOYMENT
- **Phase advance gates** with entry criteria + consensus requirements
- **Domain quality thresholds** — financial/healthcare/e-commerce/general with built-in tighten-only override discipline
- **7 hook scripts** — commit-guard, load-sdlc-context, post-edit, trigger-ai-review, test-optimizer, compact-recovery, consensus-aggregator
- **Shared `_lib.sh`** helper surface — defensive `vf_*` helpers used by every hook
- **Bash 3.2 compatibility** — works on default macOS shell without associative arrays
- **Initial integration harness** — 21 plug-in manifest + hooks.json + .mcp.json + sdlc-engine smoke checks

### Added — Sprint 2 (Truth Foundation)

- **`codebase-intel` MCP server** — per-call code analysis (structure, dependency graph, hotspots, tech debt scan). 46 vitest cases.
- **`design-bridge` MCP server** — Figma REST bridge with lazy client construction. 4 tools: fetch / extract tokens / generate styles / compare. 54 vitest cases.
- **L1 Truth Validation skills** (7 skills): architecture-validator, component-test-writer, contract-test-writer, business-rule-validator, test-data-manager, invariant-formalizer, checklist-generator
- **`test-data-manager` deterministic generator contract** — same seed → same output, no `Math.random` / `Date.now`
- **Cross-skill reference coherence** — `business-rule-validator` and `invariant-formalizer` cross-check via `test-data-manager` factories
- **`io-standard.md`** — single-source-of-truth for skill input/output naming
- **Sprint-2 integration harness** — 94 assertions covering L1 skill inventory + io-standard output coherence + cross-skill references + gate contract declarations + design-bridge round-trip
- **Bug #3 fixed** — sdlc-engine race condition under concurrent SQLite writers
- **Bug #4 fixed** — phase-index off-by-one in commit-guard
- **Bug #7 fixed** — design-bridge FIGMA_TOKEN now flows from `userConfig` instead of being hardcoded; integration harness has a regression sentinel

### Added — Sprint 3 (Execution + Decision)

- **`dev-ops` MCP server** — GitHub Actions bridge for CI orchestration. 5 tools: trigger / status / artifacts / deploy / rollback. Lazy GitHub client. 41 vitest cases.
- **`observability` MCP server** — vitest/jest/playwright reporter parser, flakiness scoring, perf trends, health dashboard. 76 vitest cases.
- **L2 Truth Execution skills** (12 skills): e2e-test-writer, uat-executor, test-result-analyzer, regression-test-runner, test-priority-engine, mutation-test-runner, environment-orchestrator, chaos-injector, cross-run-consistency, coverage-analyzer, observability-analyzer, visual-ai-analyzer
- **L3 Truth Evolution skills** (2 skills): learning-loop-engine (3 modes: test-history / production-feedback / drift-analysis), decision-recommender (4-invariant gate + structured option packages)
- **Financial-domain-only L1 skill**: reconciliation-simulator with 6 canonical ledger invariants + 6 adversarial concurrency patterns
- **Skill failure-class taxonomies** with fixed walk order and `UNCLASSIFIED-*` fallback patterns (test-result-analyzer, observability-analyzer, visual-ai-analyzer, decision-recommender)
- **Anti-AI-confidence stance** — `decision-recommender` explicitly refuses to ship a single weighted composite score, escapes to `human-judgment-needed` when confidence < 0.7
- **`reconciliation-simulator` cooperative scheduler** — deterministic interleaving for "every step is checked, not just endpoints"
- **Sprint-3 integration harness** — 111 assertions covering L1/L2/L3 skill inventory + cross-skill wiring + gate contracts + PIPELINE coverage + dev-ops/observability MCP sanity

### Added — Sprint 4 (Polish + Distribution)

- **MCP server coverage thresholds** — every server enforces 80/80/80/80 (statements/lines/functions/branches) via vitest.config.ts. observability gained 21 targeted edge-branch tests to lift parsers.ts from 54.32% to 91.66% branch coverage.
- **Hook hardening** — 7 hooks production-hardened (commit-guard Merge/Revert + command-substitution passthrough, post-edit 5s debounce + expanded skip list, trigger-ai-review 5-min rate limit, test-optimizer mtime-tagged cache, compact-recovery 4-point integrity check, consensus-aggregator 600s timeout force-finalize with APPROVED→NEEDS_REVISION demotion, load-sdlc-context degraded note). Hook test count 26 → 50 (+24 assertions).
- **Demo project** — `examples/demo-app/` showcases full VibeFlow loop against an e-commerce product catalog. 394 LoC of TypeScript across 3 modules (catalog/pricing/inventory), 45 vitest cases, 4 pre-baked VibeFlow artifacts (prd-quality-report, scenario-set, test-strategy, release-decision GO 92/100), 7-section walkthrough guide.
- **8 user docs** — GETTING-STARTED, CONFIGURATION, SKILLS-REFERENCE, PIPELINES, HOOKS, MCP-SERVERS, TROUBLESHOOTING, TEAM-MODE. Cross-referenced from a single entry point with sentinel-guarded inbound links.
- **Plugin manifest finalized** — `.claude-plugin/plugin.json` v1.0.0 with structured `repository` + `homepage` + `bugs` URLs + `ci_provider` userConfig key wired end-to-end through `.mcp.json` + dev-ops MCP `process.env.CI_PROVIDER` (defaults to github, raises loud `CiConfigError` on `gitlab` not-yet-implemented or unknown values).
- **`build-all.sh`** — single script to rebuild all 5 MCP server dist/ directories. `--check` mode for CI verification.
- **`package-plugin.sh`** — whitelist-based tarball builder with forbidden-path scan + post-archive verification + sanity caps. Produces `vibeflow-plugin-1.0.0.tar.gz` (392K, 214 files).
- **MCP server dist/ tracked in git** — `.gitignore` negation `!mcp-servers/*/dist/` so end users running `claude plugin install` get working JS without a build step. Source maps stay ignored.
- **Sprint-4 integration harness** — 285 assertions across 8 sections (S4-A through S4-H): MCP coverage config + actual coverage runs + test count floors + io-standard cross-reference + demo-app presence + user docs + plugin manifest validation + ci_provider end-to-end wiring + plugin packaging + dist tracking + tarball verification.
- **`CHANGELOG.md`** — this file.

### Test baseline growth

| Sprint | Test layers | Baseline checks |
|--------|-------------|-----------------|
| Sprint 1 | 3 (vitest, hooks, integration) | 137 |
| Sprint 2 | 5 (+ 2 new MCPs, + sprint-2 harness) | ~410 |
| Sprint 3 | 9 (+ 2 new MCPs, + sprint-3 harness) | 921 |
| Sprint 4 | 10 (+ sprint-4 harness) | **1255** |

Plus a 45-test demo-app vitest suite that ships with the plugin but is not counted in the baseline (it's a consumer of VibeFlow, not part of it).

### Bug fixes (12/12 MyVibe bugs closed)

All 12 bugs tracked in `ROADMAP.md`'s legacy MyVibe Framework backlog are
fixed and sentinel-guarded:

- **Bug #1** sdlc-engine SQLite race — Sprint 1
- **Bug #2** phase index off-by-one — Sprint 1
- **Bug #3** SQLite concurrent writer crash — Sprint 2
- **Bug #4** commit-guard phase-block fallthrough — Sprint 2
- **Bug #5** consensus aggregator quorum miscount — Sprint 2
- **Bug #6** test-data-manager non-determinism — Sprint 2
- **Bug #7** design-bridge hardcoded token — Sprint 2 (Bug #7 guard sentinel)
- **Bug #8** invariant-formalizer ambiguity false positive — Sprint 3
- **Bug #9** coverage-analyzer null-as-zero rollup — Sprint 3
- **Bug #10** chaos-injector unbounded failure cascade — Sprint 3
- **Bug #11** compact-recovery stale snapshot — Sprint 3
- **Bug #12** test-optimizer cache invalidation — Sprint 4 (S4-02)

### Breaking changes

None. v1.0.0 is the first public release.

### Migration

N/A — first release.

### Distribution

- **Tarball**: `./package-plugin.sh` produces `vibeflow-plugin-1.0.0.tar.gz`
- **Local install**: `claude --plugin-dir ~/Projects/VibeFlow`
- **Marketplace**: `claude plugin install vibeflow@vibeflow-marketplace` (when published)

### Documentation

- [Getting Started](./docs/GETTING-STARTED.md)
- [Configuration Reference](./docs/CONFIGURATION.md)
- [Skills Reference](./docs/SKILLS-REFERENCE.md) (26 skills)
- [Pipelines](./docs/PIPELINES.md) (7 canonical pipelines + decision tree)
- [Hooks](./docs/HOOKS.md)
- [MCP Servers](./docs/MCP-SERVERS.md)
- [Troubleshooting](./docs/TROUBLESHOOTING.md)
- [Team Mode](./docs/TEAM-MODE.md)
- [Demo Walkthrough](./examples/demo-app/docs/DEMO-WALKTHROUGH.md)

### Acknowledgments

Built with Claude Opus 4.6 and Claude Code, by Mustafa Yıldırım.

[1.0.0]: https://github.com/mustiyildirim/vibeflow/releases/tag/v1.0.0

---

## Pre-releases

<!-- Prerelease entries sit below this header. Stable releases stay
     above the `---` separator; prereleases never become "latest".
     Added in Sprint 8 / S8-01. -->
