---
name: test-data-manager
description: Generates deterministic test data factories and fixtures from TypeScript types, Zod schemas, or JSON Schema. Seeded RNG means same seed → same data on every machine. Injects edge cases (boundary values, nulls, unicode, empty collections) from a canonical catalog and respects declared invariants. Produces <domain>.factory.ts + fixtures/<domain>.json. PIPELINE-1 step 4.
allowed-tools: Read Grep Glob Write
context: fork
agent: Explore
---

# Test Data Manager

An L1 Truth-Validation skill. Its job is to give every test suite a
**source of deterministic, invariant-respecting data** so tests are
reproducible across machines and never lie about coverage by silently
mutating on each run.

This skill does not generate tests — `component-test-writer`,
`contract-test-writer`, and `business-rule-validator` all *consume* the
factories and fixtures this skill emits.

## When You're Invoked

- During PIPELINE-1 step 4, in parallel with the other L1 skills.
- On demand as `/vibeflow:test-data-manager <type-source-path>`.
- Re-runs automatically when `invariant-formalizer` updates
  `invariant-matrix.md` — generated data must stay compatible.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Type source | yes | TypeScript interface/type file, Zod schema file, or JSON Schema file. Path arg or auto-discovered via `repo-fingerprint.json`. |
| `scenario-set.md` | optional | Scenario-specific data hints become variant presets. |
| `invariant-matrix.md` | optional but preferred | If present, every generated object must satisfy the declared invariants. |
| `business-rules.md` | optional | Rules with `condition` fields become fixture preset triggers. |
| Existing factories | scanned | Any existing `*.factory.ts` with a `@generated-by vibeflow:test-data-manager` banner is rewritten in place; hand-written factories are never overwritten. |
| Seed | optional | `VIBEFLOW_DATA_SEED` env var, else the fixed default `1337`. Determinism depends on this being stable across CI runs. |

**Hard preconditions** — refuse to run rather than produce data nobody
should trust:

1. The type source must parse. Malformed types → single blocks-merge
   finding, stop.
2. Every referenced type must resolve. Unresolved imports are not
   silently replaced with `unknown`.
3. If `invariant-matrix.md` is present, every invariant must be
   machine-checkable (has a predicate). Prose-only invariants block
   the run with remediation: "run invariant-formalizer first".

## Algorithm

### Step 1 — Detect the type source
Order of preference:

1. Explicit path argument.
2. `repo-fingerprint.json` → pick the file(s) named by
   `moduleLayout.entryPoints` or a conventional location
   (`src/types/`, `src/models/`, `src/schemas/`).
3. Glob `**/*.ts` for files whose default export is a Zod schema or
   whose named exports are interfaces — pick the smallest file set
   the user most likely meant. Never glob node_modules.

Record the chosen source + the evidence path in the run report.

### Step 2 — Parse into CanonicalSchema
Every supported input format normalizes to the same in-memory shape:

```ts
interface CanonicalField {
  name: string;
  type: CanonicalType;
  optional: boolean;
  nullable: boolean;
  constraints: {
    min?: number; max?: number;
    minLength?: number; maxLength?: number;
    pattern?: string;
    enum?: readonly (string | number)[];
    format?: "email" | "url" | "uuid" | "iso-date" | "iso-datetime";
  };
  documentation: string | null;
}

type CanonicalType =
  | { kind: "string" }
  | { kind: "number"; integer: boolean }
  | { kind: "boolean" }
  | { kind: "date" }
  | { kind: "literal"; value: string | number | boolean }
  | { kind: "array"; items: CanonicalType }
  | { kind: "object"; fields: CanonicalField[] }
  | { kind: "union"; variants: CanonicalType[] }
  | { kind: "ref"; name: string };

interface CanonicalSchema {
  name: string;
  fields: CanonicalField[];
  invariants: readonly string[]; // predicate references, not source text
}
```

Parser rules:
- **TypeScript** — read interfaces and type aliases. `readonly` is
  recorded but does not change generation. Intersections (`A & B`)
  merge fields; conflicting types are a parse error.
- **Zod** — read via `.shape` introspection for objects, `.options`
  for unions, `.element` for arrays. `.refine()` predicates are
  recorded as invariants but not auto-satisfied — the generator
  must retry until they pass.
- **JSON Schema** — read `properties`, `required`, `items`,
  `oneOf`/`anyOf` (mapped to `union`), `enum`, `format`. `allOf` is
  merged the same way as TS intersections.

### Step 3 — Seeded RNG setup
Instantiate a seeded PRNG (mulberry32 or equivalent — tiny,
dependency-free, identical across platforms). The skill MUST NOT use
`Math.random()`, `Date.now()`, or any other wall-clock source during
generation. All randomness flows through the PRNG.

See `references/generator-patterns.md` for the exact PRNG code the
skill embeds into every generated factory so test-time generation
also stays deterministic.

### Step 4 — Generate per-schema factories
For each CanonicalSchema, emit a factory function:

```ts
export function makeUser(overrides: Partial<User> = {}, seed = 0): User {
  const rng = mulberry32(FACTORY_SEED ^ seed ^ hashName("User"));
  const base: User = {
    id: nextUserId(rng),                    // sequence-backed
    email: anEmail(rng),                     // catalog-backed
    age: anIntegerInRange(rng, 0, 150),      // constraint-aware
    createdAt: aPastDate(rng),
    roles: pickSubset(rng, ["admin", "editor", "viewer"]),
  };
  return { ...base, ...overrides };
}
```

Rules:
- **Every factory takes an `overrides` object** as its first argument
  so test authors can express "a User with `role: admin`" without
  rebuilding the whole thing.
- **Every factory takes an optional `seed` argument** that XORs with
  the global `FACTORY_SEED`. Tests that need two independent objects
  pass distinct seeds.
- **Generation order inside a factory is deterministic.** Never
  randomize the order of field assignments — that breaks the
  seed-to-output contract.
- **Invariants are satisfied by retry.** If an invariant fails after
  generation, the factory regenerates up to `MAX_INVARIANT_RETRIES`
  (100) times. After that, emit a hard error: "invariant unreachable
  with current constraints" — never silently return an invalid
  object.

### Step 5 — Inject edge-case variants
For each primitive field, offer named presets from
`references/edge-case-catalog.md`:

```ts
export const userEdgeCases = {
  emptyStrings: (): User => makeUser({ email: "", /* forbidden by regex */ }),
  maxLength: (): User => makeUser({ email: "a".repeat(254) + "@b.co" }),
  unicodeName: (): User => makeUser({ name: "Μουσταφά 山田" }),
  epochDate: (): User => makeUser({ createdAt: new Date(0) }),
  farFutureDate: (): User => makeUser({ createdAt: new Date(8640000000000000) }),
};
```

The named presets are sourced from the catalog — the skill does NOT
invent new edge cases. If a field's type has no entry in the catalog,
emit a `pending:` comment instead of a preset.

### Step 6 — Write fixture snapshots
For each schema, emit one JSON fixture at
`.vibeflow/artifacts/fixtures/<schema-name>.json` containing:

1. A canonical "happy path" object (same seed → same object every run).
2. One object per edge-case variant.
3. A metadata block recording the seed and the generator version.

Fixtures are regenerated on every run. Hand-edited fixtures outside
the `@generated-start`/`@generated-end` markers are preserved
verbatim — same convention as `component-test-writer`.

### Step 7 — Emit the run report
Append to `.vibeflow/reports/test-data-manager.md`:

```markdown
# Test Data Manager — <ISO timestamp>

## Sources
- src/types/user.ts (typescript)
- src/schemas/order.zod.ts (zod)

## Schemas parsed
- User (5 fields, 2 invariants)
- Order (8 fields, 4 invariants)

## Factories emitted
- src/types/user.factory.ts (regenerated)
- src/schemas/order.factory.ts (new)

## Fixtures
- .vibeflow/artifacts/fixtures/user.json (variants: 5)
- .vibeflow/artifacts/fixtures/order.json (variants: 7)

## Seed
- FACTORY_SEED = 1337 (from VIBEFLOW_DATA_SEED)

## Warnings
- Field User.nickname has no entry in edge-case catalog for type string — emitted pending:
- Order invariant "total == sum(lineItems.price)" required 12 retries on average
```

## Output Contract

Every generated factory file:
- starts with the `@generated-by vibeflow:test-data-manager` banner
- wraps the skill-owned region with `@generated-start` /
  `@generated-end` markers
- imports the seeded RNG helper verbatim from the reference (so tests
  never pick up two different PRNG implementations)
- exports exactly one `make<Schema>` function plus one `<schema>EdgeCases`
  object per parsed schema

Every fixture JSON file:
- is valid JSON (no comments, no trailing commas)
- records the seed in a top-level `_meta.seed` field
- is stable byte-for-byte across runs on the same seed (this is the
  determinism contract and the main thing CI should assert)

## Explainability Contract
The run report records `finding / why / impact / confidence` entries
for every decision the skill made: preset selection, invariant retry
counts, edge-case pending entries, preset omissions. The factory
files themselves do not need per-line explanations — the code is the
explanation.

## Determinism Contract
**Same seed → same output, every machine, every run.** This is the
non-negotiable invariant of the whole skill. If a generator is ever
tempted to use `Math.random()`, `Date.now()`, `new Date()` without an
injected clock, or any other wall-clock source, that's a bug — fix
it in `generator-patterns.md` and regenerate everything.

The integration harness asserts determinism by running the skill
twice on a fixture project and diffing the outputs — any drift
between runs is a gate failure.

## Non-Goals
- Does NOT generate tests — those are the `*-test-writer` skills.
- Does NOT run tests against the generated data — the test-runner
  skills do that.
- Does NOT mutate the type source. Types are read-only inputs.
- Does NOT generate mocks — mocks are behavior, not data. See
  `component-test-writer/references/test-patterns.md` §5.

## Downstream Dependencies
- `component-test-writer` — imports factories for Arrange blocks.
- `contract-test-writer` — imports factories to build request bodies
  that match the spec.
- `business-rule-validator` — imports edge-case variants to exercise
  rule boundaries.
- `invariant-formalizer` — reads `invariant-matrix.md` that this
  skill then respects. The two must be re-run together whenever
  either the type source OR the invariant matrix changes.
