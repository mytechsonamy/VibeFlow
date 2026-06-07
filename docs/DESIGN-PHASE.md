# The DESIGN phase — Claude-native or Figma

DESIGN is the one SDLC phase VibeFlow can't auto-analyze: a design has to be
*authored* before it can be reviewed. `/vibeflow:design-bootstrap` is the
author-side guide. It turns the approved PRD into the artifacts DESIGN
consensus reviews, and it lets you choose **how** the design gets made.

## One command

```
/vibeflow:design-bootstrap
```

It asks you which design source to use — **every run**, no forced default:

| # | Source | What it does | Needs |
|---|---|---|---|
| 1 | **Claude-native** | Generates an attractive, accessible UI spec + design tokens + wireframes from the PRD | nothing (zero setup) |
| 2 | **Figma (existing file)** | Pulls your Figma file via VibeFlow's `design-bridge` MCP → design tokens + `styles.css` + a spec referencing your frames | `FIGMA_TOKEN` + file URL |
| 3 | **Figma (from scratch)** | Designs from scratch in Figma via the **official** Figma MCP (`use_figma`) against a design system, then syncs back | the Figma MCP connected |

Whichever you pick, the **output is the same**: real files under `design/`
(`design-spec.md` is the primary the panel reviews) plus the consensus marker.
Then:

```
▶ Next: /vibeflow:phase-runner
```

runs cross-AI consensus on `design/design-spec.md` and advances on APPROVED.
`design.approved` + `accessibility.verified` stay operator-confirmed (a human
signs off the look + the a11y pass).

## Connecting Figma

You have two independent Figma paths; pick based on what you want.

### Option 2 — an existing Figma file (VibeFlow's `design-bridge` MCP)

Best when you already have designs in Figma and want VibeFlow to extract
tokens / styles and review them.

1. **Create a Figma personal access token:** Figma → Settings → Security →
   *Personal access tokens* → generate one with **File content: read**.
2. **Give it to the plugin:** set the plugin's `userConfig.figma_token` (it
   maps to the `FIGMA_TOKEN` env the `design-bridge` MCP reads — the token is
   never hardcoded). Restart Claude Code so the MCP picks it up.
3. Run `/vibeflow:design-bootstrap`, pick **2**, and paste your Figma file (or
   frame) URL. It's saved to `vibeflow.config.json` → `design.figmaFileUrl`
   for next time.

design-bridge then runs `db_fetch_design` (frames), `db_extract_tokens`
(colors / type / spacing with source node IDs), and `db_generate_styles`
(CSS custom properties + Tailwind) → `design/design-tokens.json` +
`design/styles.css` + `design/design-spec.md`.

### Option 3 — design from scratch (the official Figma MCP)

Best when you have a Figma account + design system and want to *create* the
screens in Figma. This uses the official Figma MCP (the `/figma-*` skills +
`use_figma`), not design-bridge. Connect the Figma MCP, then run
`/vibeflow:design-bootstrap` and pick **3** — it loads `/figma-use`, drives
`use_figma` to generate the screens against your design system, and syncs
screenshots + a spec back into `design/`.

## No Figma? Use Claude-native (option 1)

Zero setup. Claude generates a real design system from the PRD — a semantic
color palette (with dark mode), a type + spacing scale, per-screen layouts
with **all states** (empty / loading / error / success), responsive rules, and
a concrete WCAG 2.2 AA accessibility section — tuned to your domain (e.g.
calm + high-legibility for `financial`). It's the fastest path to a reviewable,
attractive design, and you can hand the spec + tokens to a designer later.

## Where it fits

```
REQUIREMENTS ──advance──▶ DESIGN
                           │
                           ├─ /vibeflow:design-bootstrap   (author: pick a source → design/ artifacts)
                           ├─ /vibeflow:phase-runner        (consensus on design/design-spec.md)
                           └─ sign off design.approved + accessibility.verified ──advance──▶ ARCHITECTURE
```

Related: `mcp-servers/design-bridge` (the Figma bridge MCP), the
`visual-ai-analyzer` skill (sees screenshots for layout / a11y / fidelity),
and `db_compare_impl` (dimension/byte compare of an implementation vs a
reference) — used later when DESIGN meets DEVELOPMENT.
