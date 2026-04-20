---
name: apply-arbiter-patch
description: Reads the patch manifest produced by consensus-arbiter, shows a git-style diff summary, asks for explicit operator confirmation (unless --yes), and applies via `git apply`. Updates `arbiter-decisions.md` with applied:true + timestamp. Optional `--run-tests` runs the project's test command afterward and reminds the operator how to revert if they break.
disable-model-invocation: true
allowed-tools: Read Write Edit Bash(git *) Bash(jq *) Bash(npm *) Bash(vitest *) Bash(jest *) Bash(pytest *) Bash(dotnet *)
context: fork
---

# Apply Arbiter Patch

This is the operator-in-the-loop half of the MyVibe closed review
cycle. `consensus-arbiter` wrote patches without touching source;
this skill shows the diffs, waits for explicit approval, and applies
them one-by-one via `git apply` with automatic rollback on failure.

## Phase Contract

This skill runs in **DEVELOPMENT** or **TESTING** when applying code
patches, and in any phase when applying markdown/doc patches — the
existing phase-write-guard hook (Sprint 13) gates by target path,
not by skill, so the patches themselves decide what's legal in the
current phase.

Before any step, read `vibeflow.config.json.currentPhase`. If the
manifest lists patches targeting `src/**` and current phase is
pre-DEVELOPMENT, emit the phase-write-guard's standard rejection and
stop — don't attempt an apply that will partially land and then
fail mid-session.

## Input

Positional:
- `$ARGUMENTS[0]` — session id. Optional; defaults to the most
  recent directory under `.vibeflow/state/patches/`.

Flags:
- `--yes` (or `-y`) — skip the interactive confirmation and apply
  immediately. Use in CI.
- `--run-tests` — after successful apply, run the project's test
  command (detected from `vibeflow.config.json.tech.testRunner` or
  package.json scripts). On failure, print the `git checkout`
  command that rolls back the last patch set.
- `--dry-run` — show the diff summary and exit without applying.

## Process

### Step 1: Resolve the session

```
if [ -n "$1" ]; then
  SESSION="$1"
else
  SESSION=$(ls -t $(vf_state_dir)/patches/ 2>/dev/null | head -1)
fi
MANIFEST=$(vf_state_dir)/patches/$SESSION/manifest.json
[ -f "$MANIFEST" ] || fail "no manifest for session $SESSION"
```

### Step 2: Summarise

Read the manifest. For each patch, compute `+N/-N` line counts via
`git apply --numstat <patch>`. Collect:

- Target files (unique)
- Total +/-
- Per-patch: file, short description, sources (reviewer ids), +/-

Emit a single structured summary block (NOT budget-capped — this
is the operator's only preview):

```
Arbiter patch preview — session <session>
  Iteration: 1
  Phase: <phase>
  Patches: 3 (targeting 2 files)
  Total: +48 -12

  01-error-flows-section.patch
    target: docs/PRD.md (+20 -2)
    sources: claude-3, codex-1
    rationale: Adds missing error-handling flow section 4.2

  02-rate-limiting-spec.patch
    target: docs/PRD.md (+18 -0)
    ...

Apply all 3? [y/N]
```

### Step 3: Prompt or auto-confirm

- If `--dry-run`: stop here, exit 0.
- If `--yes`: log "apply confirmed via --yes" and proceed.
- Otherwise: ask. Accept `y`/`yes` (case-insensitive). Anything else
  aborts with "apply cancelled by operator".

### Step 4: Apply

For each patch in manifest order:

```
git apply --check "$PATCH_FILE"          # dry-run: fails on conflict
if [ $? -ne 0 ]; then
  emit "Patch NN-<slug>.patch cannot apply cleanly (conflict)."
  emit "  Remaining patches deferred. Run /vibeflow:consensus-arbiter"
  emit "  with a fresh session to regenerate against current state."
  break
fi
git apply "$PATCH_FILE"
APPLIED_COUNT=$((APPLIED_COUNT + 1))
```

Patch application goes through phase-write-guard (Sprint 13) on the
Write tool, so the user's phase policy still governs which files
can be modified. A blocked write aborts the apply of that patch and
leaves earlier patches in place — consistent with git apply's
atomic-per-patch semantics.

### Step 5: Update the decision log

For each applied patch, edit `.vibeflow/reports/arbiter-decisions.md`:

- In the APPLY section, the line `Applied: false` flips to
  `Applied: true (appliedAt: <ISO>, patch: NN-<slug>.patch)`.
- Preserve all DEFER + REJECT entries unchanged.

### Step 6 (optional): Run tests

When `--run-tests`:

```
TESTCMD=$(jq -r '.tech.testRunner // empty' vibeflow.config.json)
case "$TESTCMD" in
  vitest|jest) npm test ;;
  pytest)      pytest ;;
  dotnet)      dotnet test ;;
  *)           npm test ;;  # fallback
esac
```

On non-zero exit:

```
Tests failed after arbiter apply. To revert the patches:
  git checkout HEAD -- <list of touched files>
Or cherry-pick the offending patch and re-run:
  /vibeflow:consensus-arbiter <session>   # regenerates against current tree
```

### Step 7: Record outcome

Append an `applied/<session>.json` under
`.vibeflow/state/patches/` summarising the run for audit:

```json
{
  "sessionId": "<session>",
  "appliedAt": "<ISO>",
  "patchCount": 3,
  "applied": 3,
  "skipped": 0,
  "testsRun": true,
  "testsPassed": true
}
```

## Output

- Modified source / doc files (via `git apply`)
- `.vibeflow/reports/arbiter-decisions.md` updated in place
- `.vibeflow/state/patches/applied/<session>.json`

## Rollback

Every git apply is a single commit-less change; use:

```
git checkout HEAD -- <file>                # revert one file
git reset --hard HEAD                      # nuke all uncommitted changes
git stash                                  # keep them for later
```

The skill does not auto-revert on test failure — it only prints the
command the operator should run. This is intentional: a tests-green
post-apply state is the only signal we trust; guessing at recovery
could compound the damage.

## Downstream Dependencies

- The Sprint 15-H harness (`tests/integration/sprint-15.sh [S15-G]`)
  pins the presence of `--yes`, `--run-tests`, `--dry-run`, the
  diff preview format, and the phase-write-guard handoff.
- `learning-loop-engine` may later consume `applied/<session>.json`
  to track which suggestion types land successfully vs. get
  reverted.

## Final Step: No Auto-Consensus

This skill applies a decision set; it does **not** re-invoke
consensus. Running consensus against the just-applied changes is the
operator's call — commit first, then `/vibeflow:consensus-orchestrator`
on the new diff if a second opinion is warranted.
