---
name: ui-quality-rules
description: >
  UI quality rules enforced by design-guard. Use whenever creating or editing
  anything user-facing: templates, pages, components, i18n resources, CSS,
  status/badge logic, report labels, empty states, error or system messages.
  Requires the project's .design-guard/glossary.md as the canonical
  terminology source.
---

# design-guard — UI writing rules

Before touching any UI file, read `.design-guard/glossary.md` (and
`.design-guard/profile.md` if you haven't this session). If they don't
exist, run the design-guard-init skill first.

## Absolute rules (apply while writing — don't leave them to the auditor)

1. **No hardcoded user-visible strings.** Everything goes through the i18n
   layer — engine/system messages included.
2. **One concept = one term.** Status badges, domain concepts, and report
   labels use the glossary's canonical form. New concept? Add it to the
   glossary FIRST (and its banned variants to rules.json), then use it.
3. **Numbers/dates follow the display locale.** Input-format hints must
   match what the user sees on screen. ISO formats only in APIs and logs.
4. **Nav = noun, button = verb.**
5. **User-visible sequences start at 1.**
6. **Hashes/digests behind an ⓘ affordance** — truncated + copy button,
   full value in tooltip.
7. **Empty states = icon + one-line explanation + CTA.** Never a bare
   sentence in a blank page.
8. **Warning = severity color + next action.** Blocked states show
   progress (n/N tasks), not a bare red error.
9. **One primary button per view.** Secondary actions are outline/ghost.
10. **Monospace only for data** (numbers, codes, hashes) — not names or
    prose.
11. **The footer/trust line is standardized** — use the glossary's exact
    sentence, identical on every page.
12. **Demo/seed data tells one consistent scenario** — same period, same
    tenant labels, coherent amounts across pages.
13. **No internal-architecture jargon in user copy.** The glossary's
    "jargon → user language" table is binding.

## Process

- When the work is done, the Stop gate will require a design-auditor pass —
  run it yourself before declaring completion, fix 🔴 BLOCKER findings, and
  include the audit summary in your final report.
