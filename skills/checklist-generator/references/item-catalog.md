# Item Catalog

Every row in this catalog is a single checkable item. The
`checklist-generator` skill assembles checklists by looking up ids
from `checklist-templates.md` here — it never invents items. If a
template references an id not in this file, the skill blocks with
remediation "add `<id>` to item-catalog.md before regenerating".

Every entry has:

- `id` — stable identifier; used in template references and in
  generated checklists
- `text` — the checkbox label the reviewer sees
- `verification` — the precise action to perform (imperative verb)
- `sourceOfTruth` — a concrete file, URL, or metric to check against
- `outcome` — the binary pass/fail condition
- `rationale` — one-line "why this matters"
- `priority` — P0 / P1 / P2
- `platform` — web / mobile / backend / all
- `context` — pr-review / release / feature / accessibility

**Verifiability contract.** Every entry MUST satisfy the Step 5
check in the skill algorithm: the verification verb must be
concrete, the source of truth must resolve, and the outcome must be
binary. The catalog is the place those qualities are enforced; if a
row can't meet the bar, it doesn't belong in the catalog.

---

## pr-review / base

### CL-PR-001
- **text**: Pull the branch and verify it builds locally
- **verification**: Run the project's declared build command (from `repo-fingerprint.json.buildTools`) on the PR branch
- **sourceOfTruth**: `repo-fingerprint.json` build command + CI job output
- **outcome**: Build exits 0
- **rationale**: Merge-blocker bugs often only show up off the author's machine
- **priority**: P0
- **platform**: all
- **context**: pr-review

### CL-PR-002
- **text**: Unit test suite runs green on the PR branch
- **verification**: Run the detected test runner (`vitest run` or `jest`) against the PR branch
- **sourceOfTruth**: test runner exit code + CI job output
- **outcome**: 0 failures, 0 skipped without a linked reason
- **rationale**: A green suite is the cheapest signal of structural correctness
- **priority**: P0
- **platform**: all
- **context**: pr-review

### CL-PR-003
- **text**: Changed files reviewed line by line
- **verification**: `git diff origin/main...HEAD -- <changed files>` walked top to bottom
- **sourceOfTruth**: the diff itself
- **outcome**: Every hunk has been inspected; comments filed for anything unclear
- **rationale**: Skimming is not reviewing
- **priority**: P0
- **platform**: all
- **context**: pr-review

### CL-PR-004
- **text**: Commit messages follow the conventional-commit format
- **verification**: `git log origin/main..HEAD --pretty=format:'%s' | grep -vE '^(feat|fix|chore|docs|test|refactor|style|perf|build|ci|revert)(\(.+\))?!?:'`
- **sourceOfTruth**: commit log
- **outcome**: grep returns no lines
- **rationale**: Changelog generation and `commit-guard.sh` both depend on the format
- **priority**: P1
- **platform**: all
- **context**: pr-review

### CL-PR-005
- **text**: Tests added for every new code path (or justified skip)
- **verification**: For each new function/class in the diff, locate a corresponding test case OR a comment linking to the skip rationale
- **sourceOfTruth**: diff + `src/**/*.test.*` files
- **outcome**: Every new path has either a test or a skip note
- **rationale**: Coverage debt in a PR compounds faster than anywhere else
- **priority**: P0
- **platform**: all
- **context**: pr-review

### CL-PR-006
- **text**: No new `any` type escapes TypeScript annotations
- **verification**: `git diff origin/main...HEAD -- '*.ts' '*.tsx' | grep ':\s*any\b'`
- **sourceOfTruth**: diff
- **outcome**: grep returns no lines
- **rationale**: `any` silently disables the type system; grows from tactical to structural
- **priority**: P1
- **platform**: backend, web
- **context**: pr-review

### CL-PR-007
- **text**: No new TODO/FIXME introduced without a ticket link
- **verification**: `git diff origin/main...HEAD | grep -E '\+(.*)(TODO|FIXME)(?!.*#[0-9]+)'`
- **sourceOfTruth**: diff
- **outcome**: grep returns no lines
- **rationale**: Untracked TODOs become permanent
- **priority**: P2
- **platform**: all
- **context**: pr-review

---

## pr-review / platform: web

### CL-PR-WEB-001
- **text**: Visual diff vs the Figma frame in design-bridge
- **verification**: Run `db_compare_impl` tool against the before/after screenshots
- **sourceOfTruth**: `db_compare_impl` verdict
- **outcome**: verdict is `identical` or `same-dimensions` with reviewer-accepted notes
- **rationale**: Design drift is cheaper to catch at PR time than after release
- **priority**: P1
- **platform**: web
- **context**: pr-review

### CL-PR-WEB-002
- **text**: Accessibility score (axe-core) did not regress
- **verification**: Run `axe-core` against the affected pages on the PR branch and on main
- **sourceOfTruth**: axe-core violation count per page
- **outcome**: PR branch count ≤ main branch count per page
- **rationale**: A11y regressions are invisible until a user with an AT reports them
- **priority**: P0
- **platform**: web
- **context**: pr-review

### CL-PR-WEB-003
- **text**: Bundle size delta is within the declared budget
- **verification**: Run the bundler's stats output on the PR branch and diff against main
- **sourceOfTruth**: bundler stats JSON
- **outcome**: delta ≤ budget in `performance-budget.json`
- **rationale**: Bundle bloat is a slow-moving UX regression
- **priority**: P1
- **platform**: web
- **context**: pr-review

---

## pr-review / platform: mobile

### CL-PR-MOB-001
- **text**: App launches on the minimum supported OS version
- **verification**: Boot a simulator/emulator at the minimum OS from the manifest and run the affected flow
- **sourceOfTruth**: minimum OS from `ios/Podfile` / `android/build.gradle`
- **outcome**: flow completes without a crash or a missing-symbol error
- **rationale**: "Works on my newest device" is how deprecation bugs ship
- **priority**: P0
- **platform**: mobile
- **context**: pr-review

### CL-PR-MOB-002
- **text**: Cold-start time stayed within the declared budget
- **verification**: Measure cold-start latency on the PR branch vs main
- **sourceOfTruth**: perf measurement tool output
- **outcome**: delta ≤ budget in `performance-budget.json`
- **rationale**: Cold start is the first-impression metric
- **priority**: P1
- **platform**: mobile
- **context**: pr-review

### CL-PR-MOB-003
- **text**: Offline mode still works for the affected flows
- **verification**: Toggle airplane mode and walk the affected flow end to end
- **sourceOfTruth**: reviewer's direct observation on the device
- **outcome**: flow completes with the documented offline-state UX
- **rationale**: Mobile users hit offline more often than they admit
- **priority**: P1
- **platform**: mobile
- **context**: pr-review

---

## pr-review / platform: backend

### CL-PR-BE-001
- **text**: Migration is forward AND backward safe
- **verification**: Apply migration on a staging DB snapshot, then `rollback` the migration, then `apply` again
- **sourceOfTruth**: migration tool output
- **outcome**: all three operations exit 0
- **rationale**: A forward-only migration is a production-incident-in-waiting
- **priority**: P0
- **platform**: backend
- **context**: pr-review

### CL-PR-BE-002
- **text**: New endpoints have contract-test-writer output
- **verification**: Locate the `@generated-by vibeflow:contract-test-writer` banner referencing each new endpoint
- **sourceOfTruth**: generated `contract.test.ts` files
- **outcome**: every new endpoint has at least one provider test case
- **rationale**: API drift is the largest source of consumer outages
- **priority**: P0
- **platform**: backend
- **context**: pr-review

### CL-PR-BE-003
- **text**: Observability hooks (log + trace) are present
- **verification**: For each new request path, verify a structured log line AND a trace span
- **sourceOfTruth**: diff + observability SDK usage sites
- **outcome**: every new path has both
- **rationale**: Silent services are un-debuggable
- **priority**: P1
- **platform**: backend
- **context**: pr-review

### CL-PR-BE-004
- **text**: Load-test delta within the declared budget
- **verification**: Run the project's declared load test on the PR branch; diff vs main
- **sourceOfTruth**: load test report
- **outcome**: p99 latency delta ≤ budget in `performance-budget.json`
- **rationale**: Performance regressions are hard to unship
- **priority**: P1
- **platform**: backend
- **context**: pr-review

---

## release / base

### CL-REL-001
- **text**: Release decision from release-decision-engine is GO or CONDITIONAL with mitigations
- **verification**: Inspect `.vibeflow/reports/release-decision.md`
- **sourceOfTruth**: release-decision.md
- **outcome**: verdict is `GO` or `CONDITIONAL` with every listed mitigation checked off
- **rationale**: The decision engine is the single aggregated signal
- **priority**: P0
- **platform**: all
- **context**: release

### CL-REL-002
- **text**: Every P0 business rule has a passing test
- **verification**: Inspect `business-rule-validator` gate status + test runner output for the BR suite
- **sourceOfTruth**: `business-rules.md` + test runner output
- **outcome**: `criticalGaps == 0` in the gap report
- **rationale**: An uncovered P0 rule is a known-unsafe release
- **priority**: P0
- **platform**: all
- **context**: release

### CL-REL-003
- **text**: Every P0 invariant is formalized and cross-checks pass
- **verification**: Inspect `invariant-formalizer` gate status + `invariant-matrix.md` cross-check column
- **sourceOfTruth**: invariant-matrix.md
- **outcome**: `unformalizedP0 == 0 && crossCheckFailures == 0`
- **rationale**: Cross-check failures mean factory and invariant disagree — data will surprise prod
- **priority**: P0
- **platform**: all
- **context**: release

### CL-REL-004
- **text**: Traceability matrix shows 100% P0 requirement coverage
- **verification**: Read the RTM generated by `traceability-engine`
- **sourceOfTruth**: `.vibeflow/reports/rtm.md`
- **outcome**: every P0 row has a linked test and passes
- **rationale**: The RTM is how we prove coverage to auditors AND to ourselves
- **priority**: P0
- **platform**: all
- **context**: release

### CL-REL-005
- **text**: Changelog is human-readable and lists every user-visible change
- **verification**: Compare the changelog entries to the commit log since the last tag
- **sourceOfTruth**: `CHANGELOG.md` + `git log`
- **outcome**: every user-visible commit since last tag has a changelog entry
- **rationale**: Users read changelogs to decide whether to upgrade
- **priority**: P1
- **platform**: all
- **context**: release

### CL-REL-006
- **text**: Rollback plan is documented and the rollback command has been dry-run
- **verification**: Execute the rollback command against the staging environment
- **sourceOfTruth**: runbook doc + staging environment state
- **outcome**: rollback completes successfully and the staging service is healthy after
- **rationale**: An untested rollback is a rollback that fails at 3am
- **priority**: P0
- **platform**: all
- **context**: release

### CL-REL-007
- **text**: On-call schedule for the release window is confirmed
- **verification**: Check the on-call rotation dashboard for the release time window
- **sourceOfTruth**: on-call dashboard
- **outcome**: primary + secondary are both assigned and have acknowledged
- **rationale**: Who-to-page matters most when the release breaks
- **priority**: P1
- **platform**: all
- **context**: release

---

## release / platform: web

### CL-REL-WEB-001
- **text**: CDN cache invalidation plan is in place
- **verification**: Inspect the release runbook for the invalidation step + test the command on staging CDN
- **sourceOfTruth**: runbook + staging CDN
- **outcome**: command runs and invalidates the expected paths
- **rationale**: Stale CDN caches are how "rolled back" releases still hit users
- **priority**: P0
- **platform**: web
- **context**: release

### CL-REL-WEB-002
- **text**: Feature-flag default state has been confirmed
- **verification**: Inspect the feature-flag service for the new flag's default
- **sourceOfTruth**: feature-flag service
- **outcome**: default matches the release plan (off for opt-in rollout, on for GA)
- **rationale**: Wrong defaults are the #1 rollout bug
- **priority**: P0
- **platform**: web
- **context**: release

### CL-REL-WEB-003
- **text**: Synthetic monitoring for the new paths is wired up
- **verification**: Inspect the synthetic monitoring service for probes covering the new paths
- **sourceOfTruth**: synthetic monitoring service
- **outcome**: probes exist, are scheduled, and produce green signals on the current build
- **rationale**: Unmonitored paths break silently
- **priority**: P1
- **platform**: web
- **context**: release

---

## release / platform: mobile

### CL-REL-MOB-001
- **text**: App-store review notes prepared
- **verification**: Inspect the release's App Store Connect / Play Console draft for reviewer notes
- **sourceOfTruth**: app store dashboards
- **outcome**: reviewer notes explain any non-obvious behavior, especially privacy
- **rationale**: Store reviewers reject releases with vague privacy copy
- **priority**: P1
- **platform**: mobile
- **context**: release

### CL-REL-MOB-002
- **text**: Previous app version still receives critical server support
- **verification**: Deploy the new backend and run the previous-version app against it
- **sourceOfTruth**: direct device testing
- **outcome**: core flows still work on the prior app version
- **rationale**: Mobile users update slowly; breaking them is unforgivable
- **priority**: P0
- **platform**: mobile
- **context**: release

### CL-REL-MOB-003
- **text**: Forced-upgrade path tested (if the release breaks wire compat)
- **verification**: Set the forced-upgrade server flag and verify the client's upgrade prompt appears on the prior version
- **sourceOfTruth**: direct device testing
- **outcome**: prior-version client shows the upgrade prompt and cannot proceed past it
- **rationale**: The emergency exit must work before you need it
- **priority**: P0 (if wire compat broke) / P2 (otherwise)
- **platform**: mobile
- **context**: release

---

## release / platform: backend

### CL-REL-BE-001
- **text**: DB migration executed on staging with production-scale data
- **verification**: Restore a recent production snapshot to staging, apply the migration, measure duration and locks
- **sourceOfTruth**: migration tool output + staging DB monitoring
- **outcome**: migration completes within the planned window; no unexpected lock contention
- **rationale**: Dev-sized data lies about production migration behavior
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-REL-BE-002
- **text**: Canary deploy planned for the first 5% of traffic
- **verification**: Inspect the deploy pipeline for the canary stage
- **sourceOfTruth**: deploy pipeline config
- **outcome**: canary stage exists, routes 5%, and has SLO-based rollback gates
- **rationale**: Rolling to 100% on faith is how tiny bugs become large outages
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-REL-BE-003
- **text**: Error budget has enough headroom for the release window
- **verification**: Read the SLO dashboard for the relevant service's error budget
- **sourceOfTruth**: SLO dashboard
- **outcome**: remaining budget > estimated release-window burn
- **rationale**: Releasing into a depleted budget compounds problems
- **priority**: P1
- **platform**: backend
- **context**: release

---

## feature / base, platforms, and accessibility / base, platforms

> **Note.** The feature and accessibility catalogs follow the same
> shape as the pr-review and release sections above. Full entries
> live in version-controlled branches of this file so the Sprint 2
> integration harness has something to validate. Keep every row
> self-contained: no row ships without text, verification, source
> of truth, outcome, rationale, priority, platform, and context.

### CL-FT-001
- **text**: Feature addresses a named requirement from the PRD (no scope creep)
- **verification**: Locate the PRD section id that motivates the change
- **sourceOfTruth**: PRD section anchor
- **outcome**: anchor exists and matches the change
- **rationale**: Scope creep is how features become maintenance burden
- **priority**: P0
- **platform**: all
- **context**: feature

### CL-FT-002
- **text**: Acceptance criteria from the PRD each have a passing test
- **verification**: Map each acceptance-criterion bullet in the PRD to a passing test
- **sourceOfTruth**: PRD + test runner output
- **outcome**: every criterion is linked and green
- **rationale**: Acceptance criteria are the only contract the author and the reviewer both signed
- **priority**: P0
- **platform**: all
- **context**: feature

### CL-FT-003
- **text**: Feature flag wraps the entire new surface area (opt-in rollout)
- **verification**: Grep the diff for the flag guard at every new entry point
- **sourceOfTruth**: diff + feature-flag SDK
- **outcome**: every new entry point is guarded
- **rationale**: Unflagged features can't be rolled back without a code revert
- **priority**: P0
- **platform**: all
- **context**: feature

### CL-FT-004
- **text**: Failure modes are documented
- **verification**: Inspect the feature's runbook or README for a "what happens when deps are down" section
- **sourceOfTruth**: feature runbook
- **outcome**: section exists and lists each dep with its degraded behavior
- **rationale**: On-call can't respond to an undocumented failure
- **priority**: P1
- **platform**: all
- **context**: feature

### CL-FT-005
- **text**: User-visible strings are localized (or flagged as English-only)
- **verification**: Locate every new user-visible string in the localization bundle
- **sourceOfTruth**: i18n bundle
- **outcome**: every string exists in the bundle OR is explicitly tagged `english-only`
- **rationale**: Accidental English strings ship as soon as the flag flips
- **priority**: P1
- **platform**: all
- **context**: feature

### CL-FT-006
- **text**: New documentation is checked in next to the code
- **verification**: Grep the PR diff for new `.md` files or README updates
- **sourceOfTruth**: diff
- **outcome**: at least one doc update exists for every non-trivial feature
- **rationale**: Code without docs is a lottery for the next reader
- **priority**: P2
- **platform**: all
- **context**: feature

### CL-FT-007
- **text**: Empty-state and zero-data flows handled
- **verification**: Walk the feature with zero data (empty db / empty list / new user)
- **sourceOfTruth**: direct observation
- **outcome**: empty-state UX is present and correct
- **rationale**: Empty states are the most common bug-report source in new features
- **priority**: P0
- **platform**: all
- **context**: feature

### CL-A11Y-001
- **text**: The change has an explicit accessibility acceptance criterion
- **verification**: Locate the a11y acceptance line in the PRD or feature brief
- **sourceOfTruth**: PRD / brief
- **outcome**: line exists and names specific behaviors
- **rationale**: "Make it accessible" is not an acceptance criterion
- **priority**: P0
- **platform**: all
- **context**: accessibility

### CL-A11Y-002
- **text**: All new icons and graphics have a text alternative
- **verification**: Inspect every new image/icon import for an alt text or label
- **sourceOfTruth**: diff
- **outcome**: every non-decorative image has alternative text
- **rationale**: Screen readers cannot describe pixels
- **priority**: P0
- **platform**: all
- **context**: accessibility

### CL-A11Y-003
- **text**: Contrast ratios meet WCAG AA for every new color pair
- **verification**: Measure contrast of every new foreground/background pair
- **sourceOfTruth**: color tokens + contrast checker output
- **outcome**: every pair meets ≥ 4.5:1 for normal text, ≥ 3:1 for large text
- **rationale**: Low contrast excludes users with low vision
- **priority**: P0
- **platform**: all
- **context**: accessibility

---

## feature / platform: web

### CL-FT-WEB-001
- **text**: Mobile-responsive layout verified at 360px / 768px / 1440px
- **verification**: Resize the browser (or use devtools device mode) to each breakpoint and walk the feature
- **sourceOfTruth**: direct observation
- **outcome**: layout is usable at every breakpoint; no clipped or overlapping elements
- **rationale**: One-breakpoint responsive is not responsive
- **priority**: P0
- **platform**: web
- **context**: feature

### CL-FT-WEB-002
- **text**: Keyboard navigation works for every interactive element
- **verification**: Tab through the feature's UI without a mouse
- **sourceOfTruth**: direct observation
- **outcome**: every interactive element is reachable and activates with Enter/Space
- **rationale**: Keyboard-only users are not a rounding error
- **priority**: P0
- **platform**: web
- **context**: feature

### CL-FT-WEB-003
- **text**: Loading / error / success states each have a visual treatment
- **verification**: Force each state (slow network, throw in handler, success) and observe the UI
- **sourceOfTruth**: direct observation
- **outcome**: each state renders a deliberate treatment, not a blank page or a stack trace
- **rationale**: Empty placeholders ship as "broken"
- **priority**: P1
- **platform**: web
- **context**: feature

## feature / platform: mobile

### CL-FT-MOB-001
- **text**: Feature behaves on a low-end device (not just a flagship)
- **verification**: Run the feature on an entry-level simulator/device matching the project's minimum supported tier
- **sourceOfTruth**: direct observation + perf trace
- **outcome**: feature is responsive; no frame drops > budget
- **rationale**: Flagship-only testing is how mobile apps get one-star reviews
- **priority**: P0
- **platform**: mobile
- **context**: feature

### CL-FT-MOB-002
- **text**: Deep links to the feature work from a cold start
- **verification**: Open the deep link from outside the app with the app fully killed
- **sourceOfTruth**: direct observation
- **outcome**: deep link opens the correct screen with the correct state
- **rationale**: Cold-start deep linking is the most commonly broken path in mobile apps
- **priority**: P1
- **platform**: mobile
- **context**: feature

### CL-FT-MOB-003
- **text**: Push notification strings (if any) are localized
- **verification**: Trigger every new push notification and inspect the delivered string
- **sourceOfTruth**: device notification center + i18n bundle
- **outcome**: every string is localized or explicitly english-only
- **rationale**: English-only pushes confuse non-English users instantly
- **priority**: P1
- **platform**: mobile
- **context**: feature

## feature / platform: backend

### CL-FT-BE-001
- **text**: API changes have contract-test-writer output
- **verification**: Locate the generated contract tests for every new or changed endpoint
- **sourceOfTruth**: generated `contract.test.ts` files
- **outcome**: every new/changed endpoint has generator output
- **rationale**: Consumer breakage is usually prevented at contract-test time
- **priority**: P0
- **platform**: backend
- **context**: feature

### CL-FT-BE-002
- **text**: Every new error code is documented in the error catalog
- **verification**: Diff the error catalog and verify it lists every new error class
- **sourceOfTruth**: error catalog file
- **outcome**: diff shows a new entry per new error
- **rationale**: Undocumented errors are undebuggable in production
- **priority**: P1
- **platform**: backend
- **context**: feature

### CL-FT-BE-003
- **text**: Rate limits tested for the new endpoints
- **verification**: Run a short load burst against each new endpoint and inspect the 429 rate
- **sourceOfTruth**: load test output + server metrics
- **outcome**: rate-limit kicks in at the declared threshold
- **rationale**: Unlimited endpoints are DoS amplifiers
- **priority**: P1
- **platform**: backend
- **context**: feature

---

## accessibility / platform: web

### CL-A11Y-WEB-001
- **text**: Every form field has a programmatically-associated label
- **verification**: Inspect each form field with devtools; verify an associated `<label>` or `aria-labelledby`
- **sourceOfTruth**: DOM tree
- **outcome**: every field has a label node reachable via the label-form association
- **rationale**: Unlabeled fields are unusable with a screen reader
- **priority**: P0
- **platform**: web
- **context**: accessibility

### CL-A11Y-WEB-002
- **text**: Focus order is logical (tab through verifies visually)
- **verification**: Tab from the first to the last focusable element and watch the focus ring
- **sourceOfTruth**: direct observation
- **outcome**: order matches the visual layout top-to-bottom, left-to-right
- **rationale**: DOM order drift from visual order is how a11y regressions hide
- **priority**: P0
- **platform**: web
- **context**: accessibility

### CL-A11Y-WEB-003
- **text**: ARIA roles added only when the semantic HTML doesn't express the role
- **verification**: Grep the diff for new `role=` attributes; verify each can't be replaced with a semantic element
- **sourceOfTruth**: diff + HTML spec
- **outcome**: no redundant roles
- **rationale**: Redundant roles override native semantics and usually break them
- **priority**: P1
- **platform**: web
- **context**: accessibility

### CL-A11Y-WEB-004
- **text**: Screen-reader walk-through of the new flow in NVDA AND VoiceOver
- **verification**: Run NVDA (Windows) and VoiceOver (macOS) through the feature end-to-end
- **sourceOfTruth**: direct observation
- **outcome**: every screen is navigable and every action is announced intelligibly
- **rationale**: Only real ATs expose real a11y bugs
- **priority**: P0
- **platform**: web
- **context**: accessibility

### CL-A11Y-WEB-005
- **text**: Reduced-motion preference respected for animations
- **verification**: Set `prefers-reduced-motion: reduce` and reload the feature
- **sourceOfTruth**: direct observation
- **outcome**: animations are disabled or reduced to instant transitions
- **rationale**: Vestibular disorders are triggered by motion some users cannot tolerate
- **priority**: P1
- **platform**: web
- **context**: accessibility

### CL-A11Y-WEB-006
- **text**: Landmarks are correctly nested
- **verification**: Inspect the DOM for `<main>`, `<nav>`, `<aside>` hierarchy
- **sourceOfTruth**: DOM tree
- **outcome**: exactly one `<main>`; navs and asides nested sensibly
- **rationale**: Landmark nav is how screen reader users skim a page
- **priority**: P1
- **platform**: web
- **context**: accessibility

### CL-A11Y-WEB-007
- **text**: Live regions announce changes at the right politeness level
- **verification**: Inspect every `aria-live` region's politeness and test with a screen reader
- **sourceOfTruth**: DOM + direct observation
- **outcome**: `assertive` only for critical alerts; `polite` for everything else
- **rationale**: Assertive live regions interrupt the user; misuse destroys trust in the feature
- **priority**: P1
- **platform**: web
- **context**: accessibility

## accessibility / platform: mobile

### CL-A11Y-MOB-001
- **text**: Every tappable element meets the minimum 44x44 dp hit target
- **verification**: Inspect the affected layouts with the accessibility inspector / axe
- **sourceOfTruth**: accessibility inspector
- **outcome**: every interactive element is ≥ 44x44 dp
- **rationale**: Smaller targets exclude users with motor impairments
- **priority**: P0
- **platform**: mobile
- **context**: accessibility

### CL-A11Y-MOB-002
- **text**: Accessibility labels exist on every interactive element
- **verification**: Inspect every new interactive element for `accessibilityLabel` (iOS) / `contentDescription` (Android)
- **sourceOfTruth**: platform accessibility inspectors
- **outcome**: every interactive element has a non-empty label
- **rationale**: Unlabeled controls are invisible to VoiceOver / TalkBack
- **priority**: P0
- **platform**: mobile
- **context**: accessibility

### CL-A11Y-MOB-003
- **text**: Dynamic-type resize tested at 200% without clipping
- **verification**: Set system font size to max and walk the feature
- **sourceOfTruth**: direct observation
- **outcome**: no clipped text; no truncated controls
- **rationale**: Users who enlarge fonts are the users who need them enlarged most
- **priority**: P0
- **platform**: mobile
- **context**: accessibility

### CL-A11Y-MOB-004
- **text**: VoiceOver / TalkBack walk-through of the new flow
- **verification**: Run the platform's screen reader through the feature end to end
- **sourceOfTruth**: direct observation
- **outcome**: every action is announced intelligibly; focus order is logical
- **rationale**: Real AT testing is the only a11y test that matters
- **priority**: P0
- **platform**: mobile
- **context**: accessibility

### CL-A11Y-MOB-005
- **text**: Reduced-motion preference respected for animations
- **verification**: Enable the platform's reduce-motion setting and reload the feature
- **sourceOfTruth**: direct observation
- **outcome**: animations are disabled or reduced
- **rationale**: Same rationale as the web version; mobile motion is often more aggressive
- **priority**: P1
- **platform**: mobile
- **context**: accessibility

---

## Domain overlay catalog

### CL-FIN-001
- **text**: Transaction-path changes include a double-entry reconciliation test
- **verification**: Locate a test that asserts `sum(credits) == sum(debits)` over the changed flow
- **sourceOfTruth**: test file + `invariant-matrix.md` (INV-FIN-DOUBLE-ENTRY)
- **outcome**: test exists and passes
- **rationale**: The double-entry invariant is the one every audit checks first
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-FIN-002
- **text**: Monetary fields use the declared decimal type (never float)
- **verification**: Grep the diff for `number` typed fields holding currency and check `invariant-matrix.md` for INV-FIN-PRECISION
- **sourceOfTruth**: diff + invariant matrix
- **outcome**: every monetary field uses `decimal` / `bigint` / string form
- **rationale**: Float precision is how real money goes missing
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-FIN-003
- **text**: Audit log entries are produced for every new mutation path
- **verification**: Locate the audit-log write site for each new mutation
- **sourceOfTruth**: diff + audit log sink
- **outcome**: every mutation path has a corresponding log write
- **rationale**: Unlogged mutations are untraceable in an incident
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-FIN-004
- **text**: Dual-control flow verified for high-value transactions
- **verification**: Attempt a high-value transaction as a single actor; assert rejection
- **sourceOfTruth**: direct test + business-rules.md INV-FIN-AUTH-LIMIT entry
- **outcome**: single-actor attempt is rejected; dual-actor attempt succeeds
- **rationale**: Dual control is the last line of defense against insider misuse
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-ECOM-001
- **text**: Order-placement idempotency key verified end-to-end
- **verification**: Send the same order twice with the same idempotency key and inspect the result
- **sourceOfTruth**: direct test + order service logs
- **outcome**: second call returns the first call's result; only one order is created
- **rationale**: Retries without idempotency cause double charges
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-ECOM-002
- **text**: Inventory consistency checked under concurrent writes
- **verification**: Hit the inventory write path concurrently with N simultaneous requests for the last unit
- **sourceOfTruth**: direct load test output + inventory counts
- **outcome**: at most one request succeeds; the rest are cleanly rejected
- **rationale**: Overselling is the #1 ecommerce trust-killer
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-ECOM-003
- **text**: PII fields retention policy is unchanged (or diff reviewed)
- **verification**: Diff the retention configuration and review every change with the privacy owner
- **sourceOfTruth**: retention config file + privacy owner sign-off
- **outcome**: no unreviewed diff
- **rationale**: Retention changes have regulatory exposure
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-ECOM-004
- **text**: Payment flow still routes through the PCI boundary
- **verification**: Trace a payment request from the entry point to the payment processor
- **sourceOfTruth**: trace output + architecture diagram
- **outcome**: payment data only touches PCI-boundary components
- **rationale**: A leaked payment field is an expensive incident
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-HLTH-001
- **text**: PHI access path produces an audit entry (actor + purpose + timestamp)
- **verification**: Read a PHI record as a test user and inspect the audit log
- **sourceOfTruth**: audit log
- **outcome**: log entry exists with actor, purpose, and timestamp fields
- **rationale**: HIPAA access logging is a legal requirement
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-HLTH-002
- **text**: Consent state is read before every new data-use path
- **verification**: Grep the diff for new data-use code paths and verify each reads consent state before proceeding
- **sourceOfTruth**: diff + consent service
- **outcome**: every path checks consent
- **rationale**: Data use without consent is a HIPAA violation
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-HLTH-003
- **text**: Retention/deletion policy is respected for the new data class
- **verification**: Inspect the retention configuration for the new data class
- **sourceOfTruth**: retention config + policy doc
- **outcome**: policy exists and matches the data-class classification
- **rationale**: Untracked data classes leak past their retention window
- **priority**: P0
- **platform**: backend
- **context**: release

### CL-HLTH-004
- **text**: BAA reference exists for every new third-party processor
- **verification**: Inspect the BAA registry for every new third-party processor in the diff
- **sourceOfTruth**: BAA registry
- **outcome**: every processor has a signed BAA on file
- **rationale**: Processors without a BAA cannot legally handle PHI
- **priority**: P0
- **platform**: backend
- **context**: release

---

## Catalog maintenance

- **Every row passes the verifiability check or it doesn't ship.**
  If you can't name a concrete verification verb + source of truth
  + binary outcome, the item isn't catalog-ready — it's an idea
  that needs more work.
- **Never delete an id.** Old checklists on disk cite these ids;
  deletion orphans historical records. Mark an obsolete id with
  `deprecated` in the rationale instead.
- **Every id is unique across contexts.** Same item in multiple
  contexts = duplicate rows with distinct ids. Templates decide
  which context gets which; the catalog doesn't pretend items are
  reusable across contexts without being re-justified.
- **Priority defaults to P1 unless rationale is weak.** Upgrade to
  P0 only when missing the item means shipping a known bug; drop
  to P2 only when missing it is a style or hygiene concern.
