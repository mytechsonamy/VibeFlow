#!/bin/bash
# Sprint 45 integration harness — mobile-stability-runner (Expo-aware crash &
# stability testing) + its platform-conditional wiring into the TESTING walk.
#
# Sections:
#   [S45-A] mobile-stability-runner skill structure
#   [S45-B] phase-runner TESTING mobile-conditional wiring
#   [S45-C] phase-policy registration + docs/MOBILE-TESTING.md
#   [S45-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

MSR="$REPO_ROOT/skills/mobile-stability-runner/SKILL.md"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
DOC="$REPO_ROOT/docs/MOBILE-TESTING.md"

# ---------------------------------------------------------------------------
echo "== [S45-A] mobile-stability-runner skill structure =="

assert_file "[S45-A] skills/mobile-stability-runner/SKILL.md exists" "$MSR"
assert_grep "[S45-A] frontmatter name" "^name: mobile-stability-runner$" "$MSR"
assert_grep "[S45-A] model-invocable" "^disable-model-invocation: false$" "$MSR"
assert_grep "[S45-A] Phase Contract = TESTING, mobile only" "TESTING\\*\\*, \\*\\*mobile only|mobile only" "$MSR"
assert_grep "[S45-A] platform guard (ios/android/all)" "ios. / .android. / .all.|not a mobile platform" "$MSR"
# Expo-aware runner auto-detect.
assert_grep "[S45-A] detects Expo vs bare RN" "Expo vs bare|Expo if .app.json" "$MSR"
assert_grep "[S45-A] Expo → Maestro" "Expo .. Maestro|Expo \\*\\*→\\*\\* Maestro|Expo → Maestro" "$MSR"
assert_grep "[S45-A] bare RN → Detox" "bare React Native .. Detox|bare.*Detox" "$MSR"
# Crash-focused battery scenarios.
assert_grep "[S45-A] cold-start smoke" "Cold-start smoke" "$MSR"
assert_grep "[S45-A] background/foreground" "Background .. foreground|background" "$MSR"
assert_grep "[S45-A] low memory" "Low memory" "$MSR"
assert_grep "[S45-A] deep links" "Deep links" "$MSR"
assert_grep "[S45-A] permission denial" "Permission denial" "$MSR"
assert_grep "[S45-A] network loss mid-flow" "Network loss" "$MSR"
# Crash detection + reporter.
assert_grep "[S45-A] detects native crash / redbox / ANR" "Native crash|redbox|ANR" "$MSR"
assert_grep "[S45-A] surfaces crash-reporter (Sentry/Crashlytics/Expo)" "Sentry|Crashlytics|Expo error reporting" "$MSR"
# Graceful degrade + arm-on-pass.
assert_grep "[S45-A] graceful-degrade when no device (breadcrumb, not hard fail)" \
  "no simulator/device|environment: unavailable|do NOT fail hard" "$MSR"
assert_grep "[S45-A] writes mobile-stability-report.md" "mobile-stability-report.md" "$MSR"
assert_grep "[S45-A] arm-on-pass (Sprint 43)" "only on PASS|only if .VERDICT == .PASS." "$MSR"

# ---------------------------------------------------------------------------
echo "== [S45-B] phase-runner mobile-conditional wiring =="

assert_grep "[S45-B] phase-runner adds the mobile crash/stability lane" \
  "crash/stability lane|mobile-stability-runner" "$RUNNER"
assert_grep "[S45-B] gated on platform ios/android/all" \
  "platform. is .ios. / .android. / .all.|ios. / .android. / .all." "$RUNNER"
assert_grep "[S45-B] Expo-aware note (Maestro / Detox)" "Expo-aware|Maestro / bare RN" "$RUNNER"
assert_grep "[S45-B] graceful-degrade noted" "Graceful-degrade|no simulator/device" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S45-C] phase-policy + docs =="

if command -v jq >/dev/null 2>&1; then
  if jq -e '.skills["mobile-stability-runner"].phases | index("TESTING") != null' "$POLICY" >/dev/null 2>&1; then
    pass "[S45-C] phase-policy registers mobile-stability-runner for TESTING"
  else
    fail "[S45-C] phase-policy registers mobile-stability-runner for TESTING"
  fi
fi
assert_file "[S45-C] docs/MOBILE-TESTING.md exists" "$DOC"
assert_grep "[S45-C] docs cover Expo-aware runner selection" "Expo-aware|Maestro|Detox" "$DOC"
assert_grep "[S45-C] docs cover the crash battery" "Cold-start smoke|crash-focused" "$DOC"
assert_grep "[S45-C] docs note graceful degrade" "graceful degrade|run this locally|NEEDS_REVISION" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S45-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-45.sh"
assert_grep "[S45-Z] sprint-45.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S45-Z] covers [S45-A]" '\[S45-A\]' "$SELF"
assert_grep "[S45-Z] covers [S45-B]" '\[S45-B\]' "$SELF"
assert_grep "[S45-Z] covers [S45-C]" '\[S45-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
