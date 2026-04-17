# Releasing VibeFlow

This document is the end-to-end walkthrough for cutting a new
VibeFlow release. It covers the `bin/release.sh` automation, the
GPG signing setup introduced in Sprint 6 / S6-05, the manual
user-gated push steps, and the rollback path if something goes
wrong partway through.

If you only want the checklist, skip to the "Quickstart" section at
the end. Everything above it is context.

## What `bin/release.sh` does

`bin/release.sh <version>` automates the mechanical parts of a
release but **stops before any public action**. It never pushes the
tag, never runs `gh release create`, and never touches shared
infrastructure. Everything it does is local and reversible.

The seven steps run in order. Any failure aborts before the next
step starts:

| Step | What it does | Skipped in `--dry-run`? |
|------|--------------|-------------------------|
| **0** — working tree cleanliness | Refuses to run on a dirty tree. Commit or stash first. | No |
| **0.25** — release branch guard | Stable releases refuse to run off `main` (or `release/*`). `--prerelease` cuts are exempt. Override: `VF_RELEASE_ALLOW_BRANCH=1`. (Sprint 9 / S9-05) | No |
| **1** — version argument | Strict SemVer (`X.Y.Z`, no prerelease suffixes). Version must be strictly greater than `plugin.json`'s current version, and the tag must not already exist. | No |
| **2** — preflight gauntlet | Runs every MCP vitest suite + hooks + all integration harnesses. Any failure aborts the release. Takes 2–5 minutes. | No |
| **3** — `plugin.json` version bump | Rewrites `.claude-plugin/plugin.json` via `jq`. | Yes |
| **4** — CHANGELOG insertion | Prepends a new `## [<version>] — <today>` stub above the previous entry. Uses the `insert_changelog_entry()` helper (portable `head`/`tail`/`grep` — no BSD awk gotcha; see v1.0.1 CHANGELOG). | Yes |
| **5** — rebuild + package | `./build-all.sh` + `./package-plugin.sh --skip-build` → `vibeflow-plugin-<version>.tar.gz`. | Yes |
| **6** — sha256 manifest | Writes `<tarball>.sha256` next to the tarball. | Yes |
| **7** — git commit + tag | Stages `plugin.json` + `CHANGELOG.md`, makes ONE local commit, creates the tag (signed or annotated — see below). **Does not push.** | Yes |

After step 7 the script prints the commands you run manually to
push the tag + create the GitHub release.

## Release branch policy (Sprint 9 / S9-05)

Stable releases must be cut from `main` (or a `release/*` branch).
The guard is enforced in step **0.25** — if `HEAD` is anywhere else,
`release.sh` aborts with three suggested fixes:

1. Open a PR from your branch → merge → run `release.sh` on `main`.
2. Re-run with `--prerelease` to cut a prerelease tag instead.
3. Set `VF_RELEASE_ALLOW_BRANCH=1` to override (one-off situations
   only — remember to reconcile `main` afterwards).

Prerelease cuts (`--prerelease`) skip the branch guard entirely.
Prereleases never become the "latest" entry, so they can safely ride
on whichever feature branch is carrying the RC bake.

### Why

During the v1.3.0 cut (Sprint 8 / S8-08) the release tag landed on a
feature branch while `origin/main` went stale since Sprint 6. Anyone
cloning fresh and running `release.sh` from main would see
`plugin.json`'s version drift from the latest tag. S9-05 makes the
expected model explicit: **feature branches ship changes, `main`
always reflects the latest released state**.

### Reconciling main after an override

If you ran `release.sh` with `VF_RELEASE_ALLOW_BRANCH=1` from a
feature branch, the Next-Steps block prints the branch-specific push
command instead of `git push origin main`. After the tag is pushed,
fast-forward main to the release commit so future releases pick up a
clean main:

```bash
git checkout main
git merge --ff-only <feature-branch>
git push origin main
git checkout <feature-branch>
```

## Tag signing (Sprint 6 / S6-05)

Signed tags let downstream consumers verify a release against the
maintainer's published GPG or SSH public key with
`git tag -v v<version>`. The release workflow probes for signing
readiness and degrades gracefully — you never need a signing key to
run `bin/release.sh`, but if one is configured the tag is signed
automatically.

The probe runs in three steps:

1. **`VF_SKIP_GPG_SIGN=1`** → opt-out. Even if a key is configured,
   the release uses `git tag -a` (annotated, unsigned). Useful for
   local dry runs or practice releases that should not produce
   signed artifacts.
2. **`git config --get user.signingkey` unset** → no key configured
   at all. Falls back to `git tag -a` automatically and prints a
   hint showing how to configure one.
3. **`git tag -s` fails** → signing was attempted but the key wasn't
   reachable (passphrase timeout, gpg-agent down, YubiKey unplugged).
   The signed-tag attempt is rolled back, an annotated tag is
   created instead, and a `WARN` line is printed so you notice.

The final "Tag mode: signed" or "Tag mode: annotated" line in the
script's output tells you which path was taken.

### One-time GPG key setup

If you want to start signing releases, configure git once:

```bash
# List your existing GPG keys (skip if you already know the key id)
gpg --list-secret-keys --keyid-format=long

# Configure git to use a specific key
git config --global user.signingkey <KEY-ID>

# Optional — sign all commits by default
git config --global commit.gpgsign true

# Optional — sign all tags by default (release.sh already does this
# for the release tag, but you may want it for other tags too)
git config --global tag.gpgsign true
```

If you do not yet have a GPG key, [the GitHub docs](https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key)
cover the generation flow end-to-end. For SSH-based signing (newer,
often simpler on macOS), see `man git-config` under `gpg.format` +
`user.signingkey`.

### Uploading your public key to GitHub

For the "Verified" badge to show up next to your release tag, your
public key must be registered with GitHub:

```bash
# Export the public key
gpg --armor --export <KEY-ID>
# Copy the output, then go to:
#   https://github.com/settings/keys → "New GPG key"
```

Tag signatures are reachable from CI / downstream consumers even
without the GitHub badge — the badge is purely cosmetic.

### Verifying a signed tag locally

Anyone with your public key can verify a signed tag:

```bash
git tag -v v1.0.1
# Output:
#   object <SHA>
#   type commit
#   tag v1.0.1
#   ...
#   gpg: Good signature from "Your Name <you@example.com>"
```

`git tag -v` exits non-zero if the signature is missing or invalid.
CI / release workflows can use the same command to fail the build
on unsigned or tampered tags.

## Quickstart

Assumes you have a clean working tree and all tests already pass.
For a first-time release, read the sections above — this is the
muscle-memory version.

```bash
# 1. Pull latest main + verify the tree is clean
git checkout main
git pull
git status --porcelain   # must be empty

# 2. Run the release pipeline (pre-flight gauntlet runs here)
bash bin/release.sh 1.2.3

# 3. Review the generated CHANGELOG stub. The release.sh step 4
#    inserts an empty stub with Added/Fixed/Changed sections — fill
#    in the real highlights before pushing.
$EDITOR CHANGELOG.md

# 4. If you edit the CHANGELOG, amend the release commit so the
#    tag points at the final CHANGELOG state:
git add CHANGELOG.md
git commit --amend --no-edit
git tag -d v1.2.3
git tag -s v1.2.3 -m "v1.2.3"   # use -s (signed) OR -a (annotated)

# 5. Push + create the GitHub release (user-authorized)
git push origin main
git push origin v1.2.3
gh release create v1.2.3 vibeflow-plugin-1.2.3.tar.gz vibeflow-plugin-1.2.3.tar.gz.sha256 \
  --title "v1.2.3" \
  --notes-file <(awk '/^## \[1.2.3\]/{f=1} /^## \[/{if(f&&NR>1)exit} f' CHANGELOG.md)
```

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
  handles prerelease sorting correctly).
- Tarball: `vibeflow-plugin-1.3.0-rc.1.tar.gz` (plugin.json
  version is used verbatim in the filename).
- Sha256 sidecar: `vibeflow-plugin-1.3.0-rc.1.tar.gz.sha256`.

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

## Rollback

If something went wrong BEFORE you pushed:

```bash
# Undo the local tag + commit
git tag -d v1.2.3
git reset --hard HEAD~1

# Clean up the release artifacts
rm -f vibeflow-plugin-1.2.3.tar.gz vibeflow-plugin-1.2.3.tar.gz.sha256
```

If you already pushed the tag but NOT the GitHub release:

```bash
git push origin --delete v1.2.3
git tag -d v1.2.3
git reset --hard HEAD~1
```

If you already created the GitHub release, the rollback is no
longer local — delete the release via the GitHub UI (or
`gh release delete v1.2.3`), then run the commands above. A
released tarball that ended up in someone's install is not
reversible — cut a patch release (`v1.2.4`) instead of trying to
pull the broken one back.

## Troubleshooting

**"release: refuse to run on a dirty working tree"** — commit or
stash your local changes first. `bin/release.sh --check-clean`
tells you exactly what it sees (exit 0 = clean, exit 1 = dirty).

**"release: version 'X.Y.Z' is not a strict SemVer X.Y.Z"** —
build-metadata suffixes (`1.0.1+git`) are rejected; they're not
supported as release identifiers. For prerelease identifiers
(`1.3.0-rc.1`, `1.3.0-beta.2`, …), re-run with `--prerelease` —
see the "Prereleases" section above. (The Sprint 6 / S6-06
reference in earlier revisions of this doc is obsolete;
prereleases shipped in Sprint 8 / S8-01.)

**"pre-flight check failed"** — one of the harnesses in the gauntlet
is red. Run each harness directly to find the failing one:

```bash
bash hooks/tests/run.sh
bash tests/integration/run.sh
bash tests/integration/sprint-2.sh
bash tests/integration/sprint-3.sh
bash tests/integration/sprint-4.sh
bash tests/integration/sprint-5.sh
bash tests/integration/sprint-6.sh
```

**`git tag -s` fails with "secret key not available"** — the
signing key ID configured in `user.signingkey` is not in your local
keyring. Either import the key (`gpg --import`), reconfigure
`user.signingkey` to a key that IS in your keyring, or set
`VF_SKIP_GPG_SIGN=1` for this release.

**`git tag -s` fails silently** — gpg-agent may have cached the
passphrase timeout. Restart the agent:

```bash
gpgconf --kill gpg-agent
```

Then re-run the release. The `WARN git tag -s failed` line in
`release.sh`'s output will show the underlying gpg error message.

**"CHANGELOG insertion failed — [X.Y.Z] header missing"** — the
post-insertion verification step in `insert_changelog_entry()`
refused to continue because the new version header is not at the
top of CHANGELOG.md. This is a safety guard added in S5-07 to
catch BSD awk regressions. If you see this, check that CHANGELOG.md
starts with a `# Changelog` header and has at least one `## [X.Y.Z]`
entry before the script runs.

**"release: pg peer dep is not installed in sdlc-engine"** — the
`pg` + `@types/pg` node modules are required for `tsc` to compile
`mcp-servers/sdlc-engine/src/state/postgres.ts`. Without them,
`build-all.sh` fails at step [5] with `Cannot find module 'pg'`.
The step [0.5] pre-flight sanity check (added in Sprint 7 / S7-04)
catches this BEFORE plugin.json + CHANGELOG have been touched, so
the tree stays clean. Fix:

```bash
cd mcp-servers/sdlc-engine && npm install pg @types/pg
```

Then re-run `bin/release.sh <version>`. `pg` is a peer dependency
(declared with `peerDependenciesMeta.pg.optional = true` so
solo-mode users don't need it) — npm install in the repo root does
not automatically pull it into sdlc-engine's node_modules.

**release.sh fails MID-FLIGHT (after step [0.5] passed)** — if a
step between [3] plugin.json bump and [7] commit aborts (e.g. you
SIGINT the build, or disk fills up), the tree is left with
plugin.json bumped but no release commit. Recovery:

1. Diagnose the failure — check the last line of release.sh output
   for the step number.
2. If you can fix the underlying issue (reinstall a dep, free up
   disk, etc.): manually run the remaining steps:

   ```bash
   bash build-all.sh
   bash package-plugin.sh --skip-build
   shasum -a 256 vibeflow-plugin-X.Y.Z.tar.gz > vibeflow-plugin-X.Y.Z.tar.gz.sha256
   git add .claude-plugin/plugin.json CHANGELOG.md
   git commit -m "Release vX.Y.Z — bump plugin.json + CHANGELOG"
   # Use -s if user.signingkey is configured, otherwise -a
   git tag -a vX.Y.Z -m vX.Y.Z
   ```

3. If you want to abort the release entirely, revert the
   plugin.json + CHANGELOG.md changes:

   ```bash
   git checkout .claude-plugin/plugin.json CHANGELOG.md
   rm -f vibeflow-plugin-X.Y.Z.tar.gz vibeflow-plugin-X.Y.Z.tar.gz.sha256
   ```

**sha256 sidecar doesn't match the uploaded tarball** — the tarball
on disk can be regenerated between `release.sh` finishing and
`gh release create`, which desyncs the sidecar. Common culprit: the
`sprint-4.sh [S4-G]` section in the preflight gauntlet runs
`package-plugin.sh` internally, producing a slightly different
tarball (tar + gzip bake timestamps, so consecutive runs produce
different bytes). Fix:

```bash
# Regenerate the sidecar against the CURRENT tarball on disk
shasum -a 256 vibeflow-plugin-X.Y.Z.tar.gz > vibeflow-plugin-X.Y.Z.tar.gz.sha256

# Replace the stale asset on the already-created GitHub release
gh release upload vX.Y.Z vibeflow-plugin-X.Y.Z.tar.gz.sha256 --clobber
```

Prefer to regenerate the sidecar as the LAST step before
`gh release create` to avoid the window entirely. A future ticket
(S7-05 long-term item) will make `package-plugin.sh` deterministic
via `tar --mtime=@0` + `gzip -n` so consecutive runs produce
byte-identical output.
