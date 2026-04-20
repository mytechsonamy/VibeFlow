---
name: advance
description: Advance the project to the next SDLC phase. Reads projectId from vibeflow.config.json, invokes the sdlc_advance_phase MCP tool, and surfaces the phase-gate's pass/fail reason. Supports humanOverrideNote for advancing under HUMAN_APPROVAL_REQUIRED consensus (Sprint 17-C).
disable-model-invocation: true
allowed-tools: Read
---

# Advance Phase

Thin wrapper around the `sdlc_advance_phase` MCP tool so operators
can move phases without hand-assembling tool-call arguments. Paired
with `/vibeflow:status` for inspection.

## Usage

```
/vibeflow:advance <TARGET_PHASE> [humanOverrideNote="..."]
```

Arguments:

- `TARGET_PHASE` (required): one of `REQUIREMENTS`, `DESIGN`,
  `ARCHITECTURE`, `PLANNING`, `DEVELOPMENT`, `TESTING`,
  `DEPLOYMENT`. Case-insensitive; the skill uppercases it
  before the tool call.
- `humanOverrideNote="<reason>"` (optional): operator-supplied
  justification when advancing under a HUMAN_APPROVAL_REQUIRED
  consensus verdict (Sprint 17-C). The note is written to the
  `phase_advanced` event payload and surfaced on subsequent
  SessionStart calls by `load-sdlc-context.sh`.

Examples:

```
/vibeflow:advance DESIGN
/vibeflow:advance DESIGN humanOverrideNote="YÖS tier resolved offline with Legal"
/vibeflow:advance design              # case-insensitive; uppercased for you
```

## Process

### Step 1: Resolve projectId

Read `vibeflow.config.json` from the current working directory.
The `project` field is the MCP-tool's `projectId` argument. If
the file is missing, emit:

```
Not a VibeFlow project — vibeflow.config.json not found.
Run /vibeflow:init first.
```

and stop.

### Step 2: Validate the target phase

Uppercase the argument. If it doesn't match one of the seven
phase names above, emit a list of valid phases and stop.
Double-advancing ("REQUIREMENTS → ARCHITECTURE" skipping DESIGN)
is a structural error the validator will reject — still let it
through to the tool call so the operator sees the exact
validator error.

### Step 3: Parse humanOverrideNote (optional)

Scan `$ARGUMENTS` for `humanOverrideNote="<anything>"` and
extract the quoted value. If absent, don't pass the field — the
MCP tool treats it as optional.

### Step 4: Invoke the MCP tool

Call `mcp__sdlc-engine__sdlc_advance_phase` with:

```json
{
  "projectId": "<from config>",
  "to": "<UPPERCASED target phase>",
  "humanOverrideNote": "<optional note>"
}
```

### Step 5: Surface the result

The tool returns one of two shapes:

**Success:**
```json
{
  "ok": true,
  "state": { "currentPhase": "DESIGN", "revision": 5, ... },
  "transition": { "ok": true, "errors": [] }
}
```
Print: `Advanced <from> → <to>. Revision now <N>.`

If `humanOverrideNote` was supplied, add:
`Audit event recorded with your override note; it will appear on next SessionStart.`

**Failure:**
```json
{
  "ok": false,
  "errors": ["Exit criteria not met for REQUIREMENTS: consensus.requirements.approved"],
  "state": { ... }
}
```
Print each error on its own line. For common errors, offer the
remediation:

- `consensus.<phase>.approved` missing → suggest running
  `/vibeflow:consensus-orchestrator` on the primary report
- `last consensus is NEEDS_REVISION / REJECTED` → suggest
  `/vibeflow:consensus-arbiter` or `/vibeflow:consensus-specialist`
  + `/vibeflow:apply-arbiter-patch`
- `testability.score>=60` / `coverage.met` / etc. → suggest the
  relevant analyzer skill to satisfy the gate

### Step 6: Follow-up suggestion

On success, print a one-liner naming the next expected step for
the new phase (e.g. "DESIGN: design-bridge + accessibility
checks. Try /vibeflow:status to see the new phase's exit
criteria.").

## Guardrails

- **No `force: true` from this skill.** Forcing a phase advance
  bypasses every exit-criterion check. That's intentionally
  left to direct MCP tool invocation — the operator has to
  type it out so the audit trail shows the explicit choice.
- **No implicit REQUIREMENTS advance.** If the project is at
  REQUIREMENTS with no consensus record, the tool rejects
  advance. Operator runs consensus-orchestrator explicitly.
- **humanOverrideNote only applies under HUMAN_APPROVAL_REQUIRED.**
  Passing the note on a fully-APPROVED advance is harmless
  (the engine only attaches it when the current consensus is
  HUMAN_APPROVAL_REQUIRED), but prefer omitting it for cleaner
  audit trails.

## See also

- `/vibeflow:status` — show current phase + missing exit criteria
- `/vibeflow:consensus-orchestrator` — satisfy `consensus.<phase>.approved`
- `/vibeflow:consensus-arbiter` / `/vibeflow:consensus-specialist` —
  resolve NEEDS_REVISION with diff-first patches
- docs/PHASE-BOUNDARIES.md — per-phase allowed paths + exit criteria
- docs/CONSENSUS-ITERATION.md — HUMAN_APPROVAL_REQUIRED flow
