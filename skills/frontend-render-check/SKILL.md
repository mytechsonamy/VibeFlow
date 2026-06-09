---
name: frontend-render-check
description: Actually stands up the front-end and verifies it RENDERS and MATCHES THE DESIGN — the step that ends the "dark tunnel" where a UI ships unit-tested but never once rendered or compared to the design. Detects the web framework, boots the dev server (catching startup bugs like a broken alias on a path with spaces), serves mock/fixture data so the UI renders with content WITHOUT a backend, captures screenshots of the hero screens, surfaces them to the operator (so you SEE it, not a green checkmark), and runs a design-conformance comparison against the Figma file (design-bridge db_compare_impl) or the design-spec mockups + tokens (colors/fonts/spacing/layout). Use in TESTING for a web UI increment; pairs with visual-ai-analyzer.
disable-model-invocation: false
allowed-tools: Read Write Bash(mkdir *) Bash(jq *) Bash(ls *) Bash(cat *) Bash(npm *) Bash(npx *) Bash(pnpm *) Bash(yarn *) Bash(vite *) Bash(next *) Bash(curl *) Bash(lsof *) Bash(kill *) Bash(npx playwright *) Bash(node *) Bash(bash *ui-styling-check.sh*) mcp__design-bridge__db_fetch_design mcp__design-bridge__db_compare_impl mcp__design-bridge__db_extract_tokens
---

# Front-end Render Check

A UI can pass every unit + component test and still be **wrong** — the wrong
colors, the wrong layout, nothing like the design — because none of those tests
ever *rendered* it. This step closes that gap: it boots the real front-end,
renders it with content, **shows you the screens**, and compares them to the
design. It is the antidote to "green checkmarks, but I've never actually seen
the screen."

## Phase Contract

Runs in **TESTING**, **web UI increments only**. Read `vibeflow.config.json` →
`platform` (`web`/`all`) and the change-type classification. If the increment
isn't UI-facing on web, say "no web UI in this increment — skipping" and stop.
(Mobile crash/visual is `mobile-stability-runner`.) Outputs land in
`.vibeflow/reports/frontend-render/` + `vibeflow.config.json`/`.vibeflow/**`.

## Step 1: Locate + boot the front-end

Find the web app (don't assume `apps/web` — detect):

- Scan for a front-end package: a `package.json` with `vite` / `next` / `react-scripts`
  / `@remix-run` / `astro` / `vue` / `svelte` in deps, and an `index.html` or
  framework entry.
- Resolve the **dev command** (`npm run dev` / `vite` / `next dev`) and port.
- **Boot it** on a fixed port. **Capture startup output** — a dev server that
  fails to start (a bad alias, a path-with-spaces `%20` encode, a missing env,
  a TS error) is a **real finding**, not an environment glitch; report it and
  stop with a BLOCKED verdict naming the error. (This alone catches the class of
  bug that ships when nobody ever ran the app.)

## Step 2: Render with content — mock data, no backend needed

The UI usually needs an API. Don't require a live backend in TESTING:

- Find the data contract — the API shape from `design/design-spec.md` /
  `packages/*/src` shared types / an existing fixtures dir.
- Serve **mock/fixture** responses for the UI's endpoints (a dev middleware /
  a static `*.json` / a tiny stub server) so the screens render with realistic
  content + the key **states** (loading, empty, error, offline, gated).
- Record what was mocked in the report — a screen that only renders against a
  mock is a *rendered* screen, clearly labelled.

## Step 3: Capture the hero screens — and SHOW them

Screenshot each hero screen from `design/design-spec.md` (or, if absent, the
app's main routes), at desktop + mobile widths, including the key states:

```bash
# headless capture (Playwright); fall back to the operator opening the URL
npx playwright screenshot --viewport-size=1440,900 "http://localhost:<port>/<route>" \
  ".vibeflow/reports/frontend-render/<screen>-impl.png"
```

Write each to `.vibeflow/reports/frontend-render/<screen>-impl.png`. **Surface
them to the operator** — this is the anti-"dark-tunnel" rule: present the
screenshots (e.g. via the file-send affordance) and name the live URL
(`http://localhost:<port>/`) so the operator can open it in Chrome themselves.
Never report "rendered ✓" without producing a viewable image.

**Graceful-degrade:** no headless browser available → do NOT fake it. Leave the
dev server running, write a `▶ Next:` breadcrumb telling the operator to open
`http://localhost:<port>/` in Chrome + (optionally) drop a screenshot in, and
record `NEEDS_REVISION` (env gap, not a design failure).

## Step 4: Design conformance — implemented vs designed

This is the heart: **does the coded screen match the design?**

**Static "skinless UI" pre-check (Sprint 55).** Even before screenshots, run
`hooks/scripts/ui-styling-check.sh .` — if it returns `"skinless"` (the UI uses
className but applies no stylesheet/tokens), the design was **never
implemented**: the screen renders as bare default HTML. That's an immediate
`BLOCKED`, nameable without a browser (exactly the case where a dashboard shipped
with matching class names but zero CSS). phase-runner surfaces the same signal in
DEVELOPMENT; here it's a hard gate.

- **If a Figma file is referenced** (a `figma.com/design/…` URL in
  `design/design-spec.md` / config) — pull the design frames via
  `mcp__design-bridge__db_fetch_design` and run
  `mcp__design-bridge__db_compare_impl` (implemented screenshot vs the design
  frame): layout, spacing, color, type, component presence.
- **Else** — compare against the design-spec's own mockups (the Sprint-36
  rendered HTML mockups under `design/…/mockups/`) + `db_extract_tokens` /
  `design-tokens.json`: palette, font families/sizes, spacing scale, radius.
- Hand both images to **`visual-ai-analyzer`** (as a Skill) for the vision-level
  read (typography drift, layout regressions, a11y).

Produce a **side-by-side** so the divergence is *visible*: write
`.vibeflow/reports/frontend-render/<screen>-design.png` next to `-impl.png`, and
embed both in the report. "The implemented screen has no relation to the design"
must come out as a concrete, named list — not a vibe.

## Step 5: Report + verdict

Write `.vibeflow/reports/frontend-conformance.md`:

- Boot result (started? startup errors?).
- Per hero screen: the `-impl.png` + `-design.png` (side-by-side), the mocked
  endpoints, and a **conformance table** — per dimension (layout / palette /
  typography / spacing / components / states): match | drift | mismatch, with the
  specific difference.
- Per finding `{ finding, why, impact, confidence }`.
- **Verdict**: `PASS` (renders + conforms) / `NEEDS_REVISION` (drift, or
  env-gap with no headless browser) / `BLOCKED` (won't boot, or the
  implementation has **no meaningful relation** to the design — a real "rebuild
  the screen against the design" signal).

## When the backend is ready (live integration — not here)

This step uses **mock data on purpose** so design conformance can run in TESTING
without infra. The **front-end + real backend** integration — the UI driving a
live API end-to-end — is `uat-executor` against a staging environment in
DEPLOYMENT. Note in the report that conformance was verified against mocks and
the live front+back walk is the DEPLOYMENT/UAT step.

## Final Step: Auto-Consensus Marker (only on PASS — Sprint 43 arm-on-pass)

Write `.vibeflow/state/consensus-needed.json` (primaryArtifact
`.vibeflow/reports/frontend-conformance.md`, createdBy `frontend-render-check`)
**only if `VERDICT == "PASS"`**. On `NEEDS_REVISION`/`BLOCKED`, do **not** write
the marker — surface the screenshots + the named divergences + a `▶ Next:` (fix
the boot error / rebuild the screen against the design), and stop.

## Output

- `.vibeflow/reports/frontend-render/<screen>-impl.png` + `<screen>-design.png`
- `.vibeflow/reports/frontend-conformance.md` (side-by-side + conformance table + verdict)
