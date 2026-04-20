# Sprint 12: v2.0.1 / v2.0.2 ✅ COMPLETE — Bundled MCP servers + manifest hotfix

## Sprint Goal

Sprint 12 is a distribution fix on top of v2.0.0. The v2.0.0 install
was reported as "hangs on `Installing plugin…`" by users whose
marketplace source was a local path with populated `node_modules`
(~500 MB across the five MCP servers). Claude Code's
`marketplace: directory` type does a naive recursive copy, so
`node_modules` was being duplicated into
`~/.claude/plugins/cache/temp_local_*` at install time.

Sprint 12 eliminates that by bundling each MCP server into a
self-contained `dist/bundle.js` and routing `.mcp.json` through the
bundle so `node_modules` is no longer a runtime requirement.
End-users migrate to the `github:mytechsonamy/VibeFlow` marketplace
source (shallow `git clone`, no untracked files). A follow-on
hotfix (v2.0.2) corrected the `plugin.json` `repository` / `bugs`
fields — Claude Code's plugin loader validates both as strings, not
the npm-style `{ type, url }` objects that pre-v2.0.2 manifests used.

## Prerequisites

- Sprint 11 ✅ COMPLETE (v2.0.0 shipped 2026-04-20)
- 1402 baseline checks across 12 test layers green

## Completion Criteria

- [x] Each MCP server builds a bundled `dist/bundle.js` (~620–690 KB)
      via `tsc && esbuild dist/index.js --bundle --platform=node
      --format=esm` with a `createRequire` banner
- [x] `.mcp.json` points every entry at `dist/bundle.js`; the tsc
      multi-file output stays for integration tests that import from
      `dist/state/*.js`
- [x] `docs/GETTING-STARTED.md` leads with
      `claude plugin marketplace add github:mytechsonamy/VibeFlow`
- [x] `plugin.json` `repository` + `bugs` are plain strings; the
      integration test `sprint-4.sh` asserts string-type
- [x] v2.0.1 + v2.0.2 tags + GitHub releases published
- [x] Install completes in seconds for end users on both marketplace
      flows (verified against a real FlowBridge_TR brownfield project)

---

## Ticket Breakdown (A–C + hotfix)

### S12-A: Bundle all MCP servers with esbuild
**Commit:** ~`4a9a…` · **Artifacts:** 5 × `dist/bundle.js`

Build script per MCP:
```
tsc && esbuild dist/index.js --bundle --platform=node --format=esm
  --outfile=dist/bundle.js
  --banner:js="import { createRequire } from 'module';
    const require = createRequire(import.meta.url);"
```
The banner shims CommonJS `require()` for deps that still use it
(e.g. `proper-lockfile` pulls in `graceful-fs`).

`esbuild` added to each MCP's `devDependencies`; no other dep
changes. Integration tests that still import from `dist/index.js` /
`dist/state/*.js` continue to work — the bundle is an *additional*
artifact, not a replacement.

### S12-B: Point .mcp.json at bundles + verify install speed
**Commit:** bundled with 12-A · **Artifacts:** `.mcp.json` updated

Five MCP entries now reference `dist/bundle.js`. `build-all.sh` runs
the bundle step for every server; `package-plugin.sh` tarball
includes both bundle and tsc output. Standalone boot test for each
bundle in an empty tmp dir confirms `node_modules` is no longer
required at runtime.

### S12-C: GitHub-source marketplace + v2.0.1 release
**Commit:** release prep · **Artifacts:** `docs/GETTING-STARTED.md`,
`CHANGELOG.md [2.0.1]`, `release-notes/2.0.1.md`, v2.0.1 tag

- `docs/GETTING-STARTED.md` rewritten: Option A is
  `claude plugin marketplace add github:mytechsonamy/VibeFlow`
  (shallow clone, no `node_modules` in the transfer). Option B is
  `claude --plugin-dir <path>` for local iteration. Explicit warning
  against `claude plugin marketplace add <local-path>` because the
  `source: directory` type still does the recursive copy.
- Prereqs trimmed: `sqlite3` + `PostgreSQL` entries removed (Sprint
  11-E retired both backends); only `jq` + `Node.js 18+` + `git`
  remain.
- `/vibeflow:init` field list trimmed from four to three (the
  Sprint 11 `mode` removal was still documented as a prompt).
- Solo-vs-team section replaced with "State layout" description of
  the `.vibeflow/state/` directory tree.

### v2.0.2 hotfix: manifest schema
**Commit:** hotfix · **Artifacts:** `plugin.json`, `sprint-4.sh`,
`release-notes/2.0.2.md`, v2.0.2 tag

`claude plugin install vibeflow@vibeflow` was failing at the
manifest validator with:
```
✘ Validation errors: repository: Invalid input: expected string,
received object
```
Root cause: `.claude-plugin/plugin.json` carried `repository` and
`bugs` as npm-style `{ type, url }` objects. Claude Code's plugin
loader (per `code.claude.com/docs/en/plugins-reference.md`)
validates these as plain URL strings.

Fix:
- `plugin.json`: `repository` + `bugs` flattened to strings. While
  there, corrected the `homepage` / `repository` URLs from the stale
  `mustiyildirim/vibeflow` slug to the actual `mytechsonamy/VibeFlow`
  repo.
- `tests/integration/sprint-4.sh`: schema assertions rewritten to
  match the loader contract (`jq -e '.repository | type == "string"
  and startswith("https://github.com/")'`).
- `release-notes/2.0.2.md` + CHANGELOG `[2.0.2]` entry with the
  upgrade path (`claude plugin marketplace update vibeflow`).

## Shipped

- **Plugin:** `2.0.0 → 2.0.1 → 2.0.2`
- **@vibeflow/sdlc-engine:** `1.0.0 → 1.0.1`
- **GitHub releases:**
  - https://github.com/mytechsonamy/VibeFlow/releases/tag/v2.0.1
  - https://github.com/mytechsonamy/VibeFlow/releases/tag/v2.0.2

## Install Flow (end-user, post-v2.0.2)

```bash
claude plugin marketplace add mytechsonamy/VibeFlow
claude plugin install vibeflow@vibeflow
```

Completes in seconds. Plugin footprint after install: ~3.2 MB (5
bundles + skills + hooks + docs).
