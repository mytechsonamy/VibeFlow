---
name: deploy-verifier
description: Verify a completed deployment by cross-checking the CI pipeline status (dev-ops MCP) + service health dashboard (observability MCP) + optional smoke-test endpoints. Auto-satisfies the DEPLOYMENT phase's `deployment.verified` and `health.checks.passed` exit criteria when every declared check returns green. Writes a consensus-needed marker so the third DEPLOYMENT criterion (`consensus.deployment.approved`) still gates through multi-AI review.
disable-model-invocation: true
allowed-tools: Read Write Bash(curl *) Bash(jq *)
---

# Deploy Verifier (DEPLOYMENT)

Sprint 18-G. Post-deployment smoke-test runner that takes the
`deployment.verified` + `health.checks.passed` criteria off the
operator's plate. Pairs with consensus-orchestrator (on the
release-decision report) for the third DEPLOYMENT criterion.

## Phase Contract

Runs in **DEPLOYMENT** only. If `currentPhase != DEPLOYMENT`,
emit:

```
deploy-verifier only runs in DEPLOYMENT. Current phase: <x>. Stopping.
```

and exit.

## Input

Read `vibeflow.config.json`:

```json
{
  "deployment": {
    "environment": "staging | production",
    "endpoints": [
      { "url": "https://api.example.com/health", "expect": { "status": 200, "bodyIncludes": "ok" } },
      { "url": "https://api.example.com/metrics", "expect": { "status": 200 } }
    ],
    "ci": {
      "provider": "github | gitlab",
      "repo": "owner/repo",
      "ref": "main | v2.6.0"
    },
    "observability": {
      "enabled": true,
      "errorBudgetBurnThreshold": 0.1
    }
  }
}
```

Every field is optional. Missing fields become "skipped checks"
(not failures), but **at least one check category must run** for
the skill to satisfy criteria.

## Process

### Step 1: Resolve check set

Build a list of checks from config:

1. **CI pipeline status** (when `deployment.ci` is configured):
   invoke `mcp__dev-ops__do_pipeline_status` with the configured
   repo + ref. Expected: latest run on that ref is `success`.
2. **Endpoint smoke tests** (when `deployment.endpoints` is
   non-empty): curl each URL, check status code + optional body
   substring.
3. **Observability cross-check** (when
   `deployment.observability.enabled`): invoke
   `mcp__observability__ob_health_dashboard` with the
   environment + error-budget burn threshold. Expected: no
   active burn above threshold.

If none of the three categories is configured, emit:

```
deploy-verifier: no checks configured. Populate
vibeflow.config.json.deployment with at least one of:
ci / endpoints / observability. Stopping.
```

and exit without satisfying the criteria.

### Step 2: Run each check

Capture per-check results: `{ name, category, status:
pass|fail|skipped, evidence }`. Run all checks — don't
short-circuit on the first failure; the operator needs the full
picture for rollback decisions.

CI pipeline status call:
```
mcp__dev-ops__do_pipeline_status {
  "repo": "<owner/repo>",
  "ref":  "<branch-or-tag>",
  "provider": "<github|gitlab>"
}
→ { ok: bool, conclusion: "success"|"failure"|"in_progress", ... }
```

Endpoint smoke test per entry:
```bash
curl -sS -o /tmp/deploy-verifier-body -w "%{http_code}" "<url>"
→ status code + body
```
Compare against expected status; if `expect.bodyIncludes` is set,
grep the body for the substring.

Observability dashboard call:
```
mcp__observability__ob_health_dashboard {
  "environment": "<staging|production>"
}
→ { errorBudget: {...}, activeBurn: [...], healthScore: 0-100, ... }
```
Fail if any metric's `activeBurn` exceeds the configured
threshold.

### Step 3: Compute category verdicts

For each of the three categories (ci, endpoints, observability):

- **PASS** — every check in that category is `pass`
- **SKIPPED** — no checks in that category were configured
- **FAIL** — one or more checks failed

Overall verdict:
- **PASS** — every configured category is PASS (SKIPPED
  categories don't affect overall)
- **FAIL** — at least one configured category is FAIL

### Step 4: Write report

`.vibeflow/reports/deploy-verification.md`:

```markdown
# Deploy Verification — <project> — <timestamp>

Verdict: **PASS | FAIL**
Environment: <staging|production>

## CI Pipeline
Status: <PASS|FAIL|SKIPPED>
<evidence: run URL, conclusion, commit SHA>

## Endpoint Smoke Tests
Status: <PASS|FAIL|SKIPPED>
| URL | Status Code | Body Match | Verdict |
|---|---|---|---|
| ... | ... | ... | ✓/✗ |

## Observability
Status: <PASS|FAIL|SKIPPED>
<evidence: health score, active burns, top alerts>

## Summary
- Categories run: <N>/3
- Categories failed: <K>
- Total check count: <M>
- Rollback hint: <from docs/runbooks/ or "manual review needed">
```

### Step 5: Auto-satisfy DEPLOYMENT criteria (MANDATORY on PASS)

Only when overall verdict == **PASS**:

```
mcp__sdlc-engine__sdlc_satisfy_criterion {
  "projectId": "<project id>",
  "criterion": "deployment.verified"
}
```

and:

```
mcp__sdlc-engine__sdlc_satisfy_criterion {
  "projectId": "<project id>",
  "criterion": "health.checks.passed"
}
```

Emit:

```
Recorded: deployment.verified, health.checks.passed.
Environment: <env>. Next: /vibeflow:consensus-orchestrator
.vibeflow/reports/release-decision.md for the third criterion.
```

**Split rationale:**
- `deployment.verified` — the deploy happened cleanly: CI green,
  artifact built, service rolled over
- `health.checks.passed` — the deployed service is actually
  responding correctly

Both signals come from the same check set, but they're recorded
separately so later audit can distinguish "CI passed but the
service is sick" (fails `health.checks.passed`, passes
`deployment.verified` if endpoints were skipped) from
"everything green" (both satisfied).

On FAIL: do NOT satisfy either criterion. Emit a visible advisory
naming the failing category + the rollback command pulled from
`docs/runbooks/` if present:

```
Deploy verification FAILED.
Failing category: <ci|endpoints|observability>
Failing check: <name>
Evidence: <path to report>

Rollback options:
- <command from docs/runbooks/, if present>
- Otherwise: follow docs/DEPLOYMENT.md rollback recipe
```

Fallback on MCP unavailability (sdlc-engine side):

```
sdlc-engine MCP unavailable — satisfy manually:
mcp__sdlc-engine__sdlc_satisfy_criterion {projectId:…, criterion:'deployment.verified'}
mcp__sdlc-engine__sdlc_satisfy_criterion {projectId:…, criterion:'health.checks.passed'}
```

### Step 6: Write the auto-consensus marker (MANDATORY)

After satisfy calls, Write `.vibeflow/state/consensus-needed.json`
for the third DEPLOYMENT criterion:

```json
{
  "artifact": ".vibeflow/reports/deploy-verification.md",
  "requiredCommand": "/vibeflow:consensus-orchestrator .vibeflow/reports/deploy-verification.md",
  "createdAt": "<current UTC ISO-8601 timestamp>",
  "createdBy": "deploy-verifier"
}
```

Sprint 16's `consensus-gate` hook blocks further tool calls
until the operator runs the orchestrator, which on APPROVED
auto-records the consensus and satisfies
`consensus.deployment.approved`.

**Skip condition**: `VF_SKIP_AUTO_CONSENSUS=1` disables the
marker (call-scoped); phase-gate still blocks advance without
a fresh consensus record.

## Output

- `.vibeflow/reports/deploy-verification.md`
- State updates (2 criteria satisfied) via MCP
- `.vibeflow/state/consensus-needed.json` marker

## Guardrails

- **No auto-rollback.** The skill identifies failure; rollback
  is an explicit operator action (pulls from docs/runbooks/).
  Reverting a live service on a skill's signal is too risky.
- **Reads only.** No deploy side effects — the deploy has
  already happened before this skill runs. It's verification,
  not re-deployment.
- **Cross-MCP dependency.** Needs dev-ops + observability MCPs
  for full coverage. Missing MCPs become SKIPPED categories;
  the skill still runs endpoint checks if configured.

## Non-goals

- Does NOT trigger deployments. That's `dev-ops` MCP territory
  (via CI pipeline dispatch, not a VibeFlow skill).
- Does NOT do long-term SLO tracking. `observability` MCP's
  `ob_perf_trend` covers that.
- Does NOT verify security posture. A future
  `security-scan-runner` skill (Sprint 21+ candidate) would
  handle that.

## See also

- `docs/AUTO-SATISFY.md` — full per-criterion matrix
- `docs/runbooks/` — rollback recipes the advisory references
- `mcp-servers/dev-ops/` — CI pipeline status source
- `mcp-servers/observability/` — health dashboard source
