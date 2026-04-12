# Scope Selection

How `regression-test-runner` picks which tests to run at Step 1 of
its algorithm. Scope is the #1 knob for "fast feedback" vs "full
audit", so getting it wrong is how a PR merges with a latent
regression the smoke set didn't cover.

There are three scopes. Every invocation resolves to exactly one.
There is no silent hybrid mode — a hybrid invocation is a caller
bug, and the skill refuses it.

---

## 1. `smoke`

**Intent:** fast feedback on every PR, every push. Target total
runtime ≤ 5 minutes. Optimized for coverage of the highest-value
paths, not for exhaustiveness.

**Composition (in order — the UNION is executed):**

1. Every test file tagged `@smoke` in a comment within the first
   20 lines of the file. The tag is a simple substring match to
   keep the scanner dependency-free:
   ```ts
   // @smoke — login happy path
   test(...)
   ```
2. Every test file listed in `test-strategy.md` → `smoke.include`.
3. Every test file matching a glob in `test-strategy.md` →
   `smoke.includeGlobs`.
4. **Every P0 test regardless of tag.** P0 is load-bearing — the
   smoke set always includes it. This rule is non-negotiable; the
   skill refuses a configuration that excludes P0 from smoke.

**Exclusions:**

- `test-strategy.md` → `smoke.exclude` (explicit file list)
- `test-strategy.md` → `smoke.excludeGlobs`
- Any test tagged `@slow` or `@slow:manual` (too expensive for
  smoke)
- Any test tagged `@quarantined` (quarantined tests never run —
  that's the whole point of the tag)

**What smoke does NOT do:**

- **Does not skip P0 tests** even if `smoke.excludeGlobs` would
  match them. P0 is always executed. The rule is enforced at
  scope-resolution time, not at runtime.
- **Does not prioritize** — smoke is a set, not an ordered list.
  Ordering is `test-priority-engine`'s job.

**When smoke is wrong:**

- If a PR regresses a test that's outside the smoke set, the regression
  lands on main and surfaces at the next `full` run. This is the
  price of fast feedback. The mitigation is in `test-strategy.md`
  — tighten the smoke set or bump more tests to P0.

---

## 2. `full`

**Intent:** total coverage. Used by release-track runs and
nightly scheduled jobs. No timeout budget beyond the runner
default (30 minutes).

**Composition:** every test file the runner would discover by
default, with a single allow-list override from `test-strategy.md`
→ `full.include` (used when the repo has generated files in
unusual directories).

**Exclusions:**

- `@slow:manual` — these require human operators and are out of
  scope for an automated regression run
- `@quarantined` — see above
- `test-strategy.md` → `full.exclude` (explicit file list, usually
  empty)

**Full scope is the only scope that promotes every baseline
entry.** A `smoke` run's verdict can refresh the smoke subset of the
baseline; the non-smoke baseline entries stay frozen until a `full`
run visits them. See `baseline-policy.md` §3.

---

## 3. `incremental`

**Intent:** lightweight feedback during local development, and the
default for `on-save` triggers wired to file watchers.

**Composition — the affected set:**

1. **Test files whose own path changed** between `--since <sha>`
   and `HEAD` → always included.
2. **Test files that import a changed source file** → included.
   Resolution:
   - Primary: call `codebase-intel` MCP's `ci_dependency_graph` to
     get the import graph, then walk transitive dependents of each
     changed source file.
   - Fallback: if `codebase-intel` is unavailable, use directory
     proximity — every test file under the same directory subtree
     as a changed source file is included. This is a less precise
     heuristic but never misses a test, at the cost of false
     positives.
3. **Every P0 test regardless of whether its file changed.** Same
   reason as smoke — P0 is always run.

**When `incremental` becomes `smoke`:** if the affected set is
larger than 50% of the smoke set, the skill promotes the scope to
`smoke` and records the promotion in the run report. Running an
"incremental" that's bigger than smoke is just smoke with worse
branding.

**When `incremental` blocks:**

- `--since <sha>` must resolve to a real commit. Unresolvable
  refs block.
- A dirty working tree with no `--allow-dirty` blocks, same as
  the precondition in the main algorithm.
- A cold start (no previous baseline) cannot use `incremental` —
  the skill refuses with "incremental scope requires a baseline;
  run a full scope first to establish one".

---

## 4. Scope decision tree (the skill's Step 1 flow)

```
┌─ --scope <explicit>? ───── yes ──► use that
└─ no
   ├─ trigger == "pr" / "push" ── yes ──► smoke
   ├─ trigger == "release" ────── yes ──► full
   └─ trigger == "manual" ─────── yes ──► smoke
```

Scope is resolved before any test file is discovered. The chosen
scope is logged in the run report AND in the run metadata JSON so
downstream consumers can tell whether a missing test is
"not-executed (out of scope)" or "not-executed (runner didn't
discover it)".

---

## 5. `test-strategy.md` fields this file consumes

```yaml
smoke:
  include:           # explicit list
    - tests/unit/auth.test.ts
  includeGlobs:
    - "tests/unit/**/*.test.ts"
  exclude:           # explicit list
    - tests/unit/legacy/*.test.ts
  excludeGlobs:
    - "tests/unit/fixtures/**"

full:
  include: []
  exclude: []

incremental:
  directoryFallbackDepth: 2   # how far up to walk when codebase-intel is down
```

All fields are optional. When `test-strategy.md` is absent, the
skill uses sensible defaults: smoke = every `@smoke`-tagged file +
every P0 test; full = everything except `@slow:manual` /
`@quarantined`; incremental = affected set with directory fallback
depth 1.

---

## 6. What scope selection does NOT do

- **Does not discover tests by running them.** That's
  backwards. The scope is computed from the filesystem + the
  dependency graph BEFORE the runner is invoked.
- **Does not parallelize selection.** The set is deterministic for
  a given (scope, sha, test-strategy.md) triple. Two runs with
  identical inputs select identical files.
- **Does not dedupe across globs.** The skill internally converts
  the union to a sorted Set of file paths so a file matched by
  three globs still runs exactly once.
- **Does not silently skip a failing runner discovery.** If the
  runner reports "0 tests discovered" but the scope resolved to a
  non-empty set, that's a runner misconfiguration and blocks the
  run.
