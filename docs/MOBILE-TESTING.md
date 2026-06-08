# Mobile testing — crash & stability (Expo-aware)

Functional E2E (`e2e-test-writer`) tells you the *flows* work. On mobile — and on
Expo especially — that's not where it breaks: the app crashes at **cold start**
(a native-module / `app.config` / env mismatch), or on a lifecycle event
(backgrounding, low memory, a denied permission, a dropped request). VibeFlow
adds a dedicated crash/stability lane for that.

## What runs, and when

`mobile-stability-runner` runs in **TESTING**, **only when the platform is
mobile** (`vibeflow.config.json.platform` is `ios` / `android` / `all`). The
phase-runner TESTING walk runs it alongside the front-end battery for a mobile
UI increment. A non-mobile platform skips it entirely.

## Expo-aware runner selection

It fingerprints the project and picks the runner automatically:

| Project | Runner | Notes |
|---|---|---|
| **Expo** (`app.config`/`app.json` + `expo` dep) | **Maestro** | runs against Expo Go or a **dev-client** build; a native-module increment needs a dev-client / `eas build --profile development` |
| **bare React Native** | **Detox** | the existing `e2e-test-writer` infra |

It also detects a crash reporter (Sentry / Crashlytics / Expo error reporting)
and surfaces anything it captured during the run.

## The crash-focused battery

Beyond the happy-path flows, it exercises the surface that actually crashes:

- **Cold-start smoke** — fresh launch reaches the first screen, no native crash / redbox. (Expo's #1 crash.)
- **Background → foreground** — suspend/resume, no crash, state intact.
- **Low memory** — memory pressure then resume, no crash.
- **Deep links** — every scheme/universal link, cold and warm, correct route, no crash.
- **Permission denial** — deny camera/location/notifications, proceed gracefully.
- **Network loss mid-flow** — drop connectivity during a key request, error surfaced not crashed.
- **Rotation + rapid navigation** — rotate, push/pop fast, no crash / leaked state.
- **JS unhandled rejection / fatal** — the global handler catches it (no silent white screen).

Detection: native crash (process exit / tombstone via `xcrun simctl diagnose` /
`adb logcat *:F`), JS fatal / redbox, ANR. Cold-start + permission + network are
weighted higher for `financial`.

## Verdict + graceful degrade

- **PASS** — every applicable scenario ran with no crash → arms consensus.
- **BLOCKED** — a crash on cold-start or a P0 flow (non-negotiable).
- **NEEDS_REVISION** — **no simulator/device/EAS available**: it does **not**
  fail hard. It records the environment gap and breadcrumbs the local command
  (`maestro test …` / `eas build --profile development` / `npx expo start`) for
  you to run on your own machine, then stops. (An env gap is not a crash.)

So in CI without a simulator you get a clear "run this locally" instead of a
false failure; on a machine with a booted simulator it's a real gate.

## Running it

Part of the one-command walk on a mobile increment:

```
/vibeflow:phase-runner        # TESTING: …front-end battery… + mobile-stability-runner
```

Or directly: `/vibeflow:mobile-stability-runner`.

## Scope note

This is **pre-release crash hunting**, not production crash monitoring — that
stays with your crash reporter + the `observability` MCP. The two complement:
this catches the crash before ship; the reporter catches the long tail after.
