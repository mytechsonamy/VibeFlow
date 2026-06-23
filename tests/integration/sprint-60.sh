#!/bin/bash
# Sprint 60 integration harness — parallel team work via per-branch work-streams.
#
# Sections:
#   [S60-A] StreamsConfigSchema (config) + vf_stream_id / vf_lifecycle_path (lib)
#   [S60-B] stream-id.sh + streams-audit.sh readers + two-stream isolation runtime
#   [S60-C] /vibeflow:streams + /vibeflow:integrate skills + registry + skill wiring
#   [S60-D] consensus-gate allowlists the read-only stream readers
#   [S60-E] docs (TEAM-WORK.md new + LIFECYCLE/CLAUDE refresh)
#   [S60-Z] harness self-audit

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

LIB="$REPO_ROOT/hooks/scripts/_lib.sh"
CONFIG_TS="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
SID_SH="$REPO_ROOT/hooks/scripts/stream-id.sh"
AUDIT_SH="$REPO_ROOT/hooks/scripts/streams-audit.sh"
GATE_SH="$REPO_ROOT/hooks/scripts/consensus-gate.sh"
STREAMS_SKILL="$REPO_ROOT/skills/streams/SKILL.md"
INTEGRATE_SKILL="$REPO_ROOT/skills/integrate/SKILL.md"
PHASE_RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
ONBOARD="$REPO_ROOT/skills/onboard/SKILL.md"
BROWNFIELD="$REPO_ROOT/skills/brownfield-intake/SKILL.md"
FLOW_STATUS="$REPO_ROOT/skills/flow-status/SKILL.md"
REGISTRY="$REPO_ROOT/skills/phase-policy.json"
TEAM_DOC="$REPO_ROOT/docs/TEAM-WORK.md"
LIFECYCLE_DOC="$REPO_ROOT/docs/LIFECYCLE.md"

# A throwaway git project with a config; leaves HEAD on `main`. $1 = streams block.
mk() {
  local block="$1" dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/vf-s60-XXXXXX")"
  cat > "$dir/vibeflow.config.json" <<EOF
{ "project": "acme", "currentPhase": "REQUIREMENTS"${block:+, $block} }
EOF
  git -C "$dir" init -q
  git -C "$dir" config user.email t@t.t
  git -C "$dir" config user.name "Musti"
  git -C "$dir" commit -q --allow-empty -m init
  git -C "$dir" branch -M main
  echo "$dir"
}

# ---------------------------------------------------------------------------
echo "== [S60-A] StreamsConfigSchema + vf_stream_id / vf_lifecycle_path =="

assert_grep "[S60-A] StreamsConfigSchema defined" "StreamsConfigSchema" "$CONFIG_TS"
assert_grep "[S60-A] streams default-off (enabled: false)" "enabled: z.boolean\\(\\).default\\(false\\)" "$CONFIG_TS"
assert_grep "[S60-A] idStrategy enum branch|fixed" 'idStrategy: z.enum\(\["branch", "fixed"\]\)' "$CONFIG_TS"
assert_grep "[S60-A] streams wired into EngineConfigSchema" "streams: StreamsConfigSchema" "$CONFIG_TS"
assert_grep "[S60-A] vf_stream_id helper present" "^vf_stream_id\\(\\)" "$LIB"
assert_grep "[S60-A] vf_lifecycle_path helper present" "^vf_lifecycle_path\\(\\)" "$LIB"
assert_grep "[S60-A] vf_state_project_dir keyed on vf_stream_id" "vf_stream_id" "$LIB"

# Runtime: off → bare; on+feature → slug; on+main → bare; override; fixed.
D="$(mk "")"; git -C "$D" checkout -q -b feature/auth
assert_eq "[S60-A] off → bare project id" "acme" \
  "$(VIBEFLOW_CWD="$D" bash -c "source '$LIB'; vf_stream_id")"
rm -rf "$D"

D="$(mk '"streams": { "enabled": true }')"; git -C "$D" checkout -q -b feature/Auth-Flow
assert_eq "[S60-A] on + feature → slugged" "acme__feature-auth-flow" \
  "$(VIBEFLOW_CWD="$D" bash -c "source '$LIB'; vf_stream_id")"
assert_eq "[S60-A] on + feature → stream-scoped lifecycle" \
  "$D/.vibeflow/state/acme__feature-auth-flow/lifecycle.json" \
  "$(VIBEFLOW_CWD="$D" bash -c "source '$LIB'; vf_lifecycle_path")"
rm -rf "$D"

D="$(mk '"streams": { "enabled": true }')"
assert_eq "[S60-A] on + main → bare (initial stream)" "acme" \
  "$(VIBEFLOW_CWD="$D" bash -c "source '$LIB'; vf_stream_id")"
# Even with streams ON, the initial/main stream keeps the legacy lifecycle path
# (only feature streams get their own subdir) — turning streams on never moves
# an existing project's lifecycle.
assert_eq "[S60-A] on + main → lifecycle stays legacy path" \
  "$D/.vibeflow/state/lifecycle.json" \
  "$(VIBEFLOW_CWD="$D" bash -c "source '$LIB'; vf_lifecycle_path")"
rm -rf "$D"

# Streams OFF → lifecycle is the legacy path regardless of branch.
D="$(mk "")"; git -C "$D" checkout -q -b feature/x
assert_eq "[S60-A] off → lifecycle legacy path" \
  "$D/.vibeflow/state/lifecycle.json" \
  "$(VIBEFLOW_CWD="$D" bash -c "source '$LIB'; vf_lifecycle_path")"
rm -rf "$D"

D="$(mk '"streams": { "enabled": true, "idStrategy": "fixed" }')"; git -C "$D" checkout -q -b feature/x
assert_eq "[S60-A] idStrategy:fixed → bare" "acme" \
  "$(VIBEFLOW_CWD="$D" bash -c "source '$LIB'; vf_stream_id")"
rm -rf "$D"

D="$(mk '"streams": { "enabled": true }')"; git -C "$D" checkout -q -b feature/x
assert_eq "[S60-A] VIBEFLOW_STREAM override" "acme__payments-v2" \
  "$(VIBEFLOW_CWD="$D" VIBEFLOW_STREAM="payments/v2" bash -c "source '$LIB'; vf_stream_id")"
rm -rf "$D"

# ---------------------------------------------------------------------------
echo "== [S60-B] stream-id.sh + streams-audit.sh + two-stream isolation =="

assert_file "[S60-B] stream-id.sh exists" "$SID_SH"
assert_file "[S60-B] streams-audit.sh exists" "$AUDIT_SH"

D="$(mk '"streams": { "enabled": true }')"; git -C "$D" checkout -q -b feature/login
SJ="$(VIBEFLOW_CWD="$D" bash "$SID_SH")"
if printf '%s' "$SJ" | jq -e . >/dev/null 2>&1; then pass "[S60-B] stream-id.sh valid JSON"; else fail "[S60-B] stream-id.sh valid JSON"; fi
assert_eq "[S60-B] stream-id.sh streamId" "acme__feature-login" "$(printf '%s' "$SJ" | jq -r '.streamId')"
assert_eq "[S60-B] stream-id.sh branch" "feature/login" "$(printf '%s' "$SJ" | jq -r '.branch')"
rm -rf "$D"

# Two streams seeded → streams-audit lists both, flags current, skips framework dirs.
D="$(mk '"streams": { "enabled": true }')"
mkdir -p "$D/.vibeflow/state/acme__feature-auth" "$D/.vibeflow/state/acme__feature-pay" "$D/.vibeflow/state/auto-apply"
printf '{"projectId":"acme__feature-auth","currentPhase":"DEVELOPMENT","revision":12,"updatedAt":"2026-06-23T10:00:00Z"}' > "$D/.vibeflow/state/acme__feature-auth/project.json"
printf '{"currentCycle":{"id":"cycle-1","title":"auth","status":"in-progress","branch":"feature/auth"}}' > "$D/.vibeflow/state/acme__feature-auth/lifecycle.json"
printf '{"projectId":"acme__feature-pay","currentPhase":"TESTING","revision":30,"updatedAt":"2026-06-23T11:00:00Z"}' > "$D/.vibeflow/state/acme__feature-pay/project.json"
printf '{"currentCycle":{"id":"cycle-1","title":"pay","status":"in-progress","branch":"feature/pay"}}' > "$D/.vibeflow/state/acme__feature-pay/lifecycle.json"
git -C "$D" checkout -q -b feature/auth
AJ="$(VIBEFLOW_CWD="$D" bash "$AUDIT_SH")"
if printf '%s' "$AJ" | jq -e . >/dev/null 2>&1; then pass "[S60-B] streams-audit valid JSON"; else fail "[S60-B] streams-audit valid JSON"; fi
assert_eq "[S60-B] streams-audit lists 2 streams (auto-apply skipped)" "2" "$(printf '%s' "$AJ" | jq -r '.streams | length')"
assert_eq "[S60-B] streams-audit flags current stream" "acme__feature-auth" "$(printf '%s' "$AJ" | jq -r '.streams[] | select(.isCurrent) | .streamId')"
assert_eq "[S60-B] streams-audit reads phase from rollup" "TESTING" "$(printf '%s' "$AJ" | jq -r '.streams[] | select(.streamId=="acme__feature-pay") | .phase')"
assert_eq "[S60-B] streams-audit owner from git" "Musti" "$(printf '%s' "$AJ" | jq -r '.owner')"
assert_eq "[S60-B] streams-audit no false conflict" "0" "$(printf '%s' "$AJ" | jq -r '.conflicts | length')"

# Engine-level isolation: two streamId dirs are physically distinct.
A="$(VIBEFLOW_CWD="$D" bash -c "source '$LIB'; vf_state_project_dir")"
git -C "$D" checkout -q -b feature/pay
B="$(VIBEFLOW_CWD="$D" bash -c "source '$LIB'; vf_state_project_dir")"
if [[ "$A" != "$B" ]]; then pass "[S60-B] two branches → two isolated state dirs"; else fail "[S60-B] two branches → two isolated state dirs"; fi
rm -rf "$D"

# Streams off → audit degrades to streamsEnabled:false.
D="$(mk "")"
AJ="$(VIBEFLOW_CWD="$D" bash "$AUDIT_SH")"
assert_eq "[S60-B] streams off → streamsEnabled false" "false" "$(printf '%s' "$AJ" | jq -r '.streamsEnabled')"
rm -rf "$D"

# ---------------------------------------------------------------------------
echo "== [S60-C] /vibeflow:streams + /vibeflow:integrate skills + wiring =="

assert_file "[S60-C] skills/streams/SKILL.md exists" "$STREAMS_SKILL"
assert_grep "[S60-C] streams frontmatter name" "^name: streams" "$STREAMS_SKILL"
assert_grep "[S60-C] streams runs streams-audit.sh" "streams-audit\\.sh" "$STREAMS_SKILL"
assert_grep "[S60-C] streams writes report" "\\.vibeflow/reports/streams\\.md" "$STREAMS_SKILL"
assert_file "[S60-C] skills/integrate/SKILL.md exists" "$INTEGRATE_SKILL"
assert_grep "[S60-C] integrate frontmatter name" "^name: integrate" "$INTEGRATE_SKILL"
assert_grep "[S60-C] integrate opens an integration cycle" "sdlc_start_cycle" "$INTEGRATE_SKILL"
assert_grep "[S60-C] integrate runs integration-verifier" "integration-verifier" "$INTEGRATE_SKILL"
assert_grep "[S60-C] integrate runs cross-feature consensus" "consensus-run\\.sh" "$INTEGRATE_SKILL"

# Registry registration.
if jq -e '.skills.streams' "$REGISTRY" >/dev/null 2>&1; then pass "[S60-C] streams registered"; else fail "[S60-C] streams registered"; fi
assert_eq "[S60-C] streams phases=ALL" "ALL" "$(jq -r '.skills.streams.phases' "$REGISTRY")"
if jq -e '.skills.integrate' "$REGISTRY" >/dev/null 2>&1; then pass "[S60-C] integrate registered"; else fail "[S60-C] integrate registered"; fi

# Skill wiring: the three lifecycle skills resolve the stream id; flow-status surfaces it.
assert_grep "[S60-C] onboard resolves vf_lifecycle_path" "vf_lifecycle_path" "$ONBOARD"
assert_grep "[S60-C] phase-runner resolves stream-id.sh" "stream-id\\.sh" "$PHASE_RUNNER"
assert_grep "[S60-C] phase-runner breadcrumbs integrate on a merge point" "/vibeflow:integrate" "$PHASE_RUNNER"
assert_grep "[S60-C] brownfield-intake resolves stream-id.sh" "stream-id\\.sh" "$BROWNFIELD"
assert_grep "[S60-C] flow-status surfaces streams" "streams-audit\\.sh" "$FLOW_STATUS"

# ---------------------------------------------------------------------------
echo "== [S60-D] consensus-gate allowlists the read-only stream readers =="

assert_grep "[S60-D] gate allowlists stream-id.sh" "stream-id\\.sh" "$GATE_SH"
assert_grep "[S60-D] gate allowlists streams-audit.sh" "streams-audit\\.sh" "$GATE_SH"

# Runtime: with an armed marker, stream-id.sh passes but a plain write blocks.
D="$(mk '"streams": { "enabled": true }')"
mkdir -p "$D/.vibeflow/state"
printf '{"primaryArtifact":"docs/prd.md","requiredCommand":"/vibeflow:consensus-orchestrator","createdAt":"x"}' > "$D/.vibeflow/state/consensus-needed.json"
IN_OK='{"tool_input":{"command":"bash hooks/scripts/stream-id.sh"}}'
RC_OK="$(echo "$IN_OK" | VIBEFLOW_CWD="$D" bash "$GATE_SH" >/dev/null 2>&1; echo $?)"
assert_eq "[S60-D] runtime: stream-id.sh allowed under armed marker" "0" "$RC_OK"
IN_BLK='{"tool_input":{"command":"echo hi > src/foo.ts"}}'
RC_BLK="$(echo "$IN_BLK" | VIBEFLOW_CWD="$D" bash "$GATE_SH" >/dev/null 2>&1; echo $?)"
assert_eq "[S60-D] runtime: a plain write still blocks" "2" "$RC_BLK"
rm -rf "$D"

# ---------------------------------------------------------------------------
echo "== [S60-E] docs =="

assert_file "[S60-E] docs/TEAM-WORK.md exists" "$TEAM_DOC"
assert_grep "[S60-E] TEAM-WORK documents streams.enabled opt-in" "streams.*enabled" "$TEAM_DOC"
assert_grep "[S60-E] TEAM-WORK documents the worktree layout" "git worktree add" "$TEAM_DOC"
assert_grep "[S60-E] TEAM-WORK documents the merge point" "/vibeflow:integrate" "$TEAM_DOC"
assert_grep "[S60-E] TEAM-WORK warns against committing state" "gitignore" "$TEAM_DOC"
assert_grep "[S60-E] LIFECYCLE.md notes per-stream lifecycle" "per work-stream" "$LIFECYCLE_DOC"
assert_grep "[S60-E] CLAUDE.md lists /vibeflow:streams" "/vibeflow:streams" "$REPO_ROOT/CLAUDE.md"

# ---------------------------------------------------------------------------
echo "== [S60-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-60.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S60-Z] shebang #!/bin/bash"; else fail "[S60-Z] shebang #!/bin/bash"; fi
for sec in S60-A S60-B S60-C S60-D S60-E S60-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S60-Z] [$sec] section header present"; else fail "[S60-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
