# VibeFlow - Getting Started

## Prerequisites
- Claude Code CLI installed (`claude` command available)
- Node.js >= 18
- Git

## Installation

### Option 1: Plugin Install (when published to marketplace)
```bash
claude plugin install vibeflow@vibeflow-marketplace
```

### Option 2: Local Development
```bash
# Clone the plugin
cd ~/Projects/VibeFlow

# Start Claude Code with the plugin loaded locally
claude --plugin-dir ./
```

## First Use

### Initialize a Project
```
/vibeflow:init
```
This will ask you for:
- Project name
- Mode: `solo` (single developer) or `team` (multi-developer)
- Domain: `financial`, `e-commerce`, `healthcare`, or `general`
- Platform: `web`, `ios`, `android`, or `all`

### Check Status
```
/vibeflow:status
```

### Analyze a PRD
```
/vibeflow:prd-quality-analyzer path/to/prd.md
```

### Generate Test Strategy
```
/vibeflow:test-strategy-planner web
```

### Trigger Multi-AI Review
```
/vibeflow:consensus-orchestrator path/to/artifact
```

### Get Release Decision
```
/vibeflow:release-decision-engine
```

## Directory Structure After Init
```
your-project/
├── vibeflow.config.json          # Project configuration
├── .vibeflow/                    # VibeFlow working directory
│   ├── reports/                  # Quality reports
│   ├── artifacts/                # Generated artifacts
│   └── traces/                   # Traceability data
└── ... (your source code)
```

## Solo vs Team Mode

| Feature | Solo | Team |
|---------|------|------|
| Database | SQLite (zero-config) | PostgreSQL |
| AI Review | Claude only | Claude + ChatGPT + Gemini |
| Hooks | Light (format + lint) | Full (all quality gates) |
| Approval | Optional auto-advance | Required at each phase |
| Pipelines | 3 (new-feature, pre-pr, hotfix) | All 7 pipelines |

## Development

### Build MCP Servers
```bash
cd mcp-servers/sdlc-engine && npm install && npm run build
```

### Test Plugin Locally
```bash
claude --plugin-dir /path/to/VibeFlow
```

### Reload After Changes
Type `/reload-plugins` in Claude Code to pick up changes without restarting.
