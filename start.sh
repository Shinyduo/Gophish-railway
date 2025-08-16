#!/bin/sh
set -eu

: "${PORT:=8080}"
: "${ADMIN_BIND:=0.0.0.0:3333}"
: "${PHISH_BIND:=0.0.0.0:8081}"
: "${USE_TLS:=false}"
: "${CONTACT_ADDRESS:=security@example.com}"

# Prefer Postgres if DATABASE_URL exists; fallback to SQLite otherwise
if [ -n "${DATABASE_URL:-}" ]; then
  DB_NAME="postgres"
  DB_PATH="${DATABASE_URL}"
else
  DB_NAME="sqlite3"
  : "${DB_PATH:=/data/gophish.db}"
fi

mkdir -p /data

CONFIG_PATH="$(pwd)/app.config.json"
cat > "${CONFIG_PATH}" <<EOF
{
  "admin_server": { "listen_url": "${ADMIN_BIND}", "use_tls": ${USE_TLS} },
  "phish_server": { "listen_url": "${PHISH_BIND}", "use_tls": ${USE_TLS} },
  "db_name": "${DB_NAME}",
  "db_path": "${DB_PATH}",
  "migrations_prefix": "db/db_",
  "contact_address": "${CONTACT_ADDRESS}",
  "logging": { "filename": "", "level": "info", "json": false },
  "smtp": {
    "host": "${SMTP_HOST:-}",
    "port": "${SMTP_PORT:-}",
    "username": "${SMTP_USERNAME:-}",
    "password": "${SMTP_PASSWORD:-}",
    "from_address": "${SMTP_FROM:-}",
    "ignore_cert_errors": ${SMTP_IGNORE_CERT_ERRORS:-false}
  },
  "phish_server_cert": "",
  "phish_server_key": ""
}
EOF
echo "Rendered ${CONFIG_PATH} (secrets redacted)."
echo "DB driver: ${DB_NAME}"

# Sanity checks
[ -x ./bin/gophish ] || { echo "ERROR: ./bin/gophish not found/executable"; exit 1; }
[ -f ./bin/VERSION ] || { echo "ERROR: ./bin/VERSION missing"; exit 1; }

# Graceful shutdown
GOPHISH_PID=""
cleanup() {
  [ -n "${GOPHISH_PID}" ] && kill "${GOPHISH_PID}" 2>/dev/null || true
}
trap cleanup INT TERM

# Run Gophish from ./bin so it sees ./VERSION
echo "Starting Gophish from ./bin (admin ${ADMIN_BIND}, phish ${PHISH_BIND})..."
(
  cd ./bin
  ./gophish --config "${CONFIG_PATH}"
) &
GOPHISH_PID=$!

# Short buffer so Caddy’s first proxy doesn’t race
sleep 2

echo "Starting Caddy on :${PORT}..."
exec caddy run --config ./Caddyfile --adapter caddyfile
