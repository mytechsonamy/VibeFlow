---
name: init
description: Initialize a new VibeFlow project. Sets up vibeflow.config.json with mode (solo/team), domain, and tech stack. Creates initial project structure for SDLC tracking.
disable-model-invocation: true
allowed-tools: Read Write Bash(mkdir *) Bash(git *)
---

# VibeFlow Project Initialization

## Steps

### Step 1: Gather Project Info
Ask the user for:
1. **Project name**: What is this project called?
2. **Mode**: solo (single developer) or team (multiple developers)?
3. **Domain**: financial, e-commerce, healthcare, or general?
4. **Platform**: web, ios, android, or all?
5. **Tech stack**: What languages/frameworks? (detect from package.json if exists)
6. **Risk tolerance**: low, medium, or high?

### Step 2: Create vibeflow.config.json
```json
{
  "project": "<name>",
  "version": "1.0.0",
  "mode": "solo|team",
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

### Step 4: Detect Existing Codebase
If source files exist (brownfield project):
- Run codebase-explorer subagent for initial analysis
- Detect actual framework (Express vs NestJS vs Fastify - do NOT assume!)
- Generate initial repo fingerprint

### Step 5: Confirm Setup
Show the user a summary of the configuration and ask for confirmation before proceeding to the REQUIREMENTS phase.

## Output
- vibeflow.config.json in project root
- .vibeflow/ directory for reports and artifacts
- Initial codebase analysis (if brownfield)
