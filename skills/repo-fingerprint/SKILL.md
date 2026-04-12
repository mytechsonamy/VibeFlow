---
name: repo-fingerprint
description: Produces a brownfield repository fingerprint — languages, frameworks, test runners, build tools, module layout, and risk hotspots. Run once when adopting VibeFlow on an existing codebase; the fingerprint is consumed by planning and test-strategy skills. Never assumes frameworks — detects them.
allowed-tools: Read Grep Glob
---

# VibeFlow Repo Fingerprint

Scans an existing codebase and writes a compact, evidence-backed snapshot to
`.vibeflow/artifacts/repo-fingerprint.json`. Every field records the file(s)
that justified the detection, so downstream skills can audit the inference.

## Detection Priorities (never guess)
1. **Package manifest first** — `package.json`, `pyproject.toml`, `go.mod`,
   `Cargo.toml`, `pom.xml`, `build.gradle(.kts)`.
2. **Import graph second** — a top-hit grep for `from fastify`, `from express`,
   `from nestjs`, `import "fmt"`, etc. confirms what the manifest declared.
3. **Heuristics last** — directory layout (`src/`, `app/`, `pkg/`) is used
   only to fill gaps, and the finding is tagged `confidence: 0.5`.

## Output Schema
```json
{
  "generatedAt": "ISO-8601",
  "languages": [{ "name": "typescript", "files": 142, "evidence": ["package.json"] }],
  "frameworks": [{ "name": "fastify", "version": "^4.26.0", "evidence": ["package.json", "src/server.ts:3"] }],
  "testRunners": [{ "name": "vitest", "evidence": ["package.json", "vitest.config.ts"] }],
  "buildTools": [{ "name": "tsc", "evidence": ["tsconfig.json"] }],
  "moduleLayout": {
    "sourceDirs": ["src/"],
    "testDirs": ["tests/", "src/**/*.test.ts"],
    "entryPoints": ["src/index.ts"]
  },
  "hotspots": [
    {
      "finding": "src/legacy/ has 2k lines untouched in 18 months",
      "why": "git log --since suggests cold code, high change ripples",
      "impact": "higher regression risk when modified",
      "confidence": 0.75
    }
  ]
}
```

## When to Run
- During `/vibeflow:init` on brownfield projects (skipped on greenfield).
- When the test-strategy-planner needs framework context it can't derive.
- Re-run on demand if the stack changes (new framework, new language).

## Non-Goals
- Does NOT modify project files.
- Does NOT install dependencies or run builds.
- Does NOT infer business domain — that lives in `vibeflow.config.json`.
