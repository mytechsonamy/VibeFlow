# Sprint 59 — Make the integration gate stack-agnostic (Python / Go / .NET backends, framework-less frontends) (v2.47.0)

## Context

Sprint 58 added the front↔back integration gate (`integration-wiring-check.sh`
detector + `integration-verifier` skill), but both are **JS/TS-only** — they grep
for `express`/`fastify`/`next` and JS `http.createServer`, and split source dirs
by the nearest **`package.json`**. A live Clera session exposed the blind spot:
Clera's backend is **Python (FastAPI)** with a static-HTML design surface, so the
detector reads `no-app`/`single-tier` and the gate never fires — exactly the
"backend claimed working, never seen running with a UI" situation the gate exists
to catch. (Clera's *current* increment is legitimately backend-only/single-tier;
the gap is that even on a future frontend increment the gate would stay dormant
because it can't recognise a Python/Go/.NET backend.)

A concrete proof from that session: a `|`-vs-`-` corruption
(`abs(txn.amount | d.gross_total)`) survived 94 tests at 100 % coverage and only
surfaced the **first time the engine was actually run** through an integration
path — reinforcing that integration execution is a distinct, irreplaceable signal.

Outcome wanted: the detector + verifier recognise the common backend stacks and
framework-less frontends, so the integration gate fires (or correctly skips) on
non-JS projects the same way it does on JS ones — **stack-agnostic**.

## Approach

Extend the two Sprint-58 artifacts; reuse VibeFlow's existing **manifest-first**
stack vocabulary (`skills/repo-fingerprint/SKILL.md` L14-15:
`pyproject.toml`/`go.mod`/`Cargo.toml`/`pom.xml`/`build.gradle`) and the
`tech.*` / `vf_config_get` command-resolution pattern (`skills/quality-gates` +
phase-runner Step 2a, Sprint 29). **Skill + hook + docs only — no engine/MCP/Zod
change** (parity with Sprint 58); backend boot-command overrides ride on env vars,
not a new config key, to avoid the EngineConfigSchema strictness question.

### S59-A — `integration-wiring-check.sh`: stack-agnostic backend detection
Rewrite the detection core in `hooks/scripts/integration-wiring-check.sh` while
keeping the four-status contract (`wired`/`unwired`/`single-tier`/`no-app`) and
the FE-vs-BE dir-split discipline (so a front-end `axios.get(` is never read as a
server route):
- **Backend project roots** = a dir whose manifest marks a server stack:
  `pyproject.toml`/`requirements.txt`/`setup.py` (Python), `go.mod` (Go),
  `*.csproj`/`*.sln` (.NET), `pom.xml`/`build.gradle*` (Java), `Cargo.toml`
  (Rust), or `package.json` with a JS server dep (existing).
- **Backend serves routes?** — per-language route-handler patterns, scoped to the
  backend dirs only: Python (`@app.(get|post|…)(`, `@router.`, `APIRouter(`,
  `add_api_route`, `@app.route(`, Django `urlpatterns`/`path(`); Go
  (`http.HandleFunc`, `ListenAndServe`, `.GET(`/`.POST(`, `mux.Handle`); .NET
  (`app.Map(Get|Post|…)(`, `[HttpGet]`, `[Route(`, `ControllerBase`); Java/Spring
  (`@GetMapping`, `@PostMapping`, `@RequestMapping`, `@RestController`); plus the
  existing JS + Next-API-dir patterns.
- **Server present (no routes yet)?** — language server entry signals
  (`uvicorn`/`gunicorn`/`FastAPI(`/`Flask(`, `http.ListenAndServe`,
  `WebApplication`/`MapControllers`) so a backend that boots but serves nothing →
  still `unwired`.
- **Frontend** stays a client-rendered web UI, but **framework-optional**: a web
  entry (`index.html`/framework config) **with** client-side server calls
  (`fetch`/`axios`/`useQuery`/`/api/`), even without a JS framework dep. The
  existing `fe_calls` requirement keeps pure static **design mockups** (no fetch,
  often under `design/`) classified `single-tier` — they are not a frontend.
- Fail-safe + surface-only unchanged. The header comment documents the supported
  stacks + the heuristic.

### S59-B — `integration-verifier`: boot non-JS backends
In `skills/integration-verifier/SKILL.md` Step 1, generalise "resolve the
start/dev command": detect the backend stack (manifest-first) and resolve a run
command — Python (`uvicorn <app>:app` / `python -m <pkg>` / a `tech.testRunner`-
adjacent run script), Go (`go run ./...`), .NET (`dotnet run`), Node (existing) —
honouring **`VF_BACKEND_CMD`** / **`VF_BACKEND_PORT`** env overrides when set. The
"no HTTP server at all → BLOCKED" rule now explicitly covers a Python/Go library
with no server entry (the Clera shape). Step 2 seeding stays "via
`test-data-manager` or the backend's own seed path" (already language-general).
Add `python`/`uvicorn`/`gunicorn`/`go`/`dotnet` to `allowed-tools`.

### S59-C — phase-runner prose touch-up
The DEVELOPMENT/TESTING wiring already *calls* the detector, so no logic change —
just note in the two surfacing blocks (`skills/phase-runner/SKILL.md`) that the
detector is **stack-agnostic** (Python/Go/.NET backends), so the `unwired`
surfacing + the TESTING `integration-verifier` gate apply regardless of language.

### S59-D — docs
`docs/INTEGRATION-TESTING.md`: a **"Supported stacks"** section (the backend
matrix + framework-less frontends + the `VF_BACKEND_CMD`/`VF_BACKEND_PORT`
override + the note that a purely server-rendered app has no separate FE↔BE wire
to verify → single-tier). Cross-link the Clera-style Python case.

### S59-E — tests + bookkeeping
- New `tests/integration/sprint-59.sh` mirroring `sprint-58.sh`: runtime detector
  probes for each stack — Python FastAPI routes + JS UI fetch → `wired`; Python
  backend, UI fetch, no routes → `unwired`; Go routes + UI fetch → `wired`; .NET
  `MapGet` + UI fetch → `wired`; Python backend-only (no UI) → `single-tier`;
  framework-less static `index.html` + `fetch` + Python routes → `wired`; the
  Sprint-58 JS fixtures **still pass** (regression); axios-in-FE guard holds.
  Plus skill/doc sentinels (`VF_BACKEND_CMD`, stacks, allowed-tools) + `[S59-Z]`.
- Bump version → **v2.47.0** (`.claude-plugin/plugin.json` + `marketplace.json` +
  README badge — *don't forget the badge*, it gates the release workflow),
  CHANGELOG `[2.47.0]` entry, CLAUDE.md ledger (test-layer bullet + Sprint 59
  history entry).
- Keep `sprint-58.sh` + `run.sh` green.

## Verification

- `bash tests/integration/sprint-59.sh` — new stack probes green.
- `bash tests/integration/sprint-58.sh` — JS regression still 47/0.
- `bash tests/integration/run.sh` + `bash tests/integration/sprint-4.sh` — baseline + the README-badge==plugin.json check green.
- Manual: run `integration-wiring-check.sh` on a Python+UI fixture (→ `wired`/`unwired`) and a Python-backend-only fixture (→ `single-tier`); confirm a JS fixture is unchanged.

## Out of scope
- No EngineConfigSchema/MCP change (env-var overrides instead of a new `tech.*` key).
- Server-rendered template frontends (Jinja/Razor/ERB) → treated as single-tier (no decoupled wire to verify); not a target this sprint.
- The Clera `|`-bug and Clera's own increment decisions live in that project, not here — this sprint only makes VibeFlow's gate able to *see* such stacks.
