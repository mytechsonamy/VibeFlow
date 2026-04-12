# Spec Parser Notes

Everything the `contract-test-writer` skill needs to know about each
supported spec format. Keep this file in lock-step with the skill's
Step 1/Step 2 algorithm — a parser quirk that isn't documented here is
one the skill cannot rely on.

---

## OpenAPI 3.x (preferred)

### File shapes
- `.yaml` / `.yml` — read as YAML, top-level `openapi: 3.x.x`.
- `.json` — read as JSON, top-level `"openapi": "3.x.x"`.
- Split specs with external `$ref`s are in scope; the skill must
  resolve them transitively.

### `$ref` handling
1. Build a bucket of all `#/components/schemas` / `parameters` / `responses`
   / `securitySchemes` as the first pass.
2. On the second pass, every `$ref: "#/..."` is replaced with a
   reference to the bucket entry — we flatten to a normalized graph,
   we do NOT emit raw $refs into the CanonicalOperation.
3. Cycles in `$ref` are legal in OpenAPI (a type that references
   itself). The skill must break cycles with a visited-set so the
   normalizer terminates.
4. External `$ref`s (`./common.yaml#/components/schemas/Error`) are
   resolved relative to the spec file's directory. Remote HTTP refs
   are refused — they introduce network non-determinism into the
   pipeline. If a spec needs a remote ref, bundle the spec first.

### `allOf` / `oneOf` / `anyOf`
- `allOf`: merge subschemas left-to-right. Required fields are the
  union of required fields. Conflicting types are a parse error.
- `oneOf`: treat as a sum type. Emit one test per branch.
- `anyOf`: same as `oneOf` for test generation — we cannot reliably
  distinguish the two from response payloads alone, and generating
  more tests is the safe default.

### `discriminator`
When a schema uses `discriminator.propertyName`, the generated test
reads the property first and picks the matching branch. Do NOT
write a test that asserts a specific branch — that's scenario-set
territory.

### Examples
1. Prefer `operation.requestBody.content[mediaType].example`.
2. Fall back to `operation.requestBody.content[mediaType].examples[*]`
   — iterate every named example and generate one test per example.
3. Fall back to the schema-level `example`.
4. If none exist, mark the test case `it.skip` with
   `pending: "awaiting example"` — never synthesize.

### Security
- `security: []` at the operation level overrides the global security
  to "none".
- `securitySchemes` entries get mapped to the skill's `auth` enum via:
  - `http.bearer` → `"bearer"`
  - `http.basic`  → `"basic"`
  - `apiKey`      → `"custom"`
  - `oauth2`      → `"custom"`
  - anything else → `"custom"`

---

## OpenAPI 2.x (Swagger)

Support is best-effort — if the project is still on 2.x, the skill
works but surfaces a WARNING in the report recommending an upgrade to
3.x. Differences to watch:

- No `components/schemas` — definitions live at `#/definitions`.
- `consumes` / `produces` are top-level, not per-operation.
- `securityDefinitions` instead of `components.securitySchemes`.
- `parameters` can have `in: body`, which 3.x replaced with
  `requestBody`. Normalize to the 3.x shape before Step 2.
- No `oneOf` / `discriminator` — any use of polymorphism in 2.x specs
  is expressed via `allOf` plus a custom convention; the skill treats
  it as a flat merge.

Do NOT attempt to rewrite the spec to 3.x — just normalize in memory
for the canonical-operation pass.

---

## GraphQL SDL

### File shapes
- `.graphql` / `.graphqls` single file with top-level `schema { query, mutation, subscription }`.
- Modular schemas split across directories — treat the union of all
  `*.graphql(s)` files in the resolved directory as one document.

### Operation enumeration
- For each field on `Query` → one operation with verb `"query"`,
  path `<fieldName>`, 200 response = the field's return type.
- For each field on `Mutation` → verb `"mutation"`.
- Subscriptions are out of scope for Sprint 2 — they fail with
  `pending: "subscriptions not yet supported"` to keep the output
  honest.

### Walking the type graph
- Depth-first, visited-set keyed by type name.
- Custom scalars: emit an `unknown` type in JsonSchema with a comment
  referencing the scalar name. Downstream test generation treats them
  as opaque strings unless `scenario-set.md` has a hint.
- Interfaces and unions: emit `oneOf` over the implementing /
  constituent types, mirroring OpenAPI's polymorphism shape.
- Input types feed request schemas; object types feed response
  schemas. Never cross them — an input type cannot show up in a
  response.

### Errors
GraphQL puts errors in a top-level `errors` array rather than in HTTP
status codes. The skill synthesizes a single 4xx response schema
containing the standard GraphQL error envelope
(`{ errors: [{ message, path, extensions }] }`) so downstream diffs
behave identically to OpenAPI.

---

## Normalizing to `CanonicalOperation`

Every parser's output goes through the same normalizer:

```ts
interface CanonicalOperation {
  id: string;
  verb: string;
  path: string;
  requestSchema: JsonSchema | null;
  responseSchemas: Record<string, JsonSchema>;
  requiredHeaders: string[];
  auth: "none" | "bearer" | "basic" | "custom";
  tags: string[];
}
```

Rules:
- Stable ordering: operations sort by `verb ASC, path ASC, id ASC` so
  the report and the test file are deterministic.
- `path` uses the OpenAPI template form (`/users/{id}`) even for
  GraphQL, where it holds the root-field name.
- `tags` for GraphQL come from the field's `@tag` directive if
  present, else `["query"]` or `["mutation"]`.

A normalizer mismatch — where the same logical operation parses
differently on the same input twice — is a skill bug. Add a test case
to the harness and fix.

---

## Parser failure policy

- **Malformed YAML/JSON** → blocker finding, skill refuses to run.
- **Dangling `$ref`** → blocker finding, cites the exact ref string.
- **Unsupported format** → blocker finding, cites the detected format.
- **Missing `operationId` (OpenAPI)** → blocker finding, cites the
  method + path.
- **Circular `allOf` merge with conflicting types** → blocker finding,
  cites both type paths.

Graceful degradation is a lie here — shipping tests generated from a
wrongly-parsed spec is worse than shipping no tests.
