---
name: e2e-test-writer
description: Generates end-to-end tests from scenario-set.md. Web target → Playwright; mobile target → Detox. Every test imports a Page Object (never touches raw selectors), uses a named auth strategy, waits on observable conditions (never sleeps), and preserves scenario ids as trace anchors. Gate contract — zero raw selectors in the test body, zero sleep-based waits, zero xpath selectors. PIPELINE-3 step 2.
allowed-tools: Read Grep Glob Write
context: fork
agent: Explore
---

# E2E Test Writer

An L2 Truth-Execution skill. Its job is to turn scenarios into
**runnable, non-flaky end-to-end tests**. The skill's main enemy is
not "writing more tests" — it's writing tests that silently lie: pass
on your machine, fail in CI, and waste hours to triage. The three
rules below are non-negotiable because each one is a common root
cause of e2e flake.

## When You're Invoked

- During PIPELINE-3 step 2, after `test-strategy-planner` has
  produced `scenario-set.md` and the target platform is declared in
  `vibeflow.config.json`.
- On demand as `/vibeflow:e2e-test-writer <scenario-glob>`.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| `scenario-set.md` | yes | Output of `test-strategy-planner`. Only scenarios tagged for the declared platform become candidates. |
| Platform | yes | `web` / `ios` / `android`. Drives which `platform-recipes.md` section loads (Playwright for `web`, Detox for `ios`/`android`). |
| Target location | yes | `web` → base URL; `ios`/`android` → bundle identifier. Never hardcoded — read from arg or from `vibeflow.config.json.targetLocations`. |
| Auth strategy catalog | derived | `references/pom-patterns.md` defines the 4 named strategies. The scenario names the one it needs. |
| Existing Page Objects | scanned | Imported when they match the scenario's target screen. Hand-written POMs are never rewritten — this skill only reads them. |
| `repo-fingerprint.json` | optional | Used to confirm the project's actual e2e runner matches the platform's expected tool. |

**Hard preconditions** — refuse with a single blocks-merge finding
rather than shipping flaky tests:

1. At least one scenario must match the declared platform. A glob
   that returns zero matches blocks with remediation "no scenarios
   match platform <p>; extend scenario-set.md first".
2. The target location must be valid: web URL must parse as a URL;
   bundle id must match `^[a-zA-Z][\w.-]*$`. Tests pinned at
   `localhost` without an explicit port block — localhost without a
   port is the #1 cause of "works on my laptop" CI failures.
3. Every scenario that maps to a test must declare an auth
   strategy. Scenarios with no auth context block — the skill
   refuses to guess.

## Algorithm

### Step 1 — Load the recipes
Read `./references/platform-recipes.md` and pick the section matching
the declared platform:

- `web` → Playwright
- `ios` → Detox (iOS runner)
- `android` → Detox (Android runner)

Record the chosen runner + the exact import block the generated file
must use. Deviating from the recipe is forbidden — if a real project
needs a different runner, add a new section to `platform-recipes.md`
first.

### Step 2 — Filter scenarios
Walk `scenario-set.md`. Keep a scenario when:

- `platform` field includes the current platform (or equals `all`)
- `coverage` field is `e2e` or `gap` (other coverage tiers are owned
  by `component-test-writer` / `contract-test-writer`)
- `status` is not `deferred`

Every surviving scenario becomes a candidate `SpecCase`:

```ts
interface SpecCase {
  scenarioId: string;       // SC-xxx
  title: string;            // human-readable
  targetScreen: string;     // named screen / route / deep link
  authStrategy: "anonymous" | "stored-session" | "token-injection" | "ui-login";
  preconditions: readonly string[];
  steps: readonly string[];
  expected: string;         // the binary outcome to assert
  priority: "P0" | "P1" | "P2" | "P3";
}
```

If a scenario is ambiguous (no target screen, no expected outcome),
mark it `pending: "awaiting scenario refinement"` and emit it as
`test.skip(...)` — never synthesize the missing pieces.

### Step 3 — Resolve Page Objects
For each scenario's `targetScreen`, look up an existing POM under
`tests/e2e/pages/<Screen>Page.ts` (or the project's equivalent path
from `repo-fingerprint.json`). If found → import and reuse. If
missing → emit a minimal skeleton using the template from
`references/pom-patterns.md` and record the emission in the run
report. Never invent selectors that don't exist in the POM.

Tests that reach raw selectors (`page.click('#login')`) are
**rejected** at Step 6 below. Every DOM / UI interaction must flow
through a POM method.

### Step 4 — Select auth strategy
For every `SpecCase`, look up its `authStrategy` in the auth catalog
(`references/pom-patterns.md` → "Auth Strategy Catalog"). Every
strategy has:

- a setup hook (beforeAll / beforeEach / none)
- a teardown hook (afterAll / afterEach / none)
- a fixture-injection function name (or "—" for anonymous)
- platform applicability (some strategies don't work on mobile)

If the scenario's strategy is not applicable to the declared
platform, block with remediation "scenario SC-xxx uses a web-only
auth strategy on a mobile target". No silent fallbacks — a wrong
auth strategy is how tests quietly start authenticating as the
wrong user.

### Step 5 — Waiting contract
Every generated spec uses **observable waits only**. The following
are forbidden at generation time:

- `await page.waitForTimeout(<ms>)` / `await sleep(<ms>)` / any
  fixed-duration sleep. These are timing races disguised as tests.
- Polling loops that check `while (!x) ...` without a bound.
- "Generous" waits ("wait 10 seconds just in case"). If the real
  operation takes <2s, a 10s wait is noise; if it takes >10s, the
  wait is wrong.

Allowed patterns:

- `await expect(pom.readyHeading).toBeVisible()` — Playwright web
- `await pom.waitForReady()` — every POM exposes a named wait
- `await waitFor(element, { timeout })` — Detox mobile
- Network-idle only when the scenario explicitly asserts it

If a scenario's steps cannot be expressed without a fixed sleep,
block and point at the scenario for refinement.

### Step 6 — Selector stability contract
Every selector referenced by the emitted POM (or the test body, in
the rare cases a test needs its own) must come from this priority:

1. `data-testid` (preferred — stable across design refactors)
2. ARIA `role` + accessible name (e.g. `getByRole('button', { name: 'Sign in' })`)
3. Visible text match (e.g. `getByText('Welcome back')`)
4. **Nothing else.** CSS class selectors are banned (refactors break
   them silently); xpath is banned outright (unreadable + brittle).

If an existing POM uses CSS/xpath, the skill emits a WARNING in the
run report and links the POM line; it does NOT rewrite the POM.
Rewriting a human-owned file is out of scope.

### Step 7 — Emit the test file
Target path convention:

- Web: `tests/e2e/<feature>.spec.ts`
- Mobile: `e2e/<feature>.e2e.ts` (Detox's conventional layout)

Every emitted file starts with the standard banner:

```ts
// @generated-by vibeflow:e2e-test-writer
// Regenerate with: /vibeflow:e2e-test-writer <scenario glob>
// Do NOT edit the @generated regions by hand — they will be overwritten.
```

Regions between `// @generated-start` and `// @generated-end` are
skill-owned; anything outside is human-owned and preserved verbatim
on re-run. Same regeneration safety contract as
`component-test-writer` / `business-rule-validator`.

Every `test(...)` title starts with the scenario id, and every body
ends with a `trace: scenarios/SC-xxx` comment so
`traceability-engine` can wire test → scenario → PRD.

## Output Contract

### `tests/e2e/<feature>.spec.ts` (Playwright example)
```ts
// @generated-by vibeflow:e2e-test-writer
// @generated-start
import { test, expect } from "@playwright/test";
import { LoginPage } from "./pages/LoginPage";
import { DashboardPage } from "./pages/DashboardPage";

test.describe("SC-112: user sees dashboard after login", () => {
  test.use({ storageState: "tests/e2e/fixtures/authed.json" }); // stored-session auth

  test("SC-112: dashboard welcome headline appears", async ({ page }) => {
    // Arrange
    const dashboard = new DashboardPage(page);

    // Act
    await dashboard.goto();

    // Assert
    await expect(dashboard.welcomeHeading).toBeVisible();

    // trace: scenarios/SC-112 — "user sees dashboard after login"
    // why: guards PRD §2.4 (authed landing page)
  });
});
// @generated-end
```

### `.vibeflow/reports/e2e-test-writer.md`

```markdown
# E2E Test Writer — <ISO timestamp>

## Target
- Platform: <web|ios|android>
- Runner: <playwright|detox>
- Base URL / bundle id: <target>

## Scenarios consumed
- SC-112 / P0 / stored-session / → tests/e2e/dashboard.spec.ts
- SC-113 / P1 / token-injection / → tests/e2e/settings.spec.ts
- SC-114 / — / skipped: no auth strategy declared (blocker)

## Page Objects
- Reused: DashboardPage, LoginPage
- Emitted (new skeleton): SettingsPage — manual implementation required

## Warnings
- tests/e2e/pages/LoginPage.ts:42 uses a CSS class selector (`.btn-primary`) — not rewritten, flagged for human review
```

## Gate Contract
**Zero raw selectors in the test body, zero sleep-based waits, zero
xpath selectors.** Those are the three regressions that reliably
re-introduce flake. Any generated file that would violate them is
rejected at Step 6 and the offending scenario is reported; no
silent degradation.

Additional blockers:
- `criticalScenariosWithoutTests == 0` (every P0 scenario tagged
  `e2e` must produce a test — `test.skip` doesn't count).
- `ambiguousScenarios == 0` — scenarios missing target/expected
  cannot be guessed.

## Non-Goals
- Does NOT generate Page Objects from scratch. The skeleton for new
  POMs is a stub with a comment telling the human to fill in the
  selectors.
- Does NOT rewrite existing POMs. Existing code is read-only.
- Does NOT run the generated tests. Wire them into CI yourself.
- Does NOT infer the auth strategy. Scenarios must declare it.

## Downstream Dependencies
- `traceability-engine` — consumes `trace:` comments to link
  test → scenario → PRD.
- `test-priority-engine` — uses the generated file list to rank
  affected tests.
- `observability` MCP (`ob_collect_metrics`, `ob_track_flaky`) —
  ingests the test runner's output when these specs actually run.
