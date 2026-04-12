---
name: checklist-generator
description: Emits context-aware review checklists (PR review, release, feature sign-off, accessibility) driven by platform (web / mobile / backend / all) and enriched with scenario-set.md coverage gaps. Every item must be verifiable (action + source of truth + binary outcome) — vague prose is rejected. PIPELINE-2 step 3.
allowed-tools: Read Grep Glob Write
context: fork
agent: Explore
---

# Checklist Generator

An L1 Truth-Validation skill. The purpose of a VibeFlow checklist is
not to remind anyone to "be careful" — it is to produce a finite set
of binary checks a reviewer can actually execute. Every item has a
precise verification action, a source of truth to check against, and
an outcome predicate. Items that don't meet that bar are rejected at
generation time, not after the reviewer has already wasted time on
them.

## When You're Invoked

- During PIPELINE-2 (change-in-place flow), step 3, after
  `component-test-writer` has produced the test file set.
- On demand as `/vibeflow:checklist-generator <context> <platform>`.
- Before a release tag, from `release-decision-engine`, when a
  CONDITIONAL verdict requires a human sign-off checklist.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Context | yes | One of `pr-review`, `release`, `feature`, `accessibility`. Drives which template family loads. |
| Platform | yes | One of `web`, `mobile`, `backend`, `all`. Drives which platform-specific items get injected. |
| `scenario-set.md` | optional | Output of `test-strategy-planner`. Scenarios with `coverage: gap` become injected items. |
| `prd-quality-report.md` | optional | P0 missing-flow findings become injected items. |
| `business-rules.md` | optional | P0 rules with `GAP-001` (uncovered) become injected items. |
| Domain config | yes | `vibeflow.config.json` → `domain`. Pulls in domain-specific overlay items (GDPR for ecommerce, HIPAA for healthcare, etc.). |

**Hard preconditions** — refuse rather than emit a useless checklist:

1. Context must be one of the four canonical values. `"other"` or
   misspellings block with remediation: "extend checklist-templates.md
   first if a new context is needed".
2. Platform must be one of the four canonical values.
3. If `context == "accessibility"` and `platform == "backend"`, abort
   — accessibility has no meaningful items for a pure backend. The
   error message points at the likely real intent (`web` or `mobile`).

## Algorithm

### Step 1 — Resolve the template family
Read `./references/checklist-templates.md`. It defines a 4×4 matrix
(context × platform) plus domain overlays. Load the intersection of:

- the base template for `<context>`
- the platform-specific additions for `<platform>`
- the domain overlay for `vibeflow.config.json.domain`

Order within the loaded set matters — items carry a stable order
because reviewers tend to execute them top-down and we want the
highest-leverage items first. Never reorder items from the
template; append-only at the end.

### Step 2 — Build the base item list
Every item is a `CanonicalItem`:

```ts
interface CanonicalItem {
  id: string;                // "CL-<CTX>-<NNN>" stable across runs
  text: string;              // the checkbox label the reviewer reads
  verification: string;      // the precise action to perform
  sourceOfTruth: string;     // file, metric, dashboard, or doc to check against
  outcome: string;           // the binary condition that makes it pass
  rationale: string;         // one-line "why this matters"
  priority: "P0" | "P1" | "P2";
  platform: "web" | "mobile" | "backend" | "all";
  context: "pr-review" | "release" | "feature" | "accessibility";
  evidence: readonly string[];
}
```

Items are pulled from `references/item-catalog.md` — the skill does
NOT invent items. An item in the template that references a
catalog id that doesn't exist is a blocker: "extend
item-catalog.md with `<id>` before regenerating".

### Step 3 — Inject scenario-gap items
If `scenario-set.md` exists, walk its entries. For every scenario
with `coverage: gap` or `status: pending`:

- Emit a new item with id `CL-GAP-<scenarioId>`.
- `text` = the scenario's natural-language description, prefixed
  with "Verify: ".
- `verification` = "run the scenario's target test; assert pass".
- `sourceOfTruth` = pointer to the scenario file `+` the target
  test file (when `component-test-writer` has produced one).
- `outcome` = "test exits 0".
- `priority` = inherited from the scenario's priority.
- `platform` = inherited, defaulting to `"all"` when absent.
- `context` = the current run's context.
- `evidence` = `[scenarioFile:anchor]`.

Gap items are appended to the base list in order of scenario id.

### Step 4 — Inject rule-gap items
If `business-rules.md` + `semantic-gaps.md` exist, walk the gap
report. For every `GAP-001` (uncovered) entry whose rule is P0:

- Emit an item with id `CL-BR-<ruleId>`.
- `text` = "Verify: <rule.normalized>".
- `verification` = "run the BR test suite; assert the rule's
  negative path is present".
- `sourceOfTruth` = `business-rules.md` entry + target test file.
- `outcome` = "rule test exists AND passes".
- `priority` = "P0" always (these are gate-blocking rules).

### Step 5 — Validate every item is verifiable
Every item — whether from the catalog, a scenario gap, or a rule
gap — must pass the **verifiability check**:

1. `verification` must contain an imperative verb that describes a
   concrete action ("run X", "inspect Y", "measure Z", "query the
   dashboard at U"). Weak verbs like "ensure", "confirm", "check
   that it is good" FAIL.
2. `sourceOfTruth` must resolve to a real file, a real URL, or a
   real metric name. "The codebase" FAILS. "Our testing docs" FAILS.
   `src/models/user.ts:42` PASSES.
3. `outcome` must be binary: the reviewer either ticks the box or
   doesn't. "Mostly done" FAILS. "Unit tests pass" PASSES.
4. Items failing the check are rejected with a blocker finding
   that names the specific failure. The skill does not silently
   downgrade them.

**Gate contract: zero unverifiable items in the generated checklist.**
This is the only thing that makes a checklist useful instead of
performative — no skill run is allowed to ship a weaker bar.

### Step 6 — Compute the verdict
```
unverifiableItems = items.filter(i => !i.passedVerifiabilityCheck).length
missingCatalogIds = templateRefs.filter(id => !catalog.has(id)).length
p0Items           = items.filter(i => i.priority === "P0").length
```

Verdict rules:

| Condition | Verdict |
|-----------|---------|
| `unverifiableItems == 0 && missingCatalogIds == 0 && p0Items >= minP0(context)` | APPROVED |
| `unverifiableItems == 0 && missingCatalogIds == 0` but `p0Items < minP0(context)` | NEEDS_REVISION |
| `unverifiableItems > 0 \|\| missingCatalogIds > 0` | BLOCKED |

`minP0(context)`: `pr-review=3`, `release=5`, `feature=3`,
`accessibility=4`. A checklist below the floor either has the wrong
context or is missing template rows — either way, generating it
anyway would be performative.

### Step 7 — Write outputs

1. **`.vibeflow/reports/checklist-<context>-<platform>-<ISO>.md`** —
   the generated checklist.
2. **`.vibeflow/reports/checklist-generator-run.md`** — append-only
   run log (which context/platform were generated, the verdict,
   counts).

Each checklist file is human-readable markdown — reviewers open it
directly. Do NOT wrap it in `@generated` markers; this output IS
the artifact, not a source file to be regenerated. Historical
checklists stay on disk so retrospectives can look at what was on
the sheet at the time.

## Output Contract

### `checklist-<context>-<platform>-<ISO>.md`
```markdown
# <Context title-cased> Checklist — <Platform title-cased>
<ISO timestamp>

- **Context**: <context>
- **Platform**: <platform>
- **Domain overlay**: <domain>
- **Items**: N (P0: a, P1: b, P2: c)
- **Scenario gaps injected**: S
- **Rule gaps injected**: R

## P0 — must pass before sign-off
- [ ] **CL-PR-001** — <text>
  - **Verify**: <verification>
  - **Source of truth**: <sourceOfTruth>
  - **Outcome**: <outcome>
  - **Rationale**: <one-line why>
- [ ] **CL-PR-002** — ...

## P1 — should pass before sign-off
- [ ] ...

## P2 — nice-to-have
- [ ] ...
```

Every bullet is a single binary check. If the reviewer cannot
decide the outcome in <60 seconds, the item failed the
verifiability check and should not be here.

## Explainability Contract
The run log records `finding / why / impact / confidence` for every
skipped item (verifiability failure, missing catalog id, wrong
context) plus every injected gap. The checklist itself does not
carry explainability metadata — the reviewer needs a clean page.

## Non-Goals
- Does NOT execute the checks. Reviewers execute them; the
  skill's job is to make sure each check is executable in the
  first place.
- Does NOT reorder items based on "importance". Template order is
  the execution order.
- Does NOT infer domain. `vibeflow.config.json.domain` is the
  single source.
- Does NOT replace human judgment. Items are the floor, not the
  ceiling — a reviewer should still think about the change.

## Downstream Dependencies
- `release-decision-engine` — pulls `p0Items` and `p0ItemsCompleted`
  into the CONDITIONAL sign-off gate during release decisions.
- `traceability-engine` — links `CL-GAP-<scenario>` and
  `CL-BR-<rule>` items back to scenarios and rules so the RTM
  records which gaps the checklist closed.
