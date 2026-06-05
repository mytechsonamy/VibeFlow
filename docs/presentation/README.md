# VibeFlow — Presentation Kit

Ready‑to‑use materials for presenting VibeFlow (v2.18.0) to two audiences:
business/leadership and technical evaluators. Each audience gets a
**slide‑based deck** (to project) and a **narrative brief** (to hand out).

## Contents

| Document | Audience | Use | Length |
|---|---|---|---|
| [`EXECUTIVE-DECK.md`](EXECUTIVE-DECK.md) | Leadership, sponsors, buyers | Present (~15 min, 14 slides) | Slides |
| [`EXECUTIVE-BRIEF.md`](EXECUTIVE-BRIEF.md) | Leadership, sponsors, buyers | Leave‑behind | ~6 min read |
| [`TECHNICAL-DECK.md`](TECHNICAL-DECK.md) | Architects, senior engineers, CTOs | Present (~25 min, 18 slides) | Slides |
| [`TECHNICAL-BRIEF.md`](TECHNICAL-BRIEF.md) | Architects, senior engineers, CTOs | Leave‑behind / evaluation | ~12 min read |
| [`ONE-PAGER.md`](ONE-PAGER.md) | Any | Email / first‑touch summary | 1 page |

## How to use the decks

The decks are **slide‑based Markdown** — each slide is separated by `---`,
with speaker notes under `> Notes:`. Convert to real slides with any of:

- **[Marp](https://marp.app/):** `marp EXECUTIVE-DECK.md -o deck.pptx` (or `--pdf`).
- **[Slidev](https://sli.dev/):** drop the slides into a Slidev project.
- **reveal.js / Pandoc:** `pandoc -t revealjs -s EXECUTIVE-DECK.md -o deck.html`.
- **PowerPoint / Google Slides:** paste each slide block onto a slide; the
  `> Notes:` lines go in the speaker‑notes pane.

> Tip: strip the `> Notes:` lines before sending slides to an external
> audience — they are for the presenter.

## Choosing what to present

- **First meeting with a business sponsor:** `ONE-PAGER.md` → `EXECUTIVE-DECK.md`,
  leave `EXECUTIVE-BRIEF.md`.
- **Technical evaluation / architecture review:** `TECHNICAL-DECK.md`,
  leave `TECHNICAL-BRIEF.md`.
- **Mixed room:** run the executive deck, keep the technical deck's
  consensus/learning‑loop/safety‑rails slides ready for deep‑dive questions.

## Source of truth

These materials summarize the product as of **v2.18.0**. For authoritative
detail, see the product docs: [`GETTING-STARTED.md`](../GETTING-STARTED.md),
[`CONSENSUS-FLOW.md`](../CONSENSUS-FLOW.md),
[`LEARNING-LOOP.md`](../LEARNING-LOOP.md),
[`AUTO-APPLY.md`](../AUTO-APPLY.md),
[`CROSS-PROJECT-LEARNING.md`](../CROSS-PROJECT-LEARNING.md), and the
top‑level `CLAUDE.md` / `ROADMAP.md`.
