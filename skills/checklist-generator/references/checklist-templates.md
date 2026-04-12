# Checklist Templates

The `checklist-generator` skill assembles every checklist by merging
three layers:

1. **Context base** — the default items for the requested review
   context (`pr-review`, `release`, `feature`, `accessibility`).
2. **Platform additions** — items that only make sense on `web`,
   `mobile`, or `backend`.
3. **Domain overlay** — extra items per domain (financial, e-commerce,
   healthcare); `general` adds nothing.

Each entry below is a list of catalog ids — **not the items themselves**.
The atomic items live in `item-catalog.md` and must exist before the
template can reference them. A template pointing at a missing catalog
id blocks the skill run; the error surfaces the specific id.

Order within each list is the **execution order**. Reviewers work
top-down; highest-leverage items first. Never reorder without
updating the template file — the skill preserves order verbatim.

---

## Context: `pr-review`

### Base (any platform)
- CL-PR-001 — Pull the branch and verify it builds locally
- CL-PR-002 — Unit test suite runs green on the PR branch
- CL-PR-003 — Changed files reviewed line by line
- CL-PR-004 — Commit messages follow the conventional-commit format
- CL-PR-005 — Tests added for every new code path (or justified skip)
- CL-PR-006 — No new `any` type escapes TypeScript annotations
- CL-PR-007 — No new TODO/FIXME introduced without a ticket link

### Platform: `web`
- CL-PR-WEB-001 — Visual diff vs the Figma frame in design-bridge
- CL-PR-WEB-002 — Accessibility score (axe-core) did not regress
- CL-PR-WEB-003 — Bundle size delta is within the declared budget

### Platform: `mobile`
- CL-PR-MOB-001 — App launches on the minimum supported OS version
- CL-PR-MOB-002 — Cold-start time stayed within the declared budget
- CL-PR-MOB-003 — Offline mode still works for the affected flows

### Platform: `backend`
- CL-PR-BE-001 — Migration is forward AND backward safe
- CL-PR-BE-002 — New endpoints have contract-test-writer output
- CL-PR-BE-003 — Observability hooks (log + trace) are present
- CL-PR-BE-004 — Load-test delta within the declared budget

---

## Context: `release`

### Base (any platform)
- CL-REL-001 — Release decision from release-decision-engine is GO or CONDITIONAL with mitigations
- CL-REL-002 — Every P0 business rule has a passing test (business-rule-validator gate green)
- CL-REL-003 — Every P0 invariant is formalized and cross-checks pass (invariant-formalizer gate green)
- CL-REL-004 — Traceability matrix shows 100% P0 requirement coverage
- CL-REL-005 — Changelog is human-readable and lists every user-visible change
- CL-REL-006 — Rollback plan is documented and the rollback command has been dry-run
- CL-REL-007 — On-call schedule for the release window is confirmed

### Platform: `web`
- CL-REL-WEB-001 — CDN cache invalidation plan is in place
- CL-REL-WEB-002 — Feature-flag default state has been confirmed
- CL-REL-WEB-003 — Synthetic monitoring for the new paths is wired up

### Platform: `mobile`
- CL-REL-MOB-001 — App-store review notes prepared
- CL-REL-MOB-002 — Previous app version still receives critical server support (no server-side break)
- CL-REL-MOB-003 — Forced-upgrade path tested (if the release breaks wire compat)

### Platform: `backend`
- CL-REL-BE-001 — DB migration executed on staging with production-scale data
- CL-REL-BE-002 — Canary deploy planned for the first 5% of traffic
- CL-REL-BE-003 — Error budget has enough headroom for the release window

---

## Context: `feature`

### Base (any platform)
- CL-FT-001 — Feature addresses a named requirement from the PRD (no scope creep)
- CL-FT-002 — Acceptance criteria from the PRD each have a passing test
- CL-FT-003 — Feature flag wraps the entire new surface area (opt-in rollout)
- CL-FT-004 — Failure modes are documented (what happens when deps are down)
- CL-FT-005 — User-visible strings are localized (or flagged as English-only)
- CL-FT-006 — New documentation is checked in next to the code
- CL-FT-007 — Empty-state and zero-data flows handled

### Platform: `web`
- CL-FT-WEB-001 — Mobile-responsive layout verified at 360px / 768px / 1440px
- CL-FT-WEB-002 — Keyboard navigation works for every interactive element
- CL-FT-WEB-003 — Loading / error / success states each have a visual treatment

### Platform: `mobile`
- CL-FT-MOB-001 — Feature behaves on a low-end device (not just a flagship)
- CL-FT-MOB-002 — Deep links to the feature work from a cold start
- CL-FT-MOB-003 — Push notification strings (if any) are localized

### Platform: `backend`
- CL-FT-BE-001 — API changes have contract-test-writer output
- CL-FT-BE-002 — Every new error code is documented in the error catalog
- CL-FT-BE-003 — Rate limits tested for the new endpoints

---

## Context: `accessibility`

### Base (platform-agnostic items intentionally minimal — accessibility is platform-specific)
- CL-A11Y-001 — The change has an explicit accessibility acceptance criterion
- CL-A11Y-002 — All new icons and graphics have a text alternative
- CL-A11Y-003 — Contrast ratios meet WCAG AA for every new color pair

### Platform: `web`
- CL-A11Y-WEB-001 — Every form field has a programmatically-associated label
- CL-A11Y-WEB-002 — Focus order is logical (tab through verifies visually)
- CL-A11Y-WEB-003 — ARIA roles added only when the semantic HTML doesn't express the role
- CL-A11Y-WEB-004 — Screen-reader walk-through of the new flow in NVDA AND VoiceOver
- CL-A11Y-WEB-005 — Reduced-motion preference respected for animations
- CL-A11Y-WEB-006 — Landmarks (`main`, `nav`, `aside`) are correctly nested
- CL-A11Y-WEB-007 — Live regions announce changes at the right politeness level

### Platform: `mobile`
- CL-A11Y-MOB-001 — Every tappable element meets minimum 44x44 dp hit target
- CL-A11Y-MOB-002 — Accessibility labels exist on every interactive element (iOS accessibilityLabel, Android contentDescription)
- CL-A11Y-MOB-003 — Dynamic-type resize tested at 200% without clipping
- CL-A11Y-MOB-004 — VoiceOver / TalkBack walk-through of the new flow
- CL-A11Y-MOB-005 — Reduced-motion preference respected for animations

### Platform: `backend` — **NOT APPLICABLE**
The skill refuses the `accessibility / backend` combination outright
in Step 1's preconditions.

---

## Domain overlays

### Financial
- CL-FIN-001 — Transaction-path changes include a double-entry reconciliation test
- CL-FIN-002 — Monetary fields use the declared decimal type (never float)
- CL-FIN-003 — Audit log entries are produced for every new mutation path
- CL-FIN-004 — Dual-control flow verified for high-value transactions

### E-commerce
- CL-ECOM-001 — Order-placement idempotency key verified end-to-end
- CL-ECOM-002 — Inventory consistency checked under concurrent writes
- CL-ECOM-003 — PII fields retention policy is unchanged (or diff reviewed)
- CL-ECOM-004 — Payment flow still routes through the PCI boundary

### Healthcare
- CL-HLTH-001 — PHI access path produces an audit entry (actor + purpose + timestamp)
- CL-HLTH-002 — Consent state is read before every new data-use path
- CL-HLTH-003 — Retention/deletion policy is respected for the new data class
- CL-HLTH-004 — BAA reference exists for every new third-party processor

### General
No overlay items. `general` uses only the base + platform layers.

---

## Template maintenance

- **Every listed id must resolve to an item in `item-catalog.md`.**
  A template pointing at a missing id blocks the skill run; fix the
  catalog first.
- **Order is execution order.** Top-down. Never alphabetize.
- **When adding a new platform,** copy an existing platform's
  sub-lists as the starting point; do not auto-duplicate across
  platforms without thinking about which items are actually
  applicable. An item that applies everywhere belongs in the Base.
- **When adding a new context,** update this file, the skill's
  preconditions (Step 1), the `minP0(context)` floor in the
  verdict table, AND the integration harness sentinels.
