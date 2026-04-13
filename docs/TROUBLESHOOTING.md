# Troubleshooting

Common failure modes with cause + fix. If your symptom isn't here,
check `.vibeflow/logs/` for hook output and the
`/vibeflow:status` command for state details.

## Phase + commit problems

### `commit-guard: commits are blocked in phase REQUIREMENTS`

**Cause**: you tried to `git commit` while the project's current SDLC
phase is before `DEVELOPMENT`. The phase order is REQUIREMENTS →
DESIGN → ARCHITECTURE → PLANNING → DEVELOPMENT, and code commits are
only allowed at DEVELOPMENT or later.

**Fix**: advance the phase via the SDLC engine, ideally one step at
a time (each phase has entry criteria):

```
/vibeflow:advance DESIGN
/vibeflow:advance ARCHITECTURE
/vibeflow:advance PLANNING
/vibeflow:advance DEVELOPMENT
```

If you're working on a hotfix and need to bypass this entirely,
you're in the wrong pipeline — use PIPELINE-5 (Hotfix), which
explicitly skips early-phase gates.

### `commit-guard: commit message must follow conventional commits`

**Cause**: your `-m` argument doesn't match the conventional-commit
regex.

**Fix**: prefix the message with `feat:` / `fix:` / `chore:` /
`docs:` / `test:` / `refactor:` / `style:` / `perf:` / `build:` /
`ci:` / `revert:`. Optional scope in parens. Example:

```bash
git commit -m "feat(catalog): add unique-SKU validation"
```

`Merge ` and `Revert "..."` prefixes (git's built-in formats) pass
through automatically — you don't need to rewrite them.

### Conventional-commit guard rejects a `$(...)` message

**Should not happen** as of S4-02. The guard detects shell command
substitution in the captured literal and passes through. If it
does fire, the bug is in `hooks/scripts/commit-guard.sh` line
~50 — the `$(...)` / `${...}` detection.

## State + database problems

### `load-sdlc-context (degraded: state.db missing; phase read from config)`

**Cause**: the `.vibeflow/state.db` file doesn't exist. You either
ran `/vibeflow:init` and the init didn't create the db, OR the db
was deleted by hand.

**Fix**: re-run `/vibeflow:init` to recreate it. The phase you see
in the degraded note comes from `vibeflow.config.json.currentPhase`,
which is fine for read-only work but will be overwritten on the
first `/vibeflow:advance` once state.db is rebuilt.

### `load-sdlc-context (degraded: state.db unreadable)`

**Cause**: state.db exists but sqlite3 can't open it. Most common
cause: the file was corrupted by a crash mid-write, or a different
sqlite3 version wrote it (incompatible page format).

**Fix**: back up the corrupted file and reinitialize:

```bash
mv .vibeflow/state.db .vibeflow/state.db.corrupted-$(date +%s)
/vibeflow:init                  # recreates state.db
```

If you have important satisfied criteria you don't want to lose,
read them out of the corrupted file with `sqlite3 .vibeflow/state.db.corrupted-* "SELECT satisfied_criteria FROM project_state;"` first.

### `state integrity degraded: config.currentPhase=REQUIREMENTS disagrees with state.db=DEVELOPMENT`

**Cause**: someone edited `vibeflow.config.json` by hand and
overwrote `currentPhase`. The compact-recovery hook caught the
disagreement.

**Fix**: state.db wins (it's authoritative). Either revert the
config change, or run `/vibeflow:status` followed by
`/vibeflow:init --sync` to reconcile the config to the db.

### `compact-recovery: state integrity degraded: jq not installed`

**Cause**: the `jq` binary isn't on PATH. Hooks need jq to parse
JSON state.

**Fix**: install jq.

```bash
brew install jq                 # macOS
sudo apt install jq             # Ubuntu / Debian
```

### `state.db database is locked`

**Cause**: another process holds the SQLite write lock — usually
another Claude Code session. SQLite serializes writes, so two
parallel sessions on the same project will collide.

**Fix**: close the other session, OR migrate to team mode
(PostgreSQL handles concurrent writes via row-level locking).

## PRD + scoring problems

### `prd-quality-analyzer: testabilityScore 42 — BLOCKED`

**Cause**: your PRD doesn't meet the minimum testability threshold
for the project's domain. `general` requires 60, `e-commerce`
requires 75, `financial` and `healthcare` require 80.

**Fix**: read the report's `ambiguousTerms` section and rewrite the
flagged sentences. The most common offenders are:

- "fast" / "performant" — replace with a specific budget (e.g. "p95 < 200ms")
- "easy" / "intuitive" — replace with a measurable usability outcome
- "scalable" — replace with a specific load target (e.g. "10k concurrent users")
- "robust" — replace with specific failure modes the system handles
- Missing acceptance criteria on P0 requirements — add a "Verify:" line per requirement

The demo PRD at `examples/demo-app/docs/PRD.md` is a good reference
for the shape that scores high.

### `prd-quality-analyzer: missingAcceptanceCriteria > 0`

**Cause**: at least one P0 requirement has no measurable outcome.

**Fix**: every P0 requirement needs a "MUST" or "REJECTS" verb plus
a single observable outcome. "The system MUST display search results
within 200ms" is testable. "The system should be fast" is not.

## Coverage + test problems

### `coverage-analyzer: zero P0 uncovered — BLOCKED`

**Cause**: at least one line in a P0-priority code path has no test
coverage. The skill's gate is hard — there's no "mostly covered"
escape.

**Fix**: read the report's `gaps` section, sorted by `gapScore`
(highest first). The first entry is the highest-leverage uncovered
file. Add a test for it, then re-run.

If the line genuinely cannot be tested (e.g. a defensive `throw`
on an unreachable code path), exclude it via a `/* coverage:
ignore */` comment AND document the exclusion in
`coverage-report.md`'s `excludedLines` section. Unjustified
exclusions are also a hard block.

### `coverage-analyzer: critical-path coverage < 100%`

**Cause**: a file listed in `vibeflow.config.json → criticalPaths`
has uncovered lines. Critical paths must hit 100% line + branch
coverage with no exception.

**Fix**: same as above, but stricter — exclusions are NOT allowed
on critical paths. Either add a test or remove the file from
`criticalPaths` (if it shouldn't be critical).

### `vitest: ERROR: Coverage for branches (75.92%) does not meet global threshold (80%)`

**Cause**: an MCP server's vitest config now enforces ≥ 80% on
all four coverage axes (statements / lines / functions / branches).
Your last edit dropped the branch coverage below 80%.

**Fix**: identify the file by running `npx vitest run --coverage`
and looking at the per-file table. Add a test that exercises the
uncovered branch. The S4-01 commit added a worked example at
`mcp-servers/observability/tests/parsers.test.ts` — its
"edge branches" describe block is full of focused branch tests.

### `Tests dropped below floor: sdlc-engine: test count 102 dropped below floor 104`

**Cause**: someone deleted tests from one of the MCP servers. The
sprint-4.sh harness records baseline floors per server.

**Fix**: either restore the tests, OR consciously update the floor
in `tests/integration/sprint-4.sh` (`TEST_FLOORS` array) AND in
the S4-01 entry of `docs/SPRINT-4.md`. Updating the floor is the
explicit "yes I removed those" gesture.

## MCP server problems

### `Cannot find dependency '@vitest/coverage-v8'`

**Cause**: you ran `npx vitest run --coverage` on an MCP server
that doesn't have the v8 coverage provider installed. This was
fixed in S4-01 — every server got the dep.

**Fix**:

```bash
cd mcp-servers/<server>
npm install --save-dev @vitest/coverage-v8@^2.1.2
```

### `design-bridge: FIGMA_TOKEN required`

**Cause**: you called a Figma-dependent tool without setting
`userConfig.figma_token`. Lazy construction means
`db_compare_impl` and `tools/list` work without a token, but
`db_fetch_design` / `db_extract_tokens` / `db_generate_styles`
all require one.

**Fix**: open Claude Code settings → Plugins → vibeflow → enter
your Figma personal access token. Create one at
[figma.com → Settings → Personal access tokens](https://www.figma.com/settings).

### `dev-ops: GITHUB_TOKEN required`

**Cause**: same shape as the Figma one but for GitHub.

**Fix**: Claude Code settings → Plugins → vibeflow → enter your
GitHub PAT. The token needs `actions:write` and `contents:read`
at minimum.

### `sdlc-engine: pg idle client error: idle client lost connection`

**Cause**: the PostgreSQL connection pool had an idle client that
the database closed. This is a transient warning and the next
query reconnects automatically.

**Fix**: ignore the warning. If it happens repeatedly under load,
adjust the pool's `idleTimeoutMillis` in
`mcp-servers/sdlc-engine/src/state/postgres.ts`.

### `Plugin loaded but commands missing`

**Cause**: you started Claude Code without `--plugin-dir` or the
plugin is installed under a different name.

**Fix**:

```bash
cd ~/Projects/VibeFlow
claude --plugin-dir ./
```

Verify with `/help` — every `/vibeflow:*` command should appear in
the list. If they don't, the plugin failed to load. Check
`.claude-plugin/plugin.json` exists at the directory you passed.

## Hook + automation problems

### `post-edit: log not updating`

**Cause**: either the file extension is in the skip list, the file
path contains `.vibeflow/`, or the same file was edited within the
debounce window (5 seconds).

**Fix**: check the file extension against the skip list in
`hooks/scripts/post-edit.sh`. Check that the path is not inside
`.vibeflow/`. If both look fine, wait 5 seconds and edit again —
the debounce only suppresses rapid same-file edits.

### `trigger-ai-review: marker not appearing despite a 100-line commit`

**Cause**: either you're in solo mode (the hook is a no-op in solo),
OR the rate limit is suppressing the write because a marker from
the last 5 minutes still exists, OR git is not available in the
PATH.

**Fix**: check `vibeflow.config.json → mode`. In team mode, check
`.vibeflow/state/review-pending.json` — if it exists with a
recent `requestedAt`, the rate limit is in effect. Wait 5 minutes
or delete the marker file and re-trigger.

### `consensus-aggregator: verdict file never appears`

**Cause**: the expected reviewer count hasn't been reached. Solo
mode expects 1, team mode expects 3. If a reviewer never reports
back (rate-limited, crashed), the aggregator stalls forever —
unless 600 seconds have passed and the timeout force-finalize
triggers.

**Fix**: check `.vibeflow/state/consensus/<session>.jsonl`. Each
line is one reviewer's verdict. Compare the count to the expected
number. If you're in team mode and stuck at 1 or 2 reviewers, wait
until the next subagent stop event fires the aggregator — at that
point, if the oldest entry is > 10 minutes old, the timeout will
force-finalize with `timeout: true` and demote any APPROVED to
NEEDS_REVISION.

## CLI + plugin problems

### `claude --plugin-dir ./ → command not found: claude`

**Cause**: the Claude Code CLI isn't installed.

**Fix**: install it from [claude.com/claude-code](https://claude.com/claude-code).

### `git commit hook produces no output but exit 1`

**Cause**: a hook script is silently failing. Either the hook
crashed before printing its error, or it exited with a non-2 code
that Claude Code interprets as "failure".

**Fix**: run the hook directly with the same input to see the
real error:

```bash
echo '{"tool_input":{"command":"git commit -m \"feat: test\""}}' \
  | bash hooks/scripts/commit-guard.sh
echo "exit=$?"
```

A nonzero exit code (other than 2) means the hook itself crashed —
check that `jq` and `sqlite3` are installed and on PATH.

## Plugin dev problems

### `npm test in mcp-servers/X fails with module not found`

**Cause**: dist files aren't built, or `npm install` was skipped.

**Fix**:

```bash
cd mcp-servers/<server>
npm install
npm run build      # or `tsc`
npm test
```

### `Integration harness sentinel fails after editing a SKILL.md`

**Cause**: a sentinel in `tests/integration/run.sh`,
`sprint-2.sh`, `sprint-3.sh`, or `sprint-4.sh` matches a literal
substring of the SKILL.md content, and your edit changed that
substring.

**Fix**: check the failure message — the sentinel name tells you
which substring is missing. Either restore the substring (if the
edit was unintentional) or update the sentinel (if the edit was
intentional and improves the doc). The same discipline applies to
every doc-tracking sentinel in the harness suite.

## When all else fails

1. Check `/vibeflow:status` — does the basic state look right?
2. Check `bash hooks/tests/run.sh` — do the hook tests still pass
   on your machine?
3. Check `bash tests/integration/run.sh` — does the platform
   harness still pass?
4. File an issue at
   [github.com/mustiyildirim/vibeflow/issues](https://github.com/mustiyildirim/vibeflow/issues)
   with the output of all three.
