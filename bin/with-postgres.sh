#!/bin/bash
# bin/with-postgres.sh — wraps a throwaway PostgreSQL 14 container
# around a command, exposing $DATABASE_URL to the wrapped shell.
#
# Used by tests/integration/sprint-5.sh [S5-B] to run a live team-mode
# walk without polluting the host filesystem or requiring a running
# postgres server.
#
# Usage:
#   bin/with-postgres.sh <command> [args...]
#
# Example:
#   bin/with-postgres.sh bash -c 'psql "$DATABASE_URL" -c "SELECT 1;"'
#
# Exit code is the wrapped command's exit code. The container is
# torn down on exit regardless of success or failure.
#
# Environment in the wrapped command:
#   DATABASE_URL — a postgresql://... string pointing at the container
#   VIBEFLOW_POSTGRES_URL — same value (sdlc-engine reads this name)
#
# Prerequisites:
#   - Docker running locally
#   - Port 55432 free on localhost
#
# Tuning knobs (overridable via env before the wrapper runs):
#   VF_PG_IMAGE        — default `postgres:14-alpine`
#   VF_PG_PORT         — default 55432
#   VF_PG_DB           — default `vibeflow_test`
#   VF_PG_USER         — default `vibeflow`
#   VF_PG_PASSWORD     — default `vibeflow_test_pw`
#   VF_PG_READY_ATTEMPTS — default 30 (pg_isready polls, 1s apart)

set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "with-postgres: docker is not installed or not on PATH" >&2
  exit 127
fi

IMAGE="${VF_PG_IMAGE:-postgres:14-alpine}"
PORT="${VF_PG_PORT:-55432}"
DB="${VF_PG_DB:-vibeflow_test}"
USER="${VF_PG_USER:-vibeflow}"
PASSWORD="${VF_PG_PASSWORD:-vibeflow_test_pw}"
READY_ATTEMPTS="${VF_PG_READY_ATTEMPTS:-30}"
NAME="vf-s5-pg-$$"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# Launch the container detached.
docker run -d --rm \
  --name "$NAME" \
  -e "POSTGRES_USER=$USER" \
  -e "POSTGRES_PASSWORD=$PASSWORD" \
  -e "POSTGRES_DB=$DB" \
  -p "$PORT:5432" \
  "$IMAGE" >/dev/null

# Wait until postgres is accepting connections. pg_isready is the
# canonical readiness probe; we exec it inside the running container
# so we don't need the client on the host.
ATTEMPT=0
while ! docker exec "$NAME" pg_isready -U "$USER" -d "$DB" >/dev/null 2>&1; do
  ATTEMPT=$((ATTEMPT + 1))
  if (( ATTEMPT >= READY_ATTEMPTS )); then
    echo "with-postgres: pg_isready timed out after $READY_ATTEMPTS attempts" >&2
    docker logs "$NAME" 2>&1 | tail -20 >&2
    exit 1
  fi
  sleep 1
done

export DATABASE_URL="postgresql://$USER:$PASSWORD@127.0.0.1:$PORT/$DB"
export VIBEFLOW_POSTGRES_URL="$DATABASE_URL"

"$@"
RC=$?
exit "$RC"
