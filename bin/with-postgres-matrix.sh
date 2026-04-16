#!/bin/bash
# bin/with-postgres-matrix.sh — run a command against every Postgres
# version in a matrix. Each version spins up its own throwaway
# container via bin/with-postgres.sh (the wrapper's standard skip +
# teardown + pg_isready probe logic is reused unchanged).
#
# Used by tests/integration/sprint-7.sh [S7-E] to verify that the
# sdlc-engine's Postgres state store works on every Postgres version
# VibeFlow claims to support. The matrix smoke-tests a combination of
# driver (`pg` module) compatibility + SQL surface compatibility
# (the DDL in sdlc-engine/src/state/postgres.ts uses plain INSERT /
# SELECT ... FOR UPDATE / pg_advisory_xact_lock — all stable since
# PG8.2, so the matrix mostly catches driver + image issues rather
# than query regressions).
#
# Usage:
#   bin/with-postgres-matrix.sh <command> [args...]
#
# Example:
#   bin/with-postgres-matrix.sh bash tests/integration/sprint-5.sh
#
# Knobs:
#   VF_PG_IMAGES — space-separated list of docker images. Default
#     covers the four Postgres versions most commonly shipped in
#     production as of 2026-04: 13-alpine, 14-alpine, 15-alpine,
#     16-alpine. Override to narrow the matrix (e.g. PG 16 only) or
#     widen it to include a managed-cloud simulator.
#   VF_PG_PORT  — passed through to with-postgres.sh. All matrix
#     iterations use the same port because they run sequentially,
#     not in parallel.
#
# Exit code:
#   0  — all matrix entries passed
#   1+ — number of failed matrix entries
#
# Sprint 7 / S7-02 — deferred from Sprint 6 / S6-03, itself deferred
# from Sprint 5 / S5-03. Original scope covered just PG 14 (the
# default at the time of Sprint 5); S7-02 expands to the full v1.2
# supported matrix.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO_ROOT/bin/with-postgres.sh"

if [[ ! -x "$WRAPPER" ]]; then
  echo "matrix: bin/with-postgres.sh not found or not executable at $WRAPPER" >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  echo "usage: $(basename "$0") <command> [args...]" >&2
  echo "       $(basename "$0") bash tests/integration/sprint-5.sh" >&2
  exit 2
fi

# Default matrix covers PG13 → PG16. Each iteration runs the wrapped
# command against a fresh container of that image. The four versions
# align with the Postgres release cadence (one per year, ~5-year
# support window): 13 = oldest still supported, 16 = latest stable
# at v1.2 cut.
IMAGES="${VF_PG_IMAGES:-postgres:13-alpine postgres:14-alpine postgres:15-alpine postgres:16-alpine}"

TOTAL=0
FAILED=0
FAILED_IMAGES=()

for image in $IMAGES; do
  TOTAL=$((TOTAL + 1))
  echo "================================================================"
  echo "matrix [$TOTAL]: $image"
  echo "================================================================"
  if VF_PG_IMAGE="$image" bash "$WRAPPER" "$@"; then
    echo "matrix: $image OK"
  else
    rc=$?
    echo "matrix: $image FAILED (rc=$rc)" >&2
    FAILED=$((FAILED + 1))
    FAILED_IMAGES+=("$image")
  fi
done

echo
echo "================================================================"
echo "matrix summary: $((TOTAL - FAILED))/$TOTAL passed"
if (( FAILED > 0 )); then
  echo "matrix: $FAILED image(s) failed:"
  for img in "${FAILED_IMAGES[@]}"; do
    echo "  - $img"
  done
fi
echo "================================================================"

if (( FAILED > 0 )); then
  exit "$FAILED"
fi
exit 0
