<!--
VibeFlow — Executive Slide Deck
Format: slide-based Markdown (--- separators). Convert with Marp, Slidev,
reveal.js, or paste each slide into PowerPoint/Google Slides.
Each slide has speaker notes under "> Notes:".
Audience: leadership, sponsors, buyers. ~14 slides, ~15 min.
-->

# VibeFlow

## AI‑Orchestrated Software Delivery — with quality built in, not bolted on

**A Claude Code plugin that runs your full SDLC through multi‑AI consensus and truth‑validated requirements.**

v2.18.0 · 7 SDLC phases · 5 engines · self‑improving · 100% local

> Notes: One‑line pitch — VibeFlow turns "vibe coding" with AI into a governed, auditable delivery pipeline. It is shipping today (v2.18.0), not a concept.

---

# The problem

**AI writes code fast. It does not guarantee you shipped the right thing, safely.**

- **Ambiguous requirements** flow straight into code — defects are born in the PRD, not the IDE.
- **A single AI model** is confidently wrong; no second opinion, no audit trail.
- **Quality is an afterthought** — testing and release checks happen at the end, when fixes are expensive.
- **No memory** — teams re‑litigate the same review points sprint after sprint.

> Notes: The pain is not "can AI code?" — it obviously can. The pain is governance, correctness, and trust at delivery time. Frame this for a buyer who has already adopted AI coding and is now nervous about it.

---

# The cost of getting it wrong

- Requirements defects are **5–10× cheaper** to fix in the PRD than in production.
- A wrong release decision in a regulated domain (finance, health) is a **compliance event**, not a bug.
- Every "the AI said it was fine" with no record is **unauditable risk**.

**The bottleneck has moved from *writing* code to *trusting* it.**

> Notes: Keep this slide short and sharp. The number to anchor on is the cost‑of‑defect curve — everyone in the room intuitively knows it.

---

# Our solution

**VibeFlow governs the whole lifecycle — requirements to release — as one orchestrated, auditable loop.**

1. **Truth‑driven** — requirements are the source of truth. Untestable requirements *block* development.
2. **Consensus‑based** — every critical artifact is reviewed by **multiple AIs** (Claude + ChatGPT + Gemini), not one.
3. **Quality‑gated** — automated gates at every phase boundary; nothing advances on a hunch.
4. **Self‑improving** — the system learns from its own review history and tunes itself, safely.

> Notes: These are the four pillars. Everything else in the deck is evidence for one of them. Memorize this slide.

---

# The 7‑phase governed pipeline

| Phase | What VibeFlow guarantees |
|---|---|
| 1 · Requirements | Testability scored; ambiguity flagged; score < 60 blocks the build |
| 2 · Design | Wireframes, design tokens, accessibility checks |
| 3 · Architecture | Decision records (ADRs), 3‑AI vote, formal verification |
| 4 · Planning | Epic breakdown, dependency graph, test strategy |
| 5 · Development | Code with automatic quality gates on every commit |
| 6 · Testing | Coverage, mutation testing, chaos injection |
| 7 · Deployment | GO / CONDITIONAL / BLOCKED release decision + rollback |

**Each boundary is a gate. You always know why you advanced.**

> Notes: This is the "scope" slide — it shows VibeFlow is not a point tool. Don't read the table; let it land visually and emphasize the gate concept.

---

# What makes it different

| | Single‑AI coding tools | VibeFlow |
|---|---|---|
| Review | One model's opinion | **Multi‑AI consensus** with quorum |
| Requirements | Trusted as‑is | **Scored & gated** (testability) |
| Scope | Code generation | **Full SDLC**, 7 phases |
| Trust | "It looked right" | **Auditable decision trail** |
| Improvement | Static | **Learns & self‑tunes** (with auto‑revert) |
| Deployment | Your laptop / their cloud | **100% local**, no data leaves |

> Notes: This is the competitive slide. The two rows that close deals are "Multi‑AI consensus" and "100% local / no data leaves" — lead with whichever matters more to this specific buyer.

---

# Consensus you can trust — and audit

- Critical artifacts get **APPROVED / NEEDS_REVISION / REJECTED** by an AI panel.
- Disagreement triggers an **iterative negotiation loop** until the panel converges or a human is asked to decide.
- Every verdict is **recorded to disk** — a durable, reviewable history.
- When AIs can't agree, the status is explicit: **HUMAN_APPROVAL_REQUIRED** — never a silent pass.

**No black‑box "trust me." Every gate has a paper trail.**

> Notes: The phrase to use out loud is "no silent passes." Regulated buyers care enormously that the system escalates to a human instead of guessing.

---

# Built for regulated, high‑stakes domains

VibeFlow tunes its release bar to the domain's risk:

| Domain | GO threshold | Weighted toward |
|---|---|---|
| Healthcare | ≥ 95 | Test coverage (30%) |
| Financial | ≥ 90 | Invariants (25%) |
| E‑commerce | ≥ 85 | User‑acceptance (25%) |
| General | ≥ 80 | Balanced |

**A healthcare release and a marketing‑site release are not held to the same bar — and shouldn't be.**

> Notes: This is the slide that differentiates VibeFlow for serious industries. The point: governance is risk‑proportional, configurable, and defensible to an auditor.

---

# It gets better the more you use it

VibeFlow closes a **learning loop** most tools never attempt:

- Mines its own consensus history for recurring problems and slow‑converging phases.
- **Remembers** resolved review points so reviewers stop repeating themselves.
- **Auto‑tunes** its own configuration — within strict, allow‑listed bounds.
- **Auto‑reverts** any change that makes outcomes worse, and learns to stop trying it.
- Optionally shares **privacy‑safe** signals across projects (no code, no content — ever).

**Safe autonomy: it can act on its own, but it can always undo itself.**

> Notes: This is the "moat" slide. Emphasize the safety rails — bounded, allow‑listed, auto‑reverting. Autonomy without a kill switch scares buyers; autonomy *with* one excites them.

---

# Your IP never leaves the building

- Runs **entirely on the developer's machine / your CI** — it's a plugin, not a SaaS.
- State is **plain files in your repo** — versioned by Git, owned by you, fully portable.
- **No external database, no vendor lock‑in, no telemetry** by default.
- Cross‑project learning, when enabled, shares only **one‑way hashes and outcomes** — never source, file names, or content.

> Notes: For security‑conscious or IP‑sensitive orgs, this is often the deciding slide. "It's a plugin, your files, your Git" removes the procurement/security‑review barrier that kills most AI‑tool deals.

---

# Proof: this is real and hardened

- **v2.18.0 shipped** — 30 engineering sprints, feature‑complete autonomous‑loop arc.
- **2,943 automated tests** across **30 test layers**, green on every release.
- **40+ specialized skills**, **5 analysis engines**, **9 AI sub‑agents**.
- Validated against real sample projects end‑to‑end (demo apps included).

**This is a maturing product with a test discipline most internal tools never reach.**

> Notes: Credibility slide. The 2,943‑tests number does a lot of work — it signals this isn't a weekend prototype. Mention the sample projects so they know it runs end‑to‑end.

---

# Where it pays off

- **Fewer escaped defects** — caught at the PRD, not in production.
- **Faster, defensible release decisions** — GO/BLOCKED with evidence, not debate.
- **Lower review fatigue** — the system remembers, so your people don't repeat.
- **Audit‑ready by default** — every gate and verdict is on disk.
- **Compounding returns** — it tunes itself, so month 6 is better than month 1.

> Notes: This is the ROI slide — translate features into outcomes a sponsor reports upward. Pick the two outcomes that match this org's stated pain.

---

# Where it fits today

- **Best fit:** AI‑assisted teams that need **governance, auditability, and quality gates** — especially in regulated or high‑stakes domains.
- **Deploys as:** a Claude Code plugin — install in minutes, no infrastructure.
- **Adopt incrementally:** start at any single phase (e.g. PRD quality scoring), expand to the full loop.

**Low‑risk entry, high‑ceiling value.**

> Notes: Lower the perceived adoption cost. The message: you don't have to swallow all 7 phases on day one — land with PRD scoring or release decisions and grow.

---

# Summary & next steps

**VibeFlow makes AI‑driven delivery *governable*: truth‑validated, multi‑AI reviewed, quality‑gated, self‑improving — and 100% yours.**

**Proposed next steps:**
1. 30‑minute live walkthrough on one of your real PRDs.
2. Pilot on a single phase (PRD quality or release decision).
3. Define success metrics (escaped‑defect rate, release‑decision time).

> Notes: Always close with a concrete, low‑commitment ask. The live walkthrough on *their* PRD is the highest‑converting next step — it makes the value tangible in minutes.
