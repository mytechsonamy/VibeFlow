# Rule Extraction — Patterns, Priority Defaults, Disambiguation

This file is the source of truth for Step 1 and Step 2 of the
`business-rule-validator` skill. Everything here is mechanical — the
skill must not invent patterns or bend priorities.

---

## Pattern tiers

### Tier 1 — RFC 2119 keywords
Strongest signal. Any sentence containing one of these uppercase
keywords in the PRD is a candidate rule:

| Keyword | Normalized verb |
|---------|-----------------|
| MUST / MUST NOT | MUST / MUST NOT |
| SHALL / SHALL NOT | MUST / MUST NOT |
| REQUIRED | MUST |
| SHOULD / SHOULD NOT | SHOULD / SHOULD NOT |
| RECOMMENDED | SHOULD |
| MAY | MAY |
| OPTIONAL | MAY |

Rules:
- Only the **uppercase** form counts. Lowercase "must" in prose is
  noise (too many false positives).
- If both "SHOULD" and "MUST" appear in the same sentence, split into
  two rules — the stronger clause usually carries the load-bearing
  requirement.
- Negations always produce a separate rule, never a condition on the
  positive one ("MUST NOT X WHEN Y" is one negated rule, not a
  conditional allowance).

### Tier 2 — Conditional imperatives
`if X then Y`, `when X, Y`, `upon X, Y must`. These rules are split
into `condition: X` and `action: Y` during normalization. The
imperative verb in the action clause determines the priority tier
(see priority defaults below).

### Tier 3 — Prohibition verbs
`cannot`, `never`, `not allowed`, `forbidden`, `disallowed`, `no one
may`. These are weaker because the same verbs also appear in prose —
the extractor needs the surrounding paragraph to confirm a rule is
being stated, not described.

Confidence cap for Tier 3 rules is 0.8 unless the paragraph is
explicitly labeled "Rules" or "Constraints" in the PRD table of
contents, in which case it rises to 0.9.

### Tier 4 — Domain trigger phrases
Each domain has extra phrases that count as rules in context:

| Domain | Trigger phrases |
|--------|-----------------|
| Financial | "balance", "limit", "authorized", "settlement", "reconcile", "audit trail" |
| E-Commerce | "out of stock", "oversold", "refund policy", "cart", "checkout", "promo" |
| Healthcare | "consent", "authorized clinician", "retention period", "PHI", "release of information" |
| General | none beyond the Universal tiers above |

Domain triggers fire only if a Tier 1/2/3 verb appears in the same
sentence — by themselves they're prose, not rules.

---

## Normalization shape

Every extracted candidate normalizes to the imperative form:

    <ACTOR> MUST <ACTION> WHEN <CONDITION>

Rules:
- Actor: the subject of the rule. If the PRD uses passive voice
  ("data is encrypted"), promote the implicit actor to an explicit
  one ("the system MUST encrypt data"). Log the promotion in the
  rule's `evidence` so reviewers can confirm.
- Action: one verb phrase. Multi-verb sentences get split (see
  BusinessRule rule: one rule per record).
- Condition: "always" if the rule is unconditional. Anything else
  must start with "WHEN".
- Negated verbs: `MUST NOT <action>` stays as one rule — do not
  rewrite to the positive with a negated condition.

---

## Priority defaults

The PRD always wins. If a section header or inline tag explicitly
sets `P0..P3`, honor it. Otherwise:

| Domain | Default priority for rules without an explicit tag |
|--------|-----------------|
| Financial | P0 for every Tier 1 rule, P1 for Tier 2, P2 for Tier 3/4 |
| Healthcare | P0 for every Tier 1 rule, P1 for Tier 2, P2 for Tier 3/4 |
| E-Commerce | P1 for Tier 1 rules unless payment/PII context → P0, P2 for Tier 2/3/4 |
| General | P1 for Tier 1, P2 for Tier 2, P3 for Tier 3/4 |

Manual overrides in `.vibeflow/artifacts/priority-hints.json` always
win, but the override must name the rule by `id` — bulk overrides
are not supported because they make the gate contract too squishy.

---

## Disambiguation rules

These edge cases bit us in the TruthLayer pilot and must be handled
explicitly:

- **Definitions vs. rules.** A sentence like "A session is defined
  as..." is a definition, not a rule. Definitions get recorded for
  glossary purposes only and never produce a `BR-NNNN`.
- **Non-functional requirements.** "The page MUST load in under
  200ms" is a rule with an action of `load in under 200ms` and no
  functional actor. Assign actor `performance` and keep the rule —
  these get picked up by performance-test pipelines later.
- **Requirements on the PRD itself.** "The PRD MUST be reviewed
  quarterly" is a process rule, not a product rule. Filter out
  every rule whose subject is the PRD / review / author.
- **Rules that reference future sections.** If a rule's condition
  says "as defined in Section X" and Section X is empty or missing,
  flag as an ambiguity-filter rejection (not a valid rule) — the
  PRD quality analyzer should have caught this already, but
  defense in depth.
- **Compound actors.** "Admins and users MUST..." splits into two
  rules with separate ids, not one multi-actor rule. Actor
  granularity is how `traceability-engine` maps rules to permission
  roles.
- **Repeated rules across sections.** See SKILL.md Step 3 —
  deduplicated by normalized string, with both source anchors
  preserved.

---

## What NOT to extract

- **Examples and rationale paragraphs.** "For example, when a user..."
  is illustrative, not prescriptive. Skip unless it contains an
  uppercase Tier 1 keyword (in which case the example is doing
  double duty and should probably be split out of the PRD).
- **Historical statements.** "The legacy system used to require..."
  are observations, not rules. No BR-NNNN.
- **Forward-looking commitments.** "In v2, we will add..." is roadmap,
  not requirements. Filter out any rule in a "Future Work" /
  "Roadmap" / "Out of Scope" section.
- **Direct quotes from external standards.** "PCI-DSS §3.4 requires..."
  is a reference, not a new rule. Record it once as evidence for a
  domain policy the `architecture-validator` will check, but do not
  promote it to `BR-NNNN` — the external standard owns the rule.
