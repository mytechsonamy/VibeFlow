# Phase Boundaries

VibeFlow's `phase-write-guard` hook (Sprint 13, v2.1.0) blocks file
writes that don't belong to the SDLC phase your project is currently
in. This document is the reference for **what's allowed where** and
**how to get out of a stuck state**.

The policy lives at `hooks/scripts/phase-policy.json` and is read on
every `Write` / `Edit` tool call. Unchanged since install? You're
looking at defaults. Want to tweak them? Edit that file and restart
your Claude Code session — there is no hot-reload.

## Allow / warn / deny per phase

A write is **allowed** (exit 0, silent) if its target matches any
glob in the phase's `allow` list. It's a **warn** (exit 0 + stderr
warning) if it matches the `warn` list. Otherwise it's **denied**
(exit 2, blocking message).

| Phase | What you can write freely | What gets a warning | What's blocked |
|---|---|---|---|
| **REQUIREMENTS** | `docs/**`, `vibeflow.config.json`, `README*`, any `*.md`, `.vibeflow/**` | — | all source code, `src/**`, `tests/**` |
| **DESIGN** | REQUIREMENTS + `design/**`, `wireframes/**`, `*.css`, `*.scss`, `*.figma` | — | source code |
| **ARCHITECTURE** | DESIGN + `contracts/**`, `.vibeflow/reports/adr-*.md`, `*.d.ts` interface stubs | — | business-logic source files |
| **PLANNING** | ARCHITECTURE + `docs/sprints/**` | — | source code |
| **DEVELOPMENT** | everything (`**`) | — | — |
| **TESTING** | `**/*.test.*`, `**/*.spec.*`, `tests/**`, `test/**`, `.vibeflow/**`, docs | `src/**` (non-test) | — |
| **DEPLOYMENT** | `CHANGELOG*`, `release-notes/**`, `.github/workflows/**`, `Dockerfile*`, `docker-compose*.yml`, docs | `src/**` | — |

Two globs are **always** in the `allow` list regardless of phase so
the framework itself never self-blocks:

- `.vibeflow/**` — all state, reports, artifacts, and traces
- `vibeflow.config.json` — project settings

## What happens when a write is blocked

`phase-write-guard` exits 2 with a message like:

```
VibeFlow phase-write-guard: REQUIREMENTS phase does not permit writes
to src/foo.ts. Run /vibeflow:advance to progress the SDLC, or set
VF_ALLOW_PHASE_WRITE=1 to bypass this single call.
```

Claude Code surfaces that stderr back to the model, so the skill or
agent sees the refusal and (in a well-behaved skill) stops. The model
is expected to either:
- pick a different target that's allowed in the current phase, or
- call `/vibeflow:advance` (if the exit criteria are satisfied), or
- ask you whether to set the escape hatch.

## Escape hatches

### Per-call override

If you know what you're doing and need to bypass exactly one
`Write` / `Edit` call:

```bash
VF_ALLOW_PHASE_WRITE=1 <the tool invocation>
```

The env var is read once per hook invocation and does not persist.
If you export it for the whole session you will silently remove the
guarantee for every subsequent write — don't do that in a long
interactive session; prefer `/vibeflow:advance` if the phase is
genuinely the wrong one.

### Missing policy = allow (fail-safe)

If `hooks/scripts/phase-policy.json` is missing, malformed, or
unreadable, the guard falls back to allow. This is deliberate: the
framework never bricks a user's install over a bad config. The
integration harness `tests/integration/sprint-13.sh [S13-A]` pins the
policy file's presence to catch accidental deletions.

### Missing python3 = allow (fail-safe)

Glob matching runs through a short `python3 -c` script. If `python3`
isn't on PATH, the guard allows. Install Python 3.8+ to get the real
enforcement.

## How skills self-check

The hook is the hard gate, but five high-risk skills also carry a
"Phase Contract" block at the top of their `SKILL.md` bodies. The
contract tells the model to read `vibeflow.config.json.currentPhase`
and stop with a named message if the phase doesn't match. This
catches a mis-phased invocation even before the model reaches for a
`Write` tool — useful because a misplaced `coverage-analyzer` run
would consume coverage JSON and emit a report based on an incomplete
TESTING pass, which is worse than no report at all.

The five skills with explicit Phase Contracts as of v2.1.0:

| Skill | Allowed phases |
|---|---|
| `onboard` | REQUIREMENTS |
| `test-strategy-planner` | PLANNING |
| `component-test-writer` | DEVELOPMENT, TESTING |
| `coverage-analyzer` | TESTING |
| `release-decision-engine` | DEPLOYMENT |

The full advisory mapping for all 31 skills lives in
`skills/phase-policy.json`. Sprint 14 can turn that into a second
hook gate on skill invocations; the current release uses it only for
documentation.

## Troubleshooting

### "I only want to scaffold one file and the guard won't let me"

That's working as intended. Either the file type is wrong for the
phase (fix the path — is it really `src/` or can it be `docs/`?), or
the phase is wrong for the work (run `/vibeflow:advance`). Use
`VF_ALLOW_PHASE_WRITE=1` only if you need to audit something quickly
and plan to revert.

### "The guard is silently allowing writes that should be blocked"

Check:
1. Is the policy file present? `ls hooks/scripts/phase-policy.json`
2. Is python3 on PATH? `command -v python3`
3. Is your phase really what you think? `/vibeflow:flow-status`

The guard is fail-safe by design, which means a missing dependency
shows up as "nothing was blocked". The integration harness assertions
catch this during CI — if you see it locally and the harness passes
on main, your install is out of sync.

### "I want a different allow/deny policy for my project"

Edit `hooks/scripts/phase-policy.json`. The file is part of the
plugin distribution so your edits will persist across `git pull` as
long as you commit them. For project-local overrides without
modifying the plugin, Sprint 14 may introduce
`.vibeflow/phase-policy.overrides.json` — filed as a nice-to-have in
the Sprint 13 plan.

## Reference implementation

- Hook script: `hooks/scripts/phase-write-guard.sh`
- Policy file: `hooks/scripts/phase-policy.json`
- Hook wiring: `hooks/hooks.json` PreToolUse matcher `Write|Edit`
- Helpers: `hooks/scripts/_lib.sh` (`vf_relpath`, `vf_policy_path`,
  `vf_phase_decision`)
- Unit tests: `hooks/tests/run.sh` section `[S13-A]`
- Integration tests: `tests/integration/sprint-13.sh`

## Phase entry / exit criteria (Sprint 26-B)

Distinct from the path-write policy above, each phase declares
`entryCriteria` and `exitCriteria` (`mcp-servers/sdlc-engine/src/phases.ts`)
that gate `/vibeflow:advance`:

- **`exitCriteria`** — what the *current* phase must have satisfied to
  leave it. **Always enforced** by the validator. (e.g. TESTING exits on
  `coverage.met` + `mutation.score.acceptable` + `consensus.testing.approved`.)
- **`entryCriteria`** — what the *target* phase expects on entry. **Not
  enforced by default** (informational) — historically advance checked
  only the source phase's `exitCriteria`.

**Opt-in entry-gate.** Set `gates.enforceEntryCriteria: true` in
`vibeflow.config.json` to *also* require the target phase's
`entryCriteria` on advance. The headline case: DEPLOYMENT's entry
criterion `release.decision.go` — with the gate on, you can't enter
DEPLOYMENT until `release-decision-engine` records a GO (Sprint 26-A).
Default **off** so existing consumers are never broken mid-flight;
`force: true` bypasses both gates (structural rules still hold). See
[TESTING-READINESS.md](TESTING-READINESS.md).
