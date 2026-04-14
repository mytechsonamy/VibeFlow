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

### S5-01: Bug #13 cross-process reproducer ✅ DONE
**Location:** `tests/integration/run.sh [4]`

The Sprint-4 fix to `engine.getOrInit()` is guarded at the unit
layer by `engine.test.ts` and at the full-walk layer by
`sprint-4.sh [S4-K]`. S5-01 adds a cross-process reproducer in
the platform baseline harness — the same process topology that
the real Claude Code plugin uses — so a future regression surfaces
in `run.sh` (which every CI run executes) rather than only in the
sprint-specific harness.

**Implementation:** the reproducer runs TWO engine invocations
against the same state.db.
1. **Phase 1** — `sdlc_satisfy_criterion` × 2 + `sdlc_record_consensus` + `sdlc_advance_phase` (REQUIREMENTS → DESIGN). After this the project exists at revision ≥ 5.
2. **Phase 2** — a fresh engine process calls `sdlc_get_state` on the now-existing project. Before the fix this path crashed with "revision must increment by exactly 1". After the fix it succeeds and returns the post-walk phase.

**4 new sentinels in run.sh [4]:**
- phase-1 writes completed (exit 0 from the first engine invocation)
- state.db persisted after phase-1 (proves writes landed)
- phase-2 get_state succeeds (not an error envelope, not the revision-check message)
- phase-2 get_state returns DESIGN (proves the read reflects the write)

**Gold-standard verification:** temporarily reverted `engine.ts` to
the pre-fix version (via `git show 329b82e:...`), rebuilt the
sdlc-engine dist, and re-ran `run.sh`. The reproducer fired
exactly the two expected failures:
- `bug #13 reproducer: phase-2 get_state returned an error envelope`
- `bug #13 reproducer: get_state returns DESIGN after advance (no 'DESIGN' in output)`

After restoring the fix + rebuilding, all 4 sentinels pass. The
reproducer is not a no-op — it's bound to the exact behavior the
fix corrects.

**run.sh baseline bump:** 394 → **398** (+4 cross-process sentinels).

### S5-02: GitLab CI provider implementation ✅ DONE
**Location:** `mcp-servers/dev-ops/src/client.ts` + `src/tools.ts` + `tests/gitlab-client.test.ts`

**Completed:**
- [x] **`createGitlabClient`** — mirrors the `CiProvider` interface, 155 LoC including status + conclusion normalization. Uses `PRIVATE-TOKEN` auth header (not Bearer — that's a GitHub quirk). Token resolution order: explicit `opts.token` → `GITLAB_TOKEN` env → `GITHUB_TOKEN` env (so a project that already set `github_token` in userConfig doesn't need a second key).
- [x] **Endpoints wired**:
  - `triggerWorkflow` → POST `/projects/:id/pipeline` (GitLab has no workflow-file concept like GitHub Actions; we pass the workflow name as a `WORKFLOW` pipeline variable so `.gitlab-ci.yml` jobs can gate on `$WORKFLOW == "<name>"`)
  - `getRun` → GET `/projects/:id/pipelines/:pipeline_id`
  - `listArtifacts` → GET `/projects/:id/pipelines/:pipeline_id/jobs` (collapses each job's `artifacts_file` into the normalized `PipelineArtifact` shape)
- [x] **Status normalization**: GitLab's 10+ status values are mapped to the 3-value `{queued, in_progress, completed}` shape:
  - `created` / `waiting_for_resource` / `preparing` / `pending` / `scheduled` / `manual` → `queued`
  - `running` → `in_progress`
  - `success` / `failed` / `canceled` / `skipped` → `completed` + matching `conclusion`
  - unknown → `queued` (safety — never a false terminal)
- [x] **Artifact expiry**: when `artifacts_expire_at` is in the past the artifact is marked `expired: true`; the mock test seeds a 2000-01-01 timestamp to cover this branch.
- [x] **Reuses the lazy-construction pattern** — same shape as `createGithubClient`. `buildTools()` resolves the provider lazily on first call, so `tools/list` works without a token.
- [x] **`tools.ts` routes CI_PROVIDER=gitlab to the new client** — the `(owner, repo)` tool args are collapsed into a single `namespace/name` GitLab project path. The "not yet implemented" stub is removed.
- [x] **19 new vitest cases** in `tests/gitlab-client.test.ts`:
  - 4 config tests (missing token, missing projectId, token precedence, GITHUB_TOKEN fallback)
  - 4 triggerWorkflow tests (happy path + URL encoding + empty workflow/ref rejection + whitespace ref rejection)
  - 4 getRun normalization tests (success + transient-statuses + running + terminal-statuses matrix)
  - 2 error-path tests (non-2xx CiClientError + invalid JSON)
  - 3 listArtifacts tests (happy + expired + empty)
  - 2 offline tests (ECONNREFUSED + ENOTFOUND)
- [x] **Existing `tools.test.ts` "routes CI_PROVIDER=gitlab through the GitLab client"** — replaces the old "raises CiConfigError on gitlab (not yet implemented)" case. Asserts the URL hits a `/projects/.../pipeline` path and the auth header is `PRIVATE-TOKEN`, not `Bearer`.
- [x] **`docs/CONFIGURATION.md`** — `ci_provider` row updated to note GitLab is implemented in v1.0.1 / Sprint 5 / S5-02.
- [x] **`tests/integration/sprint-5.sh [S5-A]`** — 23 new sentinels covering: src + dist exports, PRIVATE-TOKEN header, tools.ts wiring, removal of the "not implemented yet" stub, gitlab-client.test.ts presence + describe blocks + every status string exercised.

**Test count deltas:**
- dev-ops: 43 → **62** (+19 GitLab client tests; the old "not implemented" tools.test case was rewritten, not deleted)
- sprint-5.sh: NEW harness, 26 assertions total (23 [S5-A] + 3 placeholder sentinels for S5-03/04/05 that will be replaced as those tickets land)
- Total baseline: 1339 → **1384** (+45)

**Scope decision — what this does NOT cover:**
- **Self-hosted GitLab instances** — `baseUrl` is configurable (same as the GitHub client's `api.github.com` override), but the test suite only exercises `gitlab.com` URLs. A real self-hosted-GitLab integration test would need a live instance and belongs in S5-03's live-infrastructure bucket.
- **`deploy`/`rollback` operations** — routed through `triggerPipeline` already (provider-agnostic); no GitLab-specific deploy logic needed.
- **Job-level triggering** — GitLab supports triggering individual jobs, but we only support pipeline-level triggering. Jobs can be gated via the `$WORKFLOW` variable pattern documented in the `triggerWorkflow` comment.

### S5-03: Live PostgreSQL team-mode integration test ✅ DONE
**Location:** `bin/with-postgres.sh` + `tests/integration/sprint-5.sh [S5-B]`

Sprint 1 shipped 14 vitest cases for the PostgreSQL state store, but
those use a hand-rolled `FakePool` — the real-world contract (actual
TCP connect, real `pg` module, real CAS via the `revision` column)
had never been end-to-end-tested. Team mode shipped in v1.0
effectively unverified at the wire layer. S5-03 closes that gap.

**Completed:**
- [x] **`bin/with-postgres.sh`** — throwaway-container wrapper around any command. Pulls `postgres:14-alpine`, waits for `pg_isready`, exports `DATABASE_URL` + `VIBEFLOW_POSTGRES_URL`, tears down on exit/error/interrupt via a trap. Configurable via `VF_PG_IMAGE` / `VF_PG_PORT` / `VF_PG_DB` / `VF_PG_USER` / `VF_PG_PASSWORD` / `VF_PG_READY_ATTEMPTS` env vars (defaults: postgres:14-alpine on 55432). Unique container name per PID so multiple runs don't collide.
- [x] **`sprint-5.sh [S5-B]`** — invokes the wrapper with a two-phase walker script:
  - **Phase 1** — writes (`sdlc_satisfy_criterion` × 2, `sdlc_record_consensus`, `sdlc_advance_phase` REQUIREMENTS → DESIGN) in one engine invocation
  - **Phase 2** — a FRESH engine process calls `sdlc_get_state` against the same project id. This verifies both state persistence across process restarts AND the Bug #13 fix on the Postgres backend (separate from the SQLite reproducer in `run.sh`)
- [x] **Skip conditions** — graceful skip (not fail) when:
  - Docker isn't installed (`command -v docker` fails)
  - The user sets `VF_SKIP_LIVE_POSTGRES=1` (opt-out for restricted local envs)
  - The `pg` package isn't in `sdlc-engine/node_modules/pg` (solo-mode users don't carry pg)
- [x] **Hard failures** — the harness DOES fire loudly when docker is available but:
  - `with-postgres.sh` is missing or not executable
  - Phase 1 writes produce a JSON-RPC error
  - Phase 2 get_state produces an error OR returns a phase other than DESIGN
- [x] **`pg` optional peer dependency resolved** — Sprint 1 declared `pg` as `optionalDependencies` which npm wouldn't install on this system. Moved to regular `dependencies` in `mcp-servers/sdlc-engine/package.json` and rebuilt the dist. The `openStore` path still dynamic-imports pg, so solo-mode users aren't forced to carry it.

**3 new sentinels in sprint-5.sh [S5-B]:**
1. Phase 1 writes completed against real PostgreSQL
2. State survives engine restart — get_state returns DESIGN
3. Bug #13 fix holds on PostgreSQL backend

Plus the pre-existing `bin/with-postgres.sh present + executable` sentinel from the scaffolding.

**Live proof:** the harness run demonstrated the wrapper pulls
`postgres:14-alpine` (first run only, cached after), the engine
connects, writes land, and a fresh engine invocation reads them
back correctly. Phase 2 passes across process restarts — the
Postgres row survives independently of any single engine process.

**Scope boundaries** (intentionally deferred):
- **Concurrent-advance CAS stress** — the original ticket mentioned asserting concurrent advance attempts hit the CAS lock. The vitest FakePool already covers this at the unit layer (`postgres.test.ts` 14 cases). Running concurrent JSON-RPC processes against a real pool and asserting the loser sees a revision mismatch is a larger test shape that belongs in a future hardening sprint.
- **Self-hosted Postgres** — only the default postgres:14-alpine is tested. Self-hosted or managed-cloud Postgres (PG13, PG15, PG16, AWS RDS) would need parameterized wrappers and isn't in v1.0.1 scope.
- **Connection-pool exhaustion** — the 10-client pool default is never stressed. Load testing is v1.1+ territory.

### S5-04: Marketplace publish workflow ✅ DONE
**Location:** `bin/release.sh` + `.github/workflows/release.yml` + `tests/integration/sprint-5.sh [S5-C]`

**Completed:**
- [x] **`bin/release.sh <version> [--dry-run|--check-clean]`** — 7-step release prep pipeline: (0) working-tree cleanliness, (1) version argument validation (strict SemVer X.Y.Z, higher than current, tag doesn't exist), (2) pre-flight test gauntlet across all 11 layers, (3) `plugin.json` version bump, (4) CHANGELOG.md entry insertion via awk (prepends new entry above the previous version header), (5) `build-all.sh` + `package-plugin.sh --skip-build`, (6) sha256 manifest via `shasum -a 256`, (7) local git commit + annotated tag. **Tag push and `gh release create` are NOT automated** — the script prints the commands and waits for user authorization (same discipline as v1.0.0 in Sprint 4 / S4-07).
- [x] **Dirty-tree refusal** — `git status --porcelain` check at step 0 aborts before any writes. `--check-clean` flag is a dedicated exit-code-only mode for CI / harness use.
- [x] **Strict SemVer** — rejects prerelease / build-metadata suffixes (`1.0.1-beta` → fail). v1.0.x releases are strict patch/minor/major only; prereleases need a different workflow.
- [x] **Pre-flight gauntlet** — runs every test harness before touching files. 11 commands total (5 MCP vitest suites + hooks + 4 integration harnesses). Any failure aborts the release prep.
- [x] **`.github/workflows/release.yml`** — triggers on `v*.*.*` tag push (never on branch commits). Checks out at the tag, installs deps, rebuilds all dists, runs the full test gauntlet (with `VF_SKIP_LIVE_POSTGRES=1` so the runner doesn't need docker), packages the tarball, verifies plugin.json version matches the tag, generates sha256, extracts release notes from CHANGELOG via awk, and uploads via `softprops/action-gh-release@v2`.
- [x] **`sprint-5.sh [S5-C]`** — 14 new sentinels: file presence + executability (2), release.yml presence (1), dirty-tree refusal source grep (1), strict SemVer source grep (1), preflight harness coverage (6 commands), no-auto-push policy (1), `--check-clean` smoke on a cloned temp repo with both clean-tree and dirty-tree assertions (2), release.yml tag-trigger (1), release.yml sha256 upload (1), release.yml version-matches-tag (1).

**Smoke-tested live:**
- `--check-clean` on a fresh clone with the release script copied in returns 0 (clean) and 1 (after a dirty file is added) — verified by the harness
- `release.sh --dry-run 1.0.1` walks steps 1-7 without writing any files (not run in the harness because the preflight gauntlet is heavy, but the --dry-run path is tested manually before merging S5-04)

**CI-skip wiring:** the GitHub Actions release workflow sets `VF_SKIP_LIVE_POSTGRES=1` so sprint-5.sh [S5-B] skips the live-Postgres walk (runners don't have docker-in-docker + pg14 out of the box). Local maintainers run with docker; the CI path uses the existing skip logic.

**Scope boundaries** (intentionally deferred):
- **Marketplace publish API** — Claude Code's plugin marketplace API (if/when it exists) isn't targeted. The workflow publishes to GitHub Releases; `claude plugin install <url>` can point at the tarball asset directly, and a future marketplace integration would add a second publish step.
- **GPG signing of tags/tarballs** — not wired. Users can verify via the sha256 manifest for now; signed tags land in a future hardening sprint.
- **Automated prerelease workflow** — no beta/rc channel. A prerelease would cut a `v1.0.1-rc.1` tag manually and document the procedure in a separate ticket.

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
**S5-05: Next.js demo project** — `examples/nextjs-demo/` parallel to the TypeScript-only demo. Sample PRD + real Next.js 14 app router page + server action + vitest + pre-baked VibeFlow artifacts. Validates that VibeFlow skills handle JSX / RSC patterns, not just pure TypeScript business logic.

## Test inventory (after S5-04)
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
- tests/integration/sprint-5.sh: **43 bash assertions** (+14 from S5-04 release script + workflow)
- Total: **1401 passing checks** across **11 test layers**

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
