# Platform Recipes — Playwright (web) vs Detox (mobile)

`e2e-test-writer` copies from this file verbatim. Changing a block
here changes every file the skill emits after the change. If a real
project needs a different runner (Cypress, Nightwatch, Appium), add
a section **first**, then update the skill's Step 1 dispatch.

The skill does NOT mix frameworks in the same generated file. One
feature file, one runner, one recipe.

---

## Web — Playwright

### Imports
```ts
import { test, expect, type Page } from "@playwright/test";
import { <ScreenName>Page } from "./pages/<ScreenName>Page";
```

The skill imports one Page Object per `targetScreen`. Importing the
raw `Page` type is fine, but **never calling a raw Page method** in
the test body — every `page.click`, `page.fill`, `page.locator`
must live inside a POM method.

### Navigation
```ts
await pom.goto();               // POM owns the path; never hardcode it in the test
```

Every POM exposes a `goto()` method. The test is forbidden from
calling `page.goto('/settings')` — route shape drift is one of the
most common e2e breakages, and centralizing it in the POM is the
only fix that scales.

### Waiting (allowed)
```ts
await expect(pom.readyHeading).toBeVisible();
await expect(pom.spinner).toBeHidden();
await pom.waitForReady(); // POM-owned composite wait
```

### Waiting (forbidden)
```ts
// ❌ await page.waitForTimeout(2000);
// ❌ await new Promise(r => setTimeout(r, 1000));
// ❌ await page.waitForLoadState('networkidle'); // only when the scenario explicitly asserts network idle
```

### Assertions
```ts
await expect(pom.welcomeHeading).toHaveText(/welcome/i);
await expect(pom.alerts).toHaveCount(0);
await expect(page).toHaveURL(/\/dashboard/); // URL assertions are fine — they're stable
```

### Storage-state auth
```ts
test.use({ storageState: "tests/e2e/fixtures/authed.json" });
```

The skill writes the `storageState` line INSIDE the `describe` block
when every test in the block needs the same auth. Per-test auth uses
an explicit fixture:

```ts
test("SC-112: gated page", async ({ browser }) => {
  const context = await browser.newContext({ storageState: "tests/e2e/fixtures/authed.json" });
  const page = await context.newPage();
  // ...
});
```

### Retry budget
Playwright supports `test.describe.configure({ retries: N })`. The
skill emits `retries: 0` by default. **Retries hide flake.** Only
emit a non-zero retry count when the scenario explicitly opts in via
`scenario-set.md: { retries: N, reason: "..." }` and records the
reason in a comment. Silent retries are forbidden.

### Config file hints
- `playwright.config.ts` at project root (required)
- `@playwright/test` in devDependencies (required)

---

## Mobile — Detox (iOS and Android)

### Imports
```ts
import { device, element, by, expect } from "detox";
import { <ScreenName>Screen } from "./screens/<ScreenName>Screen";
```

Detox's `expect` is Detox-specific, not Jest's — the skill must NOT
re-import from `@jest/globals` in a Detox file. That's the cleanest
signal of "wrong framework in the wrong file".

### Navigation
```ts
await screen.goto();   // e.g. device.launchApp({ newInstance: true, url: 'myapp://dashboard' })
```

Deep-linking via the bundle id's URL scheme is the preferred
navigation form. POMs own the deep link string.

### Waiting (allowed)
```ts
await waitFor(screen.welcomeHeading).toBeVisible().withTimeout(5000);
await waitFor(screen.spinner).toBeNotVisible().withTimeout(5000);
await screen.waitForReady();
```

Detox's `waitFor` supports an explicit timeout — the skill emits
`withTimeout(5000)` by default. Longer waits must be justified in
the scenario.

### Waiting (forbidden)
```ts
// ❌ await new Promise(r => setTimeout(r, 1000));
// ❌ await device.pause(2000);
```

### Assertions
```ts
await expect(screen.welcomeHeading).toBeVisible();
await expect(screen.alerts).toHaveText("0 new");
```

### Auth — iOS / Android
Detox doesn't have a native storageState equivalent. The two
strategies are:

1. **Token injection** via a test-only launch arg that the app reads
   on startup (`device.launchApp({ launchArgs: { testToken: "…" } })`).
2. **UI login** — only acceptable for the login scenarios themselves;
   never for "incidental" auth in other flows.

The auth catalog in `pom-patterns.md` marks `stored-session` as
**not applicable to mobile**. The skill refuses to emit it and points
the user at `token-injection` instead.

### Retry budget
Same rule as web: default `retries: 0`. Detox retries mask timing
issues that production users will see on slow devices.

### Config file hints
- `.detoxrc.js` / `detox.config.js` at project root
- `detox` in devDependencies
- Device type defined in the config (iPhone N, Pixel N, etc.)

---

## Shared structural rules

### Test file layout
```
describe("<FeatureName>", () => {
  // auth config goes here when the whole block shares it

  test("SC-<id>: <human-readable outcome>", async ({ page }) => {
    // Arrange
    const pom = new <Screen>Page(page);

    // Act
    await pom.<method>();

    // Assert
    await expect(pom.<elementOrState>).<detoxOrPlaywrightAssertion>(...);

    // trace: scenarios/SC-<id> — "<scenario title>"
    // why: <one line explaining what regression this guards against>
  });
});
```

### Banned across both platforms
- **Shared mutable state across tests.** `let user` at module level
  that tests mutate → order-dependent pass/fail. The skill refuses
  to emit it; shared setup goes in a `beforeEach` that reinitializes
  per test.
- **Catch-swallow of assertion errors.** Any `try { ... } catch { }`
  around an `expect(...)` is a false-green in disguise.
- **Magic values in the test body.** Literal usernames/passwords/IDs
  live in a fixture file or a factory call; the test body only
  references the name.

---

## Adding a new runner

1. Add a top-level section above with imports, navigation, waiting,
   assertions, auth, retry budget, config file hints.
2. Update the skill's Step 1 dispatch (`platform → recipe`).
3. Extend the integration harness sentinel to assert the new section
   exists.
4. Teach the Auth Strategy Catalog which strategies apply to the
   new runner.
