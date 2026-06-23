# Operator choices — tappable decisions, not walls of text (Sprint 61)

VibeFlow pauses for an **operator decision** at several points: which design
source, how to define a brownfield increment, apply a patch or not, what to do
on a NEEDS_REVISION verdict, ship or fix at the merge point, … Historically each
skill printed a prose menu or a `[y/N]` prompt and expected you to **read the
findings and type** an answer.

That is slow on a phone. When you follow a run from Claude Code remote/web on
mobile, you scroll a wall of analysis and then thumb-type a reply. The fix:

> **Present every operator decision as tappable options.**

## The convention

When a skill needs an operator decision, it presents it with the built-in
**`AskUserQuestion`** tool instead of a free-text prompt:

- **2–4 options**, each a short **label** + a **one-line condensed rationale** in
  the description. Put the *why* — the relevant finding — in the option itself, so
  the operator can decide without scrolling the full report.
- The **recommended** option comes **first**, labelled `… (Recommended)`.
- **"Other" is automatic.** `AskUserQuestion` always appends an "Other" choice
  that lets the operator type a manual, free-form answer. So the structured form
  **never removes** the ability to type — it only adds one-tap shortcuts on top.
  Nothing is lost versus the old prose prompt; it is strictly better for
  remote/mobile.
- **Multi-decision steps** (e.g. onboarding asks domain + platform + risk) use a
  single `AskUserQuestion` call with multiple questions, so it's one interaction.

### What stays a typed prompt

Genuinely free-form inputs are **not** forced into options — they stay a normal
typed prompt (where the keyboard is the right tool anyway):

- a **project name**,
- a **file path** or an **issue URL**,
- a **prose description** of what to build.

For these, a skill may still offer a *choice of how to provide it* (e.g. "Describe
it / Point to a doc / From an issue") as options, then collect the actual text.

## Why this helps remote/mobile most

The whole point of Claude Code remote control is to keep a run moving from your
phone. Every place the run would otherwise **stall waiting for typed input**
becomes a **tap** — pick the recommended option and the SDLC advances, or pick
"Other" and type when you genuinely need to. Reviewing on the couch, you approve
or redirect with a thumb instead of composing sentences.

## Where it applies

The operator-blocking decision points across the skills, each surfaced as
options (the prose menu remains as the textual fallback):

| Skill | Decision surfaced as options |
|-------|------------------------------|
| `onboard` | domain · platform · risk tolerance (one multi-question call) |
| `brownfield-intake` | intake path: Describe / Point to a doc / Guided Q&A / From an issue |
| `design-bootstrap` | design source (Claude-native / Figma existing / Figma scratch / Both-compare / Technical) + the Both-compare pick |
| `architecture-bootstrap` | tech baseline: Propose defaults / Specify the stack / Stack-agnostic |
| `apply-arbiter-patch` | Apply / Dry-run / Skip (instead of `[y/N]`) |
| `phase-runner` | NEEDS_REVISION/REJECTED follow-up: Run specialist / Run arbiter / Apply patch / Stop |
| `integrate` | merge-point: Drive to DEPLOYMENT / Fix on feature stream / Stop |
| `release-decision-engine` | next action on GO / CONDITIONAL / BLOCKED |
| `learning-apply` | which lane / which recommendation to apply (when not `--yes`) |

### Terminal next-step breadcrumbs are tappable too (Sprint 63)

The same rule applies to a skill's **closing "Next step:" / "▶ Next:"
breadcrumb** when it implies a real action — don't leave it as prose the operator
must read and retype. The read-only status/dashboard views surface their next
action as a tappable choice (recommended first, always a **"Stay / do nothing"**
option, "Other" to type), and omit the card when there's nothing actionable:

| Read-only view | Next step surfaced as options |
|----------------|-------------------------------|
| `flow-status` | advance to `<next>` / fix branch-increment mismatch / run frontend-render-check / open streams — whichever the status surfaced · Stay |
| `loop-status` | remove a high-revert-rate key / run learning-apply / (cross-project recommendation, read-only) · Stay |
| `streams` | run integrate (merge point) / run phase-runner (continue a feature stream) / resolve a shared-branch conflict · Stay |

A read-only view that surfaces **no** actionable next step prints no card (it
still has nothing to decide). Picking an option just **launches** the named
command — these views never change state themselves.

## For skill authors

1. Add `AskUserQuestion` to the skill's `allowed-tools` frontmatter (skills are
   tool-gated; without it the tool can't be called).
2. At the decision point, add a short **"Operator choice"** instruction naming
   the options + their condensed rationales, and keep the existing prose menu
   right after it as the fallback rendering.
3. Lead with the recommended option; rely on the built-in "Other" for manual
   input — never tell the operator they can't type.
