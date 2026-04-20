---
name: init
description: Initialize a new VibeFlow project. Sets up vibeflow.config.json with domain and tech stack, creates the .vibeflow/ state directory, and records an optional brownfield fingerprint. Runs exactly once at the start of REQUIREMENTS.
disable-model-invocation: true
allowed-tools: Read Write Bash(mkdir *) Bash(git *)
---

# VibeFlow Project Initialization

## Phase Contract

This skill runs in **REQUIREMENTS** only. Before any other step, read
`vibeflow.config.json`'s `currentPhase`. If it is not REQUIREMENTS, emit:

> init is for REQUIREMENTS phase only; current is `<phase>`. If you need
> to re-run init, advance back or start a fresh project.

…and stop. The PreToolUse `phase-write-guard` (Sprint 13) will also
reject any source-code writes this skill attempts, so the only safe
outputs are `vibeflow.config.json`, `.vibeflow/**`, and `docs/**`.

## Steps

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
    "openai": "gpt-4o",
    "gemini": "gemini-2.0-flash"
  },
  "sourceDir": "src/",
  "testDir": "src/",
  "outputDir": ".vibeflow/",
  "defaultPipeline": "new-feature"
}
```

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

### Step 5: Confirm + Hand Off

Show the user a short summary of the configuration, then close with:

> Now run `/vibeflow:prd-quality-analyzer docs/<your-prd>.md` to score
> the requirements document. That command produces
> `.vibeflow/reports/prd-quality-report.md` and determines whether the
> REQUIREMENTS exit criteria (`prd.approved` + `testability.score>=60`)
> can be satisfied.

Do **not** offer to scaffold tests, generate code, or advance the phase
from this skill. Each of those actions belongs in a later phase and has
its own skill.

## Output
- `vibeflow.config.json` in project root
- `.vibeflow/` directory with `reports/`, `artifacts/`, `traces/`
- `.vibeflow/reports/codebase-fingerprint.md` (brownfield only)
