#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
BACKUP_DIR="${ROOT_DIR}/backups"
DB_CONTAINER="yemeksepeti-supabase-db"

usage() {
  cat <<'EOF'
Usage: scripts/local_supabase.sh <command>

Commands:
  up         Start local Supabase DB + API
  db-up      Start only local Supabase DB
  down       Stop local stack (keep volume)
  reset      Stop and remove volume, then start DB fresh
  status     Show compose service status
  logs       Tail DB and API logs
  dump       Export active local DB into backend/backups
  pull-remote [db_url]  Dump remote DB (old URL) and import into local DB
  restore <sql_file>   Restore .sql dump into local DB

Examples:
  scripts/local_supabase.sh up
  scripts/local_supabase.sh dump
  scripts/local_supabase.sh pull-remote
  scripts/local_supabase.sh restore backups/supabase_local_20260302_201407.sql
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "[ERROR] Missing command: $1"; exit 1; }
}

compose() {
  (cd "${ROOT_DIR}" && docker compose -f "${COMPOSE_FILE}" "$@")
}

wait_db() {
  for _ in $(seq 1 30); do
    health="$(docker inspect -f '{{.State.Health.Status}}' "${DB_CONTAINER}" 2>/dev/null || true)"
    if [[ "${health}" == "healthy" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "[ERROR] DB health check timeout"
  return 1
}

ensure_auth_schema() {
  docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres \
    -c "ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT;" >/dev/null
}

ensure_review_schema() {
  docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres \
    -f /dev/stdin < "${ROOT_DIR}/migrations/003_add_order_reviews.sql" >/dev/null
}

ensure_coupon_visibility_schema() {
  docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres \
    -f /dev/stdin < "${ROOT_DIR}/migrations/004_add_coupon_visibility.sql" >/dev/null
}

ensure_local_schema() {
  ensure_auth_schema
  ensure_review_schema
  ensure_coupon_visibility_schema
}

cmd="${1:-}"
case "${cmd}" in
  "")
    usage
    echo
    echo "Tip: local_supabase.sh status"
    exit 0
    ;;
  up)
    compose up -d --build
    ;;
  db-up)
    compose up -d supabase-db
    ;;
  down)
    compose down
    ;;
  reset)
    compose down -v
    compose up -d supabase-db
    ;;
  status)
    compose ps
    ;;
  logs)
    compose logs --tail=150 supabase-db api
    ;;
  dump)
    require_cmd docker
    mkdir -p "${BACKUP_DIR}"
    compose up -d supabase-db >/dev/null
    wait_db
    ts="$(date +%Y%m%d_%H%M%S)"
    sql_file="${BACKUP_DIR}/supabase_local_${ts}.sql"
    dump_file="${BACKUP_DIR}/supabase_local_${ts}.dump"
    docker exec "${DB_CONTAINER}" pg_dump -U postgres -d postgres --clean --if-exists > "${sql_file}"
    docker exec "${DB_CONTAINER}" pg_dump -U postgres -d postgres -Fc > "${dump_file}"
    echo "[OK] SQL:  ${sql_file}"
    echo "[OK] DUMP: ${dump_file}"
    ;;
  pull-remote)
    require_cmd docker
    mkdir -p "${BACKUP_DIR}"
    compose up -d supabase-db >/dev/null
    wait_db

    remote_raw="${2:-}"
    if [[ -z "${remote_raw}" ]]; then
      remote_raw="$(grep '^DATABASE_URL=' "${ROOT_DIR}/.env" | cut -d= -f2- || true)"
    fi
    if [[ -z "${remote_raw}" ]]; then
      echo "[ERROR] Remote DB URL not found. Provide as argument or set DATABASE_URL in .env"
      exit 1
    fi

    remote_url="${remote_raw/postgresql+asyncpg:/postgresql:}"
    ts="$(date +%Y%m%d_%H%M%S)"
    remote_sql="${BACKUP_DIR}/remote_supabase_${ts}.sql"
    filtered_sql="${BACKUP_DIR}/remote_supabase_${ts}.local.sql"

    docker run --rm --network host -v "${BACKUP_DIR}:/backup" postgres:17-alpine \
      sh -lc "pg_dump --dbname='${remote_url}' --clean --if-exists --no-owner --no-privileges -f /backup/$(basename "${remote_sql}")"

    sed -E '/^\\(un)?restrict /d; /^SET transaction_timeout =/d' "${remote_sql}" > "${filtered_sql}"
    cat "${filtered_sql}" | docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres
    ensure_local_schema

    echo "[OK] Remote dump:    ${remote_sql}"
    echo "[OK] Localized dump: ${filtered_sql}"
    echo "[OK] Remote data imported into local Supabase DB"
    ;;
  restore)
    require_cmd docker
    sql_file="${2:-}"
    if [[ -z "${sql_file}" ]]; then
      echo "[ERROR] Please provide SQL file path"
      usage
      exit 1
    fi
    if [[ ! -f "${sql_file}" ]]; then
      echo "[ERROR] File not found: ${sql_file}"
      exit 1
    fi
    compose up -d supabase-db >/dev/null
    wait_db
    sed -E '/^\\(un)?restrict /d; /^SET transaction_timeout =/d' "${sql_file}" \
      | docker exec -i "${DB_CONTAINER}" psql -U postgres -d postgres
    ensure_local_schema
    echo "[OK] Restore completed: ${sql_file}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
