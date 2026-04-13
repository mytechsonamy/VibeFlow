# Hooks

VibeFlow ships with **7 hook scripts** that wire into Claude Code's
event system. Each hook is small, defensive, and has a single
responsibility. All seven sit in `hooks/scripts/` and source the
shared `hooks/scripts/_lib.sh` for state access helpers.

| Hook | Trigger | Purpose | Async? |
|------|---------|---------|--------|
| `commit-guard.sh` | PreToolUse / Bash / `git commit` | Block commits in pre-DEVELOPMENT phases + enforce conventional commit format | no |
| `load-sdlc-context.sh` | SessionStart / startup\|resume | Inject the current SDLC state as a system note | no |
| `post-edit.sh` | PostToolUse / Edit\|Write | Append edited source files to a trace log for test selection | no |
| `trigger-ai-review.sh` | PostToolUse / Bash / `git commit` | Mark large diffs as pending multi-AI review | yes |
| `test-optimizer.sh` | PreToolUse / Bash / `npm test`\|`vitest`\|`jest` | Compute the smallest set of tests that cover the recent diff | no |
| `compact-recovery.sh` | SessionStart / compact | Re-inject SDLC state after Claude Code compacts the conversation | no |
| `consensus-aggregator.sh` | SubagentStop / * | Record reviewer verdicts and finalize when quorum is reached or timeout fires | no |

The hook event-to-script wiring lives in `hooks.json`. You should
not need to edit that file — the plugin owns it.

---

## `commit-guard.sh`

Runs **before** every `git commit` Bash invocation. Two
responsibilities:

1. **Phase gate** — if the current SDLC phase (read from
   `.vibeflow/state.db`, falling back to
   `vibeflow.config.json → currentPhase`) is BEFORE `DEVELOPMENT`
   in the canonical phase order, the commit is blocked with exit 2.
   The error message tells the user to advance the phase first.
2. **Conventional commits** — when a `-m "msg"` argument is present,
   the message must match
   `(feat|fix|chore|docs|test|refactor|style|perf|build|ci|revert)(\(scope\))?!?: subject`.

### Edge cases handled (S4-02 hardening)

- **Merge commits** — `git commit -m "Merge branch ..."` passes
  through. Git generates merge messages itself; blocking them would
  force users to rewrite git's output by hand.
- **Revert commits** — `git commit -m "Revert \"...\""` passes
  through. Same reasoning.
- **Command substitution** — `git commit -m "$(cat <<EOF ...)"`
  passes through. The hook captures the pre-expansion literal, and
  validating that against the conventional-commit regex would
  produce false rejections. The actual commit text only exists
  after shell expansion.
- **Editor flow** — `git commit` (no `-m`) passes through. The
  message is written via `$EDITOR`, which we can't see; let git
  handle it.
- **`git commit -a`** — no special handling needed, same code path.

### Customizing

Edit `hooks/scripts/commit-guard.sh` and adjust the regex on line
51. The integration harness at `hooks/tests/run.sh` will catch
regressions in either direction.

---

## `load-sdlc-context.sh`

Runs **once per session** at start or resume. Reads
`vibeflow.config.json` + `.vibeflow/state.db` and emits a one-line
context summary:

```
VibeFlow active: domain=e-commerce, mode=solo, phase=DEVELOPMENT, last_consensus=APPROVED, satisfied_criteria=4
Use /vibeflow:status for full state, /vibeflow:advance to move phase.
```

Claude Code injects this line into the session as a system note,
so the model sees the current SDLC state for every interaction.

### Degraded state (S4-02 hardening)

When sqlite3 is unavailable, state.db is missing, or state.db is
corrupt, the script falls back to the config's `currentPhase` and
appends an explicit note:

```
... satisfied_criteria=0 (degraded: state.db missing; phase read from config)
```

This is important because the model needs to know when the context
line is approximate. The fallback phase from `vibeflow.config.json`
is updated less often than the authoritative `state.db.current_phase`.

### Customizing

Edit `hooks/scripts/load-sdlc-context.sh` to add fields. To disable
the hint line entirely, edit `hooks.json` and remove the
`SessionStart / startup|resume` entry.

---

## `post-edit.sh`

Runs **after** every `Edit` or `Write` tool call on a source file.
Appends a TSV row to `.vibeflow/traces/changed-files.log`:

```
2026-04-13T11:00:00Z	DEVELOPMENT	/path/to/src/foo.ts
```

The log is the single source of truth for `test-optimizer.sh`
(recent diffs → candidate tests) and the `traceability-engine`
skill.

### Skip list (S4-02 hardening)

Files that don't represent source code are skipped silently:

- **Doc / data / lockfile extensions**: `.md`, `.json`, `.yaml`,
  `.yml`, `.toml`, `.lock`, `.log`, `.db`, `.svg`, `.png`, `.jpg`,
  `.gif`, `.ico`, `.woff/.woff2`, `.ttf`, `.eot`, `.otf`
- **Environment files**: `.env`, `.env.local`, etc.
- **OS metadata**: `.DS_Store`
- **Editor swap files**: `*.swp`, `*.swo`
- **Backup files**: `*~`, emacs lock files (`.#*`), emacs autosave
  files (`#*#`)
- **Anything inside `.vibeflow/`**: VibeFlow's own state directory
  is never logged (would create a feedback loop)

### Debounce (S4-02 hardening)

If the most recent log row for the same path is within **5 seconds**
of now, the new edit is skipped. This prevents auto-save / format-on-
save loops from hammering the log with duplicate entries. The
debounce is per-file, so editing `foo.ts` and `bar.ts` in quick
succession both log normally.

### Log cap

The log auto-trims to the last 1000 entries. Older edits are
dropped to keep `tail` reads fast.

### Customizing

Edit the skip-list regex or the `DEBOUNCE_SECONDS` constant near
the top of the script.

---

## `trigger-ai-review.sh`

Runs **after** every `git commit` Bash invocation, asynchronously.
When the most recent commit's diff is ≥ **50 changed lines**, writes
a pending-review marker to `.vibeflow/state/review-pending.json` so
the next consensus run picks it up.

### Solo mode

In solo mode, this hook is a no-op — solo means single-AI, no
multi-AI consensus, no review marker.

### Rate limit (S4-02 hardening)

In team mode, the hook enforces a **5-minute rate limit**: if a
review marker already exists and its `requestedAt` is within 300
seconds of now, the existing marker is left in place. Without this,
a flurry of rapid commits would overwrite the consensus orchestrator's
queue position on every commit.

### Customizing

The threshold is `THRESHOLD=50` on line 41. The rate limit is
`RATE_LIMIT_SECONDS=300`. Both can be edited in place.

---

## `test-optimizer.sh`

Runs **before** every `npm test` / `vitest` / `jest` Bash
invocation. Reads the changed-files log, maps each recently-edited
source file to a candidate test file using conventional name
patterns, and writes the candidate list to
`.vibeflow/state/next-test-hint.json`.

The hint is **non-blocking** — the test command runs unmodified.
Reading the hint is the responsibility of `/vibeflow:status` and
the `test-priority-engine` skill.

### Resolution patterns

For source `path/to/foo.ts`, the hook tries (in order):

1. `path/to/foo.test.ts`
2. `path/to/foo.spec.ts`
3. `path/to/__tests__/foo.test.ts`
4. `path/tests/foo.test.ts` (if the source path contains `/src/`)
5. `path/test/foo.test.ts` (same)

The first existing file wins. If none exists, the source has no
candidate test (which is itself useful information).

### Cache (S4-02 hardening)

Resolved mappings are cached in
`.vibeflow/state/test-mapping.cache.json` keyed by source file
path and tagged with the source's mtime. On the next run, if the
source file's mtime hasn't changed AND the cached test still
exists, the hook skips the resolution loop and reuses the cache
entry. Cache entries are evicted when the source file disappears.

### Customizing

Edit the `tries[]` array in the script to add new patterns (e.g.
to support `.steps.ts` for cucumber).

---

## `compact-recovery.sh`

Runs **after Claude Code compacts the conversation**. Re-injects
a snapshot of the current SDLC state so the model isn't left
reasoning from a stale summary. The snapshot is assembled fresh
from `.vibeflow/state.db` at hook time (NOT read from a cached
file) so it reflects every write that happened before compaction.

### Output shape

```
VibeFlow context restored after compact.
 phase=DEVELOPMENT, mode=solo, domain=e-commerce, last_consensus=APPROVED
 satisfied_criteria: prd.approved, testability.score>=60, design.approved
 Pending AI review: 80 lines @ a1b2c3d4.
Run /vibeflow:status for full state.
```

### Integrity check (S4-02 hardening)

Before emitting the snapshot, the hook walks four integrity checks:

1. `state.db` exists and `sqlite3 SELECT 1` succeeds
2. `satisfied_criteria` parses as JSON
3. `config.currentPhase` matches `state.db.current_phase`
4. `jq` is available

Any failure appends a `state integrity degraded: <reasons>` line so
the model knows to re-hydrate via `/vibeflow:status` rather than
trust the snapshot. The integrity check has caught real bugs
during development (config drift after a manual edit, db corruption
after a crash).

### Customizing

To suppress the snapshot entirely (rare — the model usually wants
it), remove the `SessionStart / compact` entry from `hooks.json`.

---

## `consensus-aggregator.sh`

Runs **after every subagent stops**. Records the reviewer's verdict
in `.vibeflow/state/consensus/<session>.jsonl` (one line per
reviewer). When the expected reviewer count is reached, computes an
aggregate status + agreement ratio and writes
`.vibeflow/state/consensus/<session>.verdict.json`.

### Verdict extraction

The hook scans the subagent's output text for keywords:

| Keyword | Verdict |
|---------|---------|
| `REJECTED` | REJECTED (highest precedence) |
| `NEEDS_REVISION` / `NEEDS REVISION` | NEEDS_REVISION |
| `APPROVED` | APPROVED |
| (none of the above) | UNKNOWN |

`critical issues: N` is also extracted from the output text.

### Aggregate status (CLAUDE.md thresholds)

- `criticalTotal ≥ 2` → REJECTED
- `agreement < 0.5` → REJECTED
- `agreement ≥ 0.9` AND `criticalTotal == 0` → APPROVED
- otherwise → NEEDS_REVISION

### Quorum

Solo mode expects 1 reviewer; team mode expects 3.

### Timeout (S4-02 hardening)

If a new review arrives and the oldest entry in the session log is
**> 600 seconds old** without quorum being reached, the batch is
force-finalized with `timeout: true`. This prevents the aggregator
from stalling forever when one of the 3 team reviewers never
responds (rate-limited, crashed, network dropped).

When the timeout fires, an APPROVED status is **demoted to
NEEDS_REVISION** — a partial quorum cannot ship an APPROVED
verdict because the missing reviewer could have objected. The
final verdict carries `expectedReviewers`, `receivedReviewers`,
and `timeout: true` fields for downstream auditing.

### Customizing

The timeout is `TIMEOUT_SECONDS=600`. The expected count is
implicit from `vf_mode` and cannot be customized per-session
(team mode is always 3 reviewers).

---

## `_lib.sh` — shared helpers

Every hook sources `_lib.sh`. The helpers are:

| Helper | Purpose |
|--------|---------|
| `vf_cwd` | Resolves the current project directory (respects `VIBEFLOW_CWD`) |
| `vf_config_path` | Path to `vibeflow.config.json` |
| `vf_state_db` | Path to `.vibeflow/state.db` |
| `vf_state_dir` | Path to `.vibeflow/state/` (creates if missing) |
| `vf_traces_dir` | Path to `.vibeflow/traces/` (creates if missing) |
| `vf_have_jq` / `vf_have_sqlite3` | Capability checks |
| `vf_config_get <jq-path>` | Read a field from the config (returns empty + nonzero on missing) |
| `vf_project_id` | Reads `.project` |
| `vf_mode` | Reads `.mode`, defaults to `"solo"` |
| `vf_current_phase` | Reads from state.db, falls back to config |
| `vf_last_consensus_status` | Reads the last consensus verdict |
| `vf_satisfied_criteria` | Reads the satisfied criteria array (defaults to `[]`) |
| `vf_phase_index <PHASE>` | Returns the canonical phase order index (REQUIREMENTS=0, ..., DEPLOYMENT=6) |

The helpers are deliberately defensive: every one returns a sane
empty value when its prerequisite (config / db / jq / sqlite3) is
missing. **Hooks must never crash the surrounding tool call** —
that's the load-bearing rule.

---

## Disabling a hook

To disable a hook permanently, edit `hooks.json` and remove the
matching trigger entry. To disable a hook for a single session,
set the environment variable `VIBEFLOW_HOOKS=disabled` before
launching `claude`.

To temporarily bypass `commit-guard.sh`'s phase block, advance the
phase to `DEVELOPMENT` instead of editing the hook — the phase
gate exists for a reason.

## Hook tests

Every hook has assertions in `hooks/tests/run.sh`. Run them with:

```bash
bash hooks/tests/run.sh
```

The test runner builds a throwaway temp project per hook (so
nothing touches your real `.vibeflow/`) and exercises the hook with
synthetic stdin. Current count: 50 assertions covering every hook
+ every S4-02 hardening edge case.
