# Page Object Model + Auth Strategy Catalog

Every e2e test the skill emits imports one or more Page Objects and
picks an auth strategy from this catalog. Mixing raw selectors into
the test body is the first thing that rots an e2e suite — the POM
layer is the single place where DOM / native-element churn is
absorbed.

This file holds three things:

1. The base POM template the skill emits for **new** screens.
2. The Selector Stability Policy the skill enforces at generation
   time.
3. The Auth Strategy Catalog — 4 named strategies, platform
   applicability, setup/teardown shape.

---

## 1. Base POM template — Playwright

```ts
// @generated-by vibeflow:e2e-test-writer (skeleton)
// Skill emits this once when the target screen has no existing POM.
// Fill in the selectors; the skill will NOT overwrite this file on
// re-run (only regions inside @generated-start / @generated-end are
// skill-owned, and this stub has none by design).

import type { Locator, Page } from "@playwright/test";

export class <Screen>Page {
  // Route lives in the POM — tests never hardcode paths.
  private static readonly ROUTE = "/<route>";

  // Selectors. Prefer getByTestId / getByRole / getByText — see
  // Selector Stability Policy below.
  readonly welcomeHeading: Locator;
  readonly submitButton: Locator;
  readonly spinner: Locator;

  constructor(public readonly page: Page) {
    this.welcomeHeading = page.getByRole("heading", { name: /welcome/i });
    this.submitButton = page.getByRole("button", { name: "Submit" });
    this.spinner = page.getByTestId("loading-spinner");
  }

  async goto(): Promise<void> {
    await this.page.goto(<Screen>Page.ROUTE);
    await this.waitForReady();
  }

  /**
   * Composite wait — every POM exposes one. Tests call
   * `pom.waitForReady()` instead of juggling expectations.
   */
  async waitForReady(): Promise<void> {
    await this.welcomeHeading.waitFor({ state: "visible" });
    await this.spinner.waitFor({ state: "hidden" });
  }

  /**
   * Example action method. Every UI interaction the test needs must
   * be a method on this class — never `this.page.click(...)` from
   * outside the POM.
   */
  async submitForm(): Promise<void> {
    await this.submitButton.click();
  }
}
```

## Base POM template — Detox

```ts
// @generated-by vibeflow:e2e-test-writer (skeleton)
import { element, by, waitFor } from "detox";

export class <Screen>Screen {
  private static readonly DEEP_LINK = "myapp://<screen>";

  // Detox selectors use by.id / by.label — both map to a11y ids.
  readonly welcomeHeading = element(by.id("welcome-heading"));
  readonly submitButton = element(by.id("submit-button"));
  readonly spinner = element(by.id("loading-spinner"));

  async goto(): Promise<void> {
    // Deep link is the preferred navigation form; launchApp with
    // newInstance: false keeps warm-start timing realistic.
    await device.launchApp({
      newInstance: false,
      url: <Screen>Screen.DEEP_LINK,
    });
    await this.waitForReady();
  }

  async waitForReady(): Promise<void> {
    await waitFor(this.welcomeHeading).toBeVisible().withTimeout(5000);
    await waitFor(this.spinner).toBeNotVisible().withTimeout(5000);
  }

  async submitForm(): Promise<void> {
    await this.submitButton.tap();
  }
}
```

---

## 2. Selector Stability Policy

The skill evaluates every Page Object selector (and every inline
selector it emits) against this priority. Anything below the line
is **rejected at generation time**:

| Rank | Selector | Rationale |
|------|----------|-----------|
| 1 | `getByTestId('name')` / `by.id('name')` | Survives design refactors because the id is intentional metadata, not incidental markup |
| 2 | `getByRole('button', { name: 'Sign in' })` | ARIA role + accessible name = semantic intent that also serves a11y tests |
| 3 | `getByText('Welcome back')` | Visible text — stable while copy is stable; breaks on i18n unless the scenario accounts for it |
| — | CSS class selector (`.btn-primary`) | **Rejected.** Classes are styling concerns; refactoring the theme silently breaks the test |
| — | CSS attribute selector (`[href=/x]`) | **Rejected.** Route shape drift breaks it silently |
| — | xpath (`//div[2]/span[1]`) | **Rejected outright.** Unreadable + brittle; no exceptions |

### What the skill does when it meets a banned selector in an existing POM

It does NOT rewrite the POM (that's human-owned code). It emits a
WARNING in the run report naming the file + line, and the generated
spec that depends on the POM still ships — the POM warning is a
soft signal for the next human refactor, not a gate.

### What the skill does when a scenario asks for a banned selector

It blocks with a hard finding:

> scenario SC-xxx cannot be generated: target element "foo" has no
> data-testid, no ARIA role+name, and no visible text. Add a
> data-testid before re-running.

---

## 3. Auth Strategy Catalog

Every scenario declares exactly one strategy. The skill refuses to
emit a test whose strategy doesn't match the target platform.

### Strategy `anonymous`
- **What**: no auth. The scenario targets a public path.
- **Setup**: none
- **Teardown**: none
- **Playwright**: default `page` fixture; no `storageState` line
- **Detox**: default app launch, no `launchArgs`
- **Applicable to**: web, ios, android
- **Use when**: public marketing pages, logged-out flows, registration

### Strategy `stored-session`
- **What**: reuse a pre-captured browser storage state (cookies +
  localStorage) so the test starts already authenticated.
- **Setup**: one-time capture script lives at
  `tests/e2e/fixtures/capture-authed-storage.ts`; the test file
  references the resulting JSON via `test.use({ storageState: … })`.
- **Teardown**: none (the fixture file is not mutated during the run)
- **Playwright**: `test.use({ storageState: "<fixture>.json" });`
- **Detox**: **not applicable** (mobile has no storageState
  equivalent). Blocks with "use token-injection instead".
- **Applicable to**: web only
- **Use when**: the default web auth flow — every authenticated flow
  should use this unless it explicitly tests the login UI

### Strategy `token-injection`
- **What**: inject a pre-issued auth token via launch args or URL
  parameters. The app reads it and skips the login UI.
- **Setup**: `beforeEach` calls a factory that mints a token (usually
  via a service helper or a signed JWT with a test signing key)
- **Teardown**: optional — tokens expire on their own
- **Playwright**: `await page.addInitScript(() => localStorage.setItem('token', '<t>'));`
- **Detox**: `device.launchApp({ launchArgs: { testToken: '<t>' } });`
- **Applicable to**: web, ios, android
- **Use when**: mobile auth is needed (stored-session doesn't apply),
  or when the web app authenticates without cookies

### Strategy `ui-login`
- **What**: walk the login UI before running the actual scenario.
- **Setup**: `beforeEach` navigates to the login screen, fills the
  form from a fixture, submits, waits for the post-login ready state
- **Teardown**: none
- **Playwright**: POM call `await new LoginPage(page).loginAs('qa-user')`
- **Detox**: POM call `await new LoginScreen().loginAs('qa-user')`
- **Applicable to**: web, ios, android
- **Use when**: the scenario IS a login scenario. Using `ui-login`
  for every test makes the login screen the most-tested path in the
  suite and the rest of the flows inherit its flakiness.

### Strategy rules (all platforms)

- **One strategy per test.** Nested strategies (`stored-session` +
  `ui-login`) are forbidden — they make failure attribution
  impossible.
- **Strategies are declared per scenario**, not inferred. The
  scenario YAML frontmatter names the strategy; the skill never
  guesses.
- **Applicability failures block, not degrade.** A web-only strategy
  on a mobile platform is a hard finding, not a silent fallback.

---

## 4. Shared rules

- Every POM method returns `Promise<void>` unless it explicitly
  reads state — action methods MUST NOT return element references,
  because callers would then poke at them outside the POM.
- Every POM exposes `waitForReady()`. Tests call this composite wait
  instead of chaining individual assertion waits.
- POMs are framework-neutral in naming: use `<Screen>Page` for
  Playwright, `<Screen>Screen` for Detox. Same file never contains
  both.
- When the skill emits a new POM skeleton, the file is one-shot:
  the skill comments it as "manual implementation required" in the
  run report and moves on. Selector choices belong to the human;
  the skill won't guess.
