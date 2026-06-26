---
name: frontend-render-check
description: Actually stands up the front-end and verifies it RENDERS and MATCHES THE DESIGN — the step that ends the "dark tunnel" where a UI ships unit-tested but never once rendered or compared to the design. Detects the web framework, boots the dev server (catching startup bugs like a broken alias on a path with spaces), serves mock/fixture data so the UI renders with content WITHOUT a backend, captures screenshots of the hero screens, surfaces them to the operator (so you SEE it, not a green checkmark), and runs a design-conformance comparison against the Figma file (design-bridge db_compare_impl) or the design-spec mockups + tokens (colors/fonts/spacing/layout). Stack-agnostic (Sprint 66): a JS SPA boots its dev server with mocked data; a server-rendered app (FastAPI/Flask/Django HTMLResponse·templates, Rails, Razor, a backend-served static SPA — the Clera shape) boots the REAL server and screenshots its routes. Use in TESTING for a web UI increment; pairs with visual-ai-analyzer.
disable-model-invocation: false
allowed-tools: AskUserQuestion Read Write Bash(mkdir *) Bash(jq *) Bash(ls *) Bash(cat *) Bash(npm *) Bash(npx *) Bash(pnpm *) Bash(yarn *) Bash(vite *) Bash(next *) Bash(curl *) Bash(lsof *) Bash(kill *) Bash(npx playwright *) Bash(node *) Bash(python *) Bash(python3 *) Bash(uvicorn *) Bash(gunicorn *) Bash(flask *) Bash(dotnet *) Bash(go *) Bash(mvn *) Bash(gradle *) Bash(bash *ui-styling-check.sh*) mcp__design-bridge__db_fetch_design mcp__design-bridge__db_compare_impl mcp__design-bridge__db_extract_tokens
---

# Front-end Render Check

A UI can pass every unit + component test and still be **wrong** — the wrong
colors, the wrong layout, nothing like the design — because none of those tests
ever *rendered* it. This step closes that gap: it boots the real front-end,
renders it with content, **shows you the screens**, and compares them to the
design. It is the antidote to "green checkmarks, but I've never actually seen
the screen."

## Phase Contract

Runs in **DEVELOPMENT** (render-as-you-build) **and TESTING**, **web UI increments
only** — **stack-agnostic** (Sprint 66). Read `vibeflow.config.json` → `platform`
(`web`/`all`). Classify the UI with the read-only detector (don't assume a JS
framework — a server-rendered app is still a web UI to render):

**DEVELOPMENT mode (render-as-you-build, Sprint 67).** When invoked during
DEVELOPMENT (by phase-runner, on a UI-facing increment), scope the render to the
**screens this increment built/changed** (resolve from the diff + `design-spec`),
render them with mock data, capture + **surface** the screenshots, and run the
visual-conformance pass — so every new screen/function is SEEN as it's built
instead of deferred to TESTING. In DEVELOPMENT this is a **proportionate gate**:
a `BLOCKED` verdict (won't render / skinless / no relation to the design) **stops**
with a fix breadcrumb; cosmetic drift is surfaced as findings and does **not**
block iteration. **Do NOT arm the consensus marker in DEVELOPMENT** — arm-on-pass
(the Final Step) is a TESTING-only act; DEVELOPMENT gates through `quality.gates`
+ `code.reviewed` as before. The full battery (+visual-ai-analyzer, input
validation, integration-verifier) still runs in TESTING.

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/hooks/scripts/ui-styling-check.sh" .   # or: vf_web_ui_kind
```

- `no-ui` → say "no web UI in this increment — skipping" and stop.
- a **JS SPA** (vite/next/react/vue/svelte) → Step 1 (JS) below.
- a **server-rendered** app (FastAPI/Flask/Django HTMLResponse·templates, Rails
  ERB, .NET Razor, a backend-served static SPA — the Clera shape) → **Step 1-SR**.

(Mobile crash/visual is `mobile-stability-runner`.) Outputs land in
`.vibeflow/reports/frontend-render/` + `vibeflow.config.json`/`.vibeflow/**`.

## Step 1: Locate + boot the front-end (JS SPA)

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

## Step 1-SR: Boot the real server (server-rendered apps, Sprint 66)

A server-rendered UI **is** its backend — the HTML is produced by the server
(FastAPI `HTMLResponse`/Jinja, Flask/Django templates, Rails, Razor), so there's
no JS dev server to boot and no backend to mock; you boot the **real app** and
screenshot the routes it serves. Reuse `integration-verifier`'s Sprint-59
stack-agnostic boot:

- Resolve the run command manifest-first: Python → `uvicorn <app>:app` /
  `gunicorn` / `flask run` / `python manage.py runserver`; .NET → `dotnet run`;
  Rails → `bin/rails server`; Java → `./mvnw spring-boot:run`/`./gradlew bootRun`.
  Honor `VF_BACKEND_CMD` / `VF_BACKEND_PORT` overrides.
- A web-UI repo that has **no HTTP server entry at all** (a library that only
  *builds* HTML strings with no way to serve them) is itself a **BLOCKED** finding
  — name it, don't fake a render.
- Seed deterministic data first if the screens need it (`test-data-manager` / a
  test DB) so the rendered screens show realistic content + the key states.
- Then go to Step 3 and screenshot the served routes exactly as for a JS app.

## Step 2: Render with content — mock data, no backend needed (JS SPA only)

A JS SPA usually needs an API. Don't require a live backend in TESTING:

- Find the data contract — the API shape from `design/design-spec.md` /
  `packages/*/src` shared types / an existing fixtures dir.
- Serve **mock/fixture** responses for the UI's endpoints (a dev middleware /
  a static `*.json` / a tiny stub server) so the screens render with realistic
  content + the key **states** (loading, empty, error, offline, gated).
- Record what was mocked in the report — a screen that only renders against a
  mock is a *rendered* screen, clearly labelled.
- (Server-rendered apps skip this — they render against the real server booted in
  Step 1-SR, optionally with seeded test data.)

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

## Live integration is a separate rung — not here

This step uses **mock data on purpose** so design conformance can run without
infra. The **front-end + real backend** integration is two further rungs:
`integration-verifier` (Sprint 58) runs the real front↔back **locally** with
seeded test data **in TESTING** (no deploy needed — it's a gate, not deferred),
and `uat-executor` is the **deployed staging** walk in DEPLOYMENT. Note in the
report that conformance here was verified against mocks, and that
`integration-verifier` is what proves the UI actually talks to a real backend.

## Final Step: Auto-Consensus Marker (TESTING + only on PASS — Sprint 43 arm-on-pass)

**TESTING only.** Write `.vibeflow/state/consensus-needed.json` (primaryArtifact
`.vibeflow/reports/frontend-conformance.md`, createdBy `frontend-render-check`)
**only if the current phase is TESTING AND `VERDICT == "PASS"`**. On
`NEEDS_REVISION`/`BLOCKED`, do **not** write the marker — surface the screenshots
+ the named divergences + a `▶ Next:` (fix the boot error / rebuild the screen
against the design), and stop. **In DEVELOPMENT (render-as-you-build) never arm
the marker** regardless of verdict — DEVELOPMENT gates through `quality.gates` +
`code.reviewed`, and arming the consensus gate mid-DEVELOPMENT would block the
very iteration that fixes the screen (the Sprint-43 lesson).

## Output

- `.vibeflow/reports/frontend-render/<screen>-impl.png` + `<screen>-design.png`
- `.vibeflow/reports/frontend-conformance.md` (side-by-side + conformance table + verdict)

## Breadcrumb as a tappable card (Sprint 64)

**Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`).** When you
finish with a `▶ Next:` breadcrumb naming a single next command, also present it
as a tappable **`AskUserQuestion`** so the operator can advance with one tap from
a phone: **Run `<that command>` now (Recommended)** / **Not yet**. The built-in
"Other" lets them type a different command. Keep the literal `▶ Next:` line too
(it is the textual fallback). Skip the card only when the breadcrumb names no
runnable command (e.g. a plain "add tests" advisory).
