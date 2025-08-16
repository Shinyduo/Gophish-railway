#!/bin/sh
set -eu

# ---------- CONFIG FROM ENV ----------
: "${PORT:=8080}"
: "${ADMIN_BIND:=127.0.0.1:3333}"
: "${PHISH_BIND:=127.0.0.1:8081}"
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

# Ensure binaries
if [ ! -x ./bin/gophish ]; then
  echo "ERROR: ./bin/gophish not found or not executable. Check nixpacks.toml install phase." >&2
  exit 1
fi
CADDY_BIN="${CADDY_BIN:-$(command -v caddy || true)}"
if [ -z "$CADDY_BIN" ]; then
  echo "ERROR: caddy not found in PATH. Nix should have installed it. Check nixpacks.toml setup phase." >&2
  exit 1
fi

# ---------- RENDER GOPHISH CONFIG ----------
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

# ---------- START ----------
echo "Starting Gophish..."
./bin/gophish --config /app.config.json &
GOPHISH_PID=$!

echo "Starting Caddy on :${PORT}..."
exec "$CADDY_BIN" run --config ./Caddyfile --adapter caddyfile
