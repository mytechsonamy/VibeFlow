#!/bin/bash
# Sprint 71 integration harness — Product Bible Part D: assembly/curation.
# Assemble the corpus into one coherent, navigable, shareable export at project
# end, flag gaps + cross-doc incoherence (flag-only).
#
# Sections:
#   [S71-A] /vibeflow:bible-assemble skill (index + export + curation + report)
#   [S71-B] registration + docs (bible feature-complete)
#   [S71-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

SKILL="$REPO_ROOT/skills/bible-assemble/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
DOC="$REPO_ROOT/docs/PRODUCT-BIBLE.md"

# ---------------------------------------------------------------------------
echo "== [S71-A] /vibeflow:bible-assemble skill =="

assert_file "[S71-A] skills/bible-assemble/SKILL.md exists" "$SKILL"
assert_grep "[S71-A] frontmatter name" "^name: bible-assemble" "$SKILL"
assert_grep "[S71-A] reads bible-status" "bible-status\\.sh" "$SKILL"
assert_grep "[S71-A] builds the index README" "docs/product-bible/README\\.md" "$SKILL"
assert_grep "[S71-A] builds a single-file export" "docs/product-bible/product-bible-export\\.md" "$SKILL"
assert_grep "[S71-A] links vibeflow docs where they live (no copy)" "where they (actually )?live|never copies|never duplicat" "$SKILL"
assert_grep "[S71-A] curation pass flags coherence gaps" "[Cc]uration|cross-consistency|coherence" "$SKILL"
assert_grep "[S71-A] curation flags, does not auto-fix" "flag.* don.t auto-fix|flag-only|only .*flags" "$SKILL"
assert_grep "[S71-A] completeness rollup" "completeness rollup" "$SKILL"
assert_grep "[S71-A] writes the assembly report" "\\.vibeflow/reports/bible-assembly\\.md" "$SKILL"
assert_grep "[S71-A] read-mostly (only index+export+report)" "[Rr]ead-mostly" "$SKILL"

# ---------------------------------------------------------------------------
echo "== [S71-B] registration + docs (feature-complete) =="

if jq -e '.skills["bible-assemble"].phases == "ALL"' "$POLICY" >/dev/null 2>&1; then pass "[S71-B] bible-assemble registered ALL"; else fail "[S71-B] bible-assemble registered ALL"; fi
assert_grep "[S71-B] PRODUCT-BIBLE.md marks assembly shipped" "Assembly / curation.*Sprint 71|bible-assemble" "$DOC"
assert_grep "[S71-B] PRODUCT-BIBLE.md declares feature-complete" "feature-complete" "$DOC"
# all four bible skills exist + registered
for s in product-bible bible-intake bible-update bible-assemble; do
  if jq -e --arg k "$s" '.skills[$k]' "$POLICY" >/dev/null 2>&1; then pass "[S71-B] $s registered"; else fail "[S71-B] $s registered"; fi
done

# ---------------------------------------------------------------------------
echo "== [S71-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-71.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S71-Z] shebang #!/bin/bash"; else fail "[S71-Z] shebang #!/bin/bash"; fi
for sec in S71-A S71-B S71-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S71-Z] [$sec] section header present"; else fail "[S71-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
