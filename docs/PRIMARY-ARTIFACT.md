# Primary Artifact — Marker Schema v2

Since Sprint 19 (v2.7.0), every auto-consensus marker written by a
VibeFlow analysis skill carries a `primaryArtifact` field naming the
**thing being reviewed** — the PRD, the ADR, the test strategy — and
an `evidence[]` array naming the analyzer reports that give
reviewers context. Before this refactor, the marker only carried the
analyzer's own report as `artifact`, and the consensus-orchestrator
piped that report into reviewer prompts — so the multi-AI panel
ended up reviewing the analyzer's **opinion** rather than the
project artifact itself.

## Marker schema v2

```json
{
  "primaryArtifact": "docs/FlowBridge_TR_SRS_v1_1.docx",
  "evidence": [
    ".vibeflow/reports/prd-quality-report.md",
    ".vibeflow/reports/prd-cost-avoidance.md"
  ],
  "artifact": ".vibeflow/reports/prd-quality-report.md",
  "requiredCommand": "/vibeflow:consensus-orchestrator docs/FlowBridge_TR_SRS_v1_1.docx",
  "createdAt": "<ISO-8601 UTC>",
  "createdBy": "prd-quality-analyzer"
}
```

| Field | Role |
|---|---|
| `primaryArtifact` | The file the reviewer panel actually reviews — the PRD, test-strategy.md, release-notes/X.Y.Z.md. This is the thing that decides whether the phase is done. |
| `evidence[]` | Analyzer report(s) passed as context only. Reviewers see a distilled summary, not the full report, so they focus on the primary. |
| `artifact` | **Legacy field retained for Sprint 16's `consensus-gate.sh` back-compat.** Points at the first evidence entry (the report). No hook change needed. |
| `requiredCommand` | Points at the orchestrator invoked on `primaryArtifact` (not on the report). |
| `createdAt` / `createdBy` | Unchanged from Sprint 16 marker. |

## Per-phase primary + evidence map

| Phase | Primary artifact | Evidence | Written by |
|---|---|---|---|
| REQUIREMENTS | `<PRD path from $ARGUMENTS>` (e.g. `docs/*.docx`) | `prd-quality-report.md`, `prd-cost-avoidance.md` | `prd-quality-analyzer` |
| DESIGN | `design/**` | (no analyzer ships) | — (operator runs consensus directly on the design spec) |
| ARCHITECTURE | `docs/architecture.md` | `architecture-report.md` | `architecture-validator` |
| PLANNING | `.vibeflow/reports/test-strategy.md` | `scenario-set.md`, `rtm.md`, `prd-quality-report.md` | `test-strategy-planner` |
| PLANNING (RTM pass) | `.vibeflow/reports/rtm.md` | `prd-quality-report.md`, `test-strategy.md` | `traceability-engine` |
| TESTING (coverage) | `.vibeflow/reports/coverage-report.md` | `coverage-report.md`, `mutation-report.md`, `rtm.md` | `coverage-analyzer` |
| TESTING (mutation) | `.vibeflow/reports/mutation-report.md` | `mutation-report.md`, `coverage-report.md`, `weak-assertions.md` | `mutation-test-runner` |
| DEPLOYMENT (decision) | `.vibeflow/reports/release-decision.md` | `release-decision.md`, `coverage-report.md`, `mutation-report.md`, `deploy-verification.md` | `release-decision-engine` |
| DEPLOYMENT (verify) | `release-notes/<version>.md` | `deploy-verification.md`, `release-decision.md` | `deploy-verifier` |

## Orchestrator behaviour

`consensus-orchestrator` resolves the incoming path:

- **Marker JSON** (has `.primaryArtifact` field): extract
  `primaryArtifact` + `evidence[]`. Reviewer prompt embeds the
  primary directly + a distilled summary per evidence entry.
- **Legacy single file** (no marker JSON): treat the path as the
  primary. No evidence context. Pre-v2.7.0 invocations keep
  working.

Reviewer prompt structure:

```
[base review instructions]

PRIMARY ARTIFACT UNDER REVIEW (verdict is about THIS document):
<content of primary — head + tail + findings-anchored excerpts if >30k tokens>

SUPPORTING EVIDENCE (analyzer context — informational only):
1. <evidence[0] name>: <top-3 findings distilled>
2. <evidence[1] name>: <summary>
…

Your verdict decides whether the PRIMARY ARTIFACT is ready for phase exit.
```

## Backward compatibility

- **Pre-v2.7.0 markers** (only `artifact` + `requiredCommand`): the
  orchestrator falls back to treating `artifact` as the primary.
- **`consensus-gate.sh` (Sprint 16)** reads only `artifact` +
  `requiredCommand`. Both remain in marker v2, so the hook's block
  message continues to point the operator at the right command
  without any hook change.
- **Arbiter + specialist** target `suggestions[].target.file` in
  reviewer output, which already names the primary artifact when
  reviewers are actually looking at it. No schema change on the
  reviewer side.

## Evidence distillation

When the orchestrator builds the reviewer prompt, large evidence
reports get distilled to ≤500 tokens each:

- Top heading + verdict line
- Top-3 critical / ambiguity / conflict entries (ordered by
  severity field if present)
- Any `Summary` / `Aggregate` section

The full evidence files stay on disk so the specialist can read
them directly when producing rewrites.

## Primary > 30k tokens

PRDs and architecture docs can run 20-50k lines. The orchestrator
passes:

- First ~40% of the document (sections up to ~12k tokens)
- Last ~15% (release notes, change log sections)
- Findings-anchored excerpts: each evidence entry's top finding is
  cross-referenced with the primary via `target.file` +
  `target.line_range`; the orchestrator pulls ±20 lines around
  each anchor

Specialists still receive the full file as input on the
diff-first patch path — so rewrites see the whole artifact, just
reviewers see a distilled excerpt.

## See also

- `skills/consensus-orchestrator/SKILL.md` — Step 3 marker
  resolution + prompt composition
- `docs/CONSENSUS-FLOW.md` — Layer-1 diagram update (review
  target is primary, evidence is context)
- `docs/CONSENSUS-ITERATION.md` — multi-round iteration flow
- `hooks/scripts/consensus-gate.sh` — unchanged; reads `artifact`
  + `requiredCommand` fields that stay present in v2 markers
