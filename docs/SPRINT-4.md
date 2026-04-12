# Sprint 4: Polish + Packaging + Distribution

## Sprint Goal
Production-ready plugin: full test coverage, documentation, demo project, and plugin marketplace packaging.

## Prerequisites
- Sprint 3 complete (all 5 MCPs, all 31 skills, all 7 pipelines working)

## Completion Criteria
- [ ] Plugin passes `claude plugin validate` cleanly
- [ ] Demo project completes full SDLC cycle (REQUIREMENTS → DEPLOYMENT)
- [ ] All MCP servers have >80% test coverage
- [ ] User documentation covers all skills and pipelines
- [ ] Plugin packaged and installable via `claude plugin install`
- [ ] CHANGELOG.md and versioned release (v1.0.0)

---

## Tickets

### S4-01: Comprehensive test suite ⬜ TODO
Ensure all MCP servers and critical paths are well-tested.
- [ ] codebase-intel: >80% coverage
- [ ] design-bridge: >80% coverage (mocked Figma API)
- [ ] dev-ops: >80% coverage (mocked CI APIs)
- [ ] observability: >80% coverage
- [ ] sdlc-engine: maintain >80% (currently 90 tests)
- [ ] Cross-MCP integration tests (sdlc-engine state affects codebase-intel queries)
- [ ] Skill output validation tests (each skill output matches io-standard.md schema)

### S4-02: Hook hardening ⬜ TODO
Production-ready hook scripts:
- [ ] commit-guard.sh: Handle edge cases (merge commits, rebases, initial commit)
- [ ] load-sdlc-context.sh: Graceful fallback when MCP unavailable
- [ ] post-edit.sh: Debounce rapid edits, ignore non-source files
- [ ] trigger-ai-review.sh: Rate limiting (max 1 review per 5 minutes)
- [ ] test-optimizer.sh: Cache test-file mapping for performance
- [ ] compact-recovery.sh: Verify state integrity after restore
- [ ] consensus-aggregator.sh: Timeout handling for unresponsive AI providers

### S4-03: Demo project ⬜ TODO
Create a sample project that showcases VibeFlow end-to-end.
**Location:** examples/demo-app/
**Contents:**
- Sample PRD (e-commerce product catalog)
- Pre-generated scenario-set.md
- Source code (small Next.js app)
- Test suite (vitest)
- Walk-through script: docs/DEMO-WALKTHROUGH.md
**Demonstrates:**
- /vibeflow:init → /vibeflow:prd-quality-analyzer → /vibeflow:test-strategy-planner
- Phase advance through sdlc-engine
- Consensus review (solo mode, single AI)
- Release decision (GO for demo data)

### S4-04: User documentation ⬜ TODO
Complete documentation set:
- [ ] docs/GETTING-STARTED.md — Update with final installation steps
- [ ] docs/CONFIGURATION.md — All vibeflow.config.json options, userConfig fields
- [ ] docs/SKILLS-REFERENCE.md — Auto-generated from io-standard.md, one section per skill
- [ ] docs/PIPELINES.md — Human-friendly version of orchestrator.md with diagrams
- [ ] docs/HOOKS.md — What each hook does, how to customize
- [ ] docs/MCP-SERVERS.md — Architecture of each MCP server, available tools
- [ ] docs/TROUBLESHOOTING.md — Common errors and fixes
- [ ] docs/TEAM-MODE.md — PostgreSQL setup, multi-AI consensus config, collaboration workflow

### S4-05: Plugin manifest finalization ⬜ TODO
Prepare plugin.json for distribution:
- [ ] Verify all userConfig fields have correct types, titles, descriptions
- [ ] Add `figma_token` (sensitive: true) for design-bridge
- [ ] Add `github_token` (sensitive: true) for dev-ops
- [ ] Add `ci_provider` (string: "github" | "gitlab") for dev-ops
- [ ] Version bump to 1.0.0
- [ ] Add `repository` and `homepage` URLs
- [ ] Validate with `claude plugin validate`

### S4-06: Plugin packaging ⬜ TODO
Package for distribution:
- [ ] Ensure all MCP servers have pre-built dist/ (no user-side build required)
- [ ] Create .npmignore or files whitelist (exclude tests, src, node_modules dev deps)
- [ ] Test clean install: `claude plugin install ./vibeflow-plugin.tar.gz`
- [ ] Test from npm (if publishing): `claude plugin install vibeflow`
- [ ] Verify skills, hooks, agents, MCPs all load on fresh install

### S4-07: CHANGELOG + release ⬜ TODO
- [ ] Write CHANGELOG.md covering Sprint 1-4 changes
- [ ] Git tag v1.0.0
- [ ] Create GitHub release with release notes
- [ ] Archive: vibeflow-v1.0.0.tar.gz

### S4-08: Performance + edge case hardening ⬜ TODO
- [ ] Large PRD handling (>5000 words) — ensure skills don't timeout
- [ ] Concurrent MCP requests — verify no state corruption
- [ ] Offline mode — graceful degradation when no internet (design-bridge, dev-ops)
- [ ] Memory footprint — ensure plugin doesn't bloat Claude context
- [ ] Error messages — all errors user-friendly with actionable suggestions

### S4-09: Final integration test ⬜ TODO
End-to-end validation on demo project:
- [ ] Fresh install of plugin
- [ ] /vibeflow:init on demo project
- [ ] Run PIPELINE-1 (new feature) end-to-end
- [ ] Run PIPELINE-2 (pre-PR) on a code change
- [ ] Run PIPELINE-4 (release decision) with generated data
- [ ] Run PIPELINE-5 (hotfix) on a simulated bug fix
- [ ] Verify all hooks fire correctly
- [ ] Verify /vibeflow:status shows accurate state throughout
- [ ] Test team mode with PostgreSQL (if available)

---

## Next Ticket to Work On (when sprint starts)
**S4-01: Comprehensive test suite** — Tests first, then polish. Ensures stability before documentation and packaging.

## Execution Order
S4-01 (tests) → S4-02 (hooks hardening) → S4-03 (demo) → S4-04 (docs) → S4-05 (manifest) → S4-06 (packaging) → S4-07 (changelog) → S4-08 (hardening) → S4-09 (final test)

## Definition of Done: v1.0.0
- All 31 skills functional
- All 5 MCP servers operational
- All 7 hooks implemented and tested
- All 7 pipelines executable
- >80% test coverage across all MCP servers
- Documentation complete
- Demo project works end-to-end
- Plugin installable from package
- 12/12 MyVibe bugs fixed
