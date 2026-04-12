# Breaking-Change Classification Rules

The `contract-test-writer` skill looks up diffs in this table at Step 5
of its algorithm. The skill is forbidden from inventing classifications
— if a diff shape is not covered here, the skill must refuse to
classify it and open a PR that extends the table.

Every rule has five fields:

| Field | Meaning |
|-------|---------|
| `id` | Stable identifier cited in `contract-report.md`'s `why:` field |
| `condition` | The diff shape the rule matches (old vs new) |
| `severity` | `MAJOR` / `MINOR` / `PATCH` |
| `rationale` | Why this shape has that severity — not a vibe, a consequence |
| `remediation` | What the spec author should do to lower the severity |

Severity semantics:

- **MAJOR** — at least one existing consumer will break at runtime.
  Blocks the release gate unless the diff carries an
  `x-vibeflow-migration` note that explains how to migrate.
- **MINOR** — backwards-compatible but semantically significant.
  Never blocks, but surfaces in the report so clients can opt in.
- **PATCH** — cosmetic or docs-only. Recorded for audit trail,
  never blocks, never needs a migration note.

A note on **silence vs. explicit**: a schema that previously had
`additionalProperties: true` (default) and now has
`additionalProperties: false` is a MAJOR change *even if the spec
author didn't know the old default*. Breakage is measured in client
behaviour, not in author intent.

---

## Operation-level diffs

| id | condition | severity | rationale | remediation |
|----|-----------|----------|-----------|-------------|
| OP-001 | Operation removed (old spec has operationId X, new spec does not) | MAJOR | Existing clients calling X will 404 | Deprecate first: mark `deprecated: true` in the old spec for at least one release, then remove |
| OP-002 | Operation added (new spec has operationId X, old does not) | MINOR | No client breaks; adds surface area | Document usage in release notes |
| OP-003 | `verb` changed for a given operationId (POST → PUT, etc.) | MAJOR | Existing clients send the wrong HTTP verb | Add a new operation, deprecate the old one |
| OP-004 | `path` changed for a given operationId | MAJOR | Route resolution on the server side fails | Same as OP-003 — add new, deprecate old |
| OP-005 | Auth scheme changed (none → bearer, bearer → basic, etc.) | MAJOR | Clients that previously worked without the new credential fail with 401/403 | Support both schemes for one release, then deprecate |
| OP-006 | Operation moved to a different tag | PATCH | Only affects documentation grouping | None needed |

## Request-schema diffs

| id | condition | severity | rationale | remediation |
|----|-----------|----------|-----------|-------------|
| REQ-001 | Required field added to request body | MAJOR | Existing clients that don't send the field get 400 | Make the field optional first, land the server-side acceptance, then flip to required |
| REQ-002 | Field changed from optional to required | MAJOR | Same as REQ-001 | Same as REQ-001 |
| REQ-003 | Optional field added to request body | MINOR | New capability; old clients keep working | None needed unless downstream tooling expects the field |
| REQ-004 | Field removed from request body | MINOR | Server will ignore the field; clients that sent it are unaffected | Prefer deprecating first for observability |
| REQ-005 | Type widened (integer → number, or sum type added) | MINOR | Old values still valid | None |
| REQ-006 | Type narrowed (number → integer, or sum type shrunk) | MAJOR | Old values rejected | Accept both types for one release |
| REQ-007 | Enum value removed | MAJOR | Clients sending the removed value get rejected | Accept for one release, log deprecation warnings, then remove |
| REQ-008 | Enum value added (request enum) | MAJOR if clients rely on a closed set, else MINOR | A strict client may refuse to build the request for an unknown enum | Audit clients; when in doubt treat as MAJOR |
| REQ-009 | `additionalProperties: true` → `false` | MAJOR | Previously-tolerated extra fields become rejections | Log warnings for one release, then flip |
| REQ-010 | Format or constraint tightened (pattern, minLength, etc.) | MAJOR | Previously-valid inputs rejected | Accept both for one release |
| REQ-011 | Format or constraint relaxed | MINOR | New inputs accepted; old inputs still valid | None |

## Response-schema diffs

| id | condition | severity | rationale | remediation |
|----|-----------|----------|-----------|-------------|
| RES-001 | Required response field removed | MAJOR | Clients that dereference the field crash | Keep the field with a sentinel value for one release, then drop |
| RES-002 | Required response field changed to optional | MAJOR | Clients that assumed the field's presence break | Same as RES-001 |
| RES-003 | Optional response field added | MINOR | Clients that ignore unknown fields keep working; strict clients may need updates | Document in release notes |
| RES-004 | Type widened (string → string \| null) | MAJOR | Clients that don't handle the new variant crash | Add the new variant opt-in behind a feature flag first |
| RES-005 | Type narrowed | MINOR | Clients receive a strict subset of what they expected | None |
| RES-006 | Enum value removed (response enum) | MINOR | Clients will just never see that value | None |
| RES-007 | Enum value added (response enum) | MAJOR if clients use it as an exhaustive switch, else MINOR | Unhandled branch in consumer code | Audit; default to MAJOR |
| RES-008 | Status code removed | MAJOR | Clients expecting the code for error paths break | Deprecate first |
| RES-009 | Status code added | MINOR | New outcome; existing handlers keep working | Document |
| RES-010 | Response `additionalProperties: false` → `true` | PATCH | Loosens the schema; no client breaks | None |

## Header + parameter diffs

| id | condition | severity | rationale | remediation |
|----|-----------|----------|-----------|-------------|
| HDR-001 | New required header added | MAJOR | Existing requests fail with 400 | Make the header optional first |
| HDR-002 | Required header removed | MINOR | Clients that still send it are tolerated | None |
| HDR-003 | Query parameter changed from optional to required | MAJOR | Same as REQ-001 | Same |
| HDR-004 | Query parameter removed | MINOR | Server ignores; client is fine | None |
| HDR-005 | New optional query parameter added | PATCH | Pure docs change for callers | None |

## Rule maintenance

- **Never delete a rule.** If a rule is wrong, add a new rule with a
  fresh id and mark the old one `deprecated` in the rationale column.
- **Never change a severity silently.** Severity changes require a new
  rule id so old reports stay interpretable.
- **Every `MAJOR` rule is load-bearing for the release gate.** Before
  marking anything as MAJOR, confirm it really does break at least one
  realistic client at runtime — MAJOR is expensive.
