# The ARCHITECTURE phase — author, then validate

Like DESIGN, ARCHITECTURE needs an artifact *authored* before it can be
reviewed. `architecture-validator` **validates** `docs/architecture.md` (its
hard precondition is that the doc exists and is non-empty) — but on a greenfield
project nothing authors it. `/vibeflow:architecture-bootstrap` is the
author-side guide (the counterpart to `design-bootstrap`).

## One command

```
/vibeflow:architecture-bootstrap
```

The logical architecture is largely fixed by the PRD (modules, flows, entities,
the domain's mandated controls). The genuinely open, **expensive-to-change**
fork is the technology + deployment baseline — so the skill **asks** rather than
inventing it:

| # | Baseline | What it documents |
|---|---|---|
| 1 | **Propose sensible defaults** | A domain-appropriate, cloud-native baseline (region, gateway + services, datastore, audit/event log, authn, cross-platform per `platform`), each as a **revisitable ADR** |
| 2 | **You specify the stack** | Exactly the language/framework, cloud, datastore, mobile approach you give |
| 3 | **Stack-agnostic** | Logical/component architecture + integration contracts + security/NFRs + structural ADRs only; defers concrete vendor/language to a later technical-design pass |

Whichever you pick, it authors:

- **`docs/architecture.md`** (the primary the validator + consensus review) —
  context/drivers, logical/component architecture with boundaries, data model,
  integration contracts (incl. external/licensed partners), a **domain-policy-aware
  security & privacy architecture**, NFRs, the deployment baseline, and a
  requirements trace.
- **`docs/adr/ADR-NNN-<slug>.md`** — one revisitable ADR per consequential
  decision (datastore, orchestration, security model, deployment, …).

Then it arms the consensus marker and emits:

```
▶ Next: /vibeflow:phase-runner
```

which runs `architecture-validator` on the doc, then cross-AI consensus, then
advances on APPROVED. `adr.recorded` + `consensus.architecture.approved` are
the exit criteria.

## Why "domain-policy-aware" matters

`architecture-validator` blocks advance on `criticalPolicyViolations` and
flags any domain policy the architecture is **silent** on. For a `financial`
product that means: at-rest encryption (per-tenant envelope / KMS), PII
redaction in logs, immutable audit / event logging (WORM + anchoring), row-level
isolation (RLS, no bypass), time integrity (NTP), fail-closed secrets, and a
kill-switch for autonomous actions. `architecture-bootstrap` covers these
head-on so the validator finds an architecture that *addresses* the policies,
not one that's silent on them — fewer round-trips to APPROVED.

## Where it fits

```
DESIGN ──advance──▶ ARCHITECTURE
                      │
                      ├─ /vibeflow:architecture-bootstrap  (author: ask baseline → docs/architecture.md + ADRs)
                      ├─ /vibeflow:phase-runner             (architecture-validator → consensus on docs/architecture.md)
                      └─ adr.recorded + consensus.architecture.approved ──advance──▶ PLANNING
```

> **phase-runner runs analyzers as skills, not agents.** `architecture-validator`
> (and the PLANNING/TESTING analyzers) are model-invocable **skills** —
> phase-runner invokes them with the Skill tool / `/vibeflow:<name>`, never by
> spawning a general-purpose or Explore agent (which would return codebase
> exploration, not the validation, and silently skip the policy gate). Fixed in
> v2.25.0.
