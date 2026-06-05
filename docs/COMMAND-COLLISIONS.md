# Command collisions with Claude Code built-ins

VibeFlow ships its skills under the `vibeflow:` namespace, so the fully
qualified form (`/vibeflow:onboard`) never collides. But Claude Code's
command picker **fuzzy-matches the bare name** — type `/status` and the
picker also surfaces `/vibeflow:status`, and selecting it runs VibeFlow's
skill instead of the built-in you wanted. So any skill whose **bare name
equals a built-in** is a usability collision.

This document is the audit of all VibeFlow skills against Claude Code's
built-in slash commands, and the policy for avoiding future collisions.

## Audit result (v2.20.0)

All 41 skills were checked against the built-in set
(`help, clear, compact, config, cost, status, doctor, login, logout,
model, memory, mcp, agents, hooks, permissions, bug, release-notes,
resume, export, vim, terminal-setup, add-dir, init, review, run, fast,
upgrade, pr-comments, feedback, privacy-settings, …` plus the bundled
user-invocable skills `verify, code-review, simplify, schedule, loop, …`).

**Exact collisions found and resolved:**

| VibeFlow skill | Built-in shadowed | Resolution | Version |
|---|---|---|---|
| `init` | `/init` (generate CLAUDE.md) | → `/vibeflow:onboard` | v2.19.0 |
| `status` | `/status` (usage / quota / account) | → `/vibeflow:flow-status` | v2.20.0 |

**After v2.20.0: zero exact collisions remain.** The other 39 skills use
VibeFlow-specific names (`phase-runner`, `coverage-analyzer`,
`consensus-orchestrator`, `advance`, …) that no built-in claims.

**Reviewed, intentionally kept:**

| Skill | Note |
|---|---|
| `loop-status` | Contains the `loop` and `status` tokens, but is a distinct name. `/loop` (built-in) wins on exact match; only a fuzzy search for "loop"/"status" surfaces it. Renaming would churn the Sprint-30 dashboard for no real collision. |
| `learning-loop-engine` | Contains `loop`; unambiguous, no risk. |

No deprecation shims are kept for the renamed skills — a lingering `init`
/ `status` skill would re-introduce the very collision the rename removes.

## Policy for new skills

When adding a skill, **do not name it after a Claude Code built-in**. Before
choosing a bare name, check it against the built-in list above. If the
natural name collides, prefix it with a VibeFlow concept (`flow-status`,
`onboard`) or the domain (`sdlc-…`, `consensus-…`, `phase-…`). The skill
registry in `skills/phase-policy.json` is the source of truth for the
current skill-name set; `tests/integration/sprint-32.sh` pins that no live
reference points at the retired `status` / `init` names.

## How to verify

```bash
# List every skill's bare name:
for d in skills/*/; do grep -m1 '^name:' "$d/SKILL.md"; done

# Re-run the collision check (bash, not zsh — zsh won't word-split the list):
bash -c 'bic="help clear compact config cost status doctor login logout model \
  memory mcp agents hooks permissions bug release-notes resume export vim \
  terminal-setup add-dir init review run fast"; \
  for d in skills/*/; do n=$(grep -m1 "^name:" "$d/SKILL.md" | sed "s/^name:[[:space:]]*//"); \
    for b in $bic; do [[ "$n" == "$b" ]] && echo "COLLISION: /$n"; done; done'
```
