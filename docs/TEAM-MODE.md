# Team Mode

Solo mode is the zero-config default — SQLite, single-AI reviews,
light hooks. Team mode is what you switch to when more than one
developer is working on the same project: PostgreSQL state, three-AI
consensus reviews, full hook strictness, collaborative phase advances.

This doc walks the full team-mode setup. If you're working alone,
stay in solo mode — team mode adds operational overhead that only
pays off with multiple contributors.

## 1. When to switch

Switch to team mode when **any** of these are true:

- More than one developer is committing to the same project
- You need an audit trail of who advanced which phase
- You want multi-AI consensus reviews (Claude + ChatGPT + Gemini)
- You need concurrent SDLC operations on the same project (SQLite serializes; Postgres handles)
- You want CI to record consensus verdicts via the
  `consensus-aggregator` hook from multiple machines

Stay in solo mode when:

- You're prototyping or running the demo
- You're working alone on a personal project
- You don't want to run a Postgres instance

## 2. PostgreSQL setup

The sdlc-engine MCP server speaks the same SQL schema in both
backends, so a project can migrate solo → team without losing
state.

### Minimum requirements

- PostgreSQL 14 or later
- Network reachability from every machine that will run
  Claude Code (or a single shared host with all developers
  SSH-tunneling)
- A dedicated database (recommended: `vibeflow_<project_id>`)
- A user with `CREATE`, `SELECT`, `INSERT`, `UPDATE`, `DELETE` on
  that database

### Create the database

```sql
CREATE DATABASE vibeflow_myproject;
CREATE USER vibeflow WITH PASSWORD 'change-me-now';
GRANT ALL PRIVILEGES ON DATABASE vibeflow_myproject TO vibeflow;
\c vibeflow_myproject
GRANT ALL ON SCHEMA public TO vibeflow;
```

### Schema

The sdlc-engine creates the schema lazily on first connect. You do
not need to run any DDL by hand. The schema is one table:

```sql
CREATE TABLE project_state (
  project_id          TEXT    PRIMARY KEY,
  current_phase       TEXT    NOT NULL,
  satisfied_criteria  TEXT    NOT NULL,
  last_consensus      TEXT,
  updated_at          TEXT    NOT NULL,
  revision            INTEGER NOT NULL
);
```

Same shape as the SQLite version (see
[docs/MCP-SERVERS.md](./MCP-SERVERS.md#schema)). The `revision`
column is the CAS cursor — every write increments it, and
concurrent writers re-read on conflict. PostgreSQL's row-level
locking handles the actual concurrency.

### Connection pool

The sdlc-engine uses `pg.Pool` with these defaults:

| Setting | Default | Why |
|---------|---------|-----|
| `max` | 10 | Enough for 5-10 concurrent Claude sessions |
| `idleTimeoutMillis` | 30000 | Close idle clients after 30s |
| `connectionTimeoutMillis` | 5000 | Fail fast on a hung dial |

Idle-client errors (`pg idle client error: idle client lost
connection`) are logged but not propagated — the pool reconnects
on the next query. If you see this happen on every read, the
Postgres host is dropping idle connections too aggressively;
increase your `idle_in_transaction_session_timeout`.

### Supported Postgres versions

VibeFlow exercises its state store against **PG13 / PG14 / PG15 /
PG16** in the sprint-7.sh [S7-E] matrix runner (opt-in via
`VF_RUN_PG_MATRIX=1`; the default CI run pins `postgres:14-alpine`
to keep the gauntlet fast). Anything in the
[Postgres support window](https://www.postgresql.org/support/versioning/)
works — the queries use only SQL features stable since PG9.1, and
`pg_advisory_xact_lock` is stable since PG8.2.

To run the matrix locally:

```bash
# Default matrix (PG13 → PG16)
bash bin/with-postgres-matrix.sh bash tests/integration/sprint-5.sh

# Narrow to one version
VF_PG_IMAGES="postgres:16-alpine" bash bin/with-postgres-matrix.sh \
  bash tests/integration/sprint-6.sh

# Widen to include a managed-cloud simulator image
VF_PG_IMAGES="postgres:13-alpine postgres:16-alpine timescale/timescaledb:latest-pg16" \
  bash bin/with-postgres-matrix.sh bash tests/integration/sprint-5.sh
```

### Managed-cloud Postgres (AWS RDS, GCP Cloud SQL, Azure)

VibeFlow's state store is pure SQL — no stored procedures, no
version-specific syntax, no extensions required. Managed Postgres
services run it unchanged, with three specific caveats:

1. **Require SSL.** AWS RDS and GCP Cloud SQL default to
   `sslmode=require`. Add it to the connection string:

   ```
   postgresql://user:pass@mydb.us-east-1.rds.amazonaws.com:5432/vibeflow?sslmode=require
   ```

   Without `sslmode=require`, the connection is refused and the
   `[sdlc-engine] pg connect failed for project <id>` error surfaces
   at first tool call.

2. **PgBouncer transaction-pool caveat.** If your managed Postgres
   sits behind PgBouncer in `transaction` pool mode, advisory locks
   can get handed back to a different backend mid-request, which
   defeats the `pg_advisory_xact_lock` serialization. Two fixes:
   - Switch the pool to `session` mode (safer, slightly less
     efficient)
   - OR point VibeFlow at the direct Postgres endpoint, not the
     PgBouncer pooler. RDS and Cloud SQL both expose a direct
     endpoint alongside the pooler endpoint.

   The v1.2 state store does NOT detect this misconfiguration at
   runtime — you only see its effects as occasional stale-read
   failures under concurrent load. A follow-up ticket will add a
   startup probe that rejects transaction-mode poolers explicitly.

3. **IAM / OIDC authentication.** Currently out of scope — the
   v1.2 client authenticates with a username + password only. If
   your managed Postgres requires IAM-token auth (AWS RDS IAM auth,
   Cloud SQL IAM auth), you need to provision the token externally
   and rotate the `db_connection` string in Claude Code settings on
   each rotation. A future ticket will wire IAM auth into the
   connect path.

## 3. Switch to team mode

### a. Set the connection string

In Claude Code settings → Plugins → vibeflow → set
`db_connection`:

```
postgresql://vibeflow:change-me-now@db.internal:5432/vibeflow_myproject
```

This value is **sensitive** — Claude Code stores it locally and
flows it into the sdlc-engine MCP via the `userConfig` template
substitution. It is never written to your project's source.

### b. Update `vibeflow.config.json`

```json
{
  "project": "myproject",
  "mode": "team",
  "domain": "e-commerce",
  ...
}
```

The `mode: "team"` switch tells every hook to use 3-reviewer quorum
instead of 1, and tells the sdlc-engine to use the Postgres backend
instead of SQLite.

### c. Migrate state from solo to team (optional)

If you started in solo mode and accumulated state, migrate it
before flipping the mode:

```bash
sqlite3 .vibeflow/state.db .dump > /tmp/solo-state.sql
# clean up the SQLite-specific syntax for Postgres compatibility:
sed -i 's/INSERT INTO/INSERT INTO/g' /tmp/solo-state.sql
psql $DATABASE_URL -f /tmp/solo-state.sql
```

The schemas are compatible at the `INSERT INTO project_state ...`
level. If the dump contains SQLite pragmas (lines starting with
`PRAGMA` or `BEGIN TRANSACTION`), strip them before running.

### d. Verify

```
/vibeflow:status
```

The status command prints `mode=team` and reads from Postgres on
the next call. The first read warm-starts the connection pool.

## 4. Multi-AI consensus

Team mode uses three reviewers in parallel:

| Reviewer | CLI | Default model | Configurable via |
|----------|-----|---------------|------------------|
| Claude | (built-in) | `claude-sonnet-4-6` | `vibeflow.config.json → models.claude` |
| ChatGPT | `codex` | `gpt-4o` | `userConfig.openai_model` |
| Gemini | `gemini` | `gemini-2.0-flash` | `userConfig.gemini_model` |

### Install the CLIs

You only need the CLIs for the reviewers you want to use. Set the
corresponding model id to an empty string in `userConfig` to skip
that reviewer entirely.

```bash
# OpenAI's codex CLI
npm install -g @openai/codex

# Google's gemini CLI
npm install -g @google/gemini-cli
```

Each CLI authenticates separately (codex uses `OPENAI_API_KEY`,
gemini uses `GOOGLE_API_KEY` or service account). Set those in
your shell, NOT in `userConfig` — they're per-machine secrets.

### Consensus thresholds (CLAUDE.md)

| Verdict | Condition |
|---------|-----------|
| **APPROVED** | ≥ 90% agreement AND 0 critical issues |
| **NEEDS_REVISION** | 50%-89% agreement |
| **REJECTED** | < 50% agreement OR ≥ 2 critical issues |

A 3-reviewer batch with 2 APPROVED + 1 REJECTED produces 67%
agreement → NEEDS_REVISION (unless the REJECTED reviewer flagged
2+ critical issues, which forces REJECTED regardless of agreement).

### Quorum + timeout

Team mode expects 3 reviewer entries before finalizing the
verdict. If a reviewer never reports back (rate-limited, crashed,
network dropped), the `consensus-aggregator` hook waits up to
**600 seconds** then force-finalizes the batch with `timeout:
true`. When the timeout fires:

- An APPROVED status is **demoted to NEEDS_REVISION** — a partial
  quorum cannot ship a clean APPROVED verdict because the missing
  reviewer could have objected
- The verdict file records `expectedReviewers: 3`,
  `receivedReviewers: 2`, `timeout: true` for downstream auditing

This is the S4-02 hardening — see
[docs/HOOKS.md#consensus-aggregator-sh](./HOOKS.md#consensus-aggregatorsh).

## 5. Collaborative phase advances

Solo mode auto-advances the phase as soon as criteria are met. Team
mode requires:

1. Every entry criterion is satisfied
2. The most recent consensus verdict for the source phase is
   APPROVED (not NEEDS_REVISION, not REJECTED)
3. A human triggers `/vibeflow:advance` (no auto-advance even when
   the criteria are met — explicit consent is required)

This is enforced by the sdlc-engine's `advance_phase` tool in team
mode. Attempting to advance without an APPROVED consensus returns
a clear error and leaves the phase unchanged.

### Example team flow

```
Developer A:
  /vibeflow:prd-quality-analyzer docs/PRD.md
  /vibeflow:test-strategy-planner docs/PRD.md
  /vibeflow:advance DESIGN          # auto: PRD criteria met

Developer B (different machine, same project):
  /vibeflow:status                  # sees phase=DESIGN, no consensus yet
  /vibeflow:component-test-writer src/foo.ts
  # multi-AI review fires automatically because the diff is > 50 lines
  # consensus-aggregator records 3 verdicts, finalizes APPROVED
  /vibeflow:advance ARCHITECTURE    # works: consensus.approved present
```

If Developer C tries to advance without an APPROVED consensus, the
engine refuses:

```
Cannot advance to DESIGN: missing consensus.approved (last verdict: NEEDS_REVISION).
Run /vibeflow:consensus-orchestrator to re-trigger reviewers.
```

## 6. Hook strictness

Team mode enables the full hook set. The notable differences vs
solo:

| Hook | Solo behavior | Team behavior |
|------|---------------|---------------|
| `commit-guard` | phase block + format check | phase block + format check + critical-path additional checks |
| `trigger-ai-review` | no-op | writes review marker for diffs ≥ 50 lines |
| `consensus-aggregator` | quorum = 1 | quorum = 3 + timeout force-finalize |
| `compact-recovery` | snapshot + integrity check | + warns when consensus is stale (> 1 hour) |
| `post-edit` | trace logging | trace logging (same) |
| `test-optimizer` | cache + hint | cache + hint (same) |
| `load-sdlc-context` | reads SQLite | reads PostgreSQL |

## 7. Domain quality thresholds

Team mode does NOT change the domain thresholds. The same gates
apply (financial GO ≥ 90, healthcare GO ≥ 95, e-commerce GO ≥ 85,
general GO ≥ 80). What team mode adds is the consensus dimension
on TOP of the gate scores — a project can clear every gate
individually but still get a NEEDS_REVISION consensus if two of
the three reviewers disagree about overall quality.

## 8. Common team-mode failures

| Symptom | Most likely cause | Fix |
|---------|-------------------|-----|
| `pg: connection refused` | Postgres host unreachable from the dev machine | Check VPN / firewall / SSH tunnel |
| `pg idle client error: idle client lost connection` | Transient — pool reconnects | Ignore unless persistent |
| `consensus quorum not reached` | One reviewer's CLI not installed | Install codex / gemini OR set the corresponding userConfig key to `""` |
| `consensus verdict APPROVED demoted to NEEDS_REVISION` | Timeout fired with partial quorum | Investigate which reviewer is unresponsive — may be a rate-limit issue |
| `Cannot advance to DESIGN: missing consensus.approved` | Last verdict was NEEDS_REVISION or REJECTED | Re-run consensus-orchestrator after addressing the feedback |
| `state.db database is locked` (in solo) | Two sessions on the same project | Migrate to team mode |

## 9. Switching back to solo

Set `mode: "solo"` in `vibeflow.config.json` and clear
`userConfig.db_connection`. The sdlc-engine reads from SQLite on
the next call. State doesn't migrate automatically — if you want
the team-mode Postgres state in your local SQLite, dump it first:

```bash
pg_dump -t project_state $DATABASE_URL > /tmp/team-state.sql
sqlite3 .vibeflow/state.db < /tmp/team-state.sql
```

The schemas are compatible at the `INSERT INTO project_state`
level. Strip any Postgres-specific bits (sequences, ownership)
before importing.
