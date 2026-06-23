#!/bin/bash
# Sprint 62 integration harness — consensus-gate honors the bypass after a
# leading `cd <path> &&|;` navigation preamble.
#
# Sections:
#   [S62-A] consensus-gate.sh strips a leading cd preamble before the env-prefix
#           scan (static sentinels + runtime probes); guardrails preserved
#   [S62-Z] harness self-audit

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

GATE="$REPO_ROOT/hooks/scripts/consensus-gate.sh"

# ---------------------------------------------------------------------------
echo "== [S62-A] consensus-gate cd-preamble bypass =="

assert_file "[S62-A] consensus-gate.sh exists" "$GATE"
assert_grep "[S62-A] strips a leading cd preamble (GATE_SCAN sed)" "GATE_SCAN=.*sed -E 's/\\^\\[\\[:space:\\]\\]\\*\\(cd" "$GATE"
assert_grep "[S62-A] env-prefix scan reads the cd-stripped GATE_SCAN" "GATE_LEADING_ENV=.*GATE_SCAN" "$GATE"
assert_grep "[S62-A] documents the Sprint 62 rationale" "Sprint 62" "$GATE"
assert_grep "[S62-A] only cd is strippable (guardrail noted)" "is strippable .* real work" "$GATE"

# Runtime probes against a fixture with an armed marker.
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s62-XXXXXX")"
cat > "$DIR/vibeflow.config.json" <<EOF
{ "project": "acme", "currentPhase": "ARCHITECTURE" }
EOF
mkdir -p "$DIR/.vibeflow/state"
cat > "$DIR/.vibeflow/state/consensus-needed.json" <<EOF
{ "primaryArtifact": "docs/architecture.md",
  "requiredCommand": "/vibeflow:consensus-orchestrator docs/architecture.md",
  "createdAt": "2026-06-23T00:00:00Z" }
EOF
probe() { printf '%s' "$1" | VIBEFLOW_CWD="$DIR" bash "$GATE" >/dev/null 2>&1; echo $?; }

# ALLOW (rc 0) — bypass honored after cd.
assert_eq "[S62-A] runtime: cd; then bypass → allow (the reported case)" "0" \
  "$(probe '{"tool_input":{"command":"cd /repo; VF_SKIP_CONSENSUS_GATE=1 python3 x.py"}}')"
assert_eq "[S62-A] runtime: cd && bypass → allow" "0" \
  "$(probe '{"tool_input":{"command":"cd /repo && VF_SKIP_CONSENSUS_GATE=1 python3 x.py"}}')"
assert_eq "[S62-A] runtime: cd quoted-path && bypass → allow" "0" \
  "$(probe '{"tool_input":{"command":"cd \"/p a/b\" && VF_SKIP_CONSENSUS_GATE=1 ls"}}')"
assert_eq "[S62-A] runtime: double cd && bypass → allow" "0" \
  "$(probe '{"tool_input":{"command":"cd /a && cd /b && VF_SKIP_CONSENSUS_GATE=1 ls"}}')"
assert_eq "[S62-A] runtime: leading bypass (no cd) → allow (regression)" "0" \
  "$(probe '{"tool_input":{"command":"VF_SKIP_CONSENSUS_GATE=1 python3 x.py"}}')"

# BLOCK (rc 2) — guardrails preserved.
assert_eq "[S62-A] runtime: cd && quoted-mention → block" "2" \
  "$(probe '{"tool_input":{"command":"cd /repo && echo \"VF_SKIP_CONSENSUS_GATE=1\" > x"}}')"
assert_eq "[S62-A] runtime: non-cd work && bypass → block (no sneaking ahead)" "2" \
  "$(probe '{"tool_input":{"command":"rm -rf /tmp/x && VF_SKIP_CONSENSUS_GATE=1 ls"}}')"
assert_eq "[S62-A] runtime: plain forward work → block" "2" \
  "$(probe '{"tool_input":{"command":"echo hi > src/foo.ts"}}')"
rm -rf "$DIR"

# ---------------------------------------------------------------------------
echo "== [S62-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-62.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S62-Z] shebang #!/bin/bash"; else fail "[S62-Z] shebang #!/bin/bash"; fi
for sec in S62-A S62-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S62-Z] [$sec] section header present"; else fail "[S62-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
