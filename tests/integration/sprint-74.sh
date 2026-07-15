#!/bin/bash
# Sprint 74 integration harness — consensus critical-finding dedup is
# language-agnostic (structural + lexical + semantic), so a Turkish (or any
# non-English) reviewer panel no longer double-counts the SAME finding into a
# false REJECTED. Diagnosed in a live Clera consensus round.
#
# Sections:
#   [S74-A] language-agnostic title-similarity prelude lives in _lib.sh (single source)
#   [S74-B] aggregator uses the prelude in BOTH jq blocks; old ASCII-only idiom gone
#   [S74-C] structural dedup = overlapping line_range; escalatedByCriticalCount surfaced
#   [S74-D] reduce-only semantic dedup step in phase-runner + orchestrator
#   [S74-E] reviewer contract: English titles + always-filled target
#   [S74-F] docs
#   [S74-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_ngrep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then fail "$l (unexpected '$pat' in $f)"; else pass "$l"; fi; }
assert_eq() { local l="$1" e="$2" a="$3"; if [[ "$e" == "$a" ]]; then pass "$l"; else fail "$l (expected=$e actual=$a)"; fi; }

LIB="$REPO_ROOT/hooks/scripts/_lib.sh"
AGG="$REPO_ROOT/hooks/scripts/consensus-aggregator.sh"
CRUN="$REPO_ROOT/hooks/scripts/consensus-run.sh"
PR="$REPO_ROOT/skills/phase-runner/SKILL.md"
ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"
AGENT="$REPO_ROOT/agents/claude-reviewer.md"
DOC_ITER="$REPO_ROOT/docs/CONSENSUS-ITERATION.md"

# ---------------------------------------------------------------------------
echo "== [S74-A] single-source language-agnostic title-similarity prelude =="

assert_grep "[S74-A] _lib.sh exports VF_JQ_TITLE_SIM" "VF_JQ_TITLE_SIM=" "$LIB"
assert_grep "[S74-A] prelude folds diacritics (does not delete them)" "def vf_fold" "$LIB"
assert_grep "[S74-A] prelude folds Turkish letters to ASCII" 'gsub\("\[Şş\]"; "s"\)' "$LIB"
assert_grep "[S74-A] suffix-tolerant token match via trigrams" "def vf_tmatch" "$LIB"
assert_grep "[S74-A] exposes vf_title_sim" "def vf_title_sim" "$LIB"

# Runtime: the exported prelude actually loads and scores TR duplicates high,
# distinct findings low, and keeps English behaviour.
# shellcheck disable=SC1090
source "$LIB" 2>/dev/null
TR_DUP="$(jq -n "$VF_JQ_TITLE_SIM"'(vf_title_sim("SQL injection risk in user search endpoint"; "User search endpoint vulnerable to SQL injection") >= 0.6)')"
assert_eq "[S74-A] runtime: English near-identical titles merge" "true" "$TR_DUP"
TR_DISTINCT="$(jq -n "$VF_JQ_TITLE_SIM"'(vf_title_sim("Faiz oranı yanlış yuvarlanıyor"; "Kullanıcı oturumu kapanmıyor") >= 0.6)')"
assert_eq "[S74-A] runtime: distinct TR findings do NOT merge" "false" "$TR_DISTINCT"

# ---------------------------------------------------------------------------
echo "== [S74-B] aggregator consumes the shared prelude; old idiom retired =="

assert_grep "[S74-B] aggregator sources _lib.sh" "source .*_lib\\.sh" "$AGG"
assert_grep "[S74-B] dedup pass uses vf_title_sim" "vf_title_sim" "$AGG"
# The ASCII-only tokeniser idiom (ascii_downcase | gsub non-alnum) must be gone
# from the aggregator — it now lives ONLY inside the _lib.sh prelude.
assert_ngrep "[S74-B] no local ascii-only tokeniser left in aggregator" 'ascii_downcase \| gsub\("\[\^a-z0-9 \]"' "$AGG"
# both consumers (verdict dedup + reviewer-memory compaction) reference the prelude var
BOTH="$(grep -c 'VF_JQ_TITLE_SIM' "$AGG")"
if (( BOTH >= 2 )); then pass "[S74-B] both jq blocks reference the prelude"; else fail "[S74-B] both jq blocks reference the prelude (found $BOTH)"; fi

# ---------------------------------------------------------------------------
echo "== [S74-C] structural overlap + escalation flag =="

assert_grep "[S74-C] structural dedup on OVERLAPPING line_range" "def same_location" "$AGG"
assert_grep "[S74-C] overlap test a.start<=b.end and b.start<=a.end" '\$ar\[0\]\) <= \(\$br\[1\]\)' "$AGG"
assert_grep "[S74-C] verdict carries escalatedByCriticalCount" "escalatedByCriticalCount:" "$AGG"
assert_grep "[S74-C] verdict carries dedupMethod" 'dedupMethod: "structural\+lexical"' "$AGG"
assert_grep "[S74-C] consensus-run surfaces escalatedByCriticalCount" "escalatedByCriticalCount:\\\$escalated" "$CRUN"
assert_grep "[S74-C] consensus-run surfaces criticalDeduped" "criticalDeduped:\\\$criticalDeduped" "$CRUN"

# Runtime: TR duplicate with overlapping line_range → merges → NEEDS_REVISION.
TMP="$(mktemp -d)"; export VIBEFLOW_CWD="$TMP"
mkdir -p "$TMP/.vibeflow/state/consensus"
printf '{"project":"t","currentPhase":"DEVELOPMENT","consensus":{"quorum":2}}' > "$TMP/vibeflow.config.json"
CN="$TMP/.vibeflow/state/consensus"
cat > "$CN/s.jsonl" <<'EOF'
{"recordedAt":"2026-07-14T10:00:00Z","reviewer":"codex","verdict":"REJECTED","criticalIssues":1,"criticalItems":[{"target":{"file":"src/faiz.py","line_range":[12,20]},"title":"Özkaynağına faiz devri hesaplanmıyor"}],"round":1}
{"recordedAt":"2026-07-14T10:00:05Z","reviewer":"gemini","verdict":"NEEDS_REVISION","criticalIssues":1,"criticalItems":[{"target":{"file":"src/faiz.py","line_range":[14,18]},"title":"Özkaynağa faiz devir hesabı eksik"}],"round":1}
EOF
bash "$AGG" --finalize s 1 >/dev/null 2>&1
assert_eq "[S74-C] runtime: overlapping-range TR dup → criticalTotal 1" "1" "$(jq -r '.criticalTotal' "$CN/s.verdict.json")"
assert_eq "[S74-C] runtime: merged → NEEDS_REVISION not false REJECTED" "NEEDS_REVISION" "$(jq -r '.status' "$CN/s.verdict.json")"

# Runtime: reworded TR dup, NO line_range → lexical miss → REJECTED + escalated.
cat > "$CN/e.jsonl" <<'EOF'
{"recordedAt":"2026-07-14T10:00:00Z","reviewer":"codex","verdict":"REJECTED","criticalIssues":1,"criticalItems":[{"target":{"file":"src/faiz.py"},"title":"Özkaynağına faiz devri hesaplanmıyor"}],"round":1}
{"recordedAt":"2026-07-14T10:00:05Z","reviewer":"gemini","verdict":"NEEDS_REVISION","criticalIssues":1,"criticalItems":[{"target":{"file":"src/ucret.py"},"title":"Özkaynağa faiz devir hesabı eksik"}],"round":1}
EOF
bash "$AGG" --finalize e 1 >/dev/null 2>&1
assert_eq "[S74-C] runtime: lexical-miss REJECTED flagged escalated" "true" "$(jq -r '.escalatedByCriticalCount' "$CN/e.verdict.json")"
rm -rf "$TMP"; unset VIBEFLOW_CWD

# ---------------------------------------------------------------------------
echo "== [S74-D] reduce-only semantic dedup step =="

assert_grep "[S74-D] phase-runner has the semantic dedup step" "Semantic dedup" "$PR"
assert_grep "[S74-D] phase-runner gates on escalatedByCriticalCount" "escalatedByCriticalCount == true" "$PR"
assert_grep "[S74-D] phase-runner: can only lower REJECTED -> NEEDS_REVISION" "may lower .*REJECTED" "$PR"
assert_grep "[S74-D] phase-runner: never raise to APPROVED" "never.* raise to" "$PR"
assert_grep "[S74-D] phase-runner writes dedupNote" "dedupNote" "$PR"
assert_grep "[S74-D] phase-runner appends semantic-dedup history row" 'type:"semantic-dedup"' "$PR"
assert_grep "[S74-D] orchestrator has the reduce-only semantic step" "Semantic dedup, reduce-only" "$ORCH"
assert_grep "[S74-D] orchestrator gates on escalatedByCriticalCount" "escalatedByCriticalCount == true" "$ORCH"

# ---------------------------------------------------------------------------
echo "== [S74-E] reviewer title contract =="

assert_grep "[S74-E] claude-reviewer asks for an ENGLISH title" "in ENGLISH" "$AGENT"
assert_grep "[S74-E] claude-reviewer documents the three dedup layers" "structural|lexical|semantic" "$AGENT"
assert_grep "[S74-E] consensus-run prompt asks for ENGLISH titles" "title in ENGLISH" "$CRUN"
assert_grep "[S74-E] orchestrator prompt asks for ENGLISH titles" "title in ENGLISH" "$ORCH"

# ---------------------------------------------------------------------------
echo "== [S74-F] docs =="

assert_grep "[S74-F] CONSENSUS-ITERATION documents the three dedup layers" "structural|lexical|semantic" "$DOC_ITER"
assert_grep "[S74-F] docs warn lowering the threshold causes false APPROVED" "false APPROVED|sahte APPROVED" "$DOC_ITER"

# ---------------------------------------------------------------------------
echo "== [S74-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-74.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S74-Z] shebang #!/bin/bash"; else fail "[S74-Z] shebang #!/bin/bash"; fi
for sec in S74-A S74-B S74-C S74-D S74-E S74-F S74-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S74-Z] [$sec] section header present"; else fail "[S74-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
