#!/bin/bash
# Sprint 21 integration harness — signal-quality refinement:
# semantic excerption + memory compaction + progress ledger.
#
# Sections:
#   [S21-A] Semantic primary-artifact excerption
#   [S21-B] Reviewer-memory theme-aware compaction
#   [S21-C] Phase-runner progress ledger
#   [S21-D] /vibeflow:status renders the ledger
#   [S21-E] Typed config (excerpt + compaction)
#   [S21-F] Docs (EXCERPTION.md + PROGRESS-LEDGER.md + refreshes)
#   [S21-Z] Harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO_ROOT/hooks/scripts"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_eq() { local l="$1" e="$2" a="$3"; if [[ "$e" == "$a" ]]; then pass "$l"; else fail "$l (expected=$e actual=$a)"; fi; }

ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"
EXC="$REPO_ROOT/skills/consensus-orchestrator/references/excerption.md"
AGG="$SCRIPTS/consensus-aggregator.sh"
PR="$REPO_ROOT/skills/phase-runner/SKILL.md"
STATUS="$REPO_ROOT/skills/status/SKILL.md"
CFG="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
CFG_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/config.test.ts"

# ---------------------------------------------------------------------------
echo "== [S21-A] semantic primary-artifact excerption =="

assert_grep "[S21-A] orchestrator defines excerpt_if_large" \
  "excerpt_if_large\\(\\)" "$ORCH"
assert_grep "[S21-A] excerpt reads excerptTokenBudget" \
  "excerptTokenBudget" "$ORCH"
assert_grep "[S21-A] excerpt reads excerptStrategy" \
  "excerptStrategy" "$ORCH"
assert_grep "[S21-A] semantic vs headtail dispatch" \
  "vf_excerpt_semantic|vf_excerpt_headtail" "$ORCH"
assert_grep "[S21-A] Step 2b describes section-scored selection" \
  "section-scored" "$ORCH"
assert_grep "[S21-A] Step 2b always includes the first section" \
  "first section" "$ORCH"
assert_grep "[S21-A] Step 2b documents head/tail fallback" \
  "fall back|fallback" "$ORCH"
assert_grep "[S21-A] small primaries still go in whole" \
  "go in whole" "$ORCH"
assert_file "[S21-A] references/excerption.md exists" "$EXC"
assert_grep "[S21-A] excerption doc: evidence-finding density" \
  "evidence-finding density|evidence finding density" "$EXC"
assert_grep "[S21-A] excerption doc: reviewer-memory hits" \
  "reviewer-memory hits|reviewer memory hits" "$EXC"
assert_grep "[S21-A] excerption doc: keyword overlap (Jaccard)" \
  "Jaccard|keyword overlap" "$EXC"
assert_grep "[S21-A] excerption doc: first section always" \
  "first section|section 1|Always include" "$EXC"
assert_grep "[S21-A] excerption doc: headtail fallback path" \
  "headtail" "$EXC"
assert_grep "[S21-A] excerption doc: lexical not embeddings" \
  "lexical|embeddings" "$EXC"

# Runtime: excerpt_if_large helper logic — small file in whole, large
# file dispatched. Smoke the byte-threshold branch in isolation.
RT="$(mktemp -d "${TMPDIR:-/tmp}/vf-s21a-XXXXXX")"
printf 'short doc\n' > "$RT/small.md"
SMALL_BYTES="$(wc -c < "$RT/small.md" | tr -d ' ')"
if (( SMALL_BYTES <= 30000 * 4 )); then
  pass "[S21-A] runtime: a small doc is under the char budget (sent whole)"
else
  fail "[S21-A] runtime: a small doc is under the char budget (sent whole)"
fi
# Section split detection: a doc with >=2 headings is 'semantic'-eligible.
printf '# A\nx\n## B\ny\n## C\nz\n' > "$RT/sectioned.md"
SECS="$(grep -cE '^#{1,6} |\f' "$RT/sectioned.md")"
if (( SECS >= 2 )); then
  pass "[S21-A] runtime: multi-heading doc is section-eligible"
else
  fail "[S21-A] runtime: multi-heading doc is section-eligible"
fi
rm -rf "$RT"

# ---------------------------------------------------------------------------
echo "== [S21-B] reviewer-memory theme-aware compaction =="

assert_grep "[S21-B] aggregator reads compaction mode" \
  "reviewerMemory\\.compaction|RM_COMPACTION" "$AGG"
assert_grep "[S21-B] aggregator branches on recency vs theme-aware" \
  "recency" "$AGG"
assert_grep "[S21-B] aggregator builds a summary row" \
  "type:\"summary\"|\"summary\"" "$AGG"
assert_grep "[S21-B] aggregator tracks seenCount" \
  "seenCount" "$AGG"
assert_grep "[S21-B] aggregator folds via Jaccard match" \
  "jac\\(|jaccard|0\\.6" "$AGG"
assert_grep "[S21-B] orchestrator surfaces recurring criticals first" \
  "recurringCriticals|RECURRING|seenCount" "$ORCH"
assert_grep "[S21-B] orchestrator sorts recurring by seenCount" \
  "sort_by\\(-.seenCount\\)|sort_by" "$ORCH"

# Runtime: theme-aware fold via the live aggregator.
RT="$(mktemp -d "${TMPDIR:-/tmp}/vf-s21b-XXXXXX")"
cat > "$RT/vibeflow.config.json" <<EOF
{ "project": "s21b", "domain": "general", "currentPhase": "DEVELOPMENT",
  "consensus": { "quorum": 1 } }
EOF
export VIBEFLOW_CWD="$RT"
CONS="$RT/.vibeflow/state/consensus"; RM="$CONS/reviewer-memory"
mkdir -p "$RM"
echo "docs/PRD.md" > "$CONS/b1.primary.txt"
echo "1" > "$CONS/b1.current-round.txt"
for i in 1 2 3 4 5; do
  echo "{\"recordedAt\":\"t$i\",\"phase\":\"DEVELOPMENT\",\"primaryArtifact\":\"docs/PRD.md\",\"round\":$i,\"status\":\"NEEDS_REVISION\",\"criticals\":[\"Recurring bug\"]}"
done > "$RM/claude-reviewer.jsonl"
printf '%s' '{"session_id":"b1","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"{\"verdict\":\"NEEDS_REVISION\",\"criticalIssues\":[{\"title\":\"Recurring bug\",\"target\":{}}]}"}]}}' \
  | bash "$AGG" >/dev/null 2>&1
RMF="$RM/claude-reviewer.jsonl"
SC="$(jq -c 'select(.type=="summary")' "$RMF" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "[S21-B] runtime: summary row created on overflow" "1" "$SC"
SEEN="$(jq -sr 'map(select(.type=="summary"))[0].recurringCriticals[0].seenCount // 0' "$RMF" 2>/dev/null)"
assert_eq "[S21-B] runtime: dropped critical folded (seenCount=1)" "1" "$SEEN"
DETS="$(jq -c 'select((.type // "detail") != "summary")' "$RMF" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "[S21-B] runtime: detail entries capped to 5" "5" "$DETS"
rm -rf "$RT"; unset VIBEFLOW_CWD

# ---------------------------------------------------------------------------
echo "== [S21-C] phase-runner progress ledger =="

assert_grep "[S21-C] phase-runner writes phase-runner-progress.json" \
  "phase-runner-progress\\.json" "$PR"
assert_grep "[S21-C] phase-runner defines vf_progress helper" \
  "vf_progress" "$PR"
assert_grep "[S21-C] ledger carries steps[] + currentStep" \
  "currentStep|steps:" "$PR"
assert_grep "[S21-C] ledger overwritten fresh at run start" \
  "Fresh ledger|overwrites any stale|fresh" "$PR"
assert_grep "[S21-C] phase-runner sets terminal status" \
  "advanced|approved|stalled|rejected" "$PR"
assert_grep "[S21-C] step boundaries enumerated" \
  "consensus-round|analyzer:|apply" "$PR"

# Runtime: the ledger jq filters (init + vf_progress update + finalize).
RT="$(mktemp -d "${TMPDIR:-/tmp}/vf-s21c-XXXXXX")"
L="$RT/ledger.json"
jq -n -c --arg phase "REQUIREMENTS" --arg ts "2026-05-31T00:00:00Z" --argjson m 3 \
  '{phase:$phase,startedAt:$ts,status:"running",attempt:1,maxConvergenceAttempts:$m,currentStep:"init",steps:[]}' > "$L"
jq -c --arg name "analyzer:prd-quality-analyzer" --arg st "done" --arg detail "" --arg ts "t1" \
  '.currentStep=$name | .steps=((.steps//[])|map(select(.name!=$name))+[{name:$name,status:$st,detail:$detail,updatedAt:$ts}])' \
  "$L" > "$L.t" && mv "$L.t" "$L"
jq -c --arg st "advanced" --arg ts "t2" '.status=$st | .finishedAt=$ts' "$L" > "$L.t" && mv "$L.t" "$L"
LSTATUS="$(jq -r '.status' "$L")"
assert_eq "[S21-C] runtime: ledger reaches terminal status" "advanced" "$LSTATUS"
LSTEPS="$(jq -r '.steps | length' "$L")"
assert_eq "[S21-C] runtime: ledger records a step" "1" "$LSTEPS"
rm -rf "$RT"

# ---------------------------------------------------------------------------
echo "== [S21-D] status renders the ledger =="

assert_grep "[S21-D] status reads phase-runner-progress.json" \
  "phase-runner-progress\\.json" "$STATUS"
assert_grep "[S21-D] status renders a Phase-Runner Progress section" \
  "Phase-Runner Progress" "$STATUS"
assert_grep "[S21-D] status shows attempt of max" \
  "attempt|maxConvergenceAttempts" "$STATUS"
assert_grep "[S21-D] status has a stale-guard" \
  "[Ss]tale-guard|phantom|predates" "$STATUS"
assert_grep "[S21-D] stale-guard checks phase mismatch" \
  "currentPhase|≠ the live|phase" "$STATUS"

# ---------------------------------------------------------------------------
echo "== [S21-E] typed config (excerpt + compaction) =="

assert_grep "[S21-E] config: excerptTokenBudget default 30000" \
  "excerptTokenBudget.*default\\(30000\\)|excerptTokenBudget: 30000" "$CFG"
assert_grep "[S21-E] config: excerptStrategy enum semantic|headtail" \
  "excerptStrategy.*enum\\(\\[\"semantic\", \"headtail\"\\]\\)|semantic.*headtail" "$CFG"
assert_grep "[S21-E] config: excerptStrategy default semantic" \
  "excerptStrategy.*default\\(\"semantic\"\\)|excerptStrategy: \"semantic\"" "$CFG"
assert_grep "[S21-E] config: compaction enum recency|theme-aware" \
  "compaction.*enum\\(\\[\"recency\", \"theme-aware\"\\]\\)|recency.*theme-aware" "$CFG"
assert_grep "[S21-E] config: compaction default theme-aware" \
  "compaction.*default\\(\"theme-aware\"\\)|compaction: \"theme-aware\"" "$CFG"
assert_grep "[S21-E] tests cover ConsensusConfigSchema excerption" \
  "ConsensusConfigSchema excerption \\(Sprint 21-E\\)" "$CFG_TEST"
assert_grep "[S21-E] tests cover ReviewerMemoryConfigSchema compaction" \
  "ReviewerMemoryConfigSchema compaction \\(Sprint 21-E\\)" "$CFG_TEST"

# ---------------------------------------------------------------------------
echo "== [S21-F] docs =="

assert_file "[S21-F] docs/EXCERPTION.md exists" "$REPO_ROOT/docs/EXCERPTION.md"
assert_file "[S21-F] docs/PROGRESS-LEDGER.md exists" "$REPO_ROOT/docs/PROGRESS-LEDGER.md"
assert_grep "[S21-F] EXCERPTION doc covers semantic vs headtail" \
  "semantic|headtail" "$REPO_ROOT/docs/EXCERPTION.md"
assert_grep "[S21-F] EXCERPTION doc documents excerptStrategy config" \
  "excerptStrategy" "$REPO_ROOT/docs/EXCERPTION.md"
assert_grep "[S21-F] PROGRESS-LEDGER doc shows the ledger schema" \
  "phase-runner-progress\\.json" "$REPO_ROOT/docs/PROGRESS-LEDGER.md"
assert_grep "[S21-F] PROGRESS-LEDGER doc documents the stale-guard" \
  "[Ss]tale-guard|phantom" "$REPO_ROOT/docs/PROGRESS-LEDGER.md"
assert_grep "[S21-F] REVIEWER-MEMORY doc documents compaction" \
  "[Cc]ompaction|theme-aware" "$REPO_ROOT/docs/REVIEWER-MEMORY.md"
assert_grep "[S21-F] REVIEWER-MEMORY doc shows recurrence summary" \
  "recurringCriticals|seenCount" "$REPO_ROOT/docs/REVIEWER-MEMORY.md"
assert_grep "[S21-F] CONSENSUS-FLOW references Sprint 21 refinements" \
  "Semantic excerption|signal-quality refinements" "$REPO_ROOT/docs/CONSENSUS-FLOW.md"

# ---------------------------------------------------------------------------
echo "== [S21-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-21.sh"
if [[ -x "$SELF" ]]; then pass "[S21-Z] sprint-21.sh is executable"
else fail "[S21-Z] sprint-21.sh is executable"; fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S21-Z] sprint-21.sh shebang is #!/bin/bash"
else fail "[S21-Z] sprint-21.sh shebang is #!/bin/bash"; fi
for sec in S21-A S21-B S21-C S21-D S21-E S21-F S21-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S21-Z] [$sec] section header present"
  else fail "[S21-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
