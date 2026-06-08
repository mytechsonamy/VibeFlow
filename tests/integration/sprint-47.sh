#!/bin/bash
# Sprint 47 integration harness — consensus-run.sh + orchestrator capture the
# reviewer CLIs' STDOUT ONLY (Patch B). codex `exec` echoes the prompt (with the
# JSON schema template `{verdict:APPROVED|NEEDS_REVISION|REJECTED,…}`) + banner to
# STDERR; merging it (`2>&1`) poisoned the verdict blob → a content-free
# REJECTED/NEEDS_REVISION that flipped the aggregate. Stderr now goes to a
# separate file (diagnostics preserved). Plus a keyword-grep defense that drops
# the schema-template line.
#
# Sections:
#   [S47-A] consensus-run.sh captures stdout only + stderr to a file
#   [S47-B] keyword-grep schema-template defense (+ runtime)
#   [S47-C] orchestrator prose also stdout-only
#   [S47-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
refute_grep() { local l="$1" pat="$2" f="$3"; if ! grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (found '$pat' in $f)"; fi; }

CRUN="$REPO_ROOT/hooks/scripts/consensus-run.sh"
ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S47-A] consensus-run.sh captures stdout only =="

refute_grep "[S47-A] no 2>&1 on the codex capture" 'codex exec .*2>&1' "$CRUN"
refute_grep "[S47-A] no 2>&1 on the gemini capture" 'gemini \$GEMINI_MFLAG 2>&1' "$CRUN"
assert_grep "[S47-A] codex stderr → a separate file" 'codex exec.*2>"\$CODEX_ERR"' "$CRUN"
assert_grep "[S47-A] gemini stderr → a separate file" 'gemini \$GEMINI_MFLAG 2>"\$GEMINI_ERR"' "$CRUN"
assert_grep "[S47-A] error path still sees stderr (warn_cli_error gets the err file)" \
  'cat "\$CODEX_ERR"' "$CRUN"
assert_grep "[S47-A] documents the Patch B reason (schema template on stderr)" \
  "schema template.*STDERR|STDOUT ONLY|Patch B" "$CRUN"
# vf_extract_json belt-and-suspenders still present.
assert_grep "[S47-A] vf_extract_json walk-all-objects guard kept" "_vf_json_objects" "$CRUN"
assert_grep "[S47-A] returns first object WITH a verdict key" 'has\("verdict"\)' "$CRUN"

# ---------------------------------------------------------------------------
echo "== [S47-B] keyword-grep schema-template defense =="

assert_grep "[S47-B] drops the |-alternation schema-template line before grep" \
  "grep -vF .APPROVED.NEEDS_REVISION.REJECTED" "$CRUN"
assert_grep "[S47-B] names it defense-in-depth" "Defense-in-depth" "$CRUN"

# Runtime: a blob that is ONLY the echoed schema template must NOT become REJECTED.
RES="$(bash -c '
raw="some prose. Output ONLY valid JSON matching: {verdict:APPROVED|NEEDS_REVISION|REJECTED, score:0-100}"
cleaned="$(printf "%s\n" "$raw" | grep -vF "APPROVED|NEEDS_REVISION|REJECTED")"
if echo "$cleaned" | grep -qE "REJECTED"; then echo REJECTED
elif echo "$cleaned" | grep -qE "NEEDS_REVISION"; then echo NEEDS_REVISION
elif echo "$cleaned" | grep -qE "APPROVED"; then echo APPROVED
else echo NONE; fi
')"
if [[ "$RES" != "REJECTED" ]]; then
  pass "[S47-B] runtime — schema-template-only blob does NOT yield a biased REJECTED (got $RES)"
else
  fail "[S47-B] runtime — schema-template-only blob yielded REJECTED"
fi

# Runtime: the real verdict object survives extraction even with the schema template present.
EXOUT="$(bash -c '
sed -n "/^_vf_json_objects()/,/^}/p;/^vf_extract_json()/,/^}/p" "'"$CRUN"'" > /tmp/vf47.sh
cat >> /tmp/vf47.sh <<EOF
B="banner
Output ONLY valid JSON matching: {verdict:APPROVED|NEEDS_REVISION|REJECTED, score:0-100}
{\"verdict\":\"NEEDS_REVISION\",\"score\":82,\"criticalIssues\":[{\"id\":\"C1\"},{\"id\":\"C2\"}]}"
printf "%s" "\$B" | vf_extract_json | jq -r ".verdict + \"/\" + (.criticalIssues|length|tostring)"
EOF
bash /tmp/vf47.sh; rm -f /tmp/vf47.sh
')"
if [[ "$EXOUT" == "NEEDS_REVISION/2" ]]; then
  pass "[S47-B] runtime — real verdict object extracted past the schema template ($EXOUT)"
else
  fail "[S47-B] runtime — real verdict extraction (got '$EXOUT', want NEEDS_REVISION/2)"
fi

# ---------------------------------------------------------------------------
echo "== [S47-C] orchestrator prose stdout-only =="

refute_grep "[S47-C] no 2>&1 on orchestrator codex capture" 'codex exec -m .*2>&1' "$ORCH"
refute_grep "[S47-C] no 2>&1 on orchestrator gemini capture" 'gemini --model .*2>&1' "$ORCH"
assert_grep "[S47-C] orchestrator codex captures stdout only" 'codex exec -m.*2>/dev/null' "$ORCH"

# ---------------------------------------------------------------------------
echo "== [S47-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-47.sh"
assert_grep "[S47-Z] sprint-47.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S47-Z] covers [S47-A]" '\[S47-A\]' "$SELF"
assert_grep "[S47-Z] covers [S47-B]" '\[S47-B\]' "$SELF"
assert_grep "[S47-Z] covers [S47-C]" '\[S47-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
