#!/bin/bash
# Sprint 72 integration harness — phase-write-guard: the project's own
# vibeflow.config.json is always writable, and an out-of-cwd write is diagnosed
# as a working-directory mismatch (not blamed on the phase).
#
# From a live CleraEFP onboard where Write(~/Projects/CleraEFP/vibeflow.config.json)
# was blocked: the guard matches its allow-list against cwd-relative paths, so an
# absolute path outside the session cwd couldn't be relativized to the bare
# `vibeflow.config.json` allow glob → default-deny.
#
# Sections:
#   [S72-A] guard source: config-bootstrap allowance + out-of-cwd diagnosis
#   [S72-B] runtime probes (config allow anywhere / source-outside-cwd block+msg / no regression)
#   [S72-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_eq() { local l="$1" e="$2" a="$3"; if [[ "$e" == "$a" ]]; then pass "$l"; else fail "$l (expected=$e actual=$a)"; fi; }
assert_contains() { local l="$1" n="$2" h="$3"; if [[ "$h" == *"$n"* ]]; then pass "$l"; else fail "$l (no '$n')"; fi; }

PWG="$REPO_ROOT/hooks/scripts/phase-write-guard.sh"
DOC="$REPO_ROOT/docs/PHASE-BOUNDARIES.md"

# ---------------------------------------------------------------------------
echo "== [S72-A] guard source =="

assert_grep "[S72-A] always-allow the project's own vibeflow.config.json" 'vibeflow.config.json\)' "$PWG"
assert_grep "[S72-A] config allowance keyed on basename" '\$\{FILE##\*/\}' "$PWG"
assert_grep "[S72-A] detects out-of-cwd (absolute REL)" "OUTSIDE_CWD" "$PWG"
assert_grep "[S72-A] out-of-cwd message names the session cwd mismatch" "OUTSIDE the session working directory" "$PWG"

# ---------------------------------------------------------------------------
echo "== [S72-B] runtime probes =="

mkproj() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/vf-s72-XXXXXX")"; printf '{"project":"sess","currentPhase":"REQUIREMENTS"}' > "$d/vibeflow.config.json"; echo "$d"; }
S="$(mkproj)"
rc() { echo "$1" | env -u VF_ALLOW_PHASE_WRITE VIBEFLOW_CWD="$S" bash "$PWG" >/dev/null 2>&1; echo $?; }
err() { echo "$1" | env -u VF_ALLOW_PHASE_WRITE VIBEFLOW_CWD="$S" bash "$PWG" 2>&1 >/dev/null; }

assert_eq "[S72-B] config write to ANOTHER project (absolute) → allow" "0" \
  "$(rc '{"tool_input":{"file_path":"/Users/x/Projects/CleraEFP/vibeflow.config.json"}}')"
assert_eq "[S72-B] config write in-cwd → allow" "0" \
  "$(rc '{"tool_input":{"file_path":"'"$S"'/vibeflow.config.json"}}')"
assert_eq "[S72-B] source write outside cwd → block (exit 2)" "2" \
  "$(rc '{"tool_input":{"file_path":"/Users/x/Projects/CleraEFP/src/foo.ts"}}')"
assert_contains "[S72-B] outside-cwd block diagnoses the cwd mismatch" "OUTSIDE the session working directory" \
  "$(err '{"tool_input":{"file_path":"/Users/x/Projects/CleraEFP/src/foo.ts"}}')"
# no regression: in-cwd source in REQUIREMENTS still blocks with the generic phase msg
assert_eq "[S72-B] in-cwd source REQUIREMENTS → block" "2" \
  "$(rc '{"tool_input":{"file_path":"'"$S"'/src/foo.ts"}}')"
assert_contains "[S72-B] in-cwd block keeps the generic phase message" "REQUIREMENTS phase does not permit" \
  "$(err '{"tool_input":{"file_path":"'"$S"'/src/foo.ts"}}')"
# no regression: in-cwd docs allowed
assert_eq "[S72-B] in-cwd docs/x.md → allow" "0" \
  "$(rc '{"tool_input":{"file_path":"'"$S"'/docs/x.md"}}')"
rm -rf "$S"

# ---------------------------------------------------------------------------
echo "== [S72-C] docs =="

assert_grep "[S72-C] PHASE-BOUNDARIES.md documents the config + cwd rule" "own .vibeflow.config.json|session working directory|out-of-cwd|outside the session" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S72-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-72.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S72-Z] shebang #!/bin/bash"; else fail "[S72-Z] shebang #!/bin/bash"; fi
for sec in S72-A S72-B S72-C S72-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S72-Z] [$sec] section header present"; else fail "[S72-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
