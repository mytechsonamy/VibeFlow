# Ticket Template

Shape of the tickets `test-result-analyzer` writes to
`bug-tickets.md`. A separate bot imports them into whatever
backlog tool the team uses (Linear, Jira, GitHub Issues);
this skill's only job is to emit a file the bot understands.

The template is frozen — changing a field here is a breaking
change for the downstream importer, handled with the same
discipline as the other frozen schemas in VibeFlow.

**Current ticket schema version: 1**

---

## 1. Field list

Every ticket has exactly these fields, in this order. Missing
fields cause the skill to block ticket emission for that
failure (the failure still appears in `test-results.md`, but
the `bug-tickets.md` line is not written).

- **id** — `BUG-YYYY-MM-DD-<short-hash>`
  - Stable across re-runs for the same root cause (see §3
    deduplication)
  - `<short-hash>` is the first 8 chars of the SHA-256 of
    `dedupKey`
- **dedupKey** — SHA-256 hex of
  `<testId>::<classification>::<errorSignature>`
  - `errorSignature` is the first line of the error message
    with numbers and UUIDs masked (`NUM`, `UUID`)
  - Used by Step 8 of the algorithm to match candidate
    tickets against existing history
- **title** — a single sentence, ≤ 100 chars, imperative past
  (e.g. "Checkout flow returned 500 when coupon was expired")
  - Title MUST NOT start with "Test failed" or "Test error" —
    those aren't bug titles, they're status updates
  - Title MUST NOT contain the testId — that belongs in the
    traceability section
- **severity** — one of `critical / high / medium / low`
  - Derived from the failure's priority:
    `P0 → critical`, `P1 → high`, `P2 → medium`, `P3 → low`
  - Projects CAN override via `test-strategy.md →
    ticketSeverityOverrides` but the override must map to
    a defined severity (no free-form values)
- **priority** — the raw test priority (`P0` / `P1` / `P2`
  / `P3`), preserved alongside severity for consumers that
  want the original signal
- **scenario** — the `SC-xxx` id (from `scenario-set.md`)
  - MANDATORY for ticket emission. A failure with no
    scenario link → no ticket (the failure still appears
    in `test-results.md` under `NEEDS_HUMAN_TRIAGE`)
- **requirement** — the PRD anchor from `rtm.md` (e.g.
  `PRD-§3.2`). Optional; missing when `rtm.md` is absent,
  in which case the report flags an `rtmGap`
- **occurrences** — array of `runId`s where this dedup key
  was observed. New tickets start with one entry, subsequent
  re-runs that match the dedup key append
- **firstSeenAt** — ISO timestamp of the FIRST run that
  surfaced this dedupKey
- **lastSeenAt** — ISO timestamp of the LATEST run that
  surfaced it
- **stepsToReproduce** — 1..N numbered steps, each a single
  imperative sentence
  - Extracted from the scenario's `steps` field when
    available; falls back to a terse "run the test: <testId>"
    when not
- **expected** — the scenario's `expected` field (plain text)
- **actual** — the error message + a one-line summary of what
  the system actually did
- **evidence** — array of pointers (file paths, stack trace
  refs, screenshot paths). At least one entry is required
  for ticket emission — a ticket with no evidence is not
  actionable
- **classification** — the taxonomy class id (`BUG` always for
  ticketed failures; lower classes never reach the ticket
  path)
- **confidence** — the classification confidence score
  (`[0, 1]`), always ≥ 0.7 for emitted tickets (the skill's
  gate contract downgrades `< 0.7` to `NEEDS_HUMAN_TRIAGE`)
- **source** — where the failure was ingested from (e.g.
  `uat-raw-report.md:123`)

---

## 2. Markdown shape

Every ticket is a single Markdown subsection in
`bug-tickets.md`. Parsers downstream match on the `##` header
+ the key-value bullet pairs. Keep the layout consistent — no
tabs, two-space indentation for continuations, no free-form
paragraphs interleaved with the bullet list.

```markdown
## BUG-2026-04-13-a4c9abcd
- **dedupKey**: `<64-char hex>`
- **title**: Checkout flow returned 500 when coupon was expired
- **severity**: critical
- **priority**: P0
- **scenario**: SC-112
- **requirement**: PRD-§3.2
- **occurrences**: 20260413-120000-a4c9, 20260413-140000-b7d2
- **firstSeenAt**: 2026-04-13T12:00:00Z
- **lastSeenAt**: 2026-04-13T14:00:00Z
- **classification**: BUG
- **confidence**: 0.88
- **source**: `uat-raw-report.md:123`

### Steps to reproduce
1. POST /api/checkout with a cart containing an expired promo code
2. Observe the response

### Expected
200 with `{ "status": "checkout_complete" }` body

### Actual
500 with empty body; stack trace in the server log points at
`src/pricing/promo.ts:42` (`undefined.discount`)

### Evidence
- `uat-raw-report.md#SC-112`
- `.vibeflow/artifacts/uat/20260413-120000/screenshots/SC-112-3.png`
- Stack trace: at line 1023 of per-step.jsonl
```

---

## 3. Deduplication

- **Stable `dedupKey`**: built at Step 7 of the algorithm.
  Two runs that produce the same error shape on the same
  test generate the same dedup key → the skill appends to
  `occurrences` instead of creating a new ticket.
- **Re-opened tickets**: a dedupKey that matches a ticket
  previously marked as `closed` in the external backlog
  (signaled by a `closed: true` line in the history file)
  produces a NEW ticket with `supersedes: <old-id>` — so the
  team can tell "regression of a closed bug" from "we forgot
  to close this". Same history file field controls both
  behaviours.
- **History is append-only**: `ticket-history.jsonl` is never
  rewritten. Each append records the event
  (`created` / `occurrence-added` / `closed` / `superseded`).

---

## 4. No-ticket conditions

The skill does NOT emit a ticket for a failure when any of
these is true — the failure still appears in
`test-results.md`, but `bug-tickets.md` stays clean:

1. Classification is NOT `BUG`. Only real bugs get tickets.
2. Classification is `BUG` but `confidence < 0.7`. The
   gate-contract downgrade to `NEEDS_HUMAN_TRIAGE` explicitly
   keeps low-confidence bugs off the backlog.
3. The failure has no `scenarioId`. Without scenario linkage,
   the ticket has no traceability — it would be a "find out
   yourself what this is" ticket, and those are worse than
   useless.
4. The failure has no evidence. A ticket with no evidence
   pointer is not actionable, and an unactionable ticket is
   backlog noise.
5. The failure matches an existing ticket's `dedupKey` AND
   that ticket's `occurrences` array already contains ≥ 50
   entries. At that point the ticket is a "this keeps
   happening" tracker, not a new bug — the skill stops
   appending after 50 to keep the history file sane.

---

## 5. What the template is NOT

- **Not a free-form writeup**. Everything is a structured
  field; reviewers parse the ticket automatically, not by
  reading prose.
- **Not a test failure log**. Bug tickets are about the SUT,
  not the test's own state. A test-defect failure never
  becomes a ticket here.
- **Not a metrics report**. Tickets are discrete events;
  aggregates and trends live in `learning-loop-engine`'s
  outputs.
- **Not a triage record**. When a human triages a ticket
  (accepts, assigns, closes), the update happens in the real
  backlog tool, not in this file. The history file only
  reflects events the SKILL observes (created / occurrence /
  reopen detected via supersedes).

---

## 6. Schema evolution

- Adding a field: append at the end of the list in §1, mark
  it optional for one schema version, then promote to
  required in the next version.
- Removing a field: mark `deprecated: true` in a version
  header and stop emitting it. Never delete the entry; old
  tickets still reference it.
- Changing the markdown shape: schema version bump (§8 at
  the top of this file).
- Every breaking change needs a concurrent update to the
  downstream importer bot and the integration harness
  sentinel that asserts ticket field presence.

---

## 7. Versioning contract

- **Schema version** lives at the top of this file.
- Every ticket writes its schema version into the
  `dedupKey`'s namespace: a v1 ticket and a v2 ticket with
  the same dedupKey hash are different tickets, because
  downstream consumers bucket by version.
- Historical tickets stay readable at their original version;
  the importer bot is responsible for knowing which version
  it's reading.
- Version bumps follow the VibeFlow governance discipline
  (retrospective on ≥10 runs + migration note + sentinel
  update). Silent schema edits fail CI.
