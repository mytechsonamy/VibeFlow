# Front-end testing — the UI-conditional battery

> **Stack-agnostic UI detection (Sprint 66).** The battery used to detect a web
> UI **only** by a JS framework dependency (vite/next/react/vue/svelte). A
> **server-rendered** app — FastAPI/Flask returning `HTMLResponse`,
> Jinja/Django/Rails/Razor/Thymeleaf templates, or a backend-served static SPA —
> has no such dependency, so it read as `no-ui` and the entire visual battery
> (`frontend-render-check` + `visual-ai-analyzer`) **silently skipped**; a real
> screen could ship with broken spacing / a missing glyph / no empty-state and
> nothing in the SDLC ever rendered it (found live in Clera, a FastAPI app that
> builds HTML in Python). Detection is now stack-agnostic — `vf_web_ui_kind` in
> `hooks/scripts/_lib.sh` returns `js` | `server-rendered` | `static` | `none`
> (used by `ui-styling-check.sh` + `ui-verification-debt.sh`; design-mockup /
> vendored trees excluded). A **JS SPA** boots its dev server with mocked data; a
> **server-rendered** app boots the **real** server (`uvicorn`/`flask`/`django`/
> `dotnet`/`rails`, reusing the Sprint-59 stack-agnostic boot +
> `VF_BACKEND_CMD`/`VF_BACKEND_PORT`) and screenshots the routes it serves — a
> web-UI repo with **no HTTP server entry** is itself a BLOCKED finding. Either
> way the screenshots go to `visual-ai-analyzer`, and `ui-verification-debt` now
> flags a server-rendered UI that was **never render-verified**.

When an increment touches the UI, "are the tests good?" (coverage + mutation) is
not enough — you also need "is the **UI** right?": every field matches the
design, every input is validated, every function works end-to-end and meets its
requirement. VibeFlow runs a **front-end battery** in TESTING for UI-facing
increments, on top of the default coverage + mutation gates.

## When it runs

phase-runner's TESTING walk runs the battery **only when the active increment is
UI-facing** — its change-type classification (from `brownfield-intake` /
`design-bootstrap`) is `ui` or `mixed`, or `design/design-spec.md` exists for the
cycle. A **backend / infra** increment skips it entirely (coverage + mutation
only).

## What it covers (mapped to the concerns)

| Concern | Skill | What it guarantees |
|---|---|---|
| **The UI actually renders + matches the design** | **`frontend-render-check`** (web) | boots the app, serves mock data, **captures + shows** hero-screen screenshots, compares **implemented vs designed** (Figma `db_compare_impl` / design-spec mockups + tokens) |
| Each field matches the design | `visual-ai-analyzer` (+ `design-bridge db_compare_impl` when Figma exists) | layout / typography / spacing / a11y vs `design-spec.md` (on the captured screens) |
| Data validation (numeric / alphanumeric / boundary / format) | **`input-validation-matrix`** | per field: required, type, boundary (value + length), format, type-mismatch, injection-safety, output-formatting |
| Input / output controls | `input-validation-matrix` + `e2e-test-writer` | accept/reject + the displayed/formatted value (currency precision, masking) |
| Functions work | `e2e-test-writer` (Playwright web / Detox mobile) + `regression-test-runner` | end-to-end functional flows actually run green |
| Functions meet requirements | `business-rule-validator` + `traceability-engine` | each PRD rule has a test; every UI requirement maps to a test (no untested requirement / orphan) |
| **The UI actually talks to a real backend** | **`integration-verifier`** (full-stack only) | boots the **real** back-end locally, seeds deterministic data, points the real front-end at it (not mocks), drives the `SCN-UI-*-DATA-*` data-binding scenarios — **no deploy required**. See [INTEGRATION-TESTING.md](INTEGRATION-TESTING.md) |
| End-to-end on a real environment | `uat-executor` | UAT scenarios on **deployed staging** (when a staging URL is configured) |

## Why it's a *gate*, not a side report

The validation + E2E tests are written **into the project's own test suite**, so
the existing gates enforce them automatically: they must pass
(`regression-test-runner` / `quality-gates`) and they count toward `coverage.met`.
The battery's reports (`validation-matrix.md`, `rtm.md`, the visual findings)
become **evidence** for `consensus.testing.approved`. So a UI increment can't
reach a GO without the front-end battery being green — that's the guarantee.

## The validation matrix in detail

`input-validation-matrix` builds, **for every input field**, cases across every
applicable category:

- **Required / presence** — empty / whitespace / missing → the field's message shows.
- **Type** — alpha in a numeric field, decimals in an integer, letters in a date → rejected.
- **Boundary** — `min`, `min-ε`, `max`, `max+ε`, zero, negative-where-disallowed; `minLength`/`maxLength` ± 1.
- **Format** — valid vs malformed (email, IBAN checksum, phone shape, currency decimals/separator).
- **Enum / allowed set** — each allowed value accepted; out-of-set rejected.
- **Injection / safety** — `<script>…`, `' OR 1=1`, unicode/RTL, oversized → escaped or rejected, never executed/stored raw (weighted up for `financial` / `healthcare`).
- **Output control** — the accepted value is formatted/masked as the spec says.
- **Cross-field** — "end ≥ start", "amount ≤ balance", "confirm == value".

A rule with **no wired validation** is reported as a **defect** (not merely a test
gap), and an executed/stored injection case is a hard **BLOCKED** for regulated
domains.

## Render check — ending the "dark tunnel" (Sprint 53)

Unit + component tests can all be green while the screen is **nothing like the
design** — because none of them ever *rendered* it. `frontend-render-check` is
the step that actually:

1. **boots** the front-end (and a dev server that won't start — a broken alias, a
   path-with-spaces `%20`, a missing env — is itself a finding, not an
   environment glitch);
2. serves **mock data** so the screens render with content **without a backend**;
3. **captures and surfaces** screenshots of the hero screens — you *see* them
   (and the live `http://localhost:<port>/` to open in Chrome), never a bare
   "rendered ✓";
4. compares **implemented vs designed** — the Figma frames (`db_compare_impl`)
   or the design-spec mockups + tokens — and reports the divergence as a
   concrete, named list (so "the screen has no relation to the design" becomes
   actionable, not a vibe).

It verdicts `BLOCKED` when the app won't boot **or** the implementation has no
meaningful relation to the design (a real "rebuild this screen against the
design" signal).

### Three integration rungs — mock, local-real, deployed

`frontend-render-check` uses **mock data on purpose** so design conformance can
run without infra. But "renders on mocks" is **not** "talks to a backend" — and
the live-backend check used to be `uat-executor` *only*, which needs a **deployed
staging** env most projects never stand up (a back-end with no HTTP server can't
reach staging at all). So a mock-front-end over a *claimed* backend slipped
straight to GO. Sprint 58 adds the missing middle rung:

1. **`frontend-render-check`** — renders on **mocks** → it *looks* right. (TESTING)
2. **`integration-verifier`** — real back-end booted **locally** + seeded test
   data + the real front-end pointed at it → it *talks* right, **no deploy**.
   Full-stack increments only. (TESTING) — see
   [INTEGRATION-TESTING.md](INTEGRATION-TESTING.md).
3. **`uat-executor`** — the **deployed staging** live front+back walk with the
   real backend + human steps. (DEPLOYMENT, when a staging URL exists)

A *claimed* backend is not a *verified* backend; rung 2 is where that claim is
exercised before a full-stack increment can reach GO.

## A/B and experiments

A/B testing is a **production experiment** (two variants measured live), not a
pre-release gate — it lives with the `observability` MCP (metrics/conversion),
not this battery. The battery guarantees both variants are *correct and
validated* before they ship; choosing the winner is a runtime measurement.

## Running it

It's part of the one-command walk:

```
/vibeflow:phase-runner        # TESTING: coverage + mutation + (UI) the battery
```

Or invoke a lane directly, e.g. `/vibeflow:input-validation-matrix` or
`/vibeflow:visual-ai-analyzer`.

## Render-as-you-build in DEVELOPMENT (Sprint 67)

The full battery is a TESTING gate — but waiting until TESTING to first *render* a
screen means a whole increment of UI can be built before anyone sees it. So
`frontend-render-check` now also runs in **DEVELOPMENT** (driven by phase-runner
when the increment is UI-facing), scoped to the **screens the increment changed**:
each new screen is booted, screenshotted, **shown**, and visually checked **while
it's written**.

- It's a **proportionate gate**: a `BLOCKED` verdict (won't render / skinless / no
  relation to the design) **stops** with a fix breadcrumb; cosmetic drift is
  surfaced as findings and does not block iteration.
- It **never arms the consensus marker** in DEVELOPMENT (arm-on-pass is a TESTING
  act) — so it can't block the very iteration that fixes the screen. DEVELOPMENT
  still gates through `quality.gates` + `code.reviewed`.
- The full UI-conditional battery (+ visual-ai-analyzer + input-validation +
  integration-verifier) and the hard arm-on-pass gate still run in TESTING. This
  just moves the *first eyes-on render* to where the screen is built — so visual
  defects are caught per-screen, not discovered manually after the fact.
