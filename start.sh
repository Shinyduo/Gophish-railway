#!/bin/sh
set -eu

: "${PORT:=8080}"
: "${ADMIN_BIND:=127.0.0.1:3333}"
: "${PHISH_BIND:=127.0.0.1:8081}"
: "${USE_TLS:=false}"
: "${CONTACT_ADDRESS:=security@example.com}"

if [ -n "${DATABASE_URL:-}" ]; then
  DB_NAME="postgres"
  DB_PATH="${DATABASE_URL}"
else
  DB_NAME="sqlite3"
  : "${DB_PATH:=/data/gophish.db}"
fi

mkdir -p /data

# Sanity checks
if [ ! -x ./bin/gophish ]; then
  echo "ERROR: ./bin/gophish not found or not executable." >&2
  exit 1
fi
if ! command -v caddy >/dev/null 2>&1; then
  echo "ERROR: caddy not found in PATH." >&2
  exit 1
fi

# Render config
cat > /app.config.json <<EOF
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

echo "Rendered /app.config.json (secrets redacted)."
echo "DB driver: ${DB_NAME}"

# Graceful shutdown
GOPHISH_PID=""
cleanup() {
  [ -n "${GOPHISH_PID}" ] && kill "${GOPHISH_PID}" 2>/dev/null || true
}
trap cleanup INT TERM

# --- IMPORTANT CHANGE: run from bin so ./VERSION is found ---
echo "Starting Gophish from ./bin (admin ${ADMIN_BIND}, phish ${PHISH_BIND})..."
(
  cd ./bin
  ./gophish --config ../app.config.json
) &
GOPHISH_PID=$!

echo "Starting Caddy on :${PORT}..."
exec caddy run --config ./Caddyfile --adapter caddyfile
