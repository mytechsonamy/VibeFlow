# Test Patterns — Arrange / Act / Assert

These are the templates the `component-test-writer` skill uses. Every
pattern preserves the three-section shape. If you find yourself wanting
to "just put one assertion in the Arrange block", that's a signal to
split the test — not to relax the rule.

---

## 1. Base pattern

```ts
it("SC-<id>: <short English sentence>", () => {
  // Arrange
  const input = buildFixture();

  // Act
  const result = subject(input);

  // Assert
  expect(result).toEqual(expected);

  // trace: scenarios/SC-<id> — "<scenario title>"
  // why: <one line explaining what regression this guards against>
});
```

**Why comments instead of helper functions for AAA boundaries?** Comments
survive refactoring tools that collapse whitespace and are greppable
for coverage audits. Helpers like `arrange()` / `act()` pay no
interest and cost a layer of indirection.

---

## 2. Parametrized cases

When a scenario family ("returns true for valid emails, false for invalid")
has a clear enumerable domain, use the framework's `.each`:

```ts
// vitest
it.each([
  { email: "a@b.co",   valid: true },
  { email: "no-at-sign", valid: false },
  { email: "",           valid: false },
])("SC-042: isValidEmail($email) = $valid", ({ email, valid }) => {
  // Arrange — (table row is the arrangement)

  // Act
  const result = isValidEmail(email);

  // Assert
  expect(result).toBe(valid);
});
```

Rules:
- Every row gets one representative input. Do NOT combine mutually
  exclusive scenarios into the same `.each` — they should be separate
  tests with separate scenario ids.
- The row must be the entire input. If any row needs a side helper,
  break it out of the table.

---

## 3. Table-driven with descriptive titles

When you want a single title per row to read like prose:

```ts
describe("SC-051: discount percentage", () => {
  const cases: Array<{ label: string; subtotal: number; expected: number }> = [
    { label: "zero-subtotal returns 0 discount",    subtotal: 0,     expected: 0 },
    { label: "under-threshold subtotal is ignored", subtotal: 49.99, expected: 0 },
    { label: "on-threshold triggers 10% discount",  subtotal: 50,    expected: 5 },
    { label: "large subtotal caps at 20%",          subtotal: 1000,  expected: 200 },
  ];

  for (const c of cases) {
    it(c.label, () => {
      // Arrange
      const cart = { subtotal: c.subtotal };

      // Act
      const result = computeDiscount(cart);

      // Assert
      expect(result).toBe(c.expected);
    });
  }
});
```

---

## 4. Async, with error assertion

```ts
it("SC-063: rejects when the upstream times out", async () => {
  // Arrange
  const client = makeClientWithTimeout(1); // 1ms

  // Act
  const act = () => fetchProfile(client, "user-1");

  // Assert
  await expect(act()).rejects.toThrow(/timeout/);
});
```

Rules:
- Extract the Act into a thunk (`act = () => ...`) so the assertion can
  inspect either the resolved value or the rejection without
  re-invoking the subject.
- Never use `try { await subject() } catch { expect(...) }` — it
  silently passes if the subject doesn't throw. Use
  `await expect(...).rejects.toThrow(...)`.

---

## 5. With mocked dependency

```ts
it("SC-074: caches repeat requests", () => {
  // Arrange
  const fetcher = vi.fn().mockResolvedValue({ id: 1 });
  const cache = buildUserCache(fetcher);

  // Act
  const a = await cache.get(1);
  const b = await cache.get(1);

  // Assert
  expect(a).toBe(b);
  expect(fetcher).toHaveBeenCalledTimes(1);
});
```

Rules:
- Mock at the dependency boundary, never in the middle of the subject.
- A single test asserts ONE behavior: cache hit count here, not also
  eviction correctness. Split if you're tempted to add a second
  `expect` that tests a different property.

---

## 6. With a fake clock

```ts
it("SC-081: token expires after 60 seconds", () => {
  // Arrange
  vi.useFakeTimers();
  const token = issueToken();

  // Act
  vi.advanceTimersByTime(60_001);
  const result = isTokenValid(token);

  // Assert
  expect(result).toBe(false);

  vi.useRealTimers();
});
```

Rules:
- Always restore real timers at the end of the test (or in an `afterEach`)
  so one test's fake clock doesn't leak into the next.
- Fake timers never apply to Node-native `setImmediate` callbacks
  unless you explicitly opt in — check the framework doc before using
  it for microtask-sensitive tests.

---

## 7. Forbidden shapes (skill refuses to emit these)

- **Conditional asserts:** `if (x > 0) expect(...)` — branch coverage
  lies about your real coverage. Split into two tests.
- **Mystery guests:** reading a fixture from disk without naming it in
  Arrange — the reader can't tell what the inputs were.
- **Shared mutable setup across tests:** a `let` outside `beforeEach`
  that tests mutate — order-dependent pass/fail. Always reinitialize
  per test.
- **Snapshot-only tests for pure functions:** snapshots hide intent
  and make refactoring painful. Use explicit `toEqual(expected)` with
  the expected value literal in the test body.
- **`expect.anything()` / `expect.any(Object)`:** accept only when the
  literal can't be produced deterministically. For pure functions,
  use the real value.
