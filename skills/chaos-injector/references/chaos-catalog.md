# Chaos Catalog

Every chaos type the skill is allowed to inject lives in this
file. A type not in the catalog is not a thing; the skill
refuses to make one up. Inventing a new chaos type at prompt
time would bypass the review that decided which failures we
should be able to reason about.

Every entry has eight mandatory fields:

- **id** — stable identifier cited in reports
- **category** — `network` / `dependency` / `clock` / `resource`
- **applicableProfiles** — `gentle` / `moderate` / `brutal` subset
- **targetKinds** — which component kinds the chaos can attack
- **injectCommand** — the shell/API call that applies the chaos
- **observeProbes** — probe names from the env-setup that capture
  the expected signal
- **recoveryCommand** — the matching rollback; must be idempotent
- **maxBlastRadiusSeconds** — how long the chaos can run before
  the blast-radius watcher aborts

A catalog entry missing any of the eight is rejected at load
time. There are no "draft" entries, no "we'll fill that in later".

---

## 1. Network — latency injection

### net-latency-low
- **category**: network
- **applicableProfiles**: `gentle`, `moderate`, `brutal`
- **targetKinds**: component (any container with a network
  interface)
- **injectCommand**:
  ```
  docker exec <target> tc qdisc add dev eth0 root netem delay 100ms 20ms
  ```
  Adds 100ms ± 20ms latency on the target container's primary
  interface.
- **observeProbes**: request-duration, p99-latency, client-error-rate
- **recoveryCommand**:
  ```
  docker exec <target> tc qdisc del dev eth0 root
  ```
- **maxBlastRadiusSeconds**: 60
- **notes**: The gentlest chaos type in the catalog. Apply first
  in any smoke-test-style chaos run to confirm the observation
  probes work before escalating.

### net-latency-high
- **category**: network
- **applicableProfiles**: `moderate`, `brutal`
- **targetKinds**: component
- **injectCommand**:
  ```
  docker exec <target> tc qdisc add dev eth0 root netem delay 1000ms 200ms distribution normal
  ```
  1-second mean, normally distributed ± 200ms.
- **observeProbes**: request-duration, p99-latency, circuit-breaker-state
- **recoveryCommand**:
  ```
  docker exec <target> tc qdisc del dev eth0 root
  ```
- **maxBlastRadiusSeconds**: 90
- **notes**: Tests whether upstream clients retry / back off /
  trip their circuit breaker. Cascading failures at this
  intensity on the `gentle` profile are blocked by the gate
  (and `gentle` doesn't list this type anyway).

---

## 2. Network — connection loss

### net-drop-small
- **category**: network
- **applicableProfiles**: `gentle`, `moderate`, `brutal`
- **targetKinds**: component
- **injectCommand**:
  ```
  docker exec <target> tc qdisc add dev eth0 root netem loss 5%
  ```
- **observeProbes**: client-retry-count, request-success-rate
- **recoveryCommand**:
  ```
  docker exec <target> tc qdisc del dev eth0 root
  ```
- **maxBlastRadiusSeconds**: 60

### net-drop-large
- **category**: network
- **applicableProfiles**: `moderate`, `brutal`
- **targetKinds**: component
- **injectCommand**:
  ```
  docker exec <target> tc qdisc add dev eth0 root netem loss 40%
  ```
- **observeProbes**: client-retry-count, circuit-breaker-state, error-rate
- **recoveryCommand**:
  ```
  docker exec <target> tc qdisc del dev eth0 root
  ```
- **maxBlastRadiusSeconds**: 90

---

## 3. Dependency — service unavailability

### dep-stop
- **category**: dependency
- **applicableProfiles**: `moderate`, `brutal`
- **targetKinds**: database, cache, mock-service
- **injectCommand**:
  ```
  docker stop <target>
  ```
- **observeProbes**: dependent-service-health, error-rate, queue-depth
- **recoveryCommand**:
  ```
  docker start <target>
  docker exec <target> <healthcheck command>
  ```
  Recovery verifies health before returning.
- **maxBlastRadiusSeconds**: 120
- **notes**: The bluntest dependency chaos. Tests whether the
  system degrades gracefully when a dependency is wholly
  unavailable (auth via cache, read-through fallback, queue
  backpressure).

### dep-slow
- **category**: dependency
- **applicableProfiles**: `gentle`, `moderate`, `brutal`
- **targetKinds**: database, cache, mock-service
- **injectCommand**:
  ```
  docker exec <target> tc qdisc add dev eth0 root netem delay 2000ms
  ```
  Makes the dependency respond slowly rather than failing.
- **observeProbes**: request-duration, timeout-rate, retry-count
- **recoveryCommand**:
  ```
  docker exec <target> tc qdisc del dev eth0 root
  ```
- **maxBlastRadiusSeconds**: 90
- **notes**: `gentle` profile uses this in the 2s variant; anything
  harsher moves to `moderate` or `brutal`.

---

## 4. Clock — time skew

### clock-skew-future
- **category**: clock
- **applicableProfiles**: `moderate`, `brutal`
- **targetKinds**: component (applications with clock
  dependencies)
- **injectCommand**:
  ```
  docker exec <target> faketime '+5 minutes'
  ```
  Requires `libfaketime` in the target image. The skill checks
  for its presence at preflight; targets without `faketime`
  block this injection type.
- **observeProbes**: token-validity-check, session-expiry,
  scheduled-task-drift
- **recoveryCommand**:
  ```
  docker exec <target> kill -HUP 1
  ```
  Restarts the target to clear `faketime`'s LD_PRELOAD. Verified
  via healthcheck.
- **maxBlastRadiusSeconds**: 60
- **notes**: The 5-minute default is narrow so most JWT
  expirations don't trip; to test expiry paths, a scenario with
  explicit `chaosParameters: { skewSeconds: 3600 }` moves to a
  1-hour skew and requires the `brutal` profile.

### clock-skew-past
- **category**: clock
- **applicableProfiles**: `moderate`, `brutal`
- **targetKinds**: component
- **injectCommand**:
  ```
  docker exec <target> faketime '-5 minutes'
  ```
- **observeProbes**: token-validity-check, signing-time-check,
  replay-protection
- **recoveryCommand**:
  ```
  docker exec <target> kill -HUP 1
  ```
- **maxBlastRadiusSeconds**: 60
- **notes**: Past-skew tests signature validation and replay
  windows that future-skew doesn't hit.

---

## 5. Resource — exhaustion

### cpu-stress
- **category**: resource
- **applicableProfiles**: `brutal`
- **targetKinds**: component
- **injectCommand**:
  ```
  docker exec <target> stress-ng --cpu 0 --cpu-load 95 --timeout 60s
  ```
  Uses all cores at 95% load for 60 seconds.
- **observeProbes**: request-duration, thread-pool-saturation,
  gc-pressure
- **recoveryCommand**:
  ```
  docker exec <target> pkill stress-ng
  ```
- **maxBlastRadiusSeconds**: 120

### memory-stress
- **category**: resource
- **applicableProfiles**: `brutal`
- **targetKinds**: component
- **injectCommand**:
  ```
  docker exec <target> stress-ng --vm 1 --vm-bytes 80% --timeout 60s
  ```
  Allocates 80% of the container's memory for 60 seconds.
- **observeProbes**: oom-events, process-count, gc-pressure
- **recoveryCommand**:
  ```
  docker exec <target> pkill stress-ng
  ```
- **maxBlastRadiusSeconds**: 120
- **notes**: The most dangerous catalog entry — an OOM can take
  down the whole component rather than degrading it. `brutal`
  profile only; the blast-radius watcher uses a tight 120s
  window because recovery after OOM is unreliable.

### disk-fill
- **category**: resource
- **applicableProfiles**: `brutal`
- **targetKinds**: component with named volume
- **injectCommand**:
  ```
  docker exec <target> dd if=/dev/zero of=/tmp/chaos-fill bs=1M count=<size> conv=fsync
  ```
  Fills `<size>` MB of the target's tmp volume.
- **observeProbes**: disk-available, write-error-rate
- **recoveryCommand**:
  ```
  docker exec <target> rm -f /tmp/chaos-fill
  ```
- **maxBlastRadiusSeconds**: 90

---

## 6. Catalog rules

- **No parallel chaos.** The skill never runs two catalog entries
  at once, regardless of the caller. The serial policy is
  enforced at the algorithm layer (see SKILL.md §Step 4).
- **Recovery is mandatory.** Every entry has a `recoveryCommand`,
  and that command must be idempotent (running twice is a
  no-op). An entry without a proven rollback is a time bomb.
- **Preflight-dependent capabilities.** Entries that need target
  tooling (`libfaketime`, `stress-ng`) are checked at preflight.
  A target missing the tool blocks that specific injection but
  doesn't fail the whole run — the skipped injection is recorded
  in the report.
- **Pin the injected parameters.** Randomized parameters are
  forbidden in the catalog. A scenario that wants a specific
  latency or loss rate declares it explicitly; the catalog
  never rolls dice.
- **Document the observe probes.** An injection with no probes
  has nothing to measure against — the skill rejects it at load.
  "Inject and pray" is not a thing.

---

## 7. Adding a new chaos type

1. Pick a stable id in `<category>-<specifics>` form.
2. Specify all eight mandatory fields.
3. Land the change with a retrospective from a real system where
   this chaos would have caught a real bug. "We could in theory
   do X" is not enough; a catalog entry is a commitment.
4. Tighten `applicableProfiles` conservatively — new entries
   default to `brutal` only and are promoted to `moderate` /
   `gentle` only after repeated safe runs.
5. Update the integration harness sentinel that counts catalog
   entries — silent additions are rejected at review.

---

## 8. Deprecation

Never delete a catalog entry. Old reports reference these ids.
Mark an obsolete entry `deprecated: true` with a reason in the
header; the skill stops emitting it forward and historical
reports stay interpretable.

No deprecated entries yet — this is the first version.
