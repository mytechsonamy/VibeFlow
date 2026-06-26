#!/bin/bash
# Sprint 68 integration harness — the Product Bible foundation: taxonomy +
# status reader + structure/skill. A project accumulates a curated living doc
# corpus (business/GTM → product → engineering); this reports what exists vs is
# owed, referencing VibeFlow-produced docs in place (never duplicated).
#
# Sections:
#   [S68-A] bible-manifest.json taxonomy
#   [S68-B] bible-status.sh reader (runtime: present/missing, vibeflow-glob, @tsv regression)
#   [S68-C] /vibeflow:product-bible skill + phase-policy + docs
#   [S68-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_eq() { local l="$1" e="$2" a="$3"; if [[ "$e" == "$a" ]]; then pass "$l"; else fail "$l (expected=$e actual=$a)"; fi; }

MAN="$REPO_ROOT/hooks/scripts/bible-manifest.json"
BST="$REPO_ROOT/hooks/scripts/bible-status.sh"
SKILL="$REPO_ROOT/skills/product-bible/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
DOC="$REPO_ROOT/docs/PRODUCT-BIBLE.md"

# ---------------------------------------------------------------------------
echo "== [S68-A] bible-manifest.json taxonomy =="

assert_file "[S68-A] bible-manifest.json exists" "$MAN"
if jq -e '.docs | length >= 20' "$MAN" >/dev/null 2>&1; then pass "[S68-A] taxonomy has 20+ doc-types"; else fail "[S68-A] taxonomy has 20+ doc-types"; fi
# the user's named doc-types are all present
for k in vision competitive-intelligence gartner-summaries competitor-analysis personas domain-model glossary ux-principles api-standards rule-dsl ai-strategy adr prd srs test-strategy roadmap sales-arguments rfp-templates demo-scenarios pilot-guides; do
  if jq -e --arg k "$k" '.docs[$k]' "$MAN" >/dev/null 2>&1; then pass "[S68-A] taxonomy includes $k"; else fail "[S68-A] taxonomy includes $k"; fi
done
# lifecycle + source enums present
assert_grep "[S68-A] has living docs" '"lifecycle": "living"' "$MAN"
assert_grep "[S68-A] has static docs" '"lifecycle": "static"' "$MAN"
assert_grep "[S68-A] references vibeflow-produced docs in place" '"source": "vibeflow"' "$MAN"
assert_grep "[S68-A] has bible-native docs" '"source": "bible"' "$MAN"
# vibeflow source maps to the real existing outputs (no duplication)
assert_eq "[S68-A] ADRs reference docs/adr" "docs/adr" "$(jq -r '.docs.adr.path' "$MAN")"
assert_eq "[S68-A] design-spec references design/design-spec.md" "design/design-spec.md" "$(jq -r '.docs["design-spec"].path' "$MAN")"

# ---------------------------------------------------------------------------
echo "== [S68-B] bible-status.sh reader =="

assert_file "[S68-B] bible-status.sh exists" "$BST"

# Fixture: a repo with some vibeflow-produced docs + one bible-native doc.
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s68-XXXXXX")"
mkdir -p "$DIR/docs/adr" "$DIR/design" "$DIR/.vibeflow/reports" "$DIR/docs/product-bible/product"
echo "x" > "$DIR/docs/architecture.md"
echo "x" > "$DIR/docs/adr/ADR-001-foo.md"                       # adr via dir+match
echo "x" > "$DIR/docs/myfeature-requirements.md"               # prd via docs glob+match
echo "x" > "$DIR/design/design-spec.md"
echo "x" > "$DIR/.vibeflow/reports/test-strategy.md"
echo "x" > "$DIR/docs/product-bible/product/glossary.md"       # one bible-native present
OUT="$(VIBEFLOW_CWD="$DIR" bash "$BST" 2>/dev/null)"
if printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; then pass "[S68-B] reader emits valid JSON"; else fail "[S68-B] reader emits valid JSON"; fi
st() { printf '%s' "$OUT" | jq -r --arg k "$1" '.docs[] | select(.key==$k) | .status'; }
assert_eq "[S68-B] architecture → present" "present" "$(st architecture)"
assert_eq "[S68-B] adr (dir+match) → present" "present" "$(st adr)"
assert_eq "[S68-B] prd (docs glob+match) → present (the @tsv regression)" "present" "$(st prd)"
assert_eq "[S68-B] design-spec → present" "present" "$(st design-spec)"
assert_eq "[S68-B] test-strategy → present" "present" "$(st test-strategy)"
assert_eq "[S68-B] glossary (bible-native) → present" "present" "$(st glossary)"
assert_eq "[S68-B] vision (owed) → missing" "missing" "$(st vision)"
assert_eq "[S68-B] domain-model (owed) → missing" "missing" "$(st domain-model)"
# aggregates
TOT="$(printf '%s' "$OUT" | jq -r '.total')"
assert_eq "[S68-B] total matches taxonomy size" "$(jq -r '.docs|length' "$MAN")" "$TOT"
if printf '%s' "$OUT" | jq -e '.byCategory.business and .byCategory.product and .byCategory.engineering' >/dev/null 2>&1; then
  pass "[S68-B] per-category rollup present"; else fail "[S68-B] per-category rollup present"; fi
rm -rf "$DIR"

# empty repo → all missing, fail-safe valid JSON
DIR="$(mktemp -d)"; OUT="$(VIBEFLOW_CWD="$DIR" bash "$BST" 2>/dev/null)"
assert_eq "[S68-B] empty repo → present 0" "0" "$(printf '%s' "$OUT" | jq -r '.present')"
rm -rf "$DIR"

# ---------------------------------------------------------------------------
echo "== [S68-C] /vibeflow:product-bible skill + registration =="

assert_file "[S68-C] skills/product-bible/SKILL.md exists" "$SKILL"
assert_grep "[S68-C] frontmatter name" "^name: product-bible" "$SKILL"
assert_grep "[S68-C] runs bible-status.sh" "bible-status\\.sh" "$SKILL"
assert_grep "[S68-C] scaffolds docs/product-bible/" "docs/product-bible/" "$SKILL"
assert_grep "[S68-C] never duplicates vibeflow-source docs" "referenced in place|never duplicate" "$SKILL"
if jq -e '.skills["product-bible"].phases == "ALL"' "$POLICY" >/dev/null 2>&1; then pass "[S68-C] registered ALL in phase-policy"; else fail "[S68-C] registered ALL in phase-policy"; fi
assert_file "[S68-C] docs/PRODUCT-BIBLE.md exists" "$DOC"
assert_grep "[S68-C] docs explain living vs static" "[Ll]iving vs static" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S68-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-68.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S68-Z] shebang #!/bin/bash"; else fail "[S68-Z] shebang #!/bin/bash"; fi
for sec in S68-A S68-B S68-C S68-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S68-Z] [$sec] section header present"; else fail "[S68-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
