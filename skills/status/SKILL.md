---
name: status
description: Shows current VibeFlow project status including SDLC phase, pending tasks, quality metrics, and recent review results. Use when asking about project progress.
allowed-tools: Read Grep Glob
---

# VibeFlow Status

Read vibeflow.config.json and .vibeflow/ directory to compile project status.

## Report Sections

### 1. Current Phase
- Active SDLC phase (REQUIREMENTS through DEPLOYMENT)
- Phase progress (iteration X of max Y)

### 2. Quality Metrics
- Latest testability score (from prd-quality-analyzer)
- Test coverage percentage (from coverage-analyzer)
- Traceability score (from traceability-engine)
- Last consensus result and score

### 3. Pending Tasks
- Incomplete tasks in current phase
- Blocked items requiring attention
- Upcoming quality gates

### 4. Recent Activity
- Last 5 reviews with verdicts
- Last phase transition timestamp
- Recent skill invocations

## Output
Display a concise status summary directly in the conversation. Do not create a file.
