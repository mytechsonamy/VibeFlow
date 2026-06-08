---
name: onboard
description: Onboard a new VibeFlow project (renamed from init in v2.19.0 to avoid colliding with Claude Code's built-in /init). Sets up vibeflow.config.json with domain and tech stack, creates the .vibeflow/ state directory, and records an optional brownfield fingerprint. Runs exactly once at the start of REQUIREMENTS.
disable-model-invocation: true
allowed-tools: Read Write Bash(mkdir *) Bash(git *)
---

# VibeFlow Project Onboarding

## Phase Contract

This skill runs in **REQUIREMENTS** only. Before any other step, read
`vibeflow.config.json`'s `currentPhase`. If it is not REQUIREMENTS, emit:

> onboard is for REQUIREMENTS phase only; current is `<phase>`. If you
> need to re-run onboarding, advance back or start a fresh project.

…and stop. The PreToolUse `phase-write-guard` (Sprint 13) will also
reject any source-code writes this skill attempts, so the only safe
outputs are `vibeflow.config.json`, `.vibeflow/**`, and `docs/**`.

## Steps

### Step 0: Already onboarded? Resume, don't re-onboard (Sprint 42)

**Run this first.** Onboarding is a once-per-project act. If
`vibeflow.config.json` already exists, the project is initialized — do **not**
re-onboard, and do **not** mis-read its existing source as "brownfield" (a
greenfield project that has reached DEVELOPMENT *also* has source files; file
presence is not the signal — lifecycle state is). Read
`.vibeflow/state/lifecycle.json` and route:

```bash
test -f vibeflow.config.json && echo EXISTS
[ -f .vibeflow/state/lifecycle.json ] && jq -r '.currentCycle.status' .vibeflow/state/lifecycle.json
```

- **`currentCycle.status == "in-progress"`** → an active cycle is mid-flight.
  Stop and resume:
  > Project already onboarded (cycle `<id>`, phase `<currentPhase>`). Resuming —
  > nothing to re-initialize.
  > ▶ Next: /vibeflow:phase-runner
- **`currentCycle.status == "completed"`** → the last cycle shipped; new work is
  a fresh increment:
  > Last cycle (`<title>`) is complete. New work starts a new increment.
  > ▶ Next: /vibeflow:brownfield-intake

  **"completed" means the literal status field** (which flips only on DEPLOYMENT
  GO) — **not** "the PR was merged" or "it reached DEPLOYMENT". An `in-progress`
  cycle parked at DEPLOYMENT (code merged but not yet deployed+verified) is still
  in-progress → it routes to **resume** above, never to a new increment.
- **`vibeflow.config.json` exists but no lifecycle.json** (a pre-Sprint-42
  project) → backfill an `in-progress` cycle from the current `currentPhase`,
  then resume as above.

Only when `vibeflow.config.json` does **not** exist do you continue to Step 1
(a genuinely fresh project).

### Step 1: Gather Project Info
Ask the user for:
1. **Project name**: What is this project called?
2. **Domain**: financial, e-commerce, healthcare, or general?
3. **Platform**: web, ios, android, or all?
4. **Tech stack**: What languages/frameworks? (detect from package.json / pyproject.toml / *.csproj / go.mod if present — do NOT assume)
5. **Risk tolerance**: low, medium, or high?

(Sprint 11 removed the legacy `mode: solo/team` field — state is now
filesystem-only. Do not ask about mode.)

### Step 2: Create vibeflow.config.json
```json
{
  "project": "<name>",
  "version": "1.0.0",
  "domain": "financial|e-commerce|healthcare|general",
  "platform": "web|ios|android|all",
  "riskTolerance": "low|medium|high",
  "currentPhase": "REQUIREMENTS",
  "models": {
    "claude": "claude-sonnet-4-6",
    "openai": "default",
    "gemini": "default"
  },
  "sourceDir": "src/",
  "testDir": "src/",
  "outputDir": ".vibeflow/",
  "defaultPipeline": "new-feature"
}
```

**On `models.openai` / `models.gemini`.** Leave these as `"default"`
(the value above) and consensus will NOT pass `-m`/`--model` to the
reviewer CLIs — codex uses the model in your `~/.codex/config.toml`,
gemini uses its own default. This is the robust choice: the right model
id is **account- and CLI-version-specific** (codex runs on the operator's
ChatGPT login, gemini on its own auth), and a hardcoded id like the old
`gpt-4o` / `gemini-2.0-flash` silently fails when the account doesn't
accept it. Only pin a concrete id (e.g. `"openai": "gpt-5.5"`,
`"gemini": "gemini-2.5-flash"`) if you specifically want to override the
CLI's configured default. `models.claude` is informational (the native
claude-reviewer uses the session model).

### Step 3: Create Output Directory
```bash
mkdir -p .vibeflow/{reports,artifacts,traces}
```

### Step 4: Detect Existing Codebase (brownfield only)

If source files already exist in `sourceDir`, produce a high-level
fingerprint — nothing more:

- **Write exactly one file:** `.vibeflow/reports/codebase-fingerprint.md`
  with stack summary, module graph, top risk hotspots.
- **Do not** create new files outside `.vibeflow/` or
  `vibeflow.config.json`.
- **Do not** scaffold test projects, `mkdir src/`, write
  `*.cs/*.ts/*.py/...` files, run `dotnet sln add`, or otherwise modify
  the codebase under `sourceDir`/`testDir`.
- **Do not** run `git add` or `git commit`.

If source files are absent, skip this step entirely.

### Step 4b: Open the first lifecycle cycle (Sprint 42)

Write `.vibeflow/state/lifecycle.json` recording **cycle 1** — the project's
first pass through the SDLC. The `kind` is `initial` (greenfield-from-PRD or
brownfield-from-code is a cycle-1 detail; every *later* cycle is an
`increment`). Record the branch so each cycle maps to one branch / PR:

```json
{
  "currentCycle": {
    "id": "cycle-1",
    "kind": "initial",
    "title": "<project> — initial build",
    "phase": "REQUIREMENTS",
    "branch": "<current git branch, or 'main'>",
    "prUrl": null,
    "status": "in-progress",
    "startedAt": "<UTC ISO-8601>"
  },
  "history": []
}
```

(`git rev-parse --abbrev-ref HEAD` for the branch when the dir is a git repo.)

### Step 5: Confirm + Hand Off

Show the user a short summary of the configuration, then close with the
breadcrumb as the **literal last line** of your output (the `▶ Next:` prefix
is the project-wide next-step convention — keep it verbatim). **Branch on
greenfield vs brownfield** (from Step 4):

- **Brownfield** (source files already exist) — the operator has a codebase,
  not a PRD. Point them at the brownfield on-ramp, which fingerprints the repo
  and helps them define the increment (describe it / a doc / guided Q&A / an
  issue) into a scoped requirements doc:

  ```
  ▶ Next: /vibeflow:brownfield-intake
  ```

- **Greenfield** (no source yet) — they bring a PRD; score it directly:

  ```
  ▶ Next: /vibeflow:prd-quality-analyzer docs/<your-prd>.md
  ```

Either path leads into REQUIREMENTS (`prd-quality-analyzer` produces
`.vibeflow/reports/prd-quality-report.md` and gates `prd.approved` +
`testability.score>=60`).

Do **not** offer to scaffold tests, generate code, or advance the phase
from this skill. Each of those actions belongs in a later phase and has
its own skill.

## Output
- `vibeflow.config.json` in project root
- `.vibeflow/` directory with `reports/`, `artifacts/`, `traces/`
- `.vibeflow/reports/codebase-fingerprint.md` (brownfield only)
