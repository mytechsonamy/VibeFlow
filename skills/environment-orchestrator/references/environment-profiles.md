# Environment Profiles

The skill picks exactly one profile from this file at Step 1 of
its algorithm. A profile declares what a test type **needs**, not
what a project **has** — projects that need more components add
them through `test-strategy.md → extraComponents`.

Profiles are not a buffet. You don't pick and choose components
mid-run; you pick a profile and the profile decides. If a real
project needs a fundamentally different shape, the fix is to add
a new profile to this file, not to flag-drive the existing ones.

---

## 1. `unit`

- **Intent:** pure, in-process tests; no external services.
- **Required components:** none
- **Optional components:** none
- **Seed policy:** none — unit tests build their own fixtures
  via `test-data-manager` factories at runtime
- **Healthcheck wait policy:** none — nothing to wait for
- **Teardown strategy:** none — no resources to clean
- **Applicable platforms:** `web` / `ios` / `android` / `backend`

**The skill emits an empty env-setup.md for this profile**
with a note saying "unit profile requires no external
environment; run the test runner directly". It runs so downstream
callers (pipeline steps) don't need a conditional branch, but
the output is intentionally boring.

---

## 2. `integration`

- **Intent:** tests that cross process boundaries locally —
  database, cache, mock external services, in-process app
- **Required components:**
  - One database (`postgres` or `mysql` — profile respects the
    project's `repo-fingerprint.json` declaration)
  - One cache (`redis`)
  - The app under test
- **Optional components** (activated via `test-strategy.md`):
  - `localstack` for AWS service mocks
  - `wiremock` for HTTP stubs
  - `mailhog` for SMTP capture
- **Seed policy:** fixture seed from `test-data-manager` output
- **Healthcheck wait policy:** all services `healthy` before seed
- **Teardown strategy:** full — every container, every named
  volume
- **Applicable platforms:** `backend` only. `integration / web`
  is covered by `e2e`; `integration / ios` and
  `integration / android` are out of scope (use `e2e`).

---

## 3. `e2e`

- **Intent:** browser/device tests that drive the UI against a
  running app, typically with in-memory or ephemeral backing
  services
- **Required components:**
  - The full `integration` profile's components (everything a
    real backend needs)
  - **Plus** the app's frontend server (vite/next/etc.)
- **Optional components:**
  - `selenium-grid` when the project targets multiple browsers
  - `appium` for mobile simulators
- **Seed policy:** factory seed — e2e scenarios usually need a
  known user + a populated cart/ledger/patient
- **Healthcheck wait policy:** all services `healthy` AND the
  frontend responds 200 on `/` before tests dispatch
- **Teardown strategy:** full
- **Applicable platforms:** `web` / `ios` / `android`

---

## 4. `uat`

- **Intent:** running UAT scenarios against a prepared staging
  environment. UAT does not usually stand up its own env; it
  validates an env that's already there.
- **Required components:** none (uat attaches to an existing
  staging env)
- **Optional components:** `smtp-trap` for email capture during
  UAT flows
- **Seed policy:** none — UAT uses the real staging seed
  because it's testing what staging looks like
- **Healthcheck wait policy:** health-probe the staging URL
  before allowing the UAT run to begin
- **Teardown strategy:** none (we didn't stand it up; we don't
  tear it down). But `env-setup.md` still documents the probe
  so UAT runs that start against a dead env fail fast instead
  of producing silent garbage.
- **Applicable platforms:** `web` / `ios` / `android`

---

## 5. `perf`

- **Intent:** performance / load tests that need a repeatable,
  isolated environment to avoid noise from other workloads.
- **Required components:**
  - Everything from `integration`
  - **Plus** `k6` or `artillery` as the load generator
  - **Plus** a metrics collector (`prom-stack` component from
    the catalog)
- **Optional components:**
  - `tempo` for distributed traces during the run
- **Seed policy:** factory seed with an explicit
  `perf: true` variant that scales the generated dataset
  (100k users instead of 10)
- **Healthcheck wait policy:** all services `healthy` AND an
  idle warm-up period before the load generator starts
- **Teardown strategy:** full + volume wipe (perf runs leave
  large datasets; leaving them is a disk leak)
- **Applicable platforms:** `backend` / `web`. `perf / ios` and
  `perf / android` are **not applicable** — mobile perf uses
  platform-specific tooling (XCTest / Macrobenchmark) and is
  out of scope for this skill. Asking for those combinations
  blocks at Step 1.

---

## 6. Profile applicability matrix

|              | web | ios | android | backend |
|--------------|-----|-----|---------|---------|
| `unit`       | ✓   | ✓   | ✓       | ✓       |
| `integration`| —   | —   | —       | ✓       |
| `e2e`        | ✓   | ✓   | ✓       | —       |
| `uat`        | ✓   | ✓   | ✓       | —       |
| `perf`       | ✓   | ✗   | ✗       | ✓       |

- **✓** — the skill emits a recipe
- **—** — the combination is semantically wrong; the skill
  redirects to the right profile in the error message
- **✗** — explicitly not applicable; the skill blocks the run

---

## 7. Profile extension via `test-strategy.md`

Projects can add optional components to a profile:

```yaml
environmentOrchestrator:
  integration:
    extraComponents:
      - localstack
      - wiremock
```

Rules:

- Every `extraComponents` entry MUST resolve to a catalog entry.
  Unknown names block the run.
- Projects can add, they cannot remove. A project that needs to
  run `integration` without redis has chosen the wrong profile —
  the fix is a new profile, not a flag on the existing one.
- Project-specific overrides are versioned with the rest of
  `test-strategy.md` so the set is audited and reviewed.

---

## 8. Adding a new profile

1. Pick a stable short name (lowercase, single word preferred).
2. Declare intent in one sentence — "tests that …".
3. List required and optional components, each resolving to a
   catalog entry (or add the catalog entry first).
4. Decide the seed policy. "None" is a valid choice; "mystery
   data" is not.
5. Document the healthcheck wait policy. If the profile has
   nothing to wait for, say so explicitly.
6. Document the teardown strategy. "None" is valid only for
   profiles that didn't stand up anything.
7. Update the applicability matrix in §6.
8. Update the integration harness sentinel that counts profiles.
