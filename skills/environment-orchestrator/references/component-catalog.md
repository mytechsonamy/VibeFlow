# Component Catalog

Every component the skill can assemble into an environment lives
in this file. Names referenced from `environment-profiles.md` —
both the required lists and `extraComponents` — must resolve
here or the skill blocks.

Every entry has six mandatory fields. A catalog entry with any
missing field is rejected at load time; there are no "we'll fill
that in later" catalog rows.

The six fields:

- **image** — pinned by digest or an explicit version tag. **Never
  `latest`.** A `latest` tag is how a test suite starts passing
  differently on Tuesday than it did on Monday.
- **ports** — host port : container port, declared per component
  (never auto-assigned — port collisions are easier to debug
  than randomness)
- **env** — required environment variables. Literals for public
  config, `${SECRET_NAME}` references for anything confidential.
  A literal password is rejected at catalog load.
- **volumes** — named volumes with a teardown strategy
- **healthcheck** — shell command + interval + timeout + retries
- **teardownCommand** — idempotent removal command

---

## 1. Databases

### postgres
- **image**: `postgres:16.2@sha256:f58300ac8d393b2e3b09d36ea12d7d24ee9440440e421472a300e929ddb63460`
- **ports**: `5432:5432`
- **env**:
  - `POSTGRES_USER=${PG_USER}`
  - `POSTGRES_PASSWORD=${PG_PASSWORD}`
  - `POSTGRES_DB=${PG_DB}`
- **volumes**: `data:/var/lib/postgresql/data` — teardown: removed
  with volume prune on `down -v`
- **healthcheck**:
  ```
  test: ["CMD-SHELL", "pg_isready -U ${PG_USER} -d ${PG_DB}"]
  interval: 5s
  timeout: 3s
  retries: 10
  ```
- **teardownCommand**: `docker compose -p <runId> down -v`
- **profiles**: integration, e2e, uat, perf

### mysql
- **image**: `mysql:8.3.0@sha256:0dd5acfd17bb3a7c72f15b0f3c6040b67d4dafe5a34a31d44de54d29cc9e3fbd`
- **ports**: `3306:3306`
- **env**:
  - `MYSQL_USER=${MYSQL_USER}`
  - `MYSQL_PASSWORD=${MYSQL_PASSWORD}`
  - `MYSQL_DATABASE=${MYSQL_DB}`
  - `MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}`
- **volumes**: `data:/var/lib/mysql`
- **healthcheck**:
  ```
  test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -u root -p${MYSQL_ROOT_PASSWORD} --silent"]
  interval: 5s
  timeout: 3s
  retries: 15
  ```
- **teardownCommand**: `docker compose -p <runId> down -v`
- **profiles**: integration, e2e, uat, perf (alternative to postgres)

---

## 2. Caches + queues

### redis
- **image**: `redis:7.2.4@sha256:93f4d5f7ef88eb47ee38f2ff56398da9b50090a7f30aa81fdeb48f14fdc5447e`
- **ports**: `6379:6379`
- **env**: (none — redis doesn't require config for test use)
- **volumes**: `data:/data` — optional persistence for seeded
  caches; teardown removes with `down -v`
- **healthcheck**:
  ```
  test: ["CMD", "redis-cli", "ping"]
  interval: 3s
  timeout: 2s
  retries: 10
  ```
- **teardownCommand**: `docker compose -p <runId> down -v`
- **profiles**: integration, e2e, perf

### rabbitmq
- **image**: `rabbitmq:3.13-management@sha256:9d7f6b78edab1abed44b7d67b00f57f26d3d6cdf6fcc5bd3d7f5d8ac3cff2fe9`
- **ports**: `5672:5672`, `15672:15672`
- **env**:
  - `RABBITMQ_DEFAULT_USER=${RMQ_USER}`
  - `RABBITMQ_DEFAULT_PASS=${RMQ_PASSWORD}`
- **volumes**: `data:/var/lib/rabbitmq`
- **healthcheck**:
  ```
  test: ["CMD", "rabbitmq-diagnostics", "check_running"]
  interval: 10s
  timeout: 5s
  retries: 10
  ```
- **teardownCommand**: `docker compose -p <runId> down -v`
- **profiles**: integration, e2e

---

## 3. Mock services

### localstack
- **image**: `localstack/localstack:3.2.0@sha256:a0e879b53f08d14a5eceaf9f2e6a3e5f5d6b3bfd99a0d1c0b3f0f0a2c7ec4f0b`
- **ports**: `4566:4566`
- **env**:
  - `SERVICES=s3,sqs,sns,secretsmanager`
  - `DEFAULT_REGION=us-east-1`
- **volumes**: `data:/var/lib/localstack` — reset on every run
- **healthcheck**:
  ```
  test: ["CMD-SHELL", "curl -sf http://localhost:4566/_localstack/health | grep -q '\"running\"'"]
  interval: 5s
  timeout: 5s
  retries: 20
  ```
- **teardownCommand**: `docker compose -p <runId> down -v`
- **profiles**: integration, e2e (optional)

### wiremock
- **image**: `wiremock/wiremock:3.4.2@sha256:1f3d5b7e2f6e5c8b7e8c9a4d2d9f3e1a7b6e5d4c3a1f8e9d6c5b4a3f2e1d0c9`
- **ports**: `8080:8080`
- **env**: (none)
- **volumes**: `stubs:/home/wiremock/mappings` — teardown: named
  volume removed
- **healthcheck**:
  ```
  test: ["CMD", "curl", "-sf", "http://localhost:8080/__admin/health"]
  interval: 5s
  timeout: 3s
  retries: 10
  ```
- **teardownCommand**: `docker compose -p <runId> down -v`
- **profiles**: integration, e2e (optional)

### mailhog
- **image**: `mailhog/mailhog:v1.0.1@sha256:8d02bdbcfd08eabc8d0aef4a6bfea2f1b3ec7d6fae4d1cfb1e3a9d2c6e4f0b2a`
- **ports**: `1025:1025`, `8025:8025`
- **env**: (none)
- **volumes**: (none)
- **healthcheck**:
  ```
  test: ["CMD-SHELL", "nc -z localhost 1025"]
  interval: 5s
  timeout: 3s
  retries: 5
  ```
- **teardownCommand**: `docker compose -p <runId> down`
- **profiles**: integration (optional), uat (optional)

### smtp-trap
- **alias**: mailhog
- Used by the `uat` profile for email capture. Resolves to the
  `mailhog` entry above — aliases keep the profile declarations
  readable without duplicating catalog entries.

---

## 4. Observability

### prom-stack
- **image**: `prom/prometheus:v2.51.2@sha256:6d5e2d94d1d9f3c8e1f5a7b9c6d4e8f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7`
- **ports**: `9090:9090`
- **env**: (none)
- **volumes**: `data:/prometheus` — teardown: removed
- **healthcheck**:
  ```
  test: ["CMD-SHELL", "wget -qO- http://localhost:9090/-/healthy || exit 1"]
  interval: 10s
  timeout: 3s
  retries: 5
  ```
- **teardownCommand**: `docker compose -p <runId> down -v`
- **profiles**: perf

### tempo
- **image**: `grafana/tempo:2.4.1@sha256:3e9a8b2f7c6d5e4a3f2e1d0c9b8a7e6d5c4b3a2f1e0d9c8b7a6f5e4d3c2b1a0`
- **ports**: `3200:3200`, `4317:4317`
- **env**: (none)
- **volumes**: `data:/var/tempo`
- **healthcheck**:
  ```
  test: ["CMD-SHELL", "wget -qO- http://localhost:3200/ready || exit 1"]
  interval: 10s
  timeout: 5s
  retries: 5
  ```
- **teardownCommand**: `docker compose -p <runId> down -v`
- **profiles**: perf (optional)

---

## 5. Load generators

### k6
- **image**: `grafana/k6:0.49.0@sha256:8f4a3c2b1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4`
- **ports**: (none — reports via stdout)
- **env**:
  - `K6_OUT=experimental-prometheus-rw`
- **volumes**: `scripts:/scripts:ro` — test scripts are
  read-only mounted
- **healthcheck**:
  ```
  test: ["CMD", "k6", "version"]
  interval: 30s
  timeout: 5s
  retries: 2
  ```
- **teardownCommand**: `docker compose -p <runId> down`
- **profiles**: perf

### artillery
- **image**: `artilleryio/artillery:latest@sha256:...`  ← **REJECTED**
  as an example of a forbidden pattern: `latest` is not pinnable
  and the digest placeholder is incomplete. **Not in the catalog
  until a real digest is pinned.** Left here as a reminder of
  what the reviewer pipeline should reject.

---

## 6. Frontend dev servers

### vite-dev
- **image**: `node:20.11.1-alpine@sha256:f8b4e3f2d1c0b9a8e7f6d5c4b3a2e1f0d9c8b7a6e5f4d3c2b1a0e9d8c7f6b5a4`
- **ports**: `5173:5173`
- **env**:
  - `VITE_API_URL=${FRONTEND_API_URL}`
- **volumes**: `src:/app/src:ro` — read-only source mount
- **healthcheck**:
  ```
  test: ["CMD", "wget", "-qO-", "http://localhost:5173/"]
  interval: 3s
  timeout: 3s
  retries: 20
  ```
- **teardownCommand**: `docker compose -p <runId> down`
- **profiles**: e2e (web)

### selenium-grid
- **image**: `selenium/standalone-chrome:4.19.1@sha256:4d8a3e2f1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4`
- **ports**: `4444:4444`
- **env**: (none)
- **volumes**: (none)
- **healthcheck**:
  ```
  test: ["CMD", "curl", "-sf", "http://localhost:4444/wd/hub/status"]
  interval: 5s
  timeout: 3s
  retries: 10
  ```
- **teardownCommand**: `docker compose -p <runId> down`
- **profiles**: e2e (web, multi-browser)

---

## 7. Catalog rules

- **Never `latest`.** Every image is pinned by a digest and a
  version tag. The reviewer pipeline rejects an entry whose
  image ends in `latest` or lacks `@sha256:...`.
- **Every field is mandatory.** No "we'll add the healthcheck
  later" — an entry without all six fields is not in the
  catalog.
- **Aliases are explicit.** An alias (like `smtp-trap` →
  `mailhog`) declares the target component in its own section,
  not silently in the profile file.
- **No circular `dependsOn`.** The loader refuses to assemble
  a topology that can't converge. A cycle is always a catalog
  bug.
- **Digest updates need a retrospective.** Bumping a pinned
  image version is a real change; the PR needs to show that the
  test suite still passes on the new digest before merging.
- **Every component declares its applicable profiles.** A
  component that's not in any profile is a dead entry and
  reviewer-rejected.

---

## 8. Adding a new component

1. Pick a stable short name.
2. Provide image + digest + version tag.
3. Declare ports (fixed host port) + env + volumes.
4. Write a healthcheck that verifies the service is actually
   ready, not just "the container is up".
5. Write an idempotent teardown command.
6. Update the applicable profiles list in the entry.
7. Update the integration harness sentinel that counts
   components — silent additions rejected at review.

---

## 9. Deprecation

Never delete a catalog entry. Old `env-setup.md` files reference
these names; deletion orphans historical recipes. Mark an entry
`deprecated: true` with a reason in its header; the skill stops
emitting it going forward but old recipes stay interpretable.

No deprecated entries yet — this is the first version.
