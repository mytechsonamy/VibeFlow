#!/bin/bash
# VibeFlow Sprint 7 integration harness.
#
# Complements run.sh + sprint-2.sh + sprint-3.sh + sprint-4.sh +
# sprint-5.sh + sprint-6.sh. Sprint 7 targets v1.2.0 and picks up
# items deferred from Sprint 6's scope decisions + the two lessons
# captured during the v1.1.0 release (Sprint 6 / S6-09).
#
# Sections:
#   [S7-A] — release.sh pre-step-5 pg peer-dep sanity check (S7-04)
#   [S7-B] — docs/RELEASING.md troubleshooting + sha256-drift recovery (S7-05)
#   [S7-Z] — Sprint 7 harness self-audit (mirrors [S6-Z])
#
# Sprint 7 ticket coverage (as of current commit):
#   S7-04 (release.sh pg sanity check)   → [S7-A]
#   S7-05 (RELEASING.md troubleshooting) → [S7-B]
# S7-01 / S7-02 / S7-03 / S7-06 / S7-07 are not yet picked up — if
# and when they land, they will add their own [S7-C/D/E/…] sections
# here.
#
# Exit 0 on full pass, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

# ---------------------------------------------------------------------------
echo "== [S7-A] release.sh pre-step-5 pg peer-dep sanity check =="

# S7-04 — release.sh must refuse to proceed past step [0.5] if the
# pg peer dependency is not installed in sdlc-engine's node_modules.
# Without this check, the release fails mid-flight at step [5]
# (build-all.sh) with `Cannot find module 'pg'` AFTER plugin.json
# has been bumped — leaving the working tree in an awkward
# half-released state.
#
# These sentinels are source-grep checks. Exercising the actual
# failure path would require uninstalling pg, which would break the
# normal-dev build. The structural checks are enough: if the step
# [0.5] logic is present, it must fire when pg is actually missing
# (that's the `[[ ! -d ... ]] && exit 1` guarantee).

RELEASE_SCRIPT_S7A="$REPO_ROOT/bin/release.sh"

# The [0.5] section header must be present (it's the visible marker
# of the sanity check).
if grep -q '== \[0.5\] build-dependency sanity' "$RELEASE_SCRIPT_S7A"; then
  pass "[S7-A] release.sh has a [0.5] build-dependency sanity section"
else
  fail "[S7-A] release.sh has a [0.5] build-dependency sanity section"
fi

# The probe must name the exact path that build-all.sh requires —
# mcp-servers/sdlc-engine/node_modules/pg. Anything else would be
# a weaker check.
if grep -q 'mcp-servers/sdlc-engine/node_modules/pg' "$RELEASE_SCRIPT_S7A"; then
  pass "[S7-A] release.sh probes sdlc-engine/node_modules/pg"
else
  fail "[S7-A] release.sh probes sdlc-engine/node_modules/pg"
fi

# The probe must ALSO include @types/pg — tsc needs both the
# runtime module and the types. Without the types, tsc fails with a
# different error (TS2307) that the bare pg check wouldn't catch.
if grep -q 'node_modules/@types/pg' "$RELEASE_SCRIPT_S7A"; then
  pass "[S7-A] release.sh probes sdlc-engine/node_modules/@types/pg"
else
  fail "[S7-A] release.sh probes sdlc-engine/node_modules/@types/pg"
fi

# The error output must include the fix command so the maintainer
# doesn't have to hunt for it. `cd mcp-servers/sdlc-engine && npm install pg @types/pg`
# is a one-liner we print directly.
if grep -q 'npm install pg @types/pg' "$RELEASE_SCRIPT_S7A"; then
  pass "[S7-A] release.sh prints the 'npm install pg @types/pg' fix command"
else
  fail "[S7-A] release.sh prints the 'npm install pg @types/pg' fix command"
fi

# The sanity check must run BEFORE step [1] (version argument).
# Otherwise a pg-missing release would still bump plugin.json's
# version in step [3] before failing at step [5] — same half-
# released state the ticket is designed to prevent.
#
# grep -n gives us line numbers; we compare the [0.5] position
# against the [1] position.
LINE_05="$(grep -n '== \[0.5\]' "$RELEASE_SCRIPT_S7A" | head -1 | cut -d: -f1)"
LINE_1="$(grep -n '== \[1\] version argument' "$RELEASE_SCRIPT_S7A" | head -1 | cut -d: -f1)"
if [[ -n "$LINE_05" ]] && [[ -n "$LINE_1" ]] && (( LINE_05 < LINE_1 )); then
  pass "[S7-A] [0.5] sanity check runs before [1] version argument (line $LINE_05 < $LINE_1)"
else
  fail "[S7-A] [0.5] sanity check runs before [1] version argument (got 0.5=$LINE_05 1=$LINE_1)"
fi

# The S7-04 ticket reference must appear in the section comment so
# a future contributor reading the code knows why the check exists.
if grep -q 'S7-04' "$RELEASE_SCRIPT_S7A"; then
  pass "[S7-A] release.sh [0.5] section cites S7-04 in the comment"
else
  fail "[S7-A] release.sh [0.5] section cites S7-04 in the comment"
fi

# ---------------------------------------------------------------------------
echo "== [S7-B] RELEASING.md troubleshooting + sha256-drift recovery =="

# S7-05 — docs/RELEASING.md must document the two recovery paths
# that surfaced during the v1.1.0 release:
#   1. pg peer dep missing → step [5] fails
#   2. sha256 sidecar drift after preflight regenerates the tarball
# Without these entries, a future maintainer hitting the same
# incident has to rediscover the fix from scratch.

RELEASING_DOC_S7B="$REPO_ROOT/docs/RELEASING.md"

if [[ -f "$RELEASING_DOC_S7B" ]]; then
  # Troubleshooting entry 1 — pg peer dep missing. Must mention
  # the error text ("Cannot find module 'pg'") OR the new
  # release.sh message ("pg peer dep is not installed") so a
  # maintainer searching either text finds the entry.
  if grep -q "pg peer dep is not installed" "$RELEASING_DOC_S7B" \
      || grep -q "Cannot find module 'pg'" "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md documents the pg peer-dep-missing error"
  else
    fail "[S7-B] RELEASING.md documents the pg peer-dep-missing error"
  fi
  # The entry must surface the one-liner fix so the maintainer
  # doesn't have to dig.
  if grep -q 'npm install pg @types/pg' "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md surfaces the 'npm install pg @types/pg' fix"
  else
    fail "[S7-B] RELEASING.md surfaces the 'npm install pg @types/pg' fix"
  fi

  # Troubleshooting entry 2 — mid-flight release failure recovery.
  # Must cover the manual re-run of build-all.sh + package-plugin.sh
  # + sha256 regeneration.
  if grep -q 'release.sh fails MID-FLIGHT' "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md documents the mid-flight failure recovery"
  else
    fail "[S7-B] RELEASING.md documents the mid-flight failure recovery"
  fi

  # Troubleshooting entry 3 — sha256 drift. Must describe the
  # root cause (preflight regenerates tarball) + the fix (regen
  # + gh release upload --clobber).
  if grep -q 'sha256 sidecar' "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md documents the sha256 sidecar drift"
  else
    fail "[S7-B] RELEASING.md documents the sha256 sidecar drift"
  fi
  if grep -q 'gh release upload.*--clobber' "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md includes the 'gh release upload --clobber' fix"
  else
    fail "[S7-B] RELEASING.md includes the 'gh release upload --clobber' fix"
  fi
  # The root-cause note must mention sprint-4.sh [S4-G] so future
  # readers know why the tarball regenerates and can reason about
  # whether it still applies.
  if grep -q 'sprint-4.sh \[S4-G\]' "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md attributes tarball regen to sprint-4.sh [S4-G]"
  else
    fail "[S7-B] RELEASING.md attributes tarball regen to sprint-4.sh [S4-G]"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [S7-Z] sprint-7.sh harness self-audit =="

# Mirrors sprint-6.sh [S6-Z]. Catches section-deletion, chmod -x,
# missing release.sh preflight entry, bad shebang, and missing
# set -uo pipefail — regressions a future refactor might introduce
# without firing any other harness.

SELF_S7Z="$REPO_ROOT/tests/integration/sprint-7.sh"

# 1-3. Each expected section header must still be present.
for sec_label in "S7-A" "S7-B" "S7-Z"; do
  if grep -q "echo \"== \[$sec_label\]" "$SELF_S7Z"; then
    pass "[S7-Z] [$sec_label] section header still present"
  else
    fail "[S7-Z] [$sec_label] section header still present"
  fi
done

# 4. Harness file must still be executable.
if [[ -x "$SELF_S7Z" ]]; then
  pass "[S7-Z] sprint-7.sh is executable"
else
  fail "[S7-Z] sprint-7.sh is executable"
fi

# 5. bin/release.sh preflight must reference sprint-7.sh.
if grep -q 'tests/integration/sprint-7.sh' "$REPO_ROOT/bin/release.sh"; then
  pass "[S7-Z] bin/release.sh preflight references sprint-7.sh"
else
  fail "[S7-Z] bin/release.sh preflight references sprint-7.sh"
fi

# 6. Shebang is #!/bin/bash.
if head -1 "$SELF_S7Z" | grep -q '^#!/bin/bash$'; then
  pass "[S7-Z] sprint-7.sh shebang is #!/bin/bash"
else
  fail "[S7-Z] sprint-7.sh shebang is #!/bin/bash"
fi

# 7. set -uo pipefail in effect.
if grep -q '^set -uo pipefail$' "$SELF_S7Z"; then
  pass "[S7-Z] sprint-7.sh runs under set -uo pipefail"
else
  fail "[S7-Z] sprint-7.sh runs under set -uo pipefail"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
