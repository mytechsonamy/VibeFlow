# Framework Recipes — vitest vs. jest

The `component-test-writer` skill looks up which recipe to use at
algorithm Step 1. This file is the source of truth for framework-specific
syntax so the main SKILL.md stays framework-neutral. When a new runner
is added (e.g. `bun test`), add a section here rather than scattering
conditionals through the algorithm.

> Only vitest and jest are in scope for Sprint 2. The skill must refuse
> to generate tests for any other detected runner until this file is
> extended.

---

## vitest

### Imports
```ts
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
```

### Mocks
```ts
const fetcher = vi.fn().mockResolvedValue({ id: 1 });
vi.mock("node:fs");                // module mock
vi.stubGlobal("Date", FakeDate);    // global stub
```

### Fake timers
```ts
vi.useFakeTimers();
vi.advanceTimersByTime(1000);
vi.useRealTimers();
```

### Parametrized
```ts
it.each([...rows])("title with $param", ({ param }) => { ... });
```

### Assertion cheatsheet
| Need | API |
|------|-----|
| equality | `expect(x).toBe(y)` (primitive) / `toEqual(y)` (deep) |
| async reject | `await expect(p).rejects.toThrow(/msg/)` |
| spy calls | `expect(spy).toHaveBeenCalledTimes(n)` |
| object shape | `expect(obj).toMatchObject({ ... })` |

### Config file hints
- `vitest.config.ts` at project root
- `test` field in `package.json` points to `vitest` binary
- `@vitejs/plugin-react` or `@vitest/ui` in devDependencies is an
  additional hint the project is on vitest

---

## jest

### Imports
```ts
// describe / it / expect are globals unless @jest/globals is configured
import { describe, it, expect, jest, beforeEach, afterEach } from "@jest/globals";
```

The `@jest/globals` import is required only when `injectGlobals: false`
is set in `jest.config.*`. When in doubt the skill emits the import —
it works in both modes and is a stable signal that this is a jest file.

### Mocks
```ts
const fetcher = jest.fn().mockResolvedValue({ id: 1 });
jest.mock("node:fs");              // auto-mock
jest.spyOn(obj, "method");         // spy-only
```

### Fake timers
```ts
jest.useFakeTimers();
jest.advanceTimersByTime(1000);
jest.useRealTimers();
```

### Parametrized
```ts
it.each([...rows])("title with %s", (param, ...) => { ... });
```

Note: jest's `.each` interpolates positional `%s`/`%d` tokens, not
named `$param` placeholders — don't copy vitest's template strings
into jest test titles.

### Assertion cheatsheet
Same as vitest — the expect API is broadly compatible. Exceptions:
- vitest's `toMatchSnapshot({ snapshotOptions })` vs jest's
  `toMatchSnapshot(hint)` — the skill avoids snapshots entirely
  (see `test-patterns.md` § 7).
- vitest's `vi.hoisted` has no jest equivalent — rewrite as plain
  top-level consts when targeting jest.

### Config file hints
- `jest.config.{ts,js,cjs,mjs}` at project root
- `jest` field in `package.json`
- `@types/jest` or `ts-jest` in devDependencies

---

## Detection precedence

When both frameworks are present (monorepos, migration in progress),
the skill picks the framework that matches the SOURCE FILE's nearest
config. Walk up from the source file's directory until a `vitest.config.*`
or `jest.config.*` is found. Only if neither is present does the skill
fall back to the root-level `package.json` devDependencies signal.

If detection still comes back ambiguous, refuse to generate with a
clear blocker finding: "ambiguous test framework for <file>; explicit
config required." Never guess.

---

## Adding a new framework

1. Add a section above with imports, mocks, fake-timer shape,
   parametrized syntax, and assertion cheatsheet.
2. Update the SKILL.md Step 1 detection order if the new framework
   has a distinctive config file name.
3. Add a section to `test-patterns.md` only if the pattern shape
   itself differs (e.g. ava's serial-per-file model). Most new
   frameworks reuse the existing patterns with different import
   lines.
