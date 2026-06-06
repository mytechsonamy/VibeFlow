---
name: apply-arbiter-patch
description: Reads the patch manifest produced by consensus-arbiter, shows a git-style diff summary, snapshots every target file to a git-independent backup, asks for explicit operator confirmation (unless --yes), and applies via `git apply`. Updates `arbiter-decisions.md` with applied:true + timestamp. Optional `--run-tests` runs the project's test command afterward and reminds the operator how to revert if they break.
disable-model-invocation: true
allowed-tools: Read Write Edit Bash(git *) Bash(jq *) Bash(npm *) Bash(vitest *) Bash(jest *) Bash(pytest *) Bash(dotnet *) Bash(rm *) Bash(cp *) Bash(mkdir *)
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
- `--no-chain` — skip Sprint 19-E auto-chain (Step 9). Apply the
  patch, record the outcome, drain markers, and stop. Operator
  must invoke `/vibeflow:consensus-orchestrator <primary>` manually
  to verify convergence.

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

- **Target files (unique)** → keep this list as `TARGET_FILES` (a bash
  array); Step 3.5 snapshots exactly these paths before applying.
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

### Step 3.5: Snapshot the target files (git-independent safety net)

**MANDATORY — run this after confirmation, before the first `git apply`.**
The rollback story below leans on `git checkout HEAD -- <file>`, which
only works when the project is a git repo **and** the target file is
committed. Many projects in REQUIREMENTS are just a PRD with no repo yet
(or an uncommitted doc), so `git apply` would rewrite the artifact in
place with **no way back**. Snapshot first so rollback always works,
regardless of git:

```bash
SNAP_DIR=".vibeflow/state/arbiter-backups/$SESSION"
mkdir -p "$SNAP_DIR"
# Target files = the unique list collected in Step 2 (git apply --numstat).
for f in "${TARGET_FILES[@]}"; do
  [ -f "$f" ] || continue                       # new-file patch → nothing to back up
  mkdir -p "$SNAP_DIR/$(dirname "$f")"
  cp -p "$f" "$SNAP_DIR/$f"
done
```

Emit a one-line confirmation naming the restore command so the operator
always has it in scrollback:

```
Backed up <N> file(s) to .vibeflow/state/arbiter-backups/$SESSION/ before applying.
Revert anytime:  cp -R .vibeflow/state/arbiter-backups/$SESSION/. .
```

The snapshot is the **primary** rollback path (works without git); the
`git checkout` commands below remain available as a secondary path when
the project IS a committed git repo.

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
  cp -R .vibeflow/state/arbiter-backups/<session>/. .   # git-independent (Step 3.5 snapshot)
  git checkout HEAD -- <list of touched files>          # only if a committed git repo
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

**Sprint 20-A — arbiter-decision history row.** Append a second-class
row to the cross-session roll-up `.vibeflow/state/consensus/history.jsonl`
recording which suggestion themes this apply run accepted vs rejected,
tagged with the round it acted on. The slow loop (learning-loop-engine
`consensus-history` mode, Sprint 20-C) joins these `arbiter-decision`
rows against the *next* round's `verdict` row to measure whether
applying a theme actually moved agreement — the wasted-effort signal.

```bash
CONS_DIR="$(vf_state_dir)/consensus"
HISTORY_FILE="$CONS_DIR/history.jsonl"
MANIFEST="$(vf_state_dir)/patches/$SESSION/manifest.json"
VERDICT_FILE="$CONS_DIR/$SESSION.verdict.json"
ARB_ROUND="$(jq -r '.round // .finalRound // 1' "$VERDICT_FILE" 2>/dev/null || echo 1)"
# Applied themes = patch targets from the manifest; rejected = manifest
# reject[] when the arbiter populated it (else empty — applied signal is
# what S20-C correlates on).
APPLIED_THEMES="$(jq -c '[.apply[]?.target] | unique' "$MANIFEST" 2>/dev/null || echo "[]")"
REJECTED_THEMES="$(jq -c '[.reject[]?.target] | unique' "$MANIFEST" 2>/dev/null || echo "[]")"
ARB_ROW="$(jq -n -c \
  --arg sid "$SESSION" \
  --argjson round "$ARB_ROUND" \
  --argjson applied "${APPLIED_THEMES:-[]}" \
  --argjson rejected "${REJECTED_THEMES:-[]}" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{type:"arbiter-decision", sessionId:$sid, round:$round,
    applied:$applied, rejected:$rejected, recordedAt:$ts}')"
mkdir -p "$CONS_DIR"; touch "$HISTORY_FILE"
printf '%s\n' "$ARB_ROW" >> "$HISTORY_FILE"
```

### Step 8: Drain the consensus-needed marker (Sprint 16-B)

After the applied/<session>.json record is written (and before
writing the auto-chain marker in Step 9), drain both consensus
markers so the PREVIOUS iteration is closed cleanly:

```bash
rm -f "$(vf_state_dir)/consensus-needed.json"
rm -f "$(vf_state_dir)/review-pending.json"
```

**Why:** the orchestrator and arbiter already drained these, but the
operator may have invoked `/vibeflow:apply-arbiter-patch` directly on
a stored session — in which case the marker from the original
analysis skill is still set and the next tool call would be blocked
by `consensus-gate.sh`. Draining here closes the loop no matter how
the skill was reached.

### Step 9: Auto-chain next consensus round (Sprint 19-E)

Apply completed successfully — if `--run-tests` was set, the suite
also passed. The natural next question is "did the patch actually
converge?" Until Sprint 19, operators had to hand-invoke the
orchestrator on the updated artifact. Step 9 closes the loop:
writes a fresh `consensus-needed.json` marker for iteration N+1
so `consensus-gate` blocks the next tool call with the required
command.

**Skip conditions** (all exit before marker write):

- `--no-chain` CLI flag was passed.
- `VF_SKIP_AUTO_CHAIN=1` env override.
- `git apply` failed or tests failed (covered by earlier steps
  returning non-zero — we only reach Step 9 on success).
- Convergence stall: `verdict(round).agreement -
  verdict(round-1).agreement <= 0.05` AND `round >= 2`. Emits
  `.vibeflow/reports/convergence-stalled.md` with the agreement
  curve and stops.
- Max iterations: if `nextRound > consensus.maxIterations`
  (default 5 per Sprint 17-F), write
  `.vibeflow/reports/max-iterations-reached.md` and stop.

```bash
# Sprint 19-E auto-chain. Reads verdict.round (Sprint 17-A) to
# compute the next iteration. Skipped via --no-chain or VF_SKIP_AUTO_CHAIN=1.
if [[ "${NO_CHAIN:-0}" == "1" ]] || [[ "${VF_SKIP_AUTO_CHAIN:-}" == "1" ]]; then
  echo "Auto-chain opt-out honoured. Run /vibeflow:consensus-orchestrator <primary> manually to verify convergence."
  exit 0
fi

VERDICT_FILE="$(vf_state_dir)/consensus/$SESSION_ID.verdict.json"
[ -f "$VERDICT_FILE" ] || exit 0

CURRENT_ROUND="$(jq -r '.round // .finalRound // 1' "$VERDICT_FILE")"
MAX_ITER="$(vf_config_get '.consensus.maxIterations' 2>/dev/null || echo 5)"
NEXT_ROUND=$((CURRENT_ROUND + 1))

if (( NEXT_ROUND > MAX_ITER )); then
  cat > .vibeflow/reports/max-iterations-reached.md <<EOF
# Max Iterations Reached

Session: $SESSION_ID
Reached round $CURRENT_ROUND of maxIterations=$MAX_ITER.
Convergence did not land as APPROVED within the configured budget.

Next options:
- Raise consensus.maxIterations in vibeflow.config.json
- Review verdict.json.rounds[] agreement curve and triage manually
- Advance via /vibeflow:advance with humanOverrideNote="…" (per Sprint 17-C)
EOF
  exit 0
fi

# Convergence-stall guard (round >= 2 only — round 1 has no prior).
if (( CURRENT_ROUND >= 2 )); then
  DELTA="$(jq -r --argjson r $((CURRENT_ROUND - 1)) \
    '(.rounds | map(select(.round == $r + 1))[0].agreement)
     - (.rounds | map(select(.round == $r))[0].agreement)' \
    "$VERDICT_FILE" 2>/dev/null || echo "0")"
  # "stalled" = delta in [-0.05, 0.05]
  if awk -v d="$DELTA" 'BEGIN{exit !(d <= 0.05 && d >= -0.05)}'; then
    cat > .vibeflow/reports/convergence-stalled.md <<EOF
# Convergence Stalled

Session: $SESSION_ID
Agreement delta round $((CURRENT_ROUND - 1)) → $CURRENT_ROUND: $DELTA (≤ 0.05).
Two consecutive rounds with negligible movement; auto-chain halted to avoid spinning.

Rounds so far:
$(jq -r '.rounds[] | "  round \(.round): agreement=\(.agreement), criticalTotal=\(.criticalTotal), status=\(.status)"' "$VERDICT_FILE")

Manual next step:
- /vibeflow:consensus-specialist $SESSION_ID (deep rewrite)
- or /vibeflow:advance with humanOverrideNote if results are good enough
EOF
    exit 0
  fi
fi

# Read primaryArtifact from the draining marker (preserved from the
# original analysis skill's Sprint 19-A marker).
PRIMARY="$PRIMARY_ARTIFACT_FROM_ORIGINAL_MARKER"     # carried from Step 1's manifest read
EVIDENCE_JSON="$ORIGINAL_EVIDENCE_JSON"              # same source

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --arg primary "$PRIMARY" \
  --argjson evidence "$(printf '%s' "$EVIDENCE_JSON" | jq -c '. + [".vibeflow/reports/arbiter-decisions.md"]')" \
  --arg legacy "$PRIMARY" \
  --arg cmd "/vibeflow:consensus-orchestrator $PRIMARY" \
  --arg ts "$TS" \
  --arg sid "$SESSION_ID" \
  --argjson round "$NEXT_ROUND" \
  '{
    primaryArtifact: $primary,
    evidence: $evidence,
    artifact: $legacy,
    requiredCommand: $cmd,
    createdAt: $ts,
    createdBy: "apply-arbiter-patch (auto-chain)",
    autoChain: { round: $round, parentSessionId: $sid }
  }' > "$(vf_state_dir)/consensus-needed.json"

echo "Round $CURRENT_ROUND applied. consensus-gate will block next tool call — run /vibeflow:consensus-orchestrator $PRIMARY to verify convergence (round $NEXT_ROUND). Use --no-chain or VF_SKIP_AUTO_CHAIN=1 to opt out."
```

**Why iterate on `verdict.round`, not a new manifest field?** Sprint
17-A already writes `round` / `finalRound` into verdict.json; the
orchestrator increments it via the `current-round.txt` marker. Apply
just reads the latest and points the next round at the
(now-updated) primary. No new state file needed.

## Output

- `.vibeflow/state/arbiter-backups/<session>/` — pre-apply snapshot of every
  target file (Step 3.5), the git-independent rollback source
- Modified source / doc files (via `git apply`)
- `.vibeflow/reports/arbiter-decisions.md` updated in place
- `.vibeflow/state/patches/applied/<session>.json`

## Rollback

**Primary (always works — Step 3.5 git-independent snapshot):**

```
cp -R .vibeflow/state/arbiter-backups/<session>/. .   # restore every touched file
```

**Secondary (only when the project is a committed git repo):**

```
git checkout HEAD -- <file>                # revert one file
git reset --hard HEAD                      # nuke all uncommitted changes
git stash                                  # keep them for later
```

The snapshot path is what makes rollback reliable for non-git / REQUIREMENTS
projects (e.g. a bare PRD), where `git checkout` has nothing to restore from.

The skill does not auto-revert on test failure — it only prints the
command the operator should run. This is intentional: a tests-green
post-apply state is the only signal we trust; guessing at recovery
could compound the damage. (The snapshot is kept on disk so the operator
can revert deliberately at any time.)

## Downstream Dependencies

- The Sprint 15-H harness (`tests/integration/sprint-15.sh [S15-G]`)
  pins the presence of `--yes`, `--run-tests`, `--dry-run`, the
  diff preview format, and the phase-write-guard handoff.
- `learning-loop-engine` may later consume `applied/<session>.json`
  to track which suggestion types land successfully vs. get
  reverted.

## Final Step: Auto-chain Consensus (Sprint 19-E)

Replaces the Sprint 17-era "no auto-consensus" stance. After
successful apply + (optional) tests, Step 9 writes a fresh
consensus-needed marker pointing at the same primaryArtifact for
iteration N+1. The gate blocks the next tool call with the
required command, closing the converge-then-verify loop.

Opt-out: `--no-chain` CLI flag or `VF_SKIP_AUTO_CHAIN=1`. Skipped
automatically when agreement stalls (Δ ≤ 0.05 over 2 rounds) or
when `consensus.maxIterations` is exhausted.
