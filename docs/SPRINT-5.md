# Sprint 5: v1.0.x Maintenance + GitLab + Real-World Hardening

## Sprint Goal
Post-v1.0 maintenance sprint. Close the few v1.0 forward-looking
stubs (GitLab CI provider, live PostgreSQL team-mode test), add
real-world coverage that landed too late for v1.0 (Bug #13
cross-process reproducer), and ship a marketplace-publish workflow
so v1.0.1+ releases are reproducible without hand surgery.

## Prerequisites
- Sprint 4 ✅ COMPLETE (v1.0.0 release-ready)
- v1.0.0 git tag created (user-authorization gated; run before starting Sprint 5 work)
- 1335 baseline checks across 10 test layers held green

## Completion Criteria
- [ ] `ci_provider: gitlab` actually executes a GitLab pipeline (no longer "not yet implemented")
- [ ] Live PostgreSQL team-mode integration test runs in CI against a dockerized postgres
- [ ] Marketplace publish workflow lands as a `bin/release.sh` script
- [ ] Bug #13 has a cross-process reproducer in `tests/integration/run.sh`
- [ ] At least one v1.0.x patch release ships through the new workflow
- [ ] Sprint 5 integration harness present (`tests/integration/sprint-5.sh`)

---

## Tickets

### S5-01: Bug #13 cross-process reproducer ⬜ TODO
**Location:** `tests/integration/run.sh`
**Why now:** the in-process regression test in `engine.test.ts`
guards the unit-level fix, but the bug originally surfaced via
the MCP JSON-RPC layer (sprint-4 [S4-K]). A cross-process
reproducer in run.sh ensures the fix doesn't regress at the
stdio + JSON-RPC layer.
- [ ] Add a section in run.sh [4] that calls `sdlc_get_state` twice
  in a row on the same project (with a write between)
- [ ] Assert both calls return successful responses (no
  `isError: true`)
- [ ] Sentinel-guard the assertion so a future regression in
  `engine.getOrInit` shows up in the platform baseline harness
  (run.sh), not just sprint-4

### S5-02: GitLab CI provider implementation ⬜ TODO
**Location:** `mcp-servers/dev-ops/src/client.ts` (`createGitlabClient`)
**Why now:** S4-05 declared `ci_provider: "gitlab"` in the manifest
and wired `CI_PROVIDER` through the env, but the actual GitLab
client is a `CiConfigError("not yet implemented")` placeholder.
Closing this is the highest-impact missing piece for non-GitHub
shops.
- [ ] Implement `createGitlabClient({ project, token, baseUrl, fetchImpl })`
  matching the existing `CiProvider` interface
- [ ] Tools call: `triggerWorkflow` → POST `/api/v4/projects/<id>/pipeline`
- [ ] Tools call: `getRun` → GET `/api/v4/projects/<id>/pipelines/<id>`
- [ ] Tools call: `listArtifacts` → GET `/api/v4/projects/<id>/jobs/<id>/artifacts`
- [ ] Reuse the same lazy-construction pattern as the GitHub client
- [ ] Mirror the GitHub test surface: ~12 vitest cases (config,
  trigger, status, artifacts, transport failure, ECONNREFUSED,
  invalid JSON)
- [ ] Update CONFIGURATION.md + SKILLS-REFERENCE.md to note GitLab
  is fully supported
- [ ] Remove the "not yet implemented" hint from the dev-ops
  CiConfigError path
- [ ] sprint-5.sh sentinel asserting the ci_provider=gitlab path
  reaches the GitLab client (not the not-implemented branch)

### S5-03: Live PostgreSQL team-mode integration test ⬜ TODO
**Location:** `tests/integration/sprint-5.sh` + `bin/with-postgres.sh`
**Why now:** Sprint 1 added 14 vitest cases for the PostgreSQL
state store, but those use a FakePool. The real-world contract
(actual TCP connect, real schema, real CAS) has never been
end-to-end-tested. Team mode shipped in v1.0 but is effectively
unverified.
- [ ] `bin/with-postgres.sh` — wraps a docker-compose pg14
  container, exposes `$DATABASE_URL`, tears down on exit
- [ ] sprint-5.sh [S5-A] — when `$DATABASE_URL` is set, walks the
  sdlc-engine through a full SDLC walk against the real postgres
- [ ] Re-runs the engine with the SAME project id and asserts
  state survives the restart
- [ ] Asserts concurrent advance attempts hit the CAS lock
- [ ] CI optional: skip when no postgres available, fail loud when
  `$DATABASE_URL` is set but unreachable

### S5-04: Marketplace publish workflow ⬜ TODO
**Location:** `bin/release.sh` + `.github/workflows/release.yml`
**Why now:** S4-06 ships `package-plugin.sh` which produces the
tarball, but the rest of the release process (tag → tarball
checksum → release notes from CHANGELOG → marketplace push) is
still manual. Automate it so v1.0.1+ doesn't drift from v1.0.0's
discipline.
- [ ] `bin/release.sh <version>` — version bumps plugin.json,
  CHANGELOG.md insertion, build-all + package-plugin, sha256
  manifest, gh release create, gh tag push
- [ ] Idempotency check: refuse to run when the working tree is
  dirty
- [ ] Pre-flight: `bash tests/integration/run.sh sprint-2 sprint-3
  sprint-4 sprint-5 hooks/tests/run.sh` must all pass before any
  release action
- [ ] `.github/workflows/release.yml` — triggered on `v*.*.*` tag
  push, uploads the tarball + sha256 to the GitHub release
- [ ] sprint-5.sh sentinel: the release script exists + is
  executable + refuses to run on a dirty tree

### S5-05: Next.js demo project ⬜ TODO
**Location:** `examples/nextjs-demo/`
**Why now:** the existing `examples/demo-app/` is intentionally a
non-UI TypeScript project (it's about VibeFlow workflow, not Next.js
architecture). A second demo aimed at a real Next.js app validates
that VibeFlow's skills also handle JSX / app router / RSC patterns.
- [ ] `examples/nextjs-demo/` — minimal Next.js 14 app router project
- [ ] Sample PRD that scores ≥75 on the e-commerce domain threshold
- [ ] One real page + one server action + matching tests
- [ ] Pre-baked VibeFlow artifacts (prd-quality, scenario-set,
  test-strategy, release-decision)
- [ ] `docs/NEXTJS-DEMO-WALKTHROUGH.md` parallel to the existing
  demo's walkthrough
- [ ] sprint-5.sh sentinel: nextjs-demo presence + structure +
  artifact verdicts

### S5-06: Sprint 5 integration harness ⬜ TODO
**Location:** `tests/integration/sprint-5.sh`
**Sections:**
- [ ] [S5-A] — Live PostgreSQL team-mode walk (S5-03)
- [ ] [S5-B] — GitLab provider sanity (S5-02)
- [ ] [S5-C] — Release script presence + safety guards (S5-04)
- [ ] [S5-D] — Next.js demo presence + artifact verdicts (S5-05)
- [ ] [S5-E] — Bug #13 cross-process reproducer mirrored here
  (so a future Sprint that touches the engine catches the
  regression even without re-running run.sh)

### S5-07: Sprint 5 closure + v1.0.x release notes ⬜ TODO
- [ ] CHANGELOG.md `[1.0.1] — <date>` entry covering S5-01..S5-06
- [ ] Mark Sprint 5 ✅ COMPLETE in this file
- [ ] Update CLAUDE.md test layer count
- [ ] Run the new `bin/release.sh 1.0.1` end-to-end (still pending
  user authorization for the actual tag/release push)

---

## Next Ticket to Work On
**S5-01: Bug #13 cross-process reproducer** — smallest scope, lands
in the platform baseline harness, validates that the Sprint 4 fix
holds at the stdio + JSON-RPC layer. Good warm-up for a maintenance
sprint and clears the highest-priority "unfinished business" item
from Sprint 4.

## Test inventory (entering Sprint 5)
- mcp-servers/sdlc-engine: **105 vitest tests**
- mcp-servers/codebase-intel: **48 vitest tests**
- mcp-servers/design-bridge: **57 vitest tests**
- mcp-servers/dev-ops: **43 vitest tests**
- mcp-servers/observability: **76 vitest tests**
- hooks/tests/run.sh: **52 bash assertions**
- tests/integration/run.sh: **394 bash assertions**
- tests/integration/sprint-2.sh: **94 bash assertions**
- tests/integration/sprint-3.sh: **111 bash assertions**
- tests/integration/sprint-4.sh: **355 bash assertions**
- Total: **1335 passing checks** across 10 test layers (Sprint 4 baseline)

## Sprint 5 vs Sprint 4 differences
- **No new SDLC skills.** Sprint 5 is maintenance + missing-piece
  closure. Skill work returns in v1.1 (Sprint 6+).
- **Live infrastructure dependencies are optional.** PostgreSQL +
  GitLab tests skip gracefully when their backends aren't
  available. CI may run them; local dev may not.
- **Tag/release authorization gate stays.** Same rule as S4-07:
  public-facing actions wait for explicit user go-ahead. The new
  `bin/release.sh` automates the mechanics but doesn't bypass the
  authorization gate.

## Versioning
This sprint targets **v1.0.1**. Breaking changes warrant v1.1.0 and
land in Sprint 6+, not here.
