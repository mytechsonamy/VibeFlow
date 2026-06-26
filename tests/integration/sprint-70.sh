#!/bin/bash
# Sprint 70 integration harness — Product Bible Part C: living-doc growth.
# Living bible docs grow at each phase boundary from that phase's artifacts,
# instead of going stale after intake.
#
# Sections:
#   [S70-A] manifest: living bible-native docs declare growsIn (phase list)
#   [S70-B] /vibeflow:bible-update skill (grows living docs, merge-never-clobber)
#   [S70-C] phase-runner Step 3.6 runs bible-update surface-only + registration + docs
#   [S70-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

MAN="$REPO_ROOT/hooks/scripts/bible-manifest.json"
SKILL="$REPO_ROOT/skills/bible-update/SKILL.md"
PR="$REPO_ROOT/skills/phase-runner/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
DOC="$REPO_ROOT/docs/PRODUCT-BIBLE.md"

# ---------------------------------------------------------------------------
echo "== [S70-A] manifest growsIn on living bible docs =="

# every living bible-native doc declares a non-empty growsIn
MISSING="$(jq -r '.docs | to_entries[] | select(.value.source=="bible" and .value.lifecycle=="living") | select((.value.growsIn // []) | length == 0) | .key' "$MAN")"
if [ -z "$MISSING" ]; then pass "[S70-A] every living bible doc declares growsIn"; else fail "[S70-A] living docs missing growsIn: $MISSING"; fi
# spot-checks
if jq -e '.docs.glossary.growsIn | index("ARCHITECTURE")' "$MAN" >/dev/null 2>&1; then pass "[S70-A] glossary grows in ARCHITECTURE"; else fail "[S70-A] glossary grows in ARCHITECTURE"; fi
if jq -e '.docs["domain-model"].growsIn | index("ARCHITECTURE")' "$MAN" >/dev/null 2>&1; then pass "[S70-A] domain-model grows in ARCHITECTURE"; else fail "[S70-A] domain-model grows in ARCHITECTURE"; fi
if jq -e '.docs.personas.growsIn | index("DESIGN")' "$MAN" >/dev/null 2>&1; then pass "[S70-A] personas grow in DESIGN"; else fail "[S70-A] personas grow in DESIGN"; fi
# static docs do NOT grow
if jq -e '.docs["gartner-summaries"] | has("growsIn") | not' "$MAN" >/dev/null 2>&1; then pass "[S70-A] static gartner-summaries has no growsIn"; else fail "[S70-A] static gartner-summaries has no growsIn"; fi
# runtime: list living docs for ARCHITECTURE (the query the skill uses)
ARCH="$(jq -r --arg p ARCHITECTURE '.docs|to_entries[]|select(.value.source=="bible" and .value.lifecycle=="living")|select((.value.growsIn//[])|index($p))|.key' "$MAN" | sort | tr '\n' ' ')"
case "$ARCH" in *domain-model*) pass "[S70-A] ARCHITECTURE growth set includes domain-model";; *) fail "[S70-A] ARCHITECTURE growth set includes domain-model (got: $ARCH)";; esac

# ---------------------------------------------------------------------------
echo "== [S70-B] /vibeflow:bible-update skill =="

assert_file "[S70-B] skills/bible-update/SKILL.md exists" "$SKILL"
assert_grep "[S70-B] frontmatter name" "^name: bible-update" "$SKILL"
assert_grep "[S70-B] picks living docs via growsIn for the phase" "growsIn" "$SKILL"
assert_grep "[S70-B] reads the phase artifacts as the growth source" "phase.s artifacts|this phase produced|growth source" "$SKILL"
assert_grep "[S70-B] merge never clobbers" "never clobber" "$SKILL"
assert_grep "[S70-B] dedupes" "[Dd]edupe" "$SKILL"
assert_grep "[S70-B] never invents" "[Nn]ever invent" "$SKILL"
assert_grep "[S70-B] does NOT touch vibeflow-source docs" "does \\*\\*not\\*\\* touch|not.*touch them" "$SKILL"
assert_grep "[S70-B] writes the update report" "\\.vibeflow/reports/bible-update\\.md" "$SKILL"

# ---------------------------------------------------------------------------
echo "== [S70-C] phase-runner integration + registration + docs =="

assert_grep "[S70-C] phase-runner has a Step 3.6 bible growth" "Step 3.6.*Product Bible|Grow the living Product Bible" "$PR"
assert_grep "[S70-C] phase-runner runs bible-update via Skill tool" "Skill: vibeflow:bible-update" "$PR"
assert_grep "[S70-C] surface-only, never a gate" "surface-only.*never|never blocks the walk" "$PR"
if jq -e '.skills["bible-update"].phases == "ALL"' "$POLICY" >/dev/null 2>&1; then pass "[S70-C] bible-update registered ALL"; else fail "[S70-C] bible-update registered ALL"; fi
assert_grep "[S70-C] PRODUCT-BIBLE.md marks living-doc growth shipped" "Living-doc growth.*Sprint 70|bible-update" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S70-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-70.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S70-Z] shebang #!/bin/bash"; else fail "[S70-Z] shebang #!/bin/bash"; fi
for sec in S70-A S70-B S70-C S70-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S70-Z] [$sec] section header present"; else fail "[S70-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
