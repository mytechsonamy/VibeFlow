#!/bin/bash
# bin/release.sh — v1.0.1+ release pipeline automation.
#
# Walks a new version from bump → build → package → changelog → tag
# in one pass, refusing to run unless the working tree is clean and
# every test harness is green. Tag push and `gh release create` are
# deliberately NOT automated — those are public-facing actions and
# wait for explicit user authorization (same discipline as the v1.0.0
# release in Sprint 4 / S4-07).
#
# Usage:
#   bin/release.sh <version>            # full release prep
#   bin/release.sh <version> --dry-run  # run everything except file writes + git ops
#   bin/release.sh --check-clean        # exit 0 iff the working tree is clean
#
# <version> must be in SemVer form X.Y.Z. Pre-release / build-metadata
# suffixes are rejected by design — v1.0.x releases are strict
# patch / minor / major bumps only. If you need a prerelease, cut
# the tag manually and document the process in the next sprint's
# release-workflow ticket.
#
# Pre-flight test harnesses (all must pass):
#   - 5× `npm test` per MCP server
#   - `bash hooks/tests/run.sh`
#   - `bash tests/integration/run.sh`
#   - `bash tests/integration/sprint-2.sh`
#   - `bash tests/integration/sprint-3.sh`
#   - `bash tests/integration/sprint-4.sh`
#   - `bash tests/integration/sprint-5.sh`
#
# Artifacts on success:
#   - vibeflow-plugin-<version>.tar.gz   (via package-plugin.sh)
#   - vibeflow-plugin-<version>.tar.gz.sha256
#   - git commit with version bump + CHANGELOG insertion
#   - git tag v<version> (local only — NOT pushed)
#
# After success the script prints the commands to push the commit
# + tag + create the GitHub release. The user runs them.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION=""
DRY_RUN=false
CHECK_CLEAN_ONLY=false
TEST_CHANGELOG_INSERT=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)                DRY_RUN=true ;;
    --check-clean)            CHECK_CLEAN_ONLY=true ;;
    --test-changelog-insert)  TEST_CHANGELOG_INSERT=true ;;
    -*)                       echo "unknown flag: $arg" >&2; exit 2 ;;
    *)                        if [[ -z "$VERSION" ]]; then VERSION="$arg"; else
                                echo "unexpected argument: $arg" >&2; exit 2
                              fi ;;
  esac
done

# ----- insert_changelog_entry <version> -------------------------------------
# Idempotent helper that prepends a new `## [<version>] — <today>` stub to
# CHANGELOG.md in the current directory. Extracted into a function so the
# --test-changelog-insert mode can exercise it against a fixture without
# running the full release pipeline (preflight, version checks, build, etc).
#
# The insertion uses head/tail/grep rather than `awk -v entry="$NEW_ENTRY"`
# because BSD awk on macOS rejects multiline -v values with a "newline in
# string" runtime error — the exact bug that silently broke the first
# release.sh 1.0.1 run in Sprint 5 / S5-07.
#
# Post-insertion verification refuses to continue if the new version header
# is not at the top of the rewritten CHANGELOG. Any regression here exits
# non-zero and prints to stderr.
#
# Returns 0 on success, non-zero on any failure (missing heading, missing
# file, post-insertion verification failed).
insert_changelog_entry() {
  local ver="$1"
  if [[ ! -f CHANGELOG.md ]]; then
    echo "release: CHANGELOG.md not found in $(pwd)" >&2
    return 1
  fi
  local today
  today="$(date -u +%Y-%m-%d)"
  local new_entry="## [$ver] — $today

<!-- Edit this entry with the highlights of $ver before tagging. -->

### Added
-

### Fixed
-

### Changed
-

### Breaking changes

None.

### Migration

N/A."
  local first_heading_line
  first_heading_line="$(grep -n '^## \[' CHANGELOG.md | head -1 | cut -d: -f1)"
  if [[ -z "$first_heading_line" ]]; then
    echo "release: CHANGELOG.md has no '## [...]' heading — cannot insert" >&2
    return 1
  fi
  local head_count=$((first_heading_line - 1))
  {
    if (( head_count > 0 )); then
      head -n "$head_count" CHANGELOG.md
    fi
    printf '%s\n\n' "$new_entry"
    tail -n +"$first_heading_line" CHANGELOG.md
  } > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
  if ! head -20 CHANGELOG.md | grep -qF "## [$ver]"; then
    echo "release: CHANGELOG.md insertion failed — [$ver] header missing" >&2
    return 1
  fi
  return 0
}

# --test-changelog-insert <version> ------------------------------------------
# Runs ONLY the CHANGELOG insertion step against CHANGELOG.md in the
# current working directory. Skips every other release.sh step so it can
# be called from an isolated tempdir fixture by the Sprint harnesses.
# Closes the gap identified in Sprint 5 / S5-07 — the awk BSD bug that
# slipped past every static source-grep sentinel because it only surfaced
# at runtime.
if [[ "$TEST_CHANGELOG_INSERT" == "true" ]]; then
  if [[ -z "$VERSION" ]]; then
    echo "release --test-changelog-insert: version argument is required" >&2
    exit 2
  fi
  if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "release --test-changelog-insert: version '$VERSION' is not a strict SemVer X.Y.Z" >&2
    exit 2
  fi
  if insert_changelog_entry "$VERSION"; then
    echo "  ok   CHANGELOG.md leads with [$VERSION]"
    exit 0
  else
    exit 1
  fi
fi

cd "$REPO_ROOT"

# -----------------------------------------------------------------------------
echo "== [0] working tree cleanliness =="

if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  echo "release: refuse to run on a dirty working tree." >&2
  echo "release: stash or commit your local changes first." >&2
  git status --short >&2
  exit 1
fi
echo "  ok   working tree is clean"

if [[ "$CHECK_CLEAN_ONLY" == "true" ]]; then
  exit 0
fi

# -----------------------------------------------------------------------------
echo "== [1] version argument =="

if [[ -z "$VERSION" ]]; then
  echo "release: version argument is required (X.Y.Z)" >&2
  echo "usage: bin/release.sh <version> [--dry-run]" >&2
  exit 2
fi

# Strict SemVer pattern — no prerelease, no metadata.
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "release: version '$VERSION' is not a strict SemVer X.Y.Z" >&2
  echo "release: prerelease + build-metadata suffixes are not supported by this script" >&2
  exit 2
fi
echo "  ok   version '$VERSION' is a valid SemVer triple"

# Must be strictly greater than the current version.
CURRENT_VERSION="$(jq -r '.version' .claude-plugin/plugin.json)"
if [[ "$CURRENT_VERSION" == "$VERSION" ]]; then
  echo "release: version '$VERSION' matches the current plugin.json version" >&2
  echo "release: bump to a higher X.Y.Z before running this script" >&2
  exit 1
fi
echo "  ok   current plugin.json reports $CURRENT_VERSION (will bump to $VERSION)"

# Must not already have a git tag for this version.
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "release: tag v$VERSION already exists — bump to a higher version" >&2
  exit 1
fi
echo "  ok   tag v$VERSION does not exist yet"

# -----------------------------------------------------------------------------
echo "== [2] pre-flight test gauntlet =="

PREFLIGHT_CMDS=(
  "cd mcp-servers/sdlc-engine && npm test"
  "cd mcp-servers/codebase-intel && npm test"
  "cd mcp-servers/design-bridge && npm test"
  "cd mcp-servers/dev-ops && npm test"
  "cd mcp-servers/observability && npm test"
  "bash hooks/tests/run.sh"
  "bash tests/integration/run.sh"
  "bash tests/integration/sprint-2.sh"
  "bash tests/integration/sprint-3.sh"
  "bash tests/integration/sprint-4.sh"
  "bash tests/integration/sprint-5.sh"
)

PREFLIGHT_FAILED=0
for cmd in "${PREFLIGHT_CMDS[@]}"; do
  echo "  running: $cmd"
  if ! (cd "$REPO_ROOT" && eval "$cmd" >/dev/null 2>&1); then
    echo "  FAIL   $cmd" >&2
    PREFLIGHT_FAILED=$((PREFLIGHT_FAILED + 1))
  else
    echo "  ok     $cmd"
  fi
done

if (( PREFLIGHT_FAILED > 0 )); then
  echo "release: $PREFLIGHT_FAILED pre-flight check(s) failed — aborting." >&2
  exit 1
fi
echo "  ok   all 11 pre-flight harnesses passed"

# -----------------------------------------------------------------------------
echo "== [3] plugin.json version bump =="

if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] would rewrite .claude-plugin/plugin.json version = $VERSION"
else
  jq --arg v "$VERSION" '.version = $v' .claude-plugin/plugin.json \
    > .claude-plugin/plugin.json.tmp \
    && mv .claude-plugin/plugin.json.tmp .claude-plugin/plugin.json
  echo "  ok   plugin.json.version = $VERSION"
fi

# -----------------------------------------------------------------------------
echo "== [4] CHANGELOG insertion =="

if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] would prepend a new [$VERSION] entry to CHANGELOG.md"
else
  if insert_changelog_entry "$VERSION"; then
    TODAY="$(date -u +%Y-%m-%d)"
    echo "  ok   CHANGELOG.md now leads with [$VERSION] — $TODAY"
    echo "  !    remember to fill in the entry before pushing"
  else
    echo "release: CHANGELOG insertion step failed — aborting release." >&2
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
echo "== [5] rebuild + package =="

if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] would run ./build-all.sh + ./package-plugin.sh --skip-build"
else
  if ! ./build-all.sh >/dev/null 2>&1; then
    echo "  FAIL   build-all.sh" >&2
    exit 1
  fi
  echo "  ok   build-all.sh succeeded"

  if ! ./package-plugin.sh --skip-build >/dev/null 2>&1; then
    echo "  FAIL   package-plugin.sh" >&2
    exit 1
  fi
  echo "  ok   package-plugin.sh succeeded"
fi

# -----------------------------------------------------------------------------
echo "== [6] sha256 manifest =="

TARBALL="vibeflow-plugin-${VERSION}.tar.gz"
SHAFILE="${TARBALL}.sha256"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] would write $SHAFILE"
elif [[ -f "$TARBALL" ]]; then
  # Portable sha256: prefer shasum (always on macOS), fallback to
  # sha256sum on Linux.
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$TARBALL" > "$SHAFILE"
  else
    sha256sum "$TARBALL" > "$SHAFILE"
  fi
  echo "  ok   wrote $SHAFILE"
  cat "$SHAFILE"
else
  echo "  SKIP $TARBALL not found (dry run of [5]?)"
fi

# -----------------------------------------------------------------------------
echo "== [7] git commit + tag =="

if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] would git add + commit + tag v$VERSION"
  echo "  [dry-run] no files touched, no git state changed"
else
  git add .claude-plugin/plugin.json CHANGELOG.md
  # Tarball + sha256 are release artifacts — don't commit them, they
  # live only on the GitHub release (same as v1.0.0).
  git commit -m "Release v$VERSION — bump plugin.json + CHANGELOG"
  git tag -a "v$VERSION" -m "v$VERSION"
  echo "  ok   git commit + tag v$VERSION created locally"
fi

# -----------------------------------------------------------------------------
echo
echo "==============================================================="
echo " Release v$VERSION prepared locally."
echo "==============================================================="
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  (dry-run — no files written, no git ops performed)"
else
  echo
  echo "Next steps (user-authorized public actions):"
  echo
  echo "  git push origin main"
  echo "  git push origin v$VERSION"
  echo "  gh release create v$VERSION $TARBALL $SHAFILE \\"
  echo "    --title \"v$VERSION\" --notes-file <(awk '/^## \\[$VERSION\\]/{f=1} /^## \\[/{if(f&&NR>1)exit} f' CHANGELOG.md)"
  echo
  echo "If you change your mind, undo with:"
  echo "  git tag -d v$VERSION"
  echo "  git reset --hard HEAD~1"
fi
exit 0
