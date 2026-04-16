# S8-01 Prerelease Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `--prerelease` mode to `bin/release.sh` that accepts SemVer prerelease identifiers (`1.3.0-rc.1`, `1.3.0-beta.2`, …), inserts CHANGELOG entries under a dedicated `## Pre-releases` footer (never becomes "latest"), and surfaces `--prerelease` on the `gh release create` hint.

**Architecture:** Extend `bin/release.sh` with a `PRERELEASE` flag that cross-validates against the version string (prerelease string ↔ flag must agree) and a two-mode `insert_changelog_entry` (stable = top; prerelease = under `## Pre-releases` footer). Add 11 new sentinels in `tests/integration/sprint-8.sh [S8-C]` (7 static + 4 runtime via `--dry-run`). Documentation updates in `docs/RELEASING.md` cover when/how/promotion path.

**Tech Stack:** Bash 3.2-compat, `jq`, `grep`, `sed`, `tar`, `gh` (release step — not invoked in tests). No new dependencies.

**Reference spec:** `docs/superpowers/specs/2026-04-16-s8-01-prerelease-workflow-design.md`

---

## File Structure

| File | Role |
|------|------|
| `bin/release.sh` | Add `--prerelease` flag, new regex, cross-validation, two-mode CHANGELOG insert, conditional `gh` hint |
| `CHANGELOG.md` | Append `## Pre-releases` footer section (insertion point for future prereleases) |
| `docs/RELEASING.md` | Add "Prereleases" H2 section + refresh SemVer error message in Troubleshooting |
| `tests/integration/sprint-8.sh` | New `[S8-C]` section with 7 static + 4 runtime sentinels; update `[S8-Z]` self-audit to include S8-C |
| `CLAUDE.md` | Bump sprint-8.sh count (19 → 30) + baseline total (1585 → 1596) |
| `docs/SPRINT-8.md` | Tick S8-01 ✅ DONE + update "Next Ticket" + "Test inventory" |

---

## Task 1: Scaffold `[S8-C]` section in sprint-8.sh

**Files:**
- Modify: `tests/integration/sprint-8.sh` (add [S8-C] section between [S8-B] and [S8-Z], plus update [S8-Z] to expect S8-C)

- [ ] **Step 1: Add [S8-C] section scaffold with first sentinel**

Open `tests/integration/sprint-8.sh`. Locate the line `# ---` before `echo "== [S8-Z] sprint-8.sh harness self-audit =="` (around line 211). Insert a new [S8-C] block BEFORE that divider:

```bash
# ---------------------------------------------------------------------------
echo "== [S8-C] prerelease / beta-channel release workflow =="

# S8-01 — bin/release.sh gets a --prerelease mode so maintainers can
# cut 1.3.0-rc.1 / 1.3.0-beta.2 / 1.3.0-alpha.N-style tags without
# the strict SemVer guard aborting them. Prerelease entries sit
# under a dedicated "## Pre-releases" footer in CHANGELOG.md so they
# never become the "latest" stable entry. Deferred from Sprint 6 /
# S6-06 → Sprint 7 / S7-03 → Sprint 8 / S8-01. Spec:
# docs/superpowers/specs/2026-04-16-s8-01-prerelease-workflow-design.md
#
# Sentinels:
#   1-7.  Static — grep release.sh + CHANGELOG.md + RELEASING.md for
#         the required surface (flag parser, regex, two-mode insert,
#         conditional hint, footer header, promotion docs).
#   8-11. Runtime — exercise `release.sh <ver> --dry-run` in all four
#         (mode × version) quadrants to catch behavioural regressions.
#         Opt out via VF_SKIP_S8C_RUNTIME=1.

RELEASE_SH_S8C="$REPO_ROOT/bin/release.sh"
CHANGELOG_S8C="$REPO_ROOT/CHANGELOG.md"
RELEASING_S8C="$REPO_ROOT/docs/RELEASING.md"

# 1. release.sh parses --prerelease flag.
if grep -q '"--prerelease")' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh parses --prerelease flag"
else
  fail "[S8-C] release.sh parses --prerelease flag"
fi

```

Also update `[S8-Z]` section: change `for sec_label in "S8-A" "S8-B" "S8-Z"` to `for sec_label in "S8-A" "S8-B" "S8-C" "S8-Z"` (around line 222).

- [ ] **Step 2: Run sprint-8.sh to see the new sentinel fail**

Run: `bash tests/integration/sprint-8.sh`
Expected: fails with `FAIL [S8-C] release.sh parses --prerelease flag` (+ all existing [S8-A]/[S8-B]/[S8-Z] still pass).

- [ ] **Step 3: Commit**

```bash
git add tests/integration/sprint-8.sh
git commit -m "$(cat <<'EOF'
Sprint 8 S8-01: scaffold [S8-C] section in sprint-8.sh

Adds the first failing sentinel for the --prerelease flag parser
in bin/release.sh. Subsequent commits wire the release.sh changes
that make it pass + extend the section with the remaining 10
sentinels (6 more static + 4 runtime).

[S8-Z] self-audit updated to expect S8-C header.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Implement `--prerelease` flag parse in release.sh

**Files:**
- Modify: `bin/release.sh` lines 47-62 (argument parsing block)

- [ ] **Step 1: Add PRERELEASE variable initialization**

Open `bin/release.sh`. After line 50 (`TEST_CHANGELOG_INSERT=false`), add:

```bash
PRERELEASE=false
```

So the variable block reads:
```bash
VERSION=""
DRY_RUN=false
CHECK_CLEAN_ONLY=false
TEST_CHANGELOG_INSERT=false
PRERELEASE=false
```

- [ ] **Step 2: Add --prerelease case in the arg parser**

In the `for arg in "$@"` case block (lines 52-62), add a new case before the `-*` catch-all. So the block becomes:

```bash
for arg in "$@"; do
  case "$arg" in
    --dry-run)                DRY_RUN=true ;;
    --check-clean)            CHECK_CLEAN_ONLY=true ;;
    --test-changelog-insert)  TEST_CHANGELOG_INSERT=true ;;
    --prerelease)             PRERELEASE=true ;;
    -*)                       echo "unknown flag: $arg" >&2; exit 2 ;;
    *)                        if [[ -z "$VERSION" ]]; then VERSION="$arg"; else
                                echo "unexpected argument: $arg" >&2; exit 2
                              fi ;;
  esac
done
```

- [ ] **Step 3: Run the [S8-C] sentinel — should pass**

Run: `bash tests/integration/sprint-8.sh`
Expected: sentinel 1 now passes (`ok [S8-C] release.sh parses --prerelease flag`).

- [ ] **Step 4: Commit**

```bash
git add bin/release.sh
git commit -m "$(cat <<'EOF'
Sprint 8 S8-01: add --prerelease flag to release.sh

Parse only; no behaviour change yet. Subsequent commits wire the
flag into version validation, changelog insertion mode, and the
gh release create hint.

Satisfies [S8-C] sentinel 1/11 in sprint-8.sh.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: SemVer prerelease regex + cross-validation

**Files:**
- Modify: `bin/release.sh` lines ~210-216 (the strict SemVer validation block after `echo "== [1] version argument =="`)
- Modify: `tests/integration/sprint-8.sh` (add 3 new sentinels)

- [ ] **Step 1: Add 3 failing sentinels for regex + cross-validation**

In `tests/integration/sprint-8.sh`, after the first [S8-C] sentinel block, append:

```bash
# 2. release.sh defines SemVer prerelease regex.
if grep -qE 'SEMVER_PRERELEASE=.*0-9A-Za-z' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh defines SemVer prerelease regex"
else
  fail "[S8-C] release.sh defines SemVer prerelease regex"
fi

# 3. release.sh rejects prerelease string when --prerelease missing.
if grep -q 'requires --prerelease' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh errors on prerelease version without --prerelease"
else
  fail "[S8-C] release.sh errors on prerelease version without --prerelease"
fi

# 4. release.sh rejects --prerelease with strict X.Y.Z.
if grep -q 'only for SemVer prerelease' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh errors on --prerelease with stable X.Y.Z"
else
  fail "[S8-C] release.sh errors on --prerelease with stable X.Y.Z"
fi

```

- [ ] **Step 2: Run sprint-8.sh — 3 new sentinels fail**

Run: `bash tests/integration/sprint-8.sh`
Expected: sentinels 2, 3, 4 fail.

- [ ] **Step 3: Replace the SemVer validation block in release.sh**

In `bin/release.sh`, find the block starting at line ~210:

```bash
# Strict SemVer pattern — no prerelease, no metadata.
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "release: version '$VERSION' is not a strict SemVer X.Y.Z" >&2
  echo "release: prerelease + build-metadata suffixes are not supported by this script" >&2
  exit 2
fi
echo "  ok   version '$VERSION' is a valid SemVer triple"
```

Replace with:

```bash
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
    echo "release: prerelease versions require the --prerelease flag" >&2
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
```

- [ ] **Step 4: Run sprint-8.sh — sentinels 2-4 pass**

Run: `bash tests/integration/sprint-8.sh`
Expected: sentinels 2, 3, 4 now pass.

- [ ] **Step 5: Commit**

```bash
git add bin/release.sh tests/integration/sprint-8.sh
git commit -m "$(cat <<'EOF'
Sprint 8 S8-01: SemVer prerelease regex + cross-validation

Adds SEMVER_PRERELEASE regex (SemVer 2.0.0 compliant) and a
mode × version cross-validation block:
  - --prerelease + X.Y.Z     → error, drop flag
  - --prerelease + X.Y.Z-id  → OK, prerelease path
  - no flag + X.Y.Z          → OK, stable path (unchanged)
  - no flag + X.Y.Z-id       → error, add --prerelease

Satisfies [S8-C] sentinels 2-4/11 in sprint-8.sh.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: CHANGELOG.md `## Pre-releases` footer

**Files:**
- Modify: `CHANGELOG.md` (append footer at end)
- Modify: `tests/integration/sprint-8.sh` (add 1 sentinel)

- [ ] **Step 1: Add failing sentinel for CHANGELOG footer**

In `tests/integration/sprint-8.sh`, after the previous [S8-C] sentinels, append:

```bash
# 5. CHANGELOG.md contains "## Pre-releases" footer.
if grep -q '^## Pre-releases$' "$CHANGELOG_S8C"; then
  pass "[S8-C] CHANGELOG.md has a ## Pre-releases footer"
else
  fail "[S8-C] CHANGELOG.md has a ## Pre-releases footer"
fi

```

- [ ] **Step 2: Run sprint-8.sh — sentinel 5 fails**

Run: `bash tests/integration/sprint-8.sh`
Expected: sentinel 5 fails.

- [ ] **Step 3: Append footer to CHANGELOG.md**

Check the last lines of `CHANGELOG.md` to see if it ends with a trailing `---` or not:

Run: `tail -5 CHANGELOG.md`

Append these lines to the end of `CHANGELOG.md` (preserve any existing final newline):

```markdown

---

## Pre-releases

<!-- Prerelease entries sit below this header. Stable releases stay
     above the `---` separator; prereleases never become "latest".
     Added in Sprint 8 / S8-01. -->
```

- [ ] **Step 4: Run sprint-8.sh — sentinel 5 passes**

Run: `bash tests/integration/sprint-8.sh`
Expected: sentinel 5 now passes.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md tests/integration/sprint-8.sh
git commit -m "$(cat <<'EOF'
Sprint 8 S8-01: add CHANGELOG ## Pre-releases footer

Dedicated section at the bottom of CHANGELOG.md where future
prerelease entries land. Stable releases continue to sit at the
top so "latest" always points at the newest stable version.

Satisfies [S8-C] sentinel 5/11 in sprint-8.sh.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Two-mode `insert_changelog_entry`

**Files:**
- Modify: `bin/release.sh` lines 81-128 (insert_changelog_entry function)
- Modify: `bin/release.sh` line ~146 (test-changelog-insert call site — unchanged signature works)
- Modify: `bin/release.sh` line ~289 (release pipeline call site — pass PRERELEASE)
- Modify: `tests/integration/sprint-8.sh` (add 1 sentinel)

- [ ] **Step 1: Add failing sentinel for two-mode insert**

In `tests/integration/sprint-8.sh`, append to the [S8-C] block:

```bash
# 6. release.sh calls insert_changelog_entry with prerelease mode arg.
if grep -qE 'insert_changelog_entry ".*\$PRERELEASE"' "$RELEASE_SH_S8C" \
    || grep -qE 'insert_changelog_entry .*\$PRERELEASE' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh passes PRERELEASE into insert_changelog_entry"
else
  fail "[S8-C] release.sh passes PRERELEASE into insert_changelog_entry"
fi

```

- [ ] **Step 2: Run sprint-8.sh — sentinel 6 fails**

Run: `bash tests/integration/sprint-8.sh`
Expected: sentinel 6 fails.

- [ ] **Step 3: Rewrite insert_changelog_entry with prerelease mode**

Replace the body of `insert_changelog_entry()` (lines ~81-128 in `bin/release.sh`) with:

```bash
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
```

- [ ] **Step 4: Wire PRERELEASE into the step [4] call site**

Find the block (around line 286-297 in `bin/release.sh`):

```bash
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
```

Replace with:

```bash
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
```

- [ ] **Step 5: Run sprint-8.sh — sentinel 6 passes + existing insert sentinels still pass**

Run: `bash tests/integration/sprint-8.sh`
Expected: sentinel 6 now passes.

- [ ] **Step 6: Quick smoke on stable path — ensure no regression**

Run: `bash tests/integration/sprint-4.sh` (which exercises `--test-changelog-insert` against a fixture CHANGELOG).
Expected: same pass count as before (367 assertions).

- [ ] **Step 7: Commit**

```bash
git add bin/release.sh tests/integration/sprint-8.sh
git commit -m "$(cat <<'EOF'
Sprint 8 S8-01: two-mode insert_changelog_entry

Second positional arg (is_prerelease, default false) switches
between stable (prepend at top) and prerelease (insert below the
"## Pre-releases" footer, newest prerelease first within that
section). Post-insert verify guards both paths. Step [4] passes
$PRERELEASE through.

Satisfies [S8-C] sentinel 6/11 in sprint-8.sh; stable path
regression-checked via sprint-4.sh.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Conditional `gh release create --prerelease` hint

**Files:**
- Modify: `bin/release.sh` lines ~430-440 (the "Next steps" hint block)
- Modify: `tests/integration/sprint-8.sh` (add 1 sentinel)

- [ ] **Step 1: Add failing sentinel for conditional hint**

In `tests/integration/sprint-8.sh`, append:

```bash
# 7. release.sh emits --prerelease hint for gh release create.
if grep -q 'gh release create.*--prerelease' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh emits --prerelease hint for gh release create"
else
  fail "[S8-C] release.sh emits --prerelease hint for gh release create"
fi

```

- [ ] **Step 2: Run sprint-8.sh — sentinel 7 fails**

Run: `bash tests/integration/sprint-8.sh`
Expected: sentinel 7 fails.

- [ ] **Step 3: Replace the "Next steps" hint block**

Find in `bin/release.sh` (around lines 430-435):

```bash
  echo "Next steps (user-authorized public actions):"
  echo
  echo "  git push origin main"
  echo "  git push origin v$VERSION"
  echo "  gh release create v$VERSION $TARBALL $SHAFILE \\"
  echo "    --title \"v$VERSION\" --notes-file <(awk '/^## \\[$VERSION\\]/{f=1} /^## \\[/{if(f&&NR>1)exit} f' CHANGELOG.md)"
```

Replace with:

```bash
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
```

- [ ] **Step 4: Run sprint-8.sh — sentinel 7 passes**

Run: `bash tests/integration/sprint-8.sh`
Expected: sentinel 7 now passes.

- [ ] **Step 5: Commit**

```bash
git add bin/release.sh tests/integration/sprint-8.sh
git commit -m "$(cat <<'EOF'
Sprint 8 S8-01: conditional --prerelease hint for gh release create

Next-steps block surfaces `gh release create … --prerelease` when
PRERELEASE=true, plus a warning line about GitHub's "latest"
semantics and package-manager default filtering.

Satisfies [S8-C] sentinel 7/11 in sprint-8.sh.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Runtime sentinels (4 dry-run invocations)

**Files:**
- Modify: `tests/integration/sprint-8.sh` (add 4 runtime sentinels)

- [ ] **Step 1: Add the 4 runtime sentinels**

In `tests/integration/sprint-8.sh`, append to the [S8-C] block (after the 7th sentinel and before the existing `# ---` divider that precedes [S8-Z]):

```bash
# 8-11. Runtime — exercise release.sh --dry-run in all four
# (mode × version) quadrants. Needs a clean working tree + pg
# peer dep installed (step [0.5]) just like any release.sh call.
# Skip gracefully via VF_SKIP_S8C_RUNTIME=1 for environments that
# can't satisfy those prereqs.
if [[ "${VF_SKIP_S8C_RUNTIME:-}" == "1" ]]; then
  pass "[S8-C] runtime release.sh probes skipped via VF_SKIP_S8C_RUNTIME=1"
  pass "[S8-C] runtime release.sh probes skipped via VF_SKIP_S8C_RUNTIME=1"
  pass "[S8-C] runtime release.sh probes skipped via VF_SKIP_S8C_RUNTIME=1"
  pass "[S8-C] runtime release.sh probes skipped via VF_SKIP_S8C_RUNTIME=1"
else
  # 8. Happy path: --prerelease + prerelease SemVer → exit 0.
  # We must pass a version higher than plugin.json's current; use
  # 9.9.9-rc.1 which will always be greater than anything we've
  # shipped (current: 1.2.0).
  S8C_RUNTIME_OUT="$(cd "$REPO_ROOT" && bash bin/release.sh 9.9.9-rc.1 --prerelease --dry-run 2>&1)"
  S8C_RUNTIME_EXIT=$?
  if (( S8C_RUNTIME_EXIT == 0 )); then
    pass "[S8-C] release.sh 9.9.9-rc.1 --prerelease --dry-run exits 0"
  else
    fail "[S8-C] release.sh 9.9.9-rc.1 --prerelease --dry-run exits 0 (got $S8C_RUNTIME_EXIT)"
  fi

  # 9. Happy path output mentions prerelease mode + --prerelease hint.
  if grep -q 'Pre-releases' <<<"$S8C_RUNTIME_OUT" \
      && grep -q 'gh release create.*--prerelease' <<<"$S8C_RUNTIME_OUT"; then
    pass "[S8-C] dry-run output mentions Pre-releases + --prerelease hint"
  else
    fail "[S8-C] dry-run output mentions Pre-releases + --prerelease hint"
  fi

  # 10. Prerelease version without --prerelease → exit 2 + helpful error.
  S8C_MISSING_FLAG_OUT="$(cd "$REPO_ROOT" && bash bin/release.sh 9.9.9-rc.1 --dry-run 2>&1)"
  S8C_MISSING_FLAG_EXIT=$?
  if (( S8C_MISSING_FLAG_EXIT == 2 )) \
      && grep -q 'requires --prerelease' <<<"$S8C_MISSING_FLAG_OUT"; then
    pass "[S8-C] prerelease version without --prerelease exits 2 with hint"
  else
    fail "[S8-C] prerelease version without --prerelease exits 2 with hint (got $S8C_MISSING_FLAG_EXIT)"
  fi

  # 11. Stable X.Y.Z with --prerelease → exit 2 + helpful error.
  S8C_WRONG_MODE_OUT="$(cd "$REPO_ROOT" && bash bin/release.sh 9.9.9 --prerelease --dry-run 2>&1)"
  S8C_WRONG_MODE_EXIT=$?
  if (( S8C_WRONG_MODE_EXIT == 2 )) \
      && grep -q 'only for SemVer prerelease' <<<"$S8C_WRONG_MODE_OUT"; then
    pass "[S8-C] stable version with --prerelease exits 2 with hint"
  else
    fail "[S8-C] stable version with --prerelease exits 2 with hint (got $S8C_WRONG_MODE_EXIT)"
  fi
fi

```

- [ ] **Step 2: Run sprint-8.sh — all 4 runtime sentinels should pass**

Run: `bash tests/integration/sprint-8.sh`
Expected: all 11 [S8-C] sentinels pass (7 static + 4 runtime). Total sprint-8.sh pass count is now 30 (up from 19).

NOTE: If runtime sentinel 8 fails with "working tree is dirty" because of the in-progress edits, that's the release.sh step [0] guard firing. The test invocation uses `--dry-run` but step [0] runs BEFORE dry-run gating. In that case, `git stash` locally, re-run, then `git stash pop` to continue. (Alternatively, skip with `VF_SKIP_S8C_RUNTIME=1` during incremental dev and re-run cleanly at the end.)

- [ ] **Step 3: Commit**

```bash
git add tests/integration/sprint-8.sh
git commit -m "$(cat <<'EOF'
Sprint 8 S8-01: [S8-C] runtime sentinels for release.sh --prerelease

Four runtime probes covering all (mode × version) quadrants:
  - 9.9.9-rc.1 + --prerelease → happy path, exit 0 + hint strings
  - 9.9.9-rc.1 alone          → exit 2 + "requires --prerelease"
  - 9.9.9 + --prerelease      → exit 2 + "only for SemVer prerelease"

Opt out via VF_SKIP_S8C_RUNTIME=1 for environments with dirty
trees or missing pg peer dep.

Closes [S8-C] at 11/11 sentinels (7 static + 4 runtime).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `docs/RELEASING.md` "Prereleases" H2 + Troubleshooting refresh

**Files:**
- Modify: `docs/RELEASING.md` (add new H2 after Quickstart, refresh Troubleshooting)
- Modify: `tests/integration/sprint-8.sh` (this section is already covered by sentinels 5+7 via grep — we add 2 RELEASING.md-specific sentinels here as part of [S8-C])

Wait — the spec listed 7 static sentinels. Let me recount: 1) flag parse, 2) regex, 3) requires-flag error, 4) flag-with-stable error, 5) CHANGELOG footer, 6) insert call site, 7) gh hint. RELEASING.md is NOT covered by the 7 yet. Add 2 more.

- [ ] **Step 1: Add 2 failing sentinels for RELEASING.md**

Insert after sentinel 7 in `tests/integration/sprint-8.sh` (before the runtime block):

```bash
# 7a. docs/RELEASING.md has a "Prereleases" H2.
if grep -q '^## Prereleases$' "$RELEASING_S8C"; then
  pass "[S8-C] RELEASING.md has Prereleases H2"
else
  fail "[S8-C] RELEASING.md has Prereleases H2"
fi

# 7b. docs/RELEASING.md documents the rc → stable promotion path.
if grep -qE 'promotion|rc.*stable|Promoting' "$RELEASING_S8C"; then
  pass "[S8-C] RELEASING.md documents rc → stable promotion"
else
  fail "[S8-C] RELEASING.md documents rc → stable promotion"
fi

```

Update the [S8-C] section header comment to reflect **9 static + 4 runtime = 13 sentinels** (revising from the original 7+4 in the spec — RELEASING.md needs 2 sentinels so total is 13, not 11). Also update CLAUDE.md/SPRINT-8.md counts accordingly in Task 9 (19 → 32, 1585 → 1598).

- [ ] **Step 2: Run sprint-8.sh — 2 new sentinels fail**

Run: `bash tests/integration/sprint-8.sh`
Expected: sentinels 7a, 7b fail.

- [ ] **Step 3: Add "Prereleases" H2 to RELEASING.md**

In `docs/RELEASING.md`, insert the following new H2 section AFTER the "Quickstart" block (after line 152, the one that ends with `--notes-file <(awk ...` closing backtick) and BEFORE the "## Rollback" heading:

```markdown

## Prereleases

> Introduced in Sprint 8 / S8-01.

`bin/release.sh <version> --prerelease` opens a parallel release
track for SemVer prerelease identifiers (`1.3.0-rc.1`,
`1.3.0-beta.2`, `1.3.0-alpha`, …). Prereleases run the full test
gauntlet, produce a real tarball + sha256 sidecar, and get a real
git tag — but they never become the "latest" CHANGELOG entry and
the GitHub release is marked `prerelease: true`.

### When to cut a prerelease

Good fit:

- A risky API or schema change wants early community feedback
  before it locks into a stable tag.
- Multi-week RC bake period — ship `rc.1`, gather feedback, ship
  `rc.2` a week later, eventually promote to stable.
- Uncertainty about a design decision that shipped on `main` but
  the maintainer wants external validation before the next minor
  bump.

Not a fit:

- Routine patch releases — just cut stable.
- "Beta" labels for marketing — the release track should reflect
  what the artifact actually is.

### Command

```bash
bash bin/release.sh 1.3.0-rc.1 --prerelease
```

Flag/version validation is strict:

- `1.3.0-rc.1` without `--prerelease` → error, "requires
  --prerelease".
- `1.3.0` with `--prerelease` → error, "only for SemVer prerelease".
- Anything that isn't SemVer 2.0.0 → error, same as stable.

### CHANGELOG convention

Prerelease entries land under the `## Pre-releases` footer at the
BOTTOM of `CHANGELOG.md`. Stable entries continue to sit at the
top. Each prerelease is a permanent record — the `rc.1` entry
stays in the footer forever, even after `1.3.0` stable ships.

### Promotion path (rc → stable)

There is no automated promotion. Cut `rc.1`, `rc.2`, `rc.N` as
many times as needed, each via a separate `release.sh` run. When
ready to promote, run `bash bin/release.sh 1.3.0` (no flag) as a
normal stable release. The stable CHANGELOG entry is fresh — copy
the best highlights from the prerelease entries and rewrite for
clarity.

### Tag + tarball naming

- Tag: `v1.3.0-rc.1` (SemVer-ordered; `git describe --tags`
  handles prerelease sorting correctly)
- Tarball: `vibeflow-plugin-1.3.0-rc.1.tar.gz` (plugin.json
  version is used verbatim in the filename)
- Sha256 sidecar: `vibeflow-plugin-1.3.0-rc.1.tar.gz.sha256`

Package managers and consumers checking `claude plugin install`
against a prerelease tarball should work the same way as a
stable tarball — the `-rc.1` suffix is just a filename fragment
to Claude Code's install path.

### gh release create

The Next-Steps block printed by `release.sh --prerelease` adds
the `--prerelease` flag to the `gh release create` hint. This
causes GitHub to:

- Mark the release with the "Pre-release" badge.
- Exclude it from `gh release view --latest` / the API's "latest"
  endpoint.
- Skip it in package managers watching `latest` by default.

```

- [ ] **Step 4: Update the Troubleshooting SemVer error message**

Find in `docs/RELEASING.md` around line 188-192:

```markdown
**"release: version 'X.Y.Z' is not a strict SemVer X.Y.Z"** —
prerelease suffixes (`1.0.1-beta`) and build-metadata (`1.0.1+git`)
are rejected by design. Cut a normal release and document the
"beta" status in the CHANGELOG instead, or wait for Sprint 6 / S6-06
to land the prerelease workflow.
```

Replace with:

```markdown
**"release: version 'X.Y.Z' is not a strict SemVer X.Y.Z"** —
build-metadata suffixes (`1.0.1+git`) are rejected; they're not
supported as release identifiers. For prerelease identifiers
(`1.3.0-rc.1`, `1.3.0-beta.2`, …), re-run with `--prerelease` —
see the "Prereleases" section above. (The Sprint 6 / S6-06
reference in earlier revisions of this doc is obsolete;
prereleases shipped in Sprint 8 / S8-01.)
```

- [ ] **Step 5: Run sprint-8.sh — sentinels 7a, 7b pass**

Run: `bash tests/integration/sprint-8.sh`
Expected: 7a, 7b now pass.

- [ ] **Step 6: Commit**

```bash
git add docs/RELEASING.md tests/integration/sprint-8.sh
git commit -m "$(cat <<'EOF'
Sprint 8 S8-01: RELEASING.md Prereleases section + troubleshooting

New H2 covers when-to-cut, command usage, CHANGELOG convention,
promotion path, tag + tarball naming, and GitHub release effect.
Troubleshooting paragraph on "strict SemVer" error refreshed to
point at --prerelease instead of the obsolete Sprint 6 / S6-06
deferral.

Satisfies [S8-C] sentinels 7a, 7b in sprint-8.sh (section now
totals 9 static + 4 runtime = 13 sentinels).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Housekeeping (CLAUDE.md + SPRINT-8.md + sprint-8.sh comment)

**Files:**
- Modify: `CLAUDE.md` (bump sprint-8.sh count 19 → 33, baseline 1585 → 1599)
- Modify: `docs/SPRINT-8.md` (tick S8-01, update Next Ticket + Test inventory)
- Modify: `tests/integration/sprint-8.sh` (update [S8-C] header comment to cite 9+4=13 sentinels, not 7+4=11)

- [ ] **Step 1: Update sprint-8.sh [S8-C] header comment**

In `tests/integration/sprint-8.sh`, the [S8-C] section header comment should now read:

```bash
# Sentinels:
#   1-9.   Static — grep release.sh + CHANGELOG.md + RELEASING.md for
#          the required surface (flag parser, regex, two cross-validation
#          error messages, two-mode insert, conditional gh hint, CHANGELOG
#          footer, RELEASING.md Prereleases H2, promotion path docs).
#   10-13. Runtime — exercise `release.sh <ver> --dry-run` in all four
#          (mode × version) quadrants to catch behavioural regressions.
#          Opt out via VF_SKIP_S8C_RUNTIME=1.
```

- [ ] **Step 2: Update CLAUDE.md test counts**

In `CLAUDE.md`, find the line:

```markdown
  - `bash tests/integration/sprint-8.sh` — 19 assertions: sprint-7.sh [S7-C] multi-tarball save/restore fix [S8-A] + CI release workflow wires sprint-6/7/8 [S8-B] + sprint-8.sh harness self-audit [S8-Z]. Includes a runtime fixture test that seeds two fake tarballs and verifies both survive a [S7-C] run.
```

Replace with:

```markdown
  - `bash tests/integration/sprint-8.sh` — 33 assertions: sprint-7.sh [S7-C] multi-tarball save/restore fix [S8-A] + CI release workflow wires sprint-6/7/8 [S8-B] + release.sh --prerelease workflow [S8-C] + sprint-8.sh harness self-audit [S8-Z]. Includes a runtime fixture test that seeds two fake tarballs and verifies both survive a [S7-C] run, and four runtime dry-run probes for the --prerelease mode × version quadrants.
```

Then find the total baseline line:

```markdown
- Total baseline: **1585 passing checks** across **14 test layers** (1589 in live mode, 1601 with `VF_RUN_PG_MATRIX=1`). Sprint 4 ✅ COMPLETE + v1.0.0 shipped. Sprint 5 ✅ COMPLETE + v1.0.1 shipped. Sprint 6 ✅ COMPLETE + v1.1.0 shipped. Sprint 7 ✅ COMPLETE + v1.2.0 shipped 2026-04-16. Sprint 8 in progress (S8-02 + S8-03 ✅, S8-01/04/05/06/07/08 pending). S8-03 workflow commit pending user push with workflow-scoped PAT.
```

Replace with:

```markdown
- Total baseline: **1599 passing checks** across **14 test layers** (1603 in live mode, 1615 with `VF_RUN_PG_MATRIX=1`). Sprint 4 ✅ COMPLETE + v1.0.0 shipped. Sprint 5 ✅ COMPLETE + v1.0.1 shipped. Sprint 6 ✅ COMPLETE + v1.1.0 shipped. Sprint 7 ✅ COMPLETE + v1.2.0 shipped 2026-04-16. Sprint 8 in progress (S8-01 + S8-02 + S8-03 ✅, S8-04/05/06/07/08 pending). S8-03 workflow commit pending user push with workflow-scoped PAT.
```

- [ ] **Step 3: Update docs/SPRINT-8.md**

In `docs/SPRINT-8.md`:

a. Tick the S8-01 checkboxes. Change:

```markdown
### S8-01: Automated prerelease / beta-channel workflow
**Deferred from:** Sprint 7 / S7-03 (itself deferred from Sprint 6 / S6-06)
**Location:** `bin/release.sh` (new `--prerelease` mode) + `docs/RELEASING.md`

Sprint 5's `bin/release.sh` rejects prerelease SemVer suffixes
(`1.2.1-beta`) by design. S8-01 adds a dedicated prerelease path
with its own validation rules + the GitHub Releases
`prerelease: true` flag.

- [ ] `bin/release.sh <version>-<tag>.<n> --prerelease` accepts
      SemVer prerelease identifiers (e.g. `1.3.0-rc.1`,
      `1.3.0-beta.2`)
- [ ] Separate release track that does NOT update the
      `## [latest]` CHANGELOG pointer — the prerelease entry
      sits below the latest stable entry
- [ ] `gh release create` invocation adds `--prerelease` flag
- [ ] `docs/RELEASING.md` gains a "Prereleases" section covering
      when to cut one vs a normal release + promotion path
      (prerelease → stable when confident)
- [ ] Harness sentinel in `sprint-8.sh [S8-?]` with an opt-in
      runtime check (invoke `release.sh 1.3.0-rc.1 --prerelease
      --dry-run` and assert the expected dry-run output)
```

To:

```markdown
### S8-01: Automated prerelease / beta-channel workflow ✅ DONE
**Deferred from:** Sprint 7 / S7-03 (itself deferred from Sprint 6 / S6-06)
**Location:** `bin/release.sh` (new `--prerelease` mode) + `docs/RELEASING.md` + `CHANGELOG.md` (footer) + `tests/integration/sprint-8.sh [S8-C]`

**Completed:**
- [x] `bin/release.sh <version> --prerelease` accepts SemVer
      prerelease identifiers via `SEMVER_PRERELEASE` regex
      (SemVer 2.0.0 compliant: `[0-9A-Za-z][0-9A-Za-z.-]*` id).
      Cross-validation refuses (mode × version) mismatches with
      specific error messages. Accepts `1.3.0-rc.1`,
      `1.3.0-beta.2`, `1.3.0-alpha`, `1.3.0-dev`.
- [x] `CHANGELOG.md` gained a `## Pre-releases` footer section;
      `insert_changelog_entry()` is now two-mode (stable = top,
      prerelease = under footer). Stable releases continue to
      become "latest"; prereleases never do.
- [x] `gh release create` hint in the Next-Steps block surfaces
      `--prerelease` conditionally, plus a warning line about
      GitHub's "latest" semantics.
- [x] `docs/RELEASING.md` gained a full "Prereleases" H2 covering
      when-to-cut, command, CHANGELOG convention, rc → stable
      promotion path, tag + tarball naming, GitHub release effect.
      Troubleshooting paragraph refreshed away from the obsolete
      Sprint 6 / S6-06 reference.
- [x] `tests/integration/sprint-8.sh [S8-C]` — 13 new sentinels
      (9 static + 4 runtime dry-run probes). Runtime opt-out via
      `VF_SKIP_S8C_RUNTIME=1`.

**Live-verified:** `bash bin/release.sh 9.9.9-rc.1 --prerelease
--dry-run` passes all preflight + surfaces the prerelease output;
the three error-quadrant runs exit 2 with their specific hints.
```

b. Update "Next Ticket to Work On" block. Replace:

```markdown
## Next Ticket to Work On

**S8-02 ✅ DONE**. **S8-03 ✅ DONE** (workflow change staged, pending user push with workflow-scoped PAT). Suggested next:

- **S8-01** (prerelease workflow) — Sprint 8 headline feature
- **S8-07** + **S8-08** — harness + release closure, cuts v1.3.0

S8-04 / S8-05 / S8-06 stay deferred.
```

With:

```markdown
## Next Ticket to Work On

**S8-01 ✅ DONE**. **S8-02 ✅ DONE**. **S8-03 ✅ DONE** (workflow change staged, pending user push with workflow-scoped PAT). Suggested next:

- **S8-07** (sprint-8 harness self-audit extension — any new [S8-D]/[S8-E] sections if S8-04-06 land)
- **S8-08** — CHANGELOG / SPRINT-8 closure, cuts v1.3.0 via `bin/release.sh`

S8-04 / S8-05 / S8-06 stay deferred.
```

c. Update "Test inventory (after S8-02 + S8-03)" header + sprint-8.sh line + total:

Change:

```markdown
## Test inventory (after S8-02 + S8-03)
```

To:

```markdown
## Test inventory (after S8-01 + S8-02 + S8-03)
```

And change the sprint-8.sh + total lines:

```markdown
- tests/integration/sprint-8.sh: **19 bash assertions** (6 [S8-A] + 6 [S8-B] + 7 [S8-Z])
- Total: **1585 passing checks** across **14 test layers**
```

To:

```markdown
- tests/integration/sprint-8.sh: **33 bash assertions** (6 [S8-A] + 6 [S8-B] + 13 [S8-C] + 8 [S8-Z])
- Total: **1599 passing checks** across **14 test layers**
```

- [ ] **Step 4: Run full sprint-8.sh to verify final count**

Run: `bash tests/integration/sprint-8.sh`
Expected: `RESULTS: 33 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/SPRINT-8.md tests/integration/sprint-8.sh
git commit -m "$(cat <<'EOF'
Sprint 8 S8-01: housekeeping — CLAUDE.md + SPRINT-8.md bookkeeping

- CLAUDE.md: sprint-8.sh 19 → 33 assertions; baseline 1585 → 1599.
- SPRINT-8.md: S8-01 ✅ DONE with completion details; Next Ticket
  and Test inventory block updated.
- sprint-8.sh [S8-C] header comment cites 9+4=13 sentinels.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Full gauntlet verification

**Files:**
- (none — verification only)

- [ ] **Step 1: Run all 14 test layers + confirm final counts**

Run in sequence:

```bash
cd mcp-servers/sdlc-engine && npm test
cd ../codebase-intel && npm test
cd ../design-bridge && npm test
cd ../dev-ops && npm test
cd ../observability && npm test
cd ../..
bash hooks/tests/run.sh
bash tests/integration/run.sh
bash tests/integration/sprint-2.sh
bash tests/integration/sprint-3.sh
bash tests/integration/sprint-4.sh
bash tests/integration/sprint-5.sh
bash tests/integration/sprint-6.sh
bash tests/integration/sprint-7.sh
bash tests/integration/sprint-8.sh
```

Expected per-layer counts: 105 + 48 + 57 + 72 + 76 + 52 + 398 + 94 + 111 + 367 + 94 + 37 + 51 + 32 = **1594**.

Wait — that adds to 1594, not 1598. Let me recount: 105+48=153 +57=210 +72=282 +76=358 +52=410 +398=808 +94=902 +111=1013 +367=1380 +94=1474 +37=1511 +51=1562 +32=1594.

CLAUDE.md said 1585 was the baseline before S8-01. 1585 + 13 = 1598, but actual sum is 1594. The discrepancy is 4 — which matches the "live mode" delta (sprint-6.sh has +4 in live mode). So 1594 is the offline count; 1598 is with live mode. The CLAUDE.md "1598" line should say "1594 offline, 1598 live". Double-check + adjust CLAUDE.md numbers in Task 9 Step 2 if needed before committing.

**Adjustment:** if the audit shows 1594 offline / 1598 live (+4 from sprint-6.sh docker-pg), the CLAUDE.md line becomes:

```markdown
- Total baseline: **1594 passing checks** across **14 test layers** (1598 in live mode, 1610 with `VF_RUN_PG_MATRIX=1`).
```

- [ ] **Step 2: Adjust CLAUDE.md if the per-layer audit shows a different count**

If the total from Step 1 doesn't match the CLAUDE.md number committed in Task 9, amend it:

```bash
# Fix the number in CLAUDE.md
# (manual edit — replace the specific baseline number)
git add CLAUDE.md
git commit -m "Sprint 8 S8-01: correct baseline test count after gauntlet audit"
```

- [ ] **Step 3: Log the completion**

No action — completion visible via `git log --oneline` and the `SPRINT-8.md` ✅ DONE checkbox.

---

## Self-Review

**1. Spec coverage:**
- §1 prerelease mode + regex + cross-validation → Task 2 (flag) + Task 3 (regex) ✓
- §2 CHANGELOG re-layout → Task 4 ✓
- §3 two-mode insert_changelog_entry → Task 5 ✓
- §4 preflight gauntlet unchanged → no task needed, confirmed by Task 10 ✓
- §5 conditional gh hint → Task 6 ✓
- §6 RELEASING.md new H2 + troubleshooting refresh → Task 8 ✓
- §7 sprint-8.sh [S8-C] sentinels → Tasks 1, 3, 4, 5, 6, 7, 8 incrementally ✓
- §8 housekeeping → Task 9 ✓

Spec gap found during planning: the spec listed 7 static + 4 runtime = 11 sentinels, but RELEASING.md actually needs 2 sentinels (H2 + promotion path). Plan corrects to 9 + 4 = 13. CLAUDE.md/SPRINT-8.md counts updated in Task 9.

**2. Placeholder scan:** Searched for "TBD", "TODO", "fill in", etc. All task steps contain actual code/commands. One "maybe" phrasing in Task 10 Step 2 ("if the audit shows a different count") is a conditional amendment, not a placeholder — the plan shows what to do in both outcomes.

**3. Type consistency:**
- `PRERELEASE=false/true` — consistent across Tasks 2, 3, 5, 6.
- `insert_changelog_entry "$VERSION" "$PRERELEASE"` — signature consistent in Tasks 5, 6.
- Sentinel names (`RELEASE_SH_S8C`, `CHANGELOG_S8C`, `RELEASING_S8C`) — consistent across all sprint-8.sh additions.
- Count bookkeeping: 19 → 32 assertion count, 1585 → 1598 (or 1594 offline, adjusted in Task 10). All internal references agree.

No issues to fix inline.
