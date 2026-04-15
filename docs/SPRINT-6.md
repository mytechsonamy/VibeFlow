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

### S6-01: Concurrent-advance CAS stress test against real Postgres ✅ DONE
**Location:** `tests/integration/sprint-6.sh [S6-A]` (new harness file) + `bin/release.sh` preflight + `.github/workflows/release.yml`
**Deferred from:** S5-03 scope decision

Sprint 1's 14 `FakePool` unit tests cover the CAS logic at the unit
layer. Sprint 5's `sprint-5.sh [S5-B]` walks one fresh engine process
against a real Postgres. Neither exercised **concurrent** advance
attempts against the real wire protocol. S6-01 spins up N=5 engine
processes under `bin/with-postgres.sh` — all racing to advance the
same project REQUIREMENTS → DESIGN — and verifies Postgres's advisory
lock + `SELECT ... FOR UPDATE` + revision CAS correctly serializes
them.

**Completed:**
- [x] **`tests/integration/sprint-6.sh`** — new Sprint 6 harness file. Mirrors the sprint-5.sh shape (pass/fail helpers, skip ladder, RESULTS footer). Starts with one section `[S6-A]`; future Sprint 6 tickets will extend it with their own sections.
- [x] **[S6-A] Concurrent-advance CAS stress test** — four-phase inline walker script invoked via `bin/with-postgres.sh`:
  - **Phase 1 (setup, sequential):** one engine process seeds the project with satisfied criteria + recorded consensus so the REQUIREMENTS → DESIGN gate is met.
  - **Phase 2 (race, concurrent):** 5 engine processes spawned via `&` + `wait`, each issuing ONE `sdlc_advance_phase` call targeting DESIGN. Outputs captured to per-racer log files.
  - **Phase 3 (classify):** each racer's response is parsed for the stringified `ok` marker — winners carry `\"ok\": true`, losers carry `\"ok\": false` (the MCP tool handler returns `{ ok, errors, state }` as a successful JSON-RPC response, so `isError:true` never fires for PhaseTransitionError).
  - **Phase 4 (final read):** a fresh engine process calls `sdlc_get_state` and asserts the row is consistent with exactly one committed advance.
- [x] **5 assertions (in live mode)** in [S6-A]:
  1. Phase-1 setup completed against real Postgres
  2. All 5 concurrent engines terminated (no hangs)
  3. Exactly one racer won the advance (winners=1)
  4. The remaining N-1 racers were correctly rejected (errors=4) — they acquire the advisory lock after the winner committed, read `currentPhase: DESIGN`, and fail the phase validator with "Cannot transition to the same phase (DESIGN)"
  5. Fresh-process `get_state` returns DESIGN (state survives across all the concurrent writes)
- [x] **Skip ladder** matching sprint-5.sh [S5-B]: skips gracefully when `VF_SKIP_LIVE_POSTGRES=1`, when the docker binary isn't installed, when the docker daemon isn't running, or when the `pg` optional peer dep isn't installed in sdlc-engine's node_modules. In skip mode the harness passes with 1 assertion (the skip sentinel itself) so it's always counted in the baseline.
- [x] **Latent docker-daemon skip gap fixed** in BOTH sprint-5.sh [S5-B] and sprint-6.sh [S6-A]. The original S5-B skip ladder only checked `command -v docker` — macOS contributors with docker installed but Docker Desktop not running would see the walk fire and fail instead of skipping. The strengthened check runs `docker info >/dev/null 2>&1` to probe the daemon directly.
- [x] **Wired into `bin/release.sh` preflight gauntlet** — sprint-6.sh runs alongside sprint-5.sh on every release. sprint-5.sh's [S5-C] preflight-harness-list sentinel was extended to assert release.sh contains the sprint-6.sh command so a future regression that drops it is caught immediately.
- [x] **Wired into `.github/workflows/release.yml`** — CI runs sprint-6.sh with `VF_SKIP_LIVE_POSTGRES=1` (same discipline as S5-B), so the skip path fires on GitHub runners that lack docker-in-docker.

**Live-verified:** ran the full harness against a real `postgres:14-alpine` container via `bin/with-postgres.sh`. Observed exactly 1 winner + 4 losers + final state DESIGN across N=5 concurrent engines. The winner's response contained `"ok": true`, `"state"`, and `"transition"`; each loser's response contained `"ok": false`, `"errors": ["Cannot transition to the same phase (DESIGN)"]`. The advisory lock + row-level `FOR UPDATE` lock serializes the writes so tightly that the revision CAS check never has to fire — this is a **stronger** guarantee than the original ticket expected ("revision mismatch error envelope"), because the mutual-exclusion primitive catches the conflict BEFORE the CAS does.

**Parse quirk surfaced while writing the harness:** bash's single-quoted heredoc (`<<'STRESS_OUTER'`) still tracks single-quote balance through comment lines inside the heredoc body, even though comments are supposed to be inert. An apostrophe in a heredoc comment (`# sdlc_advance_phase's tool handler`) caused a runtime "unexpected EOF while looking for matching `''" parse error downstream. Stripped all apostrophes from the heredoc body's comments to keep the heredoc parseable.

**Test count deltas:**
- `tests/integration/sprint-6.sh`: NEW — **1 assertion in normal dev** (skip path), **5 assertions in live mode** (docker+pg available)
- `tests/integration/sprint-5.sh`: 93 → **94** (+1 for the new sprint-6.sh entry in the preflight-harness-list sentinel)
- Total baseline: 1451 → **1453** (+2; live mode adds another +4 when docker+pg are present)
- Test layers: 11 → **12**

**Scope boundaries** (intentionally deferred):
- **Dedicated `mcp-servers/sdlc-engine/tests/postgres-stress.test.ts` unit test** — the ticket draft mentioned one. The bash harness is the more direct answer to the question "does the real wire protocol serialize N concurrent writers" because it exercises actual cross-process JSON-RPC + pg TCP + Postgres locks. A vitest-level stress test would duplicate coverage that the bash harness now owns, and would need its own Postgres fixture anyway. Skipped in favor of the harness.
- **Retry-loop semantics** — the ticket draft also mentioned "loser process retries via `sdlc_get_state` + re-advance". The real Postgres path never reaches the CAS under normal load (the advisory lock serializes the writes first), and no client currently implements retry. Documenting retry semantics + adding client-side retry is a v1.2 concern, not v1.1.
- **Concurrent writes on DIFFERENT criteria** — N processes each satisfying a unique criterion could verify the additive case. Skipped; the conflict case is the more stringent test and already covers the additive case as a subset.

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

### S6-04: Next.js demo — `next build` coverage + `"use client"` surface ✅ DONE
**Location:** `examples/nextjs-demo/{lib,components,tests}/` + `app/products/[id]/page.tsx` + `actions/submit-review.ts` + `sprint-6.sh [S6-B]`
**Deferred from:** S5-05 scope decision

The v1.0.1 Next.js demo was 100% React Server Components + server
actions. S6-04 adds the first client component so the demo exercises
the RSC/client boundary, plus an optional `next build` gate in the
harness so contributors who install the full dep tree get automatic
coverage of the production build path.

**Completed:**
- [x] **`lib/rating.ts`** — pure TypeScript helpers (no React) for the rating picker. Exports `computeDisplay(rating, hover)`, `clampRating(value, max?)`, `renderStars(displayValue, max?)`, `isValidSubmittedRating(value, max?)`, and the `DEFAULT_MAX_RATING = 5` constant. Every helper is a single-responsibility pure function — vitest covers every branch in the node environment without touching React.
- [x] **`components/rating-picker.tsx`** — new `"use client"` component owning `useState<number>` for both the committed rating and the hover preview. Click handlers call `clampRating(star, max)` before setting state (defense-in-depth). The component emits a `<input type="hidden" name={name} />` so the form still sees the numeric value on submit; the server action re-validates with `validateReview(...)` regardless of what the client says.
- [x] **`tests/rating.test.ts`** — 25 vitest cases covering every helper:
  - 5 `computeDisplay` cases (hover-vs-null precedence, including the subtle case where hover=0 is a valid preview override, distinct from null)
  - 9 `clampRating` cases (negative, beyond max, fractional, NaN, ±Infinity, exact bounds, custom max)
  - 5 `renderStars` cases (all empty, all filled, mixed, default max, empty array when max=0)
  - 6 `isValidSubmittedRating` cases (integer 1..max, 0, max+1, non-integer, non-numeric, custom max)
- [x] **`app/products/[id]/page.tsx` wiring** — imports `RatingPicker` via the `@/components/rating-picker` alias and replaces the plain `<input type="number">` in the review form. This is where the RSC → client boundary runs: Next 14 serializes the picker's props on the server, delivers the component as a separate client bundle, and hydrates on the client.
- [x] **`submitReviewFormAction` void wrapper** — discovered during `next build` that Next 14's `<form action={...}>` typing requires `(formData: FormData) => void | Promise<void>`, which rejects the `Promise<SubmitReviewResult>` return of `submitReviewAction`. Added a thin void wrapper in `actions/submit-review.ts` that calls the tested action and swallows the result. The page uses the wrapper; tests continue to import `submitReviewAction` directly against its structured return type. The wrapper is commented in both files with a pointer to the constraint and a real-app note about `revalidatePath()`/`redirect()`.
- [x] **`vibeflow.config.json`** — `lib/rating.ts` declared as a critical path alongside `lib/reviews.ts`, `lib/catalog.ts`, and `actions/submit-review.ts`.
- [x] **`docs/NEXTJS-DEMO-WALKTHROUGH.md`** — two new sections: "The RSC/client boundary" walks through why the picker needs `"use client"`, how hover/click state maps onto `lib/rating.ts` helpers, and the defense-in-depth validation story. "Optionally running `next build`" documents the harness gate + the `VF_SKIP_NEXT_BUILD=1` override. Test count line updated from 41 → 66. Project tree diagram updated to include `components/` and `lib/rating.ts`.
- [x] **`package-plugin.sh` whitelist** — `examples/nextjs-demo/components` added alongside `app`, `lib`, `actions`, `tests`, `docs`, `.vibeflow/reports`. Without this, the new client component would not ship in the tarball.
- [x] **`sprint-6.sh [S6-B]`** — new 17-assertion section:
  - **3 file-presence** (lib/rating.ts, components/rating-picker.tsx, tests/rating.test.ts)
  - **4 rating-picker structure** (`"use client"` directive on line 1, imports from react, uses `useState`, imports pure helpers from `@/lib/rating`)
  - **2 detail-page wiring** (`RatingPicker` referenced in the form, imported via `@/components/rating-picker` alias)
  - **1 config** (lib/rating.ts is a critical path)
  - **5 test coverage** (rating.test.ts exercises each of the 5 exports)
  - **1 optional `next build` gate** (skip via `VF_SKIP_NEXT_BUILD=1`, skip when `node_modules/next` missing, otherwise run `npm run build` and assert clean exit)

**Live-verified:** ran `cd examples/nextjs-demo && npm install && npm test && npm run build`. Test suite: **66 passed** (4 files: catalog 14 + reviews 18 + action 9 + rating 25). `next build` output:
```
Route (app)                              Size     First Load JS
┌ ○ /                                    140 B          87.4 kB
├ ○ /_not-found                          875 B          88.1 kB
├ ○ /products                            8.83 kB        96.1 kB
└ ƒ /products/[id]                       624 B          87.9 kB
+ First Load JS shared by all            87.2 kB
○  (Static)   prerendered as static content
ƒ  (Dynamic)  server-rendered on demand
```
The `[id]` route is `ƒ (Dynamic)` because the server action wires into the form — Next correctly detects the dynamic rendering requirement. Static routes (`/`, `/products`, `/_not-found`) are prerendered at build time.

**Test count deltas:**
- `examples/nextjs-demo` vitest suite: 41 → **66** (+25 rating helper tests)
- `tests/integration/sprint-6.sh`: 1 → **17** (+16 from [S6-B]; the next-build gate is 1 assertion either skip or live)
- Total baseline: 1453 → **1469** across 12 test layers
- Bonus (not in baseline): demo-app 45 + nextjs-demo 66

**Scope boundaries** (intentionally deferred):
- **Component-level rendering tests** with @testing-library/react — would require JSX transformer + jsdom in vitest config. The pure-helper approach in `lib/rating.ts` covers every branch of the picker's logic without React; the component file itself is validated structurally by `sprint-6.sh [S6-B]` (directive presence, import wiring).
- **Regenerating `.vibeflow/reports/*.md`** — the pre-baked PRD quality / scenario-set / test-strategy / release-decision reports still reference "41 tests" and the old requirement families. Refreshing them is a cosmetic update that belongs in a dedicated "demo re-bake" ticket alongside any future scoring changes. The walkthrough doc notes that pre-baked reports may drift.
- **`"use client"` component covered by the existing REV-*/ACT-* requirements** — the picker's validation mirrors REV-001 but doesn't introduce a new family. Adding a dedicated `PICK-*` family would invite PRD churn for minimal signal.

### S6-05: GPG-signed release tags + RELEASING.md walkthrough ✅ DONE
**Location:** `bin/release.sh` step [7] + `docs/RELEASING.md` (new) + `tests/integration/sprint-6.sh [S6-C]`
**Deferred from:** S5-04 scope decision

S4-07's v1.0.0 release and S5-07's v1.0.1 release both shipped with
annotated (unsigned) tags. S6-05 teaches `bin/release.sh` to sign
the release tag when a signing key is configured, with a graceful
fall-back ladder so the script still runs on contributors who have
no key or have opted out.

**Completed:**
- [x] **Signed-tag path in `bin/release.sh [7]`** — three-step probe:
  1. `VF_SKIP_GPG_SIGN=1` → annotated tag even if a key is configured (opt-out for practice releases)
  2. `git config --get user.signingkey` unset → annotated tag + hint showing how to configure one
  3. `git tag -s` fails at runtime (passphrase timeout, gpg-agent down, key unreachable) → the half-created signed tag is cleaned up with `git tag -d`, an annotated tag is created instead, and a `WARN` line is printed so the maintainer notices
- [x] **`TAG_MODE` tracking variable** — set to `"signed"` on the happy path and `"annotated"` on any fall-back. The "Release prepared locally" hint block at the bottom of the script surfaces this so the maintainer can see at a glance which path was taken (and learns about `git tag -v` to verify signed tags).
- [x] **Dry-run parity** — `release.sh <version> --dry-run` reports which tag mode it WOULD use without actually creating the tag. The three probe branches each emit a distinct `[dry-run]` line so the maintainer can test the signing configuration without committing anything.
- [x] **`docs/RELEASING.md`** (NEW, 210+ lines) — end-to-end walkthrough covering:
  - "What `bin/release.sh` does" — seven-step table with dry-run annotation
  - "Tag signing" — the three-step probe ladder explained
  - "One-time GPG key setup" — `gpg --list-secret-keys` → `git config --global user.signingkey <KEY>` with links to the GitHub docs for key generation
  - "Uploading your public key to GitHub" — `gpg --armor --export <KEY>` → https://github.com/settings/keys
  - "Verifying a signed tag locally" — `git tag -v v1.0.1` with expected output
  - "Quickstart" — the 5-step cut-and-paste checklist for muscle-memory releases
  - "Rollback" — three escalating scenarios (local-only, pushed tag only, pushed release)
  - "Troubleshooting" — 5 concrete error messages + what to do
- [x] **`sprint-6.sh [S6-C]`** — 12 new sentinels:
  - 6 source-grep checks on `bin/release.sh` (`VF_SKIP_GPG_SIGN`, `user.signingkey` probe, `git tag -s`, `git tag -a` fall-back, `TAG_MODE` tracking, `git tag -d ... || true` half-tag cleanup)
  - 1 file presence (`docs/RELEASING.md`)
  - 5 content greps on RELEASING.md (`VF_SKIP_GPG_SIGN`, `user.signingkey`, `git tag -v`, `## Quickstart`, `## Rollback`)

**Scope decision — what this ticket does NOT cover:**
- **GitHub Actions signature verification in `release.yml`** — the original ticket mentioned "Release workflow verifies the tag signature". A workflow update requires a PAT with `workflow` scope, which my current token lacks. The verification step is **deferred to a follow-up commit** the user can push manually:
  ```yaml
  - name: Report tag signature
    run: |
      TAG="${GITHUB_REF#refs/tags/}"
      if git cat-file tag "$TAG" | grep -q -- "-----BEGIN PGP SIGNATURE-----\|-----BEGIN SSH SIGNATURE-----"; then
        echo "Tag $TAG is signed"
      else
        echo "Tag $TAG is unsigned (annotated)"
      fi
  ```
  This step is a REPORT, not a hard-fail — it logs the signature status alongside the release artifacts so downstream consumers can see at a glance whether a given release tag was signed. Enforcing it would break every pre-S6-05 release tag and would need a separate migration ticket.
- **Marketplace publish API integration** — the original S5-04 ticket and this ticket draft both mentioned "Claude Code's plugin marketplace API (if/when it exists)". As of v1.0.1, no public API exists for programmatic marketplace publishing — manually uploading to GitHub Releases is the supported path. When the API ships, a dedicated ticket will wire it in.

**Test count deltas:**
- `tests/integration/sprint-6.sh`: 17 → **29** (+12 from [S6-C])
- Total baseline: 1469 → **1481** across 12 test layers (1485 in live mode)

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

### S6-07: release.sh CHANGELOG insertion runtime sentinel ✅ DONE
**Location:** `bin/release.sh` (new `insert_changelog_entry()` helper + `--test-changelog-insert` mode) + `tests/integration/sprint-5.sh [S5-C]` (6 new sentinels)
**Discovered during:** S5-07 (CHANGELOG BSD awk bug)

S5-07 uncovered a BSD awk portability bug in `release.sh` that
caused a silent broken-release (CHANGELOG never updated, release
commit claimed success). The existing `sprint-5.sh [S5-C]`
sentinels only grep release.sh source — they cannot catch a
runtime insertion failure. S6-07 closes that gap.

**Completed:**
- [x] **`insert_changelog_entry <version>` helper** extracted from the inline step-4 logic in release.sh. Idempotent, self-contained, operates on `CHANGELOG.md` in the current working directory. Uses portable head/tail/grep (no BSD awk gotcha). Includes the post-insertion verification that refuses to continue if the new version header is not at the top of the rewritten CHANGELOG. Returns non-zero on any failure.
- [x] **`release.sh --test-changelog-insert <version>`** new mode that runs ONLY the helper against CHANGELOG.md in cwd, skipping every other release step (cleanliness check, version diff, preflight gauntlet, build, package, commit, tag). Designed to be called from an isolated tempdir fixture. Strict SemVer validation + clear error messages if the version is missing or malformed.
- [x] **Step 4 in release.sh now calls the helper** — single source of truth. A future refactor cannot drift the inline path and the test path apart.
- [x] **6 new runtime sentinels in `sprint-5.sh [S5-C]`**:
  1. happy-path fixture leads with the new version header after insertion
  2. previous version's heading survives the insertion (prepend, not replace)
  3. happy-path run exits 0
  4. header-less fixture + insert → exit non-zero (post-insertion verification fires)
  5. header-less fixture left unchanged on refusal (no partial-write corruption)
  6. source-grep sentinels: `--test-changelog-insert` flag + `insert_changelog_entry()` helper both present in release.sh

**Verification:** the happy fixture starts with one `## [1.0.0]` entry and the harness runs `release.sh --test-changelog-insert 9.9.9` against it. After the run, `## [9.9.9]` appears at the top AND `## [1.0.0]` is still present below. The negative fixture has no `## [` headings at all; the harness runs the same command and asserts a non-zero exit + byte-for-byte file unchanged before/after.

**Why this matters:** the BSD awk bug was invisible to static source-grep sentinels because both the inline awk call and the error message strings were intact — only the RUNTIME behavior was broken. S6-07 adds the first runtime check in the S5-C section and locks the contract in. If someone rewrites the insertion logic (e.g. swaps head/tail for sed, or reverts to awk), the happy-path fixture will immediately catch a regression.

**Test count deltas:**
- `tests/integration/sprint-5.sh`: 87 → **93** (+6)
- Total baseline: 1445 → **1451** (+6)

**Scope boundaries** (intentionally deferred):
- **Running `release.sh` end-to-end against a fixture branch** — would require setting up a fake git repo, fake plugin.json, fake MCP dists. Too heavy for a single sentinel. The current approach tests only the CHANGELOG step, which is the part that actually broke.
- **Fuzz testing the insertion logic** — out of scope. The current sentinels cover the happy path + the one known broken-path. Mutation testing on release.sh is a future sprint concern.

### S6-08: Sprint 6 integration harness ✅ DONE
**Location:** `tests/integration/sprint-6.sh` header + new `[S6-Z]` closure section

The harness was grown organically by each Sprint 6 ticket: S6-01
bootstrapped `sprint-6.sh` with `[S6-A]`, S6-04 added `[S6-B]`, and
S6-05 added `[S6-C]`. S6-08 is the meta-ticket that closes the
harness — it formalizes the file's shape and adds a self-audit
section that catches regressions from future refactors (accidental
section deletion, `chmod -x`, missing release.sh preflight entry).

**Completed:**
- [x] **Header comment block extended** with a "Sprint 6 ticket coverage" table mapping each shipped S6 ticket to its section marker. S6-07 is noted as living in `sprint-5.sh [S5-C]` (extended during Sprint 6) rather than having its own sprint-6 section. S6-02 / S6-03 / S6-06 / S6-09 are called out as not-yet-picked-up, with a pointer that any future work would add `[S6-D/E/F/…]` sections.
- [x] **`[S6-Z]` sprint-6.sh harness self-audit** (8 new sentinels):
  1–4. **Section header presence** — each of `[S6-A]`, `[S6-B]`, `[S6-C]`, `[S6-Z]` has its `echo "== [X] ..."` marker grep'd so a refactor that silently deletes a section fires here.
  5. **Executable bit** — `[[ -x sprint-6.sh ]]`. `release.sh` invokes the harness via `bash tests/integration/sprint-6.sh` (which tolerates `chmod -x`), but direct invokers would fail.
  6. **release.sh preflight reference** — mirrors the sprint-5.sh [S5-C] check so running just `sprint-6.sh` still catches the regression.
  7. **Shebang is `#!/bin/bash`** — bash 3.2-compatible constructs (no associative arrays) are used throughout, but a shebang swap to `/bin/sh` would break `[[ ... ]]` and `$(( ))`.
  8. **`set -uo pipefail`** — unbound variables and broken pipes must fire loudly. The BSD awk bug in v1.0.1 (S5-07) and the "MISSING: unbound variable" discovery during S6-01 would have been harder to catch without strict mode.

**Test count deltas:**
- `tests/integration/sprint-6.sh`: 29 → **37** (+8 from `[S6-Z]`)
- Total baseline: 1481 → **1489** across 12 test layers (1493 in live mode)

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

**S6-07 ✅ DONE** (release.sh CHANGELOG runtime sentinel). **S6-01 ✅ DONE** (concurrent Postgres CAS stress test). **S6-04 ✅ DONE** (Next.js `"use client"` surface + optional next build). **S6-05 ✅ DONE** (GPG-signed release tags + RELEASING.md). **S6-08 ✅ DONE** (sprint-6.sh closure + self-audit). Suggested next:

1. **S6-09** — Sprint 6 closure + v1.1.0 release notes. Cuts v1.1.0 through the new signing workflow, marks Sprint 6 ✅ COMPLETE, bumps CLAUDE.md counts, seeds `docs/SPRINT-7.md`. This is the sprint-ending ticket.
2. **S6-02** / **S6-03** / **S6-06** — larger items, confirm scope with user before picking up. Could also be deferred to a v1.2 sprint.

## Test inventory (after S6-08)

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
- tests/integration/sprint-6.sh: **37 bash assertions** (+8 from S6-08 [S6-Z] harness self-audit)
- Total: **1489 passing checks** across **12 test layers** (1493 with docker + pg live mode)
- Bonus (not in baseline): demo-app 45 vitest tests + nextjs-demo **66** vitest tests (41 from S5-05 + 25 from S6-04)

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
