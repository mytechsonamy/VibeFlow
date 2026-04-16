# S8-01 — Prerelease / Beta-Channel Workflow

**Sprint:** 8 (v1.3.0 scope)
**Originally deferred from:** Sprint 6 / S6-06 → Sprint 7 / S7-03 → Sprint 8 / S8-01
**Status:** Design approved 2026-04-16

## Goal

Add a prerelease release track to `bin/release.sh` so maintainers can
cut `1.3.0-rc.1`, `1.3.0-beta.2`, `1.3.0-alpha.3`-style tags without
the existing strict-SemVer guard aborting them. Prereleases must not
become the "latest" stable entry in the CHANGELOG and must surface
the `--prerelease` flag on `gh release create`.

## Non-goals

- **Automated promotion `rc.N → stable`** — promotion is still a
  separate `bin/release.sh <X.Y.Z>` invocation. No auto-upgrade.
- **Prerelease-only CI channel** (e.g. a separate `prerelease` branch
  or workflow trigger). Stays on the same release workflow.
- **Cross-host deterministic tarballs** (S8-04 owns that).
- **`gh release create` auto-invocation** — the human still runs it.

## Design

### 1. `bin/release.sh` prerelease mode

**New flag:** `--prerelease`

**Flag × version cross-validation:**

| `--prerelease` | Version form                  | Result                                                                                   |
|----------------|-------------------------------|------------------------------------------------------------------------------------------|
| false (default)| Strict `X.Y.Z`                | OK — existing stable path                                                                |
| false          | `X.Y.Z-<id>` prerelease       | Error (exit 2): *"prerelease version requires --prerelease flag"*                        |
| true           | Strict `X.Y.Z`                | Error (exit 2): *"--prerelease is only for SemVer prerelease identifiers (X.Y.Z-…)"*     |
| true           | `X.Y.Z-<id>` prerelease       | OK — prerelease path                                                                     |

**SemVer prerelease regex (SemVer 2.0.0 compliant):**

```bash
SEMVER_PRERELEASE='^[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z][0-9A-Za-z.-]*$'
```

Accepts: `1.3.0-rc.1`, `1.3.0-beta.2`, `1.3.0-alpha`, `1.3.0-dev`,
`1.3.0-preview.4`.
Rejects: `1.3.0-` (empty id), `1.3.0-.rc` (leading dot),
`1.3.0+build` (build-metadata — out of scope for this ticket).

**Monotonicity checks:**

- `plugin.json`'s current version must differ from `<version>` (same
  as stable). No string-lex ordering check beyond that — `rc.1` vs
  `rc.2` comparison is not enforced in code (human-driven).
- Tag `v<version>` must not already exist (same as stable).

### 2. CHANGELOG.md one-time re-layout

Append at the end of the current CHANGELOG (below the oldest entry):

```markdown

---

## Pre-releases

<!-- Prerelease entries sit below this header. Stable releases stay
     above the `---` separator; prereleases never become "latest". -->
```

This is a single commit as part of S8-01 — the header is laid down
explicitly so the first `release.sh … --prerelease` run has a
stable insertion point to append under.

### 3. `insert_changelog_entry()` two-mode

```bash
insert_changelog_entry() {
  local ver="$1"
  local is_prerelease="${2:-false}"
  # ... (stub content unchanged)

  if [[ "$is_prerelease" == "true" ]]; then
    # Locate "## Pre-releases" header line number.
    # Insert new entry immediately AFTER the header comment block
    # so newer prereleases appear on top within the Pre-releases
    # section.
    # Post-insert verify: the new "## [$ver] — $today" line exists
    # AFTER the "## Pre-releases" line.
  else
    # Existing behavior: prepend at top, above first `## [X.Y.Z]` line.
  fi
}
```

**Stub content unchanged** for both modes — `Added / Fixed / Changed
/ Breaking changes / Migration`. The prerelease author fills it in
the same way.

### 4. Preflight gauntlet

**Unchanged.** Prereleases still run the full 14-layer gauntlet (~5
min on a warm box). A prerelease is still a shipped artifact; we
don't want it weaker than stable.

### 5. `gh release create` hint line

In the "Next steps" block at the end of the script:

```bash
if [[ "$PRERELEASE" == "true" ]]; then
  echo "  gh release create v$VERSION $TARBALL $SHAFILE --prerelease \\"
else
  echo "  gh release create v$VERSION $TARBALL $SHAFILE \\"
fi
```

Everything else in the Next-Steps block (title, notes-file, undo
hint) stays the same.

### 6. `docs/RELEASING.md` "Prereleases" section

Insert as new H2 after the "Quickstart" section, before "Rollback".

Content covers:

- **When to cut a prerelease:** risky API changes, early community
  feedback window, multi-week RC bake, uncertainty about a design
  decision that shipped in the main branch but wants external
  validation before it enters a stable tag.
- **Command:** `bash bin/release.sh 1.3.0-rc.1 --prerelease`
- **CHANGELOG convention:** prerelease entries live under
  `## Pre-releases` at the bottom. They are NOT promoted into the
  stable section — each prerelease is a permanent record of what
  was shipped.
- **Promotion path (rc → stable):** cut rc.1, rc.2, rc.N until
  confident, then `bash bin/release.sh 1.3.0` (no flag) — copy the
  best prerelease CHANGELOG bullets into the fresh stable stub.
- **Troubleshooting update:** the existing "not a strict SemVer"
  error message paragraph points at Sprint 6 / S6-06 as the "wait
  for prerelease workflow" fix — update it to say "use
  `--prerelease`" and drop the Sprint 6 reference.

### 7. `tests/integration/sprint-8.sh [S8-C]` sentinel

**Static sentinels (grep-based, always run):**

1. `bin/release.sh` parses `--prerelease` flag
2. `bin/release.sh` defines SemVer prerelease regex
3. `bin/release.sh` calls `insert_changelog_entry` with a
   prerelease-mode second argument
4. `bin/release.sh` emits `--prerelease` hint conditionally
5. `CHANGELOG.md` contains `## Pre-releases` header
6. `docs/RELEASING.md` contains `## Prereleases` H2
7. `docs/RELEASING.md` documents the promotion path (grep for
   keywords like "promotion" or "rc → stable")

**Runtime sentinels (opt-out via `VF_SKIP_S8C_RUNTIME=1`):**

8. `bash bin/release.sh 1.3.0-rc.1 --prerelease --dry-run` → exit 0
9. Output contains "prerelease" keyword AND the `--prerelease` hint
   string for `gh release create`
10. `bash bin/release.sh 1.3.0-rc.1 --dry-run` (no flag) → exit 2 +
    stderr contains "requires --prerelease"
11. `bash bin/release.sh 1.3.0 --prerelease --dry-run` → exit 2 +
    stderr mentions "prerelease identifier"

**Test count delta:** 11 new sentinels (7 static + 4 runtime).

### 8. Housekeeping updates

- **`CLAUDE.md`**: bump sprint-8.sh count from 19 → 30 and
  baseline total from 1585 → 1596 (+11 for [S8-C]).
- **`docs/SPRINT-8.md`**: tick S8-01 checkbox ✅ DONE, update
  "Next Ticket to Work On" to S8-07/S8-08, update
  "Test inventory" block with new counts.

## File touch list

| File                                     | Change                                               |
|------------------------------------------|------------------------------------------------------|
| `bin/release.sh`                         | Add `--prerelease` flag + regex + two-mode insert    |
| `CHANGELOG.md`                           | Append `## Pre-releases` footer section              |
| `docs/RELEASING.md`                      | New H2 "Prereleases" + troubleshooting tweak         |
| `tests/integration/sprint-8.sh`          | New `[S8-C]` section with 11 sentinels               |
| `CLAUDE.md`                              | Test count bump                                      |
| `docs/SPRINT-8.md`                       | S8-01 ✅ DONE + updated Next Ticket + inventory       |

## Risks / known unknowns

- **Plugin.json version field accepts prerelease format?** —
  `package-plugin.sh` reads via `jq -r '.version'`, so whatever
  string we put there gets piped into the tarball filename
  verbatim. `vibeflow-plugin-1.3.0-rc.1.tar.gz` should be valid.
  **Verify at implementation time** by running the dry-run path.
- **Claude Code plugin install compatibility** — `claude plugin
  install ./vibeflow-plugin-1.3.0-rc.1.tar.gz` may or may not
  handle prerelease versions. Not this ticket's problem, but
  flag it in the RELEASING.md section so a maintainer isn't
  surprised.
- **Git tag ordering** — `git describe` sorts `v1.3.0-rc.1`
  alphabetically before `v1.3.0` which is correct for SemVer
  ordering. Should "just work"; no changes needed.

## Verification plan

1. Run all static sentinels — fast, catch typos.
2. Run the 4 runtime sentinels against an actual `--dry-run`
   invocation — catches flag/regex/hint regressions.
3. Full gauntlet (`bash tests/integration/sprint-8.sh`) green.
4. Manual: edit a fixture `plugin.json` to `1.3.0-rc.1`, run
   `package-plugin.sh --dry-run` → verify tarball name is
   `vibeflow-plugin-1.3.0-rc.1.tar.gz`.

## Out-of-scope (future tickets)

- **Automated rc promotion** (cut rc.1, auto-bump to rc.2 on next
  main merge) — not worth the complexity yet.
- **Prerelease CHANGELOG diff view** (`## [latest stable]` vs
  `## [latest prerelease]` nav at the top of CHANGELOG) — cosmetic.
- **Prerelease-only dependency installation tests** (e.g. `claude
  plugin install` against a `*-rc.1` tarball in CI) — picks up
  when S8-06 adds live-install CI coverage.
