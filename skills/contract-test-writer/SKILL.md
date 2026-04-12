---
name: contract-test-writer
description: Generates consumer + provider contract tests from an OpenAPI (2.x/3.x) or GraphQL SDL file, and diffs the current spec against the previous one to classify breaking changes (MAJOR/MINOR/PATCH). Emits contract.test.ts + contract-report.md. MAJOR diffs block the release gate. PIPELINE-1 step 4.
allowed-tools: Read Grep Glob Write
context: fork
agent: Explore
---

# Contract Test Writer

An L1 Truth-Validation skill. Its job is to turn an API specification
into two things at once:

1. **Runnable contract tests** — provider-side tests that assert the
   real implementation matches the spec, plus consumer-side
   request-shape snapshots for any declared consumer.
2. **A semantic diff of the spec itself** — every change since the
   previous version classified as MAJOR, MINOR, or PATCH, with the
   rationale rendered in the standard explainability contract.

## When You're Invoked

- During PIPELINE-1 step 4, in parallel with `component-test-writer`,
  `business-rule-validator`, and `test-data-manager`.
- On demand as `/vibeflow:contract-test-writer <spec path>`.
- Automatically from `release-decision-engine` when a spec file changed
  in the diff since the last release tag.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Spec file | yes | OpenAPI 3.x (preferred), 2.x, or GraphQL SDL. Path arg or `.vibeflow/artifacts/api-spec.yaml`. |
| Previous spec | optional but preferred | `.vibeflow/artifacts/contracts/previous/<name>` — if absent, the skill skips breaking-change detection and reports "baseline established" instead. |
| `scenario-set.md` | optional | When present, scenario ids link to the specific operations they exercise (SC → operationId). |
| Consumer registry | optional | `.vibeflow/artifacts/contracts/consumers.json` — a list of named downstream consumers with their expected operation set. |
| Framework config | derived | Read from `repo-fingerprint.json` / `ci_analyze_structure` — reuses the same detection path as `component-test-writer` (vitest | jest). |

**Hard preconditions** — refuse to run with a single blocks-merge finding
rather than producing wrong tests:

1. The spec must parse cleanly. A malformed spec is not a test target —
   fix the spec first.
2. Every referenced `$ref` must resolve. Dangling refs are a hard
   block; we will not silently emit `any` in their place.
3. Every operation must have an `operationId`. No operationId → no
   stable test name → no traceability. Emit a blocker with remediation:
   "add operationId to <method> <path>".

## Algorithm

### Step 1 — Identify spec format
1. If file is `.json` or `.yaml`/`.yml` with a top-level `openapi:` or
   `swagger:` key → OpenAPI (version from the key).
2. If file is `.graphql` / `.graphqls` or contains `schema { query ... }`
   at top level → GraphQL SDL.
3. Otherwise refuse with "unsupported spec format".

See `references/spec-parsers.md` for per-format notes (how to resolve
`$ref`, how `allOf`/`oneOf` get normalized, how to walk a GraphQL type
graph without repeating visits).

### Step 2 — Normalize operations
Flatten the spec into a canonical list of operations:

```ts
interface CanonicalOperation {
  id: string;              // operationId (OpenAPI) or Query/Mutation field name
  verb: string;            // HTTP verb for OpenAPI; "query"/"mutation" for GraphQL
  path: string;            // path template or GraphQL root field name
  requestSchema: JsonSchema | null;
  responseSchemas: Record<string /*status code*/, JsonSchema>;
  requiredHeaders: string[];
  auth: "none" | "bearer" | "basic" | "custom";
  tags: string[];          // for grouping
}
```

For GraphQL, status codes map to `{"200": responseType, "4xx": errorUnion}`
so the downstream test shape is identical.

### Step 3 — Generate provider contract tests
For each operation, emit one `describe(operation.id, () => { ... })`
block with the following cases:

1. **Happy path** — valid request body (generated from the request
   schema via `test-data-manager` if it exists; otherwise inline a
   minimal example from the spec's `example` field; fall back to
   `it.skip` with a `pending: "awaiting example"` note).
2. **Required-field omission** — one case per required request field,
   asserting the response matches the 4xx schema.
3. **Auth missing** — one case asserting the 401/403 schema when auth
   is required.
4. **Response shape** — every declared status code gets a single
   assertion that the response body validates against its schema.

Each generated `it(...)` follows the Arrange-Act-Assert shape defined
in `../component-test-writer/references/test-patterns.md`. The titles
prefix with the operationId and, when available, the scenario id:

    it("SC-112 / getUserById: responds 200 with UserSummary", ...)

### Step 4 — Generate consumer request snapshots
If `consumers.json` is present, for each consumer+operation pair emit
a JSON snapshot under
`.vibeflow/artifacts/contracts/consumers/<consumerName>/<operationId>.json`
capturing the minimal valid request the consumer MUST be able to send.
The snapshot includes the request body, path params, query params,
and required headers. Consumer-side tests (owned by the consumer
repo) load these snapshots and assert their own request builder can
reproduce them verbatim.

If `consumers.json` is absent, skip this step — do NOT invent
consumer names.

### Step 5 — Breaking-change diff
If a previous spec exists at `.vibeflow/artifacts/contracts/previous/<name>`:

1. Parse both, normalize via Step 2.
2. Walk the cartesian product (old operations × new operations) keyed
   by `operationId`.
3. For each diff, classify via `references/breaking-change-rules.md`.
4. Record every diff as a finding in the standard explainability
   shape `{ finding, why, impact, confidence, evidence }`.

Classification **must** come from the rules table — no ad-hoc severity.
If a diff shape is not in the table, add it to the table first (and
update the harness sentinel); do not silently downgrade to "unknown".

### Step 6 — Compute the verdict
```
majorBreakingChanges = findings.filter(f.severity == "MAJOR").length
minorChanges         = findings.filter(f.severity == "MINOR").length
patchChanges         = findings.filter(f.severity == "PATCH").length
```

Verdict rules:

| Condition | Verdict |
|-----------|---------|
| `majorBreakingChanges == 0` | APPROVED |
| `majorBreakingChanges > 0` but every MAJOR has an explicit migration note in the spec (`x-vibeflow-migration`) | NEEDS_REVISION |
| `majorBreakingChanges > 0` and at least one lacks a migration note | BLOCKED |

The gate contract is **`MAJOR breaking changes block the release`** —
no other condition can produce BLOCKED and no condition can suppress it.

### Step 7 — Write outputs
1. **`contract.test.ts`** — next to the spec file. Uses the same
   `@generated-by` banner + `@generated-start`/`@generated-end`
   markers as `component-test-writer`, so regeneration preserves any
   hand-written additions outside the skill-owned region.
2. **`.vibeflow/reports/contract-report.md`** — the breaking-change
   report (see output contract below).
3. **`.vibeflow/artifacts/contracts/previous/<name>`** — copy the
   current spec here on successful APPROVED run, so the next
   invocation has a fresh baseline. NEVER overwrite the baseline on
   a BLOCKED verdict.

## Output Contract

### `contract-report.md`
```markdown
# Contract Diff Report

## Summary
- Spec: <path>
- Previous baseline: <path or "none — first run">
- Verdict: [APPROVED|NEEDS_REVISION|BLOCKED]
- MAJOR: N
- MINOR: M
- PATCH: K
- Operations evaluated: X
- Operations added: A
- Operations removed: R

## MAJOR (gate-blocking)
For each:
- **finding**: <diff description>
- **why**: <which rule from breaking-change-rules.md>
- **impact**: <who breaks and how>
- **confidence**: <0..1>
- **evidence**: <old line → new line>
- **mitigation**: <concrete migration path; never "rewrite the API">
- **migration note present**: yes | no

## MINOR
<same shape>

## PATCH
<same shape>

## Added operations
- <verb> <path> (operationId: <id>)

## Removed operations
- <verb> <path> (operationId: <id>)
```

## Explainability Contract
Every finding — MAJOR, MINOR, PATCH, added, removed — MUST carry
`finding / why / impact / confidence / evidence`. The classification
**must** cite a rule id from `references/breaking-change-rules.md`.
Undocumented classifications are forbidden.

## Non-Goals
- Does NOT validate the spec against the actual running service —
  that's an integration test, not a contract test.
- Does NOT generate client SDKs — we emit tests, not stubs.
- Does NOT reorder operations or rename anything in the spec. Diffs
  are observed, never silently fixed.

## Downstream Dependencies
- `release-decision-engine` — reads `majorBreakingChanges` as a hard
  blocker signal
- `traceability-engine` — links operationId ↔ test ids ↔ scenario ids
- `test-priority-engine` — uses the list of changed operations to
  rank affected tests for the next test run
