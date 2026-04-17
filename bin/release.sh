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
#   - `bash tests/integration/sprint-6.sh`
#   - `bash tests/integration/sprint-7.sh`
#   - `bash tests/integration/sprint-8.sh`
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
PRERELEASE=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)                DRY_RUN=true ;;
    --check-clean)            CHECK_CLEAN_ONLY=true ;;
    --test-changelog-insert)  TEST_CHANGELOG_INSERT=true ;;
    "--prerelease")           PRERELEASE=true ;;
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
  local is_prerelease="${2:-false}"
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

  if [[ "$is_prerelease" == "true" ]]; then
    # Prerelease mode — insert under the "## Pre-releases" footer.
    # The footer is laid down in CHANGELOG.md by Sprint 8 / S8-01;
    # if it is missing we abort rather than silently re-insert at
    # the top (that would defeat the point of "never become latest").
    local prerel_header_line
    prerel_header_line="$(grep -n '^## Pre-releases$' CHANGELOG.md | head -1 | cut -d: -f1)"
    if [[ -z "$prerel_header_line" ]]; then
      echo "release: CHANGELOG.md is missing '## Pre-releases' footer" >&2
      echo "release: add it once per S8-01 before cutting prereleases" >&2
      return 1
    fi
    # Insert AFTER the header comment block. We find the first
    # "## [" entry line AFTER the Pre-releases header, and insert
    # immediately before it. If there are no prior prerelease
    # entries, append at end of file.
    local insert_at_line
    insert_at_line="$(awk -v start="$prerel_header_line" '
      NR > start && /^## \[/ { print NR; exit }
    ' CHANGELOG.md)"
    if [[ -z "$insert_at_line" ]]; then
      # No prior prerelease entries — append at end of file.
      {
        cat CHANGELOG.md
        printf '%s\n' "$new_entry"
      } > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
    else
      local head_count=$((insert_at_line - 1))
      {
        head -n "$head_count" CHANGELOG.md
        printf '%s\n\n' "$new_entry"
        tail -n +"$insert_at_line" CHANGELOG.md
      } > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
    fi
    # Post-insert verify: new version header appears AFTER the
    # Pre-releases header (not before).
    local ver_line
    ver_line="$(grep -n "^## \[$ver\]" CHANGELOG.md | head -1 | cut -d: -f1)"
    local prerel_line_after
    prerel_line_after="$(grep -n '^## Pre-releases$' CHANGELOG.md | head -1 | cut -d: -f1)"
    if [[ -z "$ver_line" ]] || [[ -z "$prerel_line_after" ]] \
        || (( ver_line <= prerel_line_after )); then
      echo "release: CHANGELOG.md prerelease insertion failed — [$ver] not under ## Pre-releases" >&2
      return 1
    fi
    return 0
  fi

  # Stable mode — prepend above the first existing "## [X.Y.Z]" entry.
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
echo "== [0.5] build-dependency sanity =="

# Sprint 7 / S7-04 — pg is a peer dependency of sdlc-engine (Sprint 5
# / S5-03 moved it from optionalDependencies so team-mode users get
# it by default). The sdlc-engine TypeScript source has a static
# `import 'pg'` in src/state/postgres.ts, so `tsc` requires pg +
# @types/pg to be resolvable at build time. If the peer dep was
# uninstalled for testing (as happened during S6-01 live-verification
# before the v1.1.0 release), `build-all.sh` fails halfway through
# step [5] with `Cannot find module 'pg'` AFTER plugin.json has
# already been bumped — leaving the working tree in an awkward
# half-released state.
#
# Catching this pre-flight keeps the release atomic: the tree stays
# clean until the build actually runs. The fix is a one-liner
# (`cd mcp-servers/sdlc-engine && npm install pg @types/pg`) so we
# print it directly rather than make the maintainer hunt for it.
PG_NODE_MODULES="$REPO_ROOT/mcp-servers/sdlc-engine/node_modules/pg"
PG_TYPES_NODE_MODULES="$REPO_ROOT/mcp-servers/sdlc-engine/node_modules/@types/pg"

if [[ ! -d "$PG_NODE_MODULES" ]] || [[ ! -d "$PG_TYPES_NODE_MODULES" ]]; then
  echo "release: pg peer dep is not installed in sdlc-engine." >&2
  echo "release: `build-all.sh` will fail at step [5] without it." >&2
  echo "release: fix with:" >&2
  echo "release:   cd mcp-servers/sdlc-engine && npm install pg @types/pg" >&2
  exit 1
fi
echo "  ok   pg + @types/pg installed in sdlc-engine/node_modules"

# -----------------------------------------------------------------------------
echo "== [1] version argument =="

if [[ -z "$VERSION" ]]; then
  echo "release: version argument is required (X.Y.Z)" >&2
  echo "usage: bin/release.sh <version> [--dry-run]" >&2
  exit 2
fi

# SemVer validation — mode depends on --prerelease flag.
# - default:     strict X.Y.Z, no suffix
# - --prerelease: X.Y.Z-<id>, where <id> is SemVer 2.0.0 compliant
SEMVER_STABLE='^[0-9]+\.[0-9]+\.[0-9]+$'
SEMVER_PRERELEASE='^[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z][0-9A-Za-z.-]*$'

if [[ "$PRERELEASE" == "true" ]]; then
  if [[ "$VERSION" =~ $SEMVER_STABLE ]]; then
    echo "release: --prerelease is only for SemVer prerelease identifiers (X.Y.Z-<id>)" >&2
    echo "release: got '$VERSION' which is a strict SemVer triple — drop --prerelease for stable releases" >&2
    exit 2
  fi
  if [[ ! "$VERSION" =~ $SEMVER_PRERELEASE ]]; then
    echo "release: version '$VERSION' is not a valid SemVer prerelease (X.Y.Z-<id>)" >&2
    echo "release: example valid forms: 1.3.0-rc.1, 1.3.0-beta.2, 1.3.0-alpha" >&2
    exit 2
  fi
  echo "  ok   version '$VERSION' is a valid SemVer prerelease (prerelease mode)"
else
  if [[ "$VERSION" =~ $SEMVER_PRERELEASE ]]; then
    echo "release: version '$VERSION' is a SemVer prerelease identifier" >&2
    echo "release: prerelease versions requires --prerelease flag" >&2
    echo "release: re-run with: bin/release.sh $VERSION --prerelease" >&2
    exit 2
  fi
  if [[ ! "$VERSION" =~ $SEMVER_STABLE ]]; then
    echo "release: version '$VERSION' is not a strict SemVer X.Y.Z" >&2
    echo "release: prerelease + build-metadata suffixes require --prerelease (see docs/RELEASING.md)" >&2
    exit 2
  fi
  echo "  ok   version '$VERSION' is a valid SemVer triple"
fi

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
  "bash tests/integration/sprint-6.sh"
  "bash tests/integration/sprint-7.sh"
  "bash tests/integration/sprint-8.sh"
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
  if [[ "$PRERELEASE" == "true" ]]; then
    echo "  [dry-run] would insert a new [$VERSION] entry under ## Pre-releases in CHANGELOG.md"
  else
    echo "  [dry-run] would prepend a new [$VERSION] entry to CHANGELOG.md"
  fi
else
  if insert_changelog_entry "$VERSION" "$PRERELEASE"; then
    TODAY="$(date -u +%Y-%m-%d)"
    if [[ "$PRERELEASE" == "true" ]]; then
      echo "  ok   CHANGELOG.md gained [$VERSION] — $TODAY under ## Pre-releases"
    else
      echo "  ok   CHANGELOG.md now leads with [$VERSION] — $TODAY"
    fi
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

# Sprint 6 / S6-05 — tag signing.
#
# Signed tags let downstream consumers verify the release via
# `git tag -v v<version>` against the maintainer's published GPG (or
# SSH) public key. The release workflow probes for signing readiness
# in three steps and degrades gracefully:
#
#   1. VF_SKIP_GPG_SIGN=1      → opt-out (annotated tag, even if a key
#                                is configured). Useful for local dry
#                                runs or test releases.
#   2. user.signingkey unset   → no key configured at all, fall back
#                                to an annotated tag automatically.
#   3. `git tag -s` fails      → signing was attempted but the key
#                                wasn't reachable (passphrase timeout,
#                                gpg-agent down, yubikey unplugged).
#                                Fall back to annotated + print a
#                                warning so the maintainer notices.
#
# The chosen path is recorded in TAG_MODE so the "next steps" hint
# block at the bottom of the script can surface it clearly.
TAG_MODE="annotated"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] would git add + commit + tag v$VERSION"
  echo "  [dry-run] no files touched, no git state changed"
  if [[ "${VF_SKIP_GPG_SIGN:-}" == "1" ]]; then
    echo "  [dry-run] VF_SKIP_GPG_SIGN=1 — would use `git tag -a`"
  elif git config --get user.signingkey >/dev/null 2>&1; then
    SIGNING_KEY="$(git config --get user.signingkey)"
    echo "  [dry-run] user.signingkey=$SIGNING_KEY — would use `git tag -s`"
  else
    echo "  [dry-run] no user.signingkey configured — would use `git tag -a`"
  fi
else
  git add .claude-plugin/plugin.json CHANGELOG.md
  # Tarball + sha256 are release artifacts — don't commit them, they
  # live only on the GitHub release (same as v1.0.0).
  git commit -m "Release v$VERSION — bump plugin.json + CHANGELOG"

  if [[ "${VF_SKIP_GPG_SIGN:-}" == "1" ]]; then
    echo "  !    VF_SKIP_GPG_SIGN=1 — skipping tag signature"
    git tag -a "v$VERSION" -m "v$VERSION"
    TAG_MODE="annotated"
  elif git config --get user.signingkey >/dev/null 2>&1; then
    SIGNING_KEY="$(git config --get user.signingkey)"
    echo "  signing tag with key $SIGNING_KEY"
    if git tag -s "v$VERSION" -m "v$VERSION" 2>/tmp/vf-release-sign.err; then
      TAG_MODE="signed"
      echo "  ok   signed tag v$VERSION created"
    else
      echo "  WARN git tag -s failed — falling back to annotated tag" >&2
      echo "  WARN error:" >&2
      sed 's/^/  WARN   /' /tmp/vf-release-sign.err >&2 || true
      # The failed signed tag may or may not have been created — make
      # sure the slot is free before creating the annotated fallback.
      git tag -d "v$VERSION" >/dev/null 2>&1 || true
      git tag -a "v$VERSION" -m "v$VERSION"
      TAG_MODE="annotated"
    fi
    rm -f /tmp/vf-release-sign.err
  else
    echo "  !    no user.signingkey configured — using annotated tag"
    echo "  !    configure a signing key to sign future releases:"
    echo "  !      git config --global user.signingkey <KEY-ID>"
    git tag -a "v$VERSION" -m "v$VERSION"
    TAG_MODE="annotated"
  fi
  echo "  ok   git commit + tag v$VERSION ($TAG_MODE) created locally"
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
  echo "Tag mode: $TAG_MODE"
  if [[ "$TAG_MODE" == "signed" ]]; then
    echo "Verify with:"
    echo "  git tag -v v$VERSION"
  else
    echo "(Unsigned — configure user.signingkey to sign future releases.)"
  fi
  echo
  echo "Next steps (user-authorized public actions):"
  echo
  echo "  git push origin main"
  echo "  git push origin v$VERSION"
  if [[ "$PRERELEASE" == "true" ]]; then
    echo "  gh release create v$VERSION $TARBALL $SHAFILE --prerelease \\"
    echo "    --title \"v$VERSION\" --notes-file <(awk '/^## \\[$VERSION\\]/{f=1} /^## \\[/{if(f&&NR>1)exit} f' CHANGELOG.md)"
    echo
    echo "  ! this is a PRERELEASE — the GitHub Releases page will mark it so,"
    echo "    and package managers watching 'latest' will skip it by default."
  else
    echo "  gh release create v$VERSION $TARBALL $SHAFILE \\"
    echo "    --title \"v$VERSION\" --notes-file <(awk '/^## \\[$VERSION\\]/{f=1} /^## \\[/{if(f&&NR>1)exit} f' CHANGELOG.md)"
  fi
  echo
  echo "If you change your mind, undo with:"
  echo "  git tag -d v$VERSION"
  echo "  git reset --hard HEAD~1"
fi
exit 0
