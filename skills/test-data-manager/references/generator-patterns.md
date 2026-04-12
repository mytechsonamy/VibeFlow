# Generator Patterns

Everything the `test-data-manager` skill embeds into generated factory
files. The skill copies code blocks from this file **verbatim** so all
generated factories use the same PRNG, the same override shape, and
the same retry strategy. If you change a block here, every factory
regenerated after that change picks up the new version.

---

## The PRNG — mulberry32

Single 32-bit seed, 32-bit output, uniform distribution. Small enough
to embed in every generated file; deterministic across Node, Deno,
and browsers; no external dependency.

```ts
// @generated-start
export function mulberry32(seed: number): () => number {
  let t = seed >>> 0;
  return function rng() {
    t = (t + 0x6D2B79F5) >>> 0;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}
// @generated-end
```

Rules:
- **Never import a random library.** Every generated factory needs a
  PRNG it can embed statically. Pulling in `seedrandom` or `faker`
  breaks the "single file, single seed, reproducible" promise.
- **Seeds are 32-bit unsigned.** Anything wider truncates silently
  and hides collisions.
- **The PRNG is pure.** It takes a seed, returns a closure. Never
  mutate module-level state.

---

## Seed composition

Every factory is built on top of a composition function that folds
multiple seed sources deterministically:

```ts
// @generated-start
const FACTORY_SEED =
  Number(process.env.VIBEFLOW_DATA_SEED ?? 1337) >>> 0;

export function hashName(name: string): number {
  // FNV-1a 32-bit. Good enough to distinguish factory names; NOT a
  // cryptographic hash, never use for security.
  let h = 0x811c9dc5;
  for (let i = 0; i < name.length; i++) {
    h ^= name.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

export function factoryRng(factoryName: string, localSeed = 0): () => number {
  return mulberry32(FACTORY_SEED ^ hashName(factoryName) ^ localSeed);
}
// @generated-end
```

Every factory calls `factoryRng("<SchemaName>", seed)`. Two factories
with different names never collide, and the same name always produces
the same stream for the same seed — that's the whole determinism
contract.

---

## The `make<Schema>` shape

Every factory function exported by the skill has this exact signature:

```ts
export function make<Schema>(
  overrides: Partial<Schema> = {},
  seed = 0,
): Schema {
  const rng = factoryRng("<Schema>", seed);

  const base: Schema = {
    // field-by-field construction, always in source order
    ...
  };

  const withOverrides = { ...base, ...overrides };

  // Invariant retry loop — see next section.
  return satisfyInvariants(withOverrides, seed, "<Schema>");
}
```

Rules:
- **Overrides always win.** If the user passes `overrides.email`, the
  factory uses it verbatim — it does NOT validate against constraints
  or retry. Tests that want invalid data should be able to ask for
  invalid data.
- **Override + invariant conflict is explicit.** When an override
  causes an invariant to fail, the factory throws
  `InvariantViolationFromOverride` with both the override and the
  invariant id. Tests that want invalid invariants should use the
  edge-case preset, not an override.
- **Field order matches the source type's declaration order.** Never
  sort alphabetically — it makes diffs noisy when the source type
  has dependent field logic.

---

## Invariant retry strategy

When a schema declares invariants (via Zod `.refine()`, JSON Schema
`allOf` constraints, or `invariant-matrix.md`), generation must
satisfy them. The strategy is **retry with a bumped seed**, not
"bias the distribution to likely-valid values":

```ts
// @generated-start
const MAX_INVARIANT_RETRIES = 100;

export function satisfyInvariants<T>(
  candidate: T,
  originalSeed: number,
  factoryName: string,
): T {
  for (let attempt = 0; attempt < MAX_INVARIANT_RETRIES; attempt++) {
    if (checkInvariants(candidate)) return candidate;
    candidate = regenerate(factoryName, originalSeed + attempt + 1);
  }
  throw new Error(
    `test-data-manager: invariant unreachable for ${factoryName} ` +
    `after ${MAX_INVARIANT_RETRIES} retries; check constraints.`,
  );
}
// @generated-end
```

Rules:
- **Retries walk the seed forward deterministically** (`seed + attempt`),
  so the retry count is reproducible — tests on different machines
  hit the same retry count for the same schema.
- **Biasing distributions toward "likely valid" is forbidden.** It's
  how bugs hide. If invariants keep failing, the real fix is to
  loosen the generator's raw range, not to cheat the distribution.
- **Hard-fail after `MAX_INVARIANT_RETRIES`.** Silently returning
  the last candidate is how flaky data sneaks into CI.

---

## Sequence-backed ids

Auto-incrementing ids are a lie for tests — they leak test order into
test data. Instead, use the PRNG to pick a stable-but-distinct id
from a large space:

```ts
// @generated-start
export function nextId(rng: () => number, prefix = ""): string {
  // 9-digit decimal derived from PRNG; unique enough for tests,
  // deterministic across runs with the same seed.
  const n = Math.floor(rng() * 1_000_000_000);
  return `${prefix}${n.toString().padStart(9, "0")}`;
}
// @generated-end
```

Factories requiring ids call `nextId(rng, "user_")`. Two consecutive
calls with the same seed produce the same two ids — same determinism
contract, no module-level counter state.

---

## Picking from a set

```ts
// @generated-start
export function pickOne<T>(rng: () => number, xs: readonly T[]): T {
  if (xs.length === 0) throw new Error("pickOne: empty");
  return xs[Math.floor(rng() * xs.length)]!;
}

export function pickSubset<T>(
  rng: () => number,
  xs: readonly T[],
  min = 0,
  max = xs.length,
): T[] {
  const size = min + Math.floor(rng() * (max - min + 1));
  const copy = [...xs];
  // Fisher-Yates — deterministic shuffle with the same RNG stream.
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [copy[i], copy[j]] = [copy[j]!, copy[i]!];
  }
  return copy.slice(0, size);
}
// @generated-end
```

The Fisher-Yates shuffle is the ONLY acceptable shuffle — the
`sort(() => rng() - 0.5)` trick is biased and non-deterministic
across JS engines.

---

## Dates

Dates always come from the PRNG, never from `Date.now()`:

```ts
// @generated-start
export function aDate(
  rng: () => number,
  opts: { minEpochMs?: number; maxEpochMs?: number } = {},
): Date {
  const lo = opts.minEpochMs ?? 0;                     // 1970-01-01
  const hi = opts.maxEpochMs ?? 4102444800_000;        // 2100-01-01
  return new Date(lo + Math.floor(rng() * (hi - lo)));
}

export function aPastDate(rng: () => number): Date {
  // Anchored at a fixed point so "past" means the same thing every run.
  const ANCHOR = 1_735_689_600_000; // 2025-01-01 UTC
  return new Date(ANCHOR - Math.floor(rng() * 365 * 24 * 3600 * 1000));
}

export function aFutureDate(rng: () => number): Date {
  const ANCHOR = 1_735_689_600_000;
  return new Date(ANCHOR + Math.floor(rng() * 365 * 24 * 3600 * 1000));
}
// @generated-end
```

**The anchor timestamp is part of the determinism contract** — if
"past" meant "before Date.now()", the same seed would produce
different data on different days. The anchor is fixed. If you need
"yesterday", pass `opts.maxEpochMs` explicitly.

---

## Override conflict detection

When a user passes an `overrides` object that contradicts the
schema's invariants, the factory needs to decide: apply the override
or respect the invariant? The rule is **override wins, throw on
contradiction**:

```ts
// @generated-start
export class InvariantViolationFromOverride extends Error {
  constructor(factoryName: string, invariantId: string) {
    super(
      `test-data-manager: ${factoryName} override violates ` +
      `invariant ${invariantId}. Use the edge-case preset for ` +
      `intentionally-invalid data.`,
    );
    this.name = "InvariantViolationFromOverride";
  }
}
// @generated-end
```

Tests that genuinely need invalid data use the named edge-case
presets (see `edge-case-catalog.md`). Those presets document the
specific violation intent, which overrides cannot.
