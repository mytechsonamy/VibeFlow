---
name: environment-orchestrator
description: Produces env-setup.md — a reproducible, teardown-safe environment recipe for a given test profile (unit/integration/e2e/uat/perf) and platform. Assembles components from a catalog, pins image versions, declares healthchecks, and never inlines secrets. Gate contract — every component has a healthcheck, every setup has a teardown, secrets flow through references only. PIPELINE-3 step 1.
allowed-tools: Read Write Grep Glob
context: fork
agent: Explore
---

# Environment Orchestrator

An L2 Truth-Execution skill. Before any test runner can exercise
scenarios, **the environment has to be real** — ephemeral
databases, message queues, mock services, feature flags, seed
data. This skill emits the recipe that makes the environment
reproducible, pinnable, and tear-downable. It does not itself
provision cloud resources; that's the `dev-ops` MCP's job.
Thinking otherwise is how a "setup skill" ends up quietly leaking
cloud accounts.

## When You're Invoked

- **PIPELINE-3 step 1** — before `e2e-test-writer` /
  `uat-executor` run against a new fixture environment.
- **On demand** as
  `/vibeflow:environment-orchestrator <profile> <platform>`.
- **From `regression-test-runner`** when an integration suite
  needs a stood-up environment its local test harness can't
  provide.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Test type (profile) | yes | One of `unit / integration / e2e / uat / perf`. Loaded from `references/environment-profiles.md` §1–§5. |
| Platform | yes | `web / ios / android / backend`. Some profiles don't apply to some platforms — the skill refuses `perf / ios` outright (iOS perf has its own toolchain, out of scope). |
| Target environment name | yes | `--env <name>` — resolves to `vibeflow.config.json.environments[name]`. Production is rejected at the same layer as `uat-executor` (no override). |
| Project config | derived | `vibeflow.config.json` for secrets path, environment URLs, domain. |
| `repo-fingerprint.json` | optional | When present, informs which test runner the profile should wire into the compose output. |
| `test-strategy.md` | optional | Can add `extraComponents: [...]` for project-specific components that live outside the catalog. Each must still resolve to a catalog entry. |

**Hard preconditions** — refuse to run rather than emit a recipe
that leaves resources hanging or secrets in cleartext:

1. The target environment MUST NOT be production. Same rule as
   `uat-executor` — no override, no escape hatch, no "it's fine".
2. Every component the profile asks for must exist in the
   component catalog. An unknown component name blocks with
   "extend component-catalog.md before re-running". Silently
   dropping an unknown component would quietly leave a test
   environment with missing capabilities.
3. Secrets referenced by the recipe must resolve to names in
   `vibeflow.config.json.secretsPath` (or the declared secret
   store). A literal password in the recipe → blocker with
   "inline secrets are forbidden; use ${SECRET_NAME}".
4. The recipe's teardown command must exist. A setup with no
   matching teardown blocks — zero leaked resources is the
   whole reason this skill exists.

## Algorithm

### Step 1 — Load the profile
Read `references/environment-profiles.md` and look up the
`(profile, platform)` combination. Each profile declares:

- required components (named entries from the catalog)
- optional components (activated by `test-strategy.md` flags)
- seed policy (no seed / fixture seed / factory seed)
- healthcheck wait policy
- default teardown strategy

A combination marked `not applicable` in the profile table (e.g.
`perf / ios`) is a hard block — the skill refuses to hallucinate
a recipe for a target it was never meant to handle.

### Step 2 — Resolve components
For every required component, read its entry from
`references/component-catalog.md`. Each entry declares:

- `image` — pinned by digest or explicit version (never `latest`)
- `ports` — declared mapping, host-port fixed per project to
  avoid contention
- `env` — required env vars, each either a literal safe value
  or a `${SECRET_NAME}` reference
- `volumes` — named volumes with an explicit teardown strategy
- `healthcheck` — shell command + interval + timeout + retries
- `dependsOn` — other catalog components that must be up first
- `teardownCommand` — how the component is removed (`docker rm -v`,
  `localstack stop`, etc.)

Every component that appears in the final recipe **must** carry
all six fields. A catalog entry with a missing field is rejected
at load time.

### Step 3 — Assemble the compose topology
Build a `docker-compose.yml` (or `kind cluster` manifest for
backend profiles that need kubernetes) from the resolved
components:

1. Add every required component as a service.
2. Populate `dependsOn` to match the catalog's declared ordering.
3. For each `volumes` entry, declare a named volume with the
   naming convention `<runId>_<component>_<volumeName>` so
   concurrent runs don't collide.
4. Add the healthcheck block to every service, copied verbatim
   from the catalog. Tests that wait on "all services healthy"
   have to be able to trust the healthcheck.
5. Set a global `--project-name` equal to the `runId` so the
   whole topology is addressable for teardown.

The output is a single `docker-compose.yml` (or k8s manifest)
that can be `up`'d and `down`'d without any manual fix-up.

### Step 4 — Secret resolution
Walk the generated compose and verify every `${SECRET_NAME}`
reference resolves:

1. The secret name must match a key in the project's secret
   store (env var, HashiCorp Vault path, AWS Secrets Manager
   arn, etc. — the secret store is declared in
   `vibeflow.config.json.secretsBackend`).
2. The skill does NOT read the secret values. It verifies the
   NAMES exist; the actual injection happens at environment
   startup time via the secret store's CLI.
3. An unresolved secret name blocks with "secret '<NAME>' not
   found in '<backend>'; add it before running the recipe".

**A literal password, API key, or connection string in a recipe
is a blocker.** The skill scans the generated compose for
common secret patterns (regex on `password=[^$]`, `key=[^$]`,
`token=[^$]`) and fails the emission if any are found.

### Step 5 — Declare the teardown
Every recipe carries a matching teardown command in
`env-setup.md`. The teardown:

- Must be idempotent — running it twice must not error.
- Must not depend on the recipe's startup state. If the compose
  failed to reach `healthy`, teardown still has to clean up
  everything it can.
- Must remove **named volumes**, not just containers. A container
  rm that leaves a volume behind is a leak.
- Must run within 60 seconds on a typical laptop. A teardown
  that takes 5 minutes is a footgun during CI failure handling.

### Step 6 — Seed data
For profiles that need seed data (`integration`, `e2e`, `uat`),
the recipe includes the seed command — typically a reference to
a `test-data-manager` factory output. The seed script:

- Runs AFTER the healthcheck passes (`dependsOn` + wait logic)
- Uses deterministic data (see `test-data-manager`'s
  determinism contract)
- Never seeds from the developer's personal laptop state — the
  data source must be a file committed to the repo or a
  `test-data-manager` factory invocation

Seed failures are loud: the recipe's startup exits non-zero if
seeding fails, and the failure propagates to CI. No "soft seed"
that pretends to succeed.

### Step 7 — Write outputs

1. **`env-setup.md`** — human-readable recipe that tells the
   operator (or a CI job) how to stand up, verify, and tear
   down the environment (see contract below)
2. **`docker-compose.yml`** (or equivalent) — the machine-
   readable topology that the recipe refers to
3. **`.vibeflow/artifacts/env/<runId>/setup-manifest.json`** — a
   serialized list of every component + image digest + healthcheck
   + teardown command. Consumed by `release-decision-engine` and
   `learning-loop-engine` to correlate test outcomes with
   environment recipes over time.

## Output Contract

### `env-setup.md`
```markdown
# Environment Setup — <profile> / <platform>

## Header
- Profile: integration
- Platform: backend
- Target env: staging
- Run id: <runId>
- Components: 5 (postgres, redis, localstack, wiremock, app)
- Secret store: env vars
- Generated: <ISO>
- Environment-orchestrator version: 0.1.0

## Preflight
- [ ] Docker Desktop / colima is running
- [ ] Secret store is reachable (`echo $SECRETS_PATH` returns a directory)
- [ ] No prior run of `<runId>` is still alive (`docker ps --filter name=<runId>` is empty)

## Start
```bash
docker compose -p <runId> -f docker-compose.yml up -d
./scripts/wait-for-health.sh <runId>
./scripts/seed.sh <runId>
```

## Verify
```bash
docker compose -p <runId> ps     # all services should say "healthy"
./scripts/smoke-connect.sh <runId>
```

## Teardown (run on failure, run on success, run twice if needed)
```bash
docker compose -p <runId> down -v --remove-orphans
docker volume ls --filter name=<runId>_ -q | xargs -r docker volume rm
```

## Components
| Name | Image | Ports | Secrets referenced | Teardown |
|------|-------|-------|---------------------|----------|
| postgres | postgres:16.2@sha256:... | 5432:5432 | ${PG_PASSWORD} | docker rm -v |
| ...      | ...                      | ...        | ...              | ...           |

## Seed
- Source: `test-data-manager` factory output at
  `.vibeflow/artifacts/fixtures/users.json`
- Applied after: all services healthy
- Failure mode: startup exits non-zero if seeding fails

## Warnings
- <list of non-blocking surface area the operator should know>
```

## Gate Contract
**Every component has a healthcheck, every setup has a teardown,
secrets flow through references only.** Three ways to violate:

1. A component missing its healthcheck → blocked at Step 2
   (the catalog entry is incomplete).
2. A recipe missing its teardown → blocked at Step 5. Half-
   tear-downable is not tear-downable.
3. A literal secret value anywhere in the recipe → blocked at
   Step 4. Not NEEDS_REVISION — blocked. Secrets in files are
   how laptops get compromised.

No override flag. A project that genuinely can't provide a
healthcheck for a component has the wrong component; that
conversation belongs in the component-catalog, not in a flag.

## Non-Goals
- Does NOT provision cloud infrastructure. That's `dev-ops` MCP's
  `do_trigger_pipeline` against an infra-provisioning workflow.
- Does NOT run tests. Tests run against the environment this
  skill sets up, but the running is someone else's job.
- Does NOT read secret values. It verifies names exist; runtime
  injection is the secret store's responsibility.
- Does NOT set up production environments. There is no override
  flag. Same rule as `uat-executor`.
- Does NOT back up or restore seed data. Seeds are derived
  outputs from `test-data-manager`; the source of truth is the
  factory, not a database snapshot.

## Downstream Dependencies
- `e2e-test-writer` — its generated Playwright/Detox specs point
  at the base URL this skill's recipe produces.
- `uat-executor` — reads `env-setup.md` to know which
  environment to drive and which teardown to emit on halt.
- `regression-test-runner` — integration scope runs use this
  skill's recipe when the local test harness isn't enough.
- `release-decision-engine` — consumes
  `setup-manifest.json` to correlate "which environment shape
  was up when we made the decision".
- `learning-loop-engine` — ingests manifest history to spot
  recipes that correlate with flaky outcomes.
