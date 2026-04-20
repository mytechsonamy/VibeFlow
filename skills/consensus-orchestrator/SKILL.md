---
name: consensus-orchestrator
description: Orchestrates multi-AI review process. Coordinates Claude, ChatGPT (codex CLI), and Gemini (gemini CLI) reviews. Aggregates results with weighted scoring. Gracefully degrades when external AIs are unavailable. Use for SDLC review cycles.
disable-model-invocation: true
allowed-tools: Read Bash(codex *) Bash(gemini *) Grep Glob
---

# Consensus Orchestrator

Manages the multi-AI review cycle that replaces MyVibe's CLI subprocess approach. Fixes Bug #1 (case mismatch), Bug #2 (model names), and Bug #8 (no CLI fallback).

## Input
- $ARGUMENTS: Path to artifact(s) to review, or "review last commit"
- vibeflow.config.json: model names, domain

## Consensus Flow

### Step 1: Read Configuration
```
openaiModel = vibeflow.config.json.models.openai  // default: "gpt-4o" (NOT gpt-5.3!)
geminiModel = vibeflow.config.json.models.gemini   // default: "gemini-2.0-flash"
```

**Note (Sprint 14-A):** There is no `mode` concept anymore. Every
reviewer participation is decided by CLI availability — codex and
gemini join the panel when their CLIs are on `PATH`, full stop. Both
CLIs use the operator's own authenticated session, so there is no
API billing concern to gate on.

### Step 2: Claude Review (Always Available)
Use the claude-reviewer subagent for native review. This always runs.

### Step 3: External AI Reviews (CLI-availability only)
Run every CLI that is on `PATH`. Skip the ones that aren't — never
gate on a mode switch, environment variable, or config flag.

**ChatGPT Review (via codex CLI):**
```bash
if command -v codex &>/dev/null; then
  cat <artifact> | codex exec "Review this for quality, security, maintainability. Return JSON: {score, issues, verdict}" -m $openaiModel --skip-git-repo-check --ephemeral
fi
```

**Gemini Review (via gemini CLI):**
```bash
if command -v gemini &>/dev/null; then
  (echo "Review this for quality, security, maintainability. Return JSON: {score, issues, verdict}" && cat <artifact>) | gemini --model $geminiModel
fi
```

Both CLIs inherit the operator's authenticated session (ChatGPT
subscription, Gemini Pro, Workspace, etc.). There is no VibeFlow-
emitted API key and no per-call billing.

### Step 4: Consensus Calculation

**Available AIs:**
- 3 AIs: Normal consensus (weighted average)
- 2 AIs: 2-AI consensus (both must agree for APPROVED)
- 1 AI (Claude only): Single review with WARNING that consensus is degraded

**Scoring:**
```
consensusScore = weightedAverage(claudeScore, chatgptScore?, geminiScore?)
```

**Decision (use enum, NEVER string literals):**
```
if consensusScore >= 90 AND criticalIssues == 0:
  status = "APPROVED"      // Always UPPERCASE
elif consensusScore < 50 OR criticalIssues >= 2:
  status = "REJECTED"      // Always UPPERCASE (fixes Bug #1!)
else:
  status = "NEEDS_REVISION" // Always UPPERCASE
```

### Step 5: Disagreement Resolution
If AIs disagree significantly (>30 point spread):
1. Round 1: Share each AI's review with the others
2. Round 2: Each AI reconsiders with full context
3. Round 3: If still no consensus, escalate to human

Max 3 negotiation rounds. After that: human decision required.

## Output Format
```markdown
# Consensus Review Report

## Decision: [APPROVED | NEEDS_REVISION | REJECTED]
## Consensus Score: XX/100
## AIs Participating: X/3

## Individual Reviews
### Claude (score: XX/100)
[Summary and key findings]

### ChatGPT (score: XX/100) [or "Not available"]
[Summary and key findings]

### Gemini (score: XX/100) [or "Not available"]
[Summary and key findings]

## Aggregated Issues
### Critical
[Merged and deduplicated critical issues]

### High
[...]

## Consensus Notes
[Any disagreements, negotiation rounds, or degradation warnings]
```
