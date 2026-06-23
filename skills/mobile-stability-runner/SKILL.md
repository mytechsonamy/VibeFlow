---
name: mobile-stability-runner
description: Mobile crash & stability testing for a UI increment on iOS/Android. Expo-aware — auto-detects Expo (managed/bare) and picks the runner (Expo → Maestro on Expo Go / dev-client, bare React Native → Detox). Runs a crash-focused battery beyond functional E2E — cold-start smoke, background/foreground, low-memory, deep links, permission denial, network loss mid-flow, rotation, rapid navigation — and detects native crashes / JS redbox / ANR, surfacing anything captured by a configured crash reporter (Sentry / Crashlytics / Expo). Writes mobile-stability-report.md. Graceful-degrades to a local-run breadcrumb when no simulator/device is available. Use in TESTING when the platform is mobile.
disable-model-invocation: false
allowed-tools: AskUserQuestion Read Write Bash(mkdir *) Bash(jq *) Bash(ls *) Bash(npx *) Bash(npm *) Bash(yarn *) Bash(pnpm *) Bash(expo *) Bash(eas *) Bash(maestro *) Bash(detox *) Bash(xcrun *) Bash(adb *) Bash(curl *)
---

# Mobile Stability Runner

Functional E2E asks "does the flow work?"; this asks "**does the app crash?**" —
the failure mode that actually bites mobile, and especially Expo, where the
crash is usually *not* in the happy path but at cold start (a native-module /
config mismatch) or on a lifecycle event. It's the mobile sibling of the
front-end battery.

## Phase Contract

Runs in **TESTING**, **mobile only**. Read `vibeflow.config.json` → `platform`.
If it is not `ios` / `android` / `all`, emit "not a mobile platform — skipping"
and stop. Writes test/flow files into the project + `.vibeflow/reports/mobile-stability-report.md`.

## Step 1: Detect the stack + runner (Expo-aware)

Fingerprint the mobile project — never assume:

- **Expo vs bare RN** — Expo if `app.json` / `app.config.{js,ts}` exists **and**
  `expo` is a dependency. Note managed vs bare (`expo prebuild` / an `ios`/`android`
  dir present).
- **Runner (auto-detect):**
  - **Expo → Maestro** (works against Expo Go or a dev-client build; the smoothest
    path for managed Expo). Use a **dev-client** / **EAS Build** when the increment
    uses native modules Expo Go can't host.
  - **bare React Native → Detox** (existing `e2e-test-writer` infra).
  - Record the choice + why in the report.
- **Crash reporter** — detect Sentry (`@sentry/react-native`), Crashlytics
  (`@react-native-firebase/crashlytics`), or Expo error reporting; if present,
  you'll pull crashes captured during the run.
- **Device / simulator availability** — `xcrun simctl list devices booted`
  (iOS) / `adb devices` (Android) / EAS. **If none is available**, do NOT fail
  hard: write the report with `runner: <chosen>`, `environment: unavailable`,
  and a `▶ Next:` breadcrumb for the operator to run locally
  (`maestro test …` / `eas build --profile development` / `npx expo start`),
  then stop with verdict `NEEDS_REVISION` (not BLOCKED — it's an env gap, not a
  crash).

## Step 2: The crash-focused battery

Beyond the functional scenarios (those belong to `e2e-test-writer`), exercise the
**crash-prone** surface. Generate a flow per item in the runner's format
(Maestro `.yaml` flows / Detox specs):

- **Cold-start smoke** — launch the app fresh; assert it reaches the first screen
  with **no native crash and no redbox**. (Expo's #1 crash: a native module /
  `app.config` / env mismatch that only shows at startup.)
- **Background → foreground** — send to background, wait, resume; no crash, state intact.
- **Low memory** — simulate memory pressure (`xcrun simctl … / adb shell`), resume; no crash.
- **Deep links** — open each registered scheme/universal link cold and warm; no crash, correct route.
- **Permission denial** — deny camera/location/notifications and proceed; graceful, no crash.
- **Network loss mid-flow** — drop connectivity during a key request; no crash, error surfaced.
- **Rotation + rapid navigation** — rotate, push/pop fast; no crash, no leaked state.
- **JS unhandled rejection / fatal** — assert the global handler catches it (no silent white screen).

Weight cold-start + permission + network higher for `financial` (a crash on a
payment/auth screen is a hard fail).

## Step 3: Run + collect crashes

Run the flows via the chosen runner. For each, detect:

- **Native crash** — the app process exits / a `.crash` / tombstone appears
  (`xcrun simctl … diagnose` / `adb logcat *:F`).
- **JS fatal / redbox** — a fatal exception or red-box error.
- **ANR** (Android) — main-thread block.

Pull any crashes the configured reporter captured during the window (Sentry /
Crashlytics / Expo). Attach the stack + the minimal repro (the flow + step).

## Step 4: Report

Write `.vibeflow/reports/mobile-stability-report.md`:

- Runner + environment + Expo-mode used.
- A **scenario × outcome** table: passed / crashed (with crash type + stack) /
  not-applicable (reason) / skipped-env-unavailable.
- Per finding `{ finding, why, impact, confidence }` + a repro.
- **Verdict**: `PASS` (every applicable scenario ran with no crash) /
  `NEEDS_REVISION` (env unavailable, or a non-P0 soft issue) / `BLOCKED` (any
  crash on cold-start or a P0 flow — non-negotiable).

## Final Step: Auto-Consensus Marker (only on PASS — Sprint 43 arm-on-pass)

Write `.vibeflow/state/consensus-needed.json` (primaryArtifact
`.vibeflow/reports/mobile-stability-report.md`, createdBy
`mobile-stability-runner`) **only if `VERDICT == "PASS"`**. On
`NEEDS_REVISION`/`BLOCKED`, do **not** write the marker — emit the crash/env
advisory + a `▶ Next:` (fix the crash, or run locally with the named command),
and stop, so `consensus-gate` doesn't block the fix.

## Output

- runner flow files (Maestro `.yaml` / Detox specs) in the project
- `.vibeflow/reports/mobile-stability-report.md` (scenario × crash outcome + verdict)

## Breadcrumb as a tappable card (Sprint 64)

**Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`).** When you
finish with a `▶ Next:` breadcrumb naming a single next command, also present it
as a tappable **`AskUserQuestion`** so the operator can advance with one tap from
a phone: **Run `<that command>` now (Recommended)** / **Not yet**. The built-in
"Other" lets them type a different command. Keep the literal `▶ Next:` line too
(it is the textual fallback). Skip the card only when the breadcrumb names no
runnable command (e.g. a plain "add tests" advisory).
