#!/bin/bash
# Sprint 69 integration harness — Product Bible Part B: intake/ingestion.
# Review the input documents brought into a project, classify them into the bible
# taxonomy, file them (referencing VibeFlow-produced docs in place), and SEED the
# living docs (glossary/domain-model/personas) from the corpus.
#
# Sections:
#   [S69-A] /vibeflow:bible-intake skill (ingest + classify + file + seed + report)
#   [S69-B] phase-policy registration + docs
#   [S69-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

SKILL="$REPO_ROOT/skills/bible-intake/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
DOC="$REPO_ROOT/docs/PRODUCT-BIBLE.md"

# ---------------------------------------------------------------------------
echo "== [S69-A] /vibeflow:bible-intake skill =="

assert_file "[S69-A] skills/bible-intake/SKILL.md exists" "$SKILL"
assert_grep "[S69-A] frontmatter name" "^name: bible-intake" "$SKILL"
assert_grep "[S69-A] reads bible-status to know what's owed" "bible-status\\.sh" "$SKILL"
assert_grep "[S69-A] gathers inputs (operator choice)" "OPERATOR-CHOICES\\.md|Operator choice" "$SKILL"
assert_grep "[S69-A] classifies into the taxonomy" "bible-manifest\\.json|taxonomy" "$SKILL"
assert_grep "[S69-A] files into docs/product-bible/<category>/" "docs/product-bible/<category>/" "$SKILL"
assert_grep "[S69-A] references vibeflow-produced docs in place (no duplication)" "never duplicate|references it in place|do \\*\\*not\\*\\* copy" "$SKILL"
assert_grep "[S69-A] merge never clobbers" "never clobber|merges? never clobber" "$SKILL"
assert_grep "[S69-A] seeds the Glossary living doc" "[Gg]lossary" "$SKILL"
assert_grep "[S69-A] seeds the Domain Model living doc" "[Dd]omain [Mm]odel" "$SKILL"
assert_grep "[S69-A] seeds Personas" "[Pp]ersonas" "$SKILL"
assert_grep "[S69-A] marks inferred content + never invents" "inferred|[Nn]ever invent" "$SKILL"
assert_grep "[S69-A] writes the intake report" "\\.vibeflow/reports/bible-intake\\.md" "$SKILL"
assert_grep "[S69-A] binary docs (PDF/DOCX) not faked" "PDF|DOCX|binary" "$SKILL"

# ---------------------------------------------------------------------------
echo "== [S69-B] registration + docs =="

if jq -e '.skills["bible-intake"].phases == "ALL"' "$POLICY" >/dev/null 2>&1; then pass "[S69-B] registered ALL in phase-policy"; else fail "[S69-B] registered ALL in phase-policy"; fi
assert_grep "[S69-B] PRODUCT-BIBLE.md marks intake shipped" "[Ii]ntake / ingestion.*Sprint 69|bible-intake" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S69-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-69.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S69-Z] shebang #!/bin/bash"; else fail "[S69-Z] shebang #!/bin/bash"; fi
for sec in S69-A S69-B S69-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S69-Z] [$sec] section header present"; else fail "[S69-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
