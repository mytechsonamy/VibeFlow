---
name: architecture-bootstrap
description: The ARCHITECTURE-phase author-side guide — the counterpart to design-bootstrap. architecture-validator VALIDATES docs/architecture.md but nothing authors it, so a greenfield ARCHITECTURE phase had no skill to produce the doc. This authors docs/architecture.md (logical/component architecture, data model, integration contracts, a domain-policy-aware security & privacy architecture, NFRs, deployment baseline) + one revisitable ADR per consequential decision, after ASKING the operator the technology/deployment baseline (propose sensible defaults / specify the stack / stack-agnostic). Then arms the consensus marker so architecture-validator + consensus review it. Use at the start of ARCHITECTURE.
disable-model-invocation: false
allowed-tools: Read Write AskUserQuestion Bash(mkdir *) Bash(jq *) Bash(ls *) mcp__codebase-intel__ci_dependency_graph mcp__codebase-intel__ci_analyze_structure
---

# Architecture Bootstrap

ARCHITECTURE has the same gap DESIGN had before `design-bootstrap`:
`architecture-validator` **validates** `docs/architecture.md` (its hard
precondition is that the doc "must exist and be non-empty") but **nothing
authors it**. On a greenfield project there's no architecture doc to validate,
so the phase stalls. This skill authors it — and the consequential, expensive
technology decisions get **asked**, never invented silently.

## Phase Contract

Runs in **ARCHITECTURE** only. Before anything else, read
`vibeflow.config.json`'s `currentPhase`. If it is not ARCHITECTURE, emit:

> architecture-bootstrap is for the ARCHITECTURE phase only; current is
> `<phase>`. Advance to ARCHITECTURE first (`/vibeflow:advance`).

…and stop. Writes are confined to `docs/**`, `contracts/**`,
`.vibeflow/reports/adr-*.md`, `*.d.ts`, `.vibeflow/**`, and
`vibeflow.config.json` (the ARCHITECTURE phase-write policy).

## Step 1: Resolve context

Read:
- `vibeflow.config.json` → `domain`, `platform`, `riskTolerance`, `project`.
- The **approved PRD** (REQUIREMENTS' primary) + `.vibeflow/reports/prd-quality-report.md`
  (the validator requires testability ≥ 60 — confirm it passed).
- The **approved design** (`design/design-spec.md` from DESIGN) — the
  architecture must serve it.
- Existing `docs/architecture.md` + `docs/adr/*.md` (re-runs refine, never
  clobber silently).
- **Brownfield only:** the current import graph via
  `mcp__codebase-intel__ci_dependency_graph` / `ci_analyze_structure`, so the
  authored architecture reflects (and constrains) the real code.

## Step 2: ASK the technology / deployment baseline (always)

The logical architecture is largely fixed by the PRD (modules, flows,
entities, the domain's mandated controls). The genuinely open, **expensive-to-change**
fork is the technology + deployment baseline — do **not** invent it silently.

**Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`).** Surface
the baseline with the **`AskUserQuestion`** tool as three tappable options
(header e.g. "Tech baseline"): Propose defaults (Recommended) / Specify the stack
/ Stack-agnostic, each with the one-line rationale below. "Other" lets the
operator type constraints directly (which feeds option 2). The prose menu below
is the textual fallback:

```
ARCHITECTURE baseline for <project> (domain=<domain>, platform=<platform>)?
The PRD fixes the logical architecture; what technology baseline do I document?

  1. Propose sensible defaults — I document a domain-appropriate, cloud-native
     baseline (region, gateway + services, datastore, audit/event log, authn,
     cross-platform per <platform>), each as a REVISITABLE ADR. Fast; change
     any ADR later.
  2. I'll specify the stack — you give language/framework, cloud, datastore,
     mobile approach; I document exactly that. Best if you have constraints.
  3. Stack-agnostic — logical/component architecture + integration contracts +
     security/NFRs + ADRs for structural decisions only; defer concrete
     vendor/language to a later technical-design pass. Lighter commitment.

Pick 1 / 2 / 3:
```

Whatever the operator picks, the **output is the same** (Step 4): a non-empty
`docs/architecture.md` + ADRs + the consensus marker.

## Step 3: Author the architecture

Write **`docs/architecture.md`** (the PRIMARY the validator + consensus
review). Make it concrete and decision-bearing, not a template:

- **Context + drivers** — the PRD goals, constraints, and the domain's
  regulatory drivers this architecture must satisfy.
- **Logical / component architecture** — services / modules, their
  responsibilities, and their **boundaries** (what each owns, what it must not
  touch). For a brownfield repo, reconcile with the real import graph.
- **Data model** — key entities, ownership, and the data-flow between
  components; tenancy model if multi-tenant.
- **Integration contracts** — internal APIs / events and **external**
  dependencies (for `financial`: licensed-partner execution, market-data, KYC,
  payment rails) with their trust boundaries.
- **Security & privacy architecture — domain-policy-aware (load-bearing).**
  `architecture-validator` blocks advance on `criticalPolicyViolations`, and it
  flags any domain policy the architecture is **silent** on. So address the
  domain's policy areas head-on. For `financial`, explicitly cover:
  at-rest encryption (per-tenant envelope / KMS), PII redaction in
  logs/telemetry, immutable audit / event logging (WORM + anchoring), row-level
  isolation (RLS + no bypass), time integrity (NTP), secrets handling
  (fail-closed), and a kill-switch / circuit-breaker for autonomous actions.
  Adapt the set for healthcare (PHI, consent, coverage) / e-commerce (PCI, UAT)
  / general. Name the controls — don't gesture at them.
- **Non-functional requirements** — performance, scalability, availability,
  observability, failure modes + degradation.
- **Deployment / infra baseline** — per the Step-2 choice (concrete for 1/2;
  deferred-with-rationale for 3).
- **Requirements trace** — map the major architecture decisions back to PRD
  requirements + the design, so nothing is unjustified.

And one **`docs/adr/ADR-NNN-<slug>.md`** per consequential structural decision
(datastore, orchestration model, security model, deployment, external-partner
strategy, …). Each ADR: `Status` (Proposed/Accepted), `Context`, `Decision`,
`Consequences`, `Alternatives considered`. Number them from ADR-001 (or
continue an existing series). They are **revisitable** — that's the point.

## Step 4: Arm consensus + breadcrumb

Announce the manual/auto criteria: `adr.recorded` is auto-satisfied by
`architecture-validator` when it accepts the ADRs;
`consensus.architecture.approved` comes from the consensus round.

Write `.vibeflow/state/consensus-needed.json` (marker schema v2) so consensus
reviews the architecture:

```json
{
  "primaryArtifact": "docs/architecture.md",
  "evidence": ["docs/adr/ADR-001-<slug>.md"],
  "artifact": "docs/architecture.md",
  "requiredCommand": "/vibeflow:phase-runner",
  "createdAt": "<UTC ISO-8601>",
  "createdBy": "architecture-bootstrap"
}
```

Then close with the breadcrumb as the **literal last line**:

```
▶ Next: /vibeflow:phase-runner
   (runs architecture-validator on docs/architecture.md, then cross-AI consensus, then advances on APPROVED)
```

## Output

- `docs/architecture.md` (primary)
- `docs/adr/ADR-NNN-<slug>.md` (one per consequential decision)
- `.vibeflow/state/consensus-needed.json` (arms ARCHITECTURE validation + consensus)

## Breadcrumb as a tappable card (Sprint 64)

**Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`).** When you
finish with a `▶ Next:` breadcrumb naming a single next command, also present it
as a tappable **`AskUserQuestion`** so the operator can advance with one tap from
a phone: **Run `<that command>` now (Recommended)** / **Not yet**. The built-in
"Other" lets them type a different command. Keep the literal `▶ Next:` line too
(it is the textual fallback). Skip the card only when the breadcrumb names no
runnable command (e.g. a plain "add tests" advisory).
