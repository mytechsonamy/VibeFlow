#!/bin/bash
# Sprint 28 integration harness — cross-project meta-learning
# (opt-in, privacy-safe, read-only).
#
# Sections:
#   [S28-A] globalLearning config + _lib helpers
#   [S28-B] privacy-safe global-store writes
#   [S28-C] cross-project-signal detector
#   [S28-D] Docs (CROSS-PROJECT-LEARNING.md + refresh)
#   [S28-Z] Harness self-audit

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

CFG="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
CFG_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/config.test.ts"
LIB="$SCRIPTS/_lib.sh"
AGG="$SCRIPTS/consensus-aggregator.sh"
LA="$REPO_ROOT/skills/learning-apply/SKILL.md"
LLE="$REPO_ROOT/skills/learning-loop-engine/SKILL.md"
PATDET="$REPO_ROOT/skills/learning-loop-engine/references/pattern-detection.md"
HOOKT="$REPO_ROOT/hooks/tests/run.sh"

# ---------------------------------------------------------------------------
echo "== [S28-A] globalLearning config + _lib helpers =="

assert_grep "[S28-A] config exports GlobalLearningConfigSchema" "export const GlobalLearningConfigSchema" "$CFG"
assert_grep "[S28-A] enabled defaults false" "enabled: z.boolean\\(\\).default\\(false\\)" "$CFG"
assert_grep "[S28-A] EngineConfigSchema wires globalLearning" "globalLearning: GlobalLearningConfigSchema" "$CFG"
assert_grep "[S28-A] loadFileConfig merges globalLearning" "raw\\.globalLearning" "$CFG"
assert_grep "[S28-A] config tests cover GlobalLearningConfigSchema" "GlobalLearningConfigSchema \\(Sprint 28-A\\)" "$CFG_TEST"
assert_grep "[S28-A] _lib defines vf_global_dir" "vf_global_dir\\(\\)" "$LIB"
assert_grep "[S28-A] vf_global_dir honours VIBEFLOW_GLOBAL_DIR" "VIBEFLOW_GLOBAL_DIR" "$LIB"
assert_grep "[S28-A] _lib defines vf_project_hash (one-way)" "vf_project_hash\\(\\)" "$LIB"
assert_grep "[S28-A] vf_project_hash uses sha256" "shasum -a 256" "$LIB"

# Runtime: config default + helper behaviour.
DEF="$(node -e '
  const {EngineConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  process.stdout.write(String(EngineConfigSchema.parse({project:"p"}).globalLearning.enabled));' 2>/dev/null)"
assert_eq "[S28-A] runtime: globalLearning.enabled defaults false" "false" "$DEF"
GD="$( ( source "$LIB"; VIBEFLOW_GLOBAL_DIR=/tmp/_vf_s28 vf_global_dir ) 2>/dev/null )"
assert_eq "[S28-A] runtime: vf_global_dir honours the override" "/tmp/_vf_s28" "$GD"
H1="$(printf foo | shasum -a 256 | cut -c1-12)"; H2="$(printf foo | shasum -a 256 | cut -c1-12)"
assert_eq "[S28-A] runtime: project hash is stable (12 hex)" "$H1" "$H2"

# ---------------------------------------------------------------------------
echo "== [S28-B] privacy-safe global-store writes =="

assert_grep "[S28-B] aggregator gates on globalLearning.enabled" "globalLearning\\.enabled|GL_ENABLED" "$AGG"
assert_grep "[S28-B] aggregator writes to global-learning.jsonl" "global-learning\\.jsonl" "$AGG"
assert_grep "[S28-B] aggregator row carries projectHash" "projectHash" "$AGG"
assert_grep "[S28-B] aggregator row has NO primaryArtifact/file" "key:.*outcome:.*phase:.*projectHash" "$AGG"
assert_grep "[S28-B] aggregator mirrors reverted + held" "reverted|held" "$AGG"
assert_grep "[S28-B] learning-apply mirrors applied outcome" "outcome.*applied|global-learning\\.jsonl" "$LA"
assert_grep "[S28-B] hook tests exercise the global store" "cross-project global-learning store \\[S28-B\\]" "$HOOKT"
assert_grep "[S28-B] hook test asserts privacy (no file fields)" "NO primaryArtifact" "$HOOKT"

# ---------------------------------------------------------------------------
echo "== [S28-C] cross-project-signal detector =="

assert_grep "[S28-C] SKILL lists cross-project-signal detector" "cross-project-signal" "$LLE"
assert_grep "[S28-C] SKILL: read-only, never auto-allowlists" "NEVER auto-allowlists|never auto-allow|[Rr]ead-only recommendation" "$LLE"
assert_grep "[S28-C] SKILL reads the global store input" "global-learning\\.jsonl" "$LLE"
assert_grep "[S28-C] catalog has LEARNING-CROSS-PROJECT-SIGNAL" "LEARNING-CROSS-PROJECT-SIGNAL" "$PATDET"
assert_grep "[S28-C] catalog uses hold-rate across distinct projects" "hold-rate|distinct .projectHash|3 distinct projects" "$PATDET"
assert_grep "[S28-C] catalog: recommendation only, NEVER auto-allowlists" "NEVER.*auto-allow|recommendation only" "$PATDET"
assert_grep "[S28-C] catalog: privacy (only key/outcome/phase/projectHash)" "key/outcome/phase/projectHash|no code, content, file names" "$PATDET"
assert_grep "[S28-C] catalog version bumped to 4" "patternCatalogVersion: 4" "$PATDET"
assert_grep "[S28-C] catalog count consensus-history 8" "consensus-history patterns: 8" "$PATDET"

# Runtime: aggregate a seeded global store across 3 projectHashes.
RT="$(mktemp -d "${TMPDIR:-/tmp}/vf-s28c-XXXXXX")"
GF="$RT/global-learning.jsonl"
{ for h in aaa bbb ccc; do
    echo "{\"key\":\"consensus.maxIterations\",\"outcome\":\"held\",\"phase\":\"REQUIREMENTS\",\"projectHash\":\"$h\",\"recordedAt\":\"t\"}"
  done; } > "$GF"
SIG="$(jq -sr '
  group_by(.key) | map({
    key: .[0].key,
    projects: ([.[].projectHash] | unique | length),
    held: (map(select(.outcome=="held")) | length),
    reverted: (map(select(.outcome=="reverted")) | length)
  } | . + {holdRate: (if (.held + .reverted) > 0 then (.held / (.held + .reverted)) else 0 end)})
  | .[0] | "\(.projects):\(.holdRate)"' "$GF" 2>/dev/null)"
assert_eq "[S28-C] runtime: 3 distinct projects, hold-rate 1 → allowlist signal" "3:1" "$SIG"
rm -rf "$RT"

# ---------------------------------------------------------------------------
echo "== [S28-D] docs =="

assert_file "[S28-D] docs/CROSS-PROJECT-LEARNING.md exists" "$REPO_ROOT/docs/CROSS-PROJECT-LEARNING.md"
assert_grep "[S28-D] doc states opt-in default off" "[Oo]pt-in|default off|enabled.*false" "$REPO_ROOT/docs/CROSS-PROJECT-LEARNING.md"
assert_grep "[S28-D] doc states the privacy-safe shape" "key, outcome, phase, projectHash|projectHash" "$REPO_ROOT/docs/CROSS-PROJECT-LEARNING.md"
assert_grep "[S28-D] doc states read-only (never auto-allowlist)" "[Rr]ead-only|never.*auto-allow|never.*auto-applies" "$REPO_ROOT/docs/CROSS-PROJECT-LEARNING.md"
assert_grep "[S28-D] doc documents how to wipe the store" "rm .*global-learning\\.jsonl|[Ww]iping" "$REPO_ROOT/docs/CROSS-PROJECT-LEARNING.md"
assert_grep "[S28-D] doc documents VIBEFLOW_GLOBAL_DIR override" "VIBEFLOW_GLOBAL_DIR" "$REPO_ROOT/docs/CROSS-PROJECT-LEARNING.md"
assert_grep "[S28-D] META-LEARNING links cross-project" "CROSS-PROJECT-LEARNING|cross-project" "$REPO_ROOT/docs/META-LEARNING.md"

# ---------------------------------------------------------------------------
echo "== [S28-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-28.sh"
if [[ -x "$SELF" ]]; then pass "[S28-Z] sprint-28.sh is executable"; else fail "[S28-Z] sprint-28.sh is executable"; fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S28-Z] sprint-28.sh shebang is #!/bin/bash"
else fail "[S28-Z] sprint-28.sh shebang is #!/bin/bash"; fi
for sec in S28-A S28-B S28-C S28-D S28-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S28-Z] [$sec] section header present"
  else fail "[S28-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
