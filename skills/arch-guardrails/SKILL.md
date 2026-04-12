---
name: arch-guardrails
description: Validates proposed changes against architectural rules — layering, allowed dependencies, forbidden imports, naming conventions. Use before merging or when reviewing a refactor that touches cross-module boundaries. Blocks work that violates ADR-recorded constraints.
allowed-tools: Read Grep Glob
---

# VibeFlow Architecture Guardrails

Statically checks that a change respects the project's recorded architectural
rules. The rules live in `.vibeflow/artifacts/arch-rules.yaml` (or a path set
via `vibeflow.config.json` → `archRulesPath`). Absent rules mean "no
constraints"; the skill reports success in that case rather than inventing
defaults.

## Inputs
- `.vibeflow/artifacts/arch-rules.yaml` — declared rules
- Optional: a changeset file list (from `.vibeflow/traces/changed-files.log`)
  so the scan is incremental. Without one, the skill scans the whole tree.

## Rule Types
1. **Layering**: module A may only import from modules in its allow-list
   (e.g. `ui/` must not import from `infra/`).
2. **Forbidden imports**: no file matching pattern X may reference symbol Y
   (e.g. no test utility outside `tests/`).
3. **Naming**: file names in directory D must match pattern P
   (e.g. `*.test.ts` lives next to `*.ts`).
4. **Dependency version pins**: certain packages must stay on a pinned
   version because of a compatibility ADR.

## Output Contract
Every finding follows the standard explainability shape:
```json
{
  "finding":    "...rule violation summary...",
  "why":        "...which rule + which file/line...",
  "impact":     "blocks merge | soft warning | informational",
  "confidence": 0.0
}
```
Write the findings list to `.vibeflow/reports/arch-guardrails.md`. Exit with
a non-zero code only when at least one finding has `impact: blocks merge`.

## When to Run
- During `/vibeflow:advance` from DESIGN → ARCHITECTURE (check preconditions)
- Before every commit in DEVELOPMENT (wired via `commit-guard.sh` in Sprint 2)
- On demand: `/vibeflow:arch-guardrails`
