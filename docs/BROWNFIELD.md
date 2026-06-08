# Using VibeFlow on a brownfield project

VibeFlow's SDLC starts at REQUIREMENTS, which assumes a requirements doc to
score. Greenfield projects bring a PRD. **Brownfield** projects already have
code — and you're almost never rebuilding the whole product, you're doing an
**increment** (a feature, refactor, bug-fix, migration). The on-ramp makes
VibeFlow understand the existing code first, then helps you define the
increment.

## The flow

```
1. /vibeflow:onboard            ← detects the existing code, writes a fingerprint,
                                  and (brownfield) breadcrumbs to brownfield-intake
2. /vibeflow:brownfield-intake  ← understands the repo + helps you define the increment
3. /vibeflow:prd-quality-analyzer docs/<increment>-requirements.md
4. /vibeflow:phase-runner       ← walks the SDLC, scoped to the increment
```

`onboard` notices the codebase and points you at `brownfield-intake` instead of
straight to `prd-quality-analyzer` (which expects a PRD that doesn't exist yet).

## What `brownfield-intake` does

**1 — Understands the code so you don't have to explain it.** It fingerprints
the repo via the `codebase-intel` MCP — languages, frameworks, test runners,
module layout (`ci_analyze_structure`), the import graph + cycles
(`ci_dependency_graph`), churn×complexity hotspots (`ci_find_hotspots`), and
tech-debt markers (`ci_tech_debt_scan`) — into
`.vibeflow/reports/codebase-fingerprint.md`. That's the context every later step
anchors to.

**2 — Asks how you want to define the work** (four ways, your choice):

| # | Path | You give | Best for |
|---|---|---|---|
| 1 | **Describe it** | plain-language intent | the fastest start — just say what you want |
| 2 | **Point to a doc** | a path to a requirements/spec/ticket file | you already wrote it down |
| 3 | **Guided Q&A** | answers to goal / change-type / area / acceptance | newcomers; the most structured |
| 4 | **From an issue** | a GitHub/GitLab issue (`gh`/`glab`) by number/URL, or pasted text | the work lives in your tracker |

**3 — Synthesizes a *code-anchored, increment-scoped* requirements doc**
(`docs/<increment>-requirements.md`): goal, explicit in/out scope, **which
modules it touches** (from the dependency graph), the patterns to follow, the
hotspots/debt it lands near, a **change-type classification** (UI / backend /
infra), functional + acceptance criteria, compatibility constraints, and risks.

**4 — Hands off** to `prd-quality-analyzer` → `phase-runner`, scoped to the
increment — not the whole product.

## Why the change-type classification matters

The increment's nature routes the later phases:

- **Backend / infra increment** → DESIGN is light (a *technical* note via
  `design-bootstrap` option 5, not UI), and the architecture is largely fixed by
  the existing code (`architecture-bootstrap` "stack-agnostic / incremental").
- **UI increment** → DESIGN is central (`design-bootstrap` Claude-native / Figma).

`brownfield-intake` states the classification + the phase implications up front,
so the SDLC walk isn't a surprise. (This is exactly what FlowBridge did by hand —
a backend "Faz 3" increment on a branch — now formalized.)

## Prerequisites

- The `codebase-intel` MCP loads with the plugin (no extra setup).
- For path 4: `gh` (GitHub) or `glab` (GitLab) on PATH if you want to pull an
  issue by number/URL; otherwise paste the ticket text.
