#!/bin/sh
set -eu

# ---------- CONFIG FROM ENV ----------
: "${PORT:=8080}"                    # Railway routes HTTPS -> $PORT
: "${ADMIN_BIND:=127.0.0.1:3333}"    # Admin binds internally
: "${PHISH_BIND:=127.0.0.1:8081}"    # Phish binds internally
: "${USE_TLS:=false}"                # Railway terminates TLS
: "${CONTACT_ADDRESS:=security@example.com}"

# Prefer Postgres if DATABASE_URL exists; fallback to SQLite otherwise
if [ -n "${DATABASE_URL:-}" ]; then
  DB_NAME="postgres"
  DB_PATH="${DATABASE_URL}"
else
  DB_NAME="sqlite3"
  : "${DB_PATH:=/data/gophish.db}"
fi

# Ensure runtime dirs
mkdir -p /data

# Ensure binaries from nixpacks install phase
if [ ! -x ./bin/gophish ]; then
  echo "ERROR: ./bin/gophish not found or not executable. Check nixpacks.toml install phase." >&2
  exit 1
fi
if [ ! -x ./bin/caddy ]; then
  echo "ERROR: ./bin/caddy not found or not executable. Check nixpacks.toml install phase." >&2
  exit 1
fi

# Defensive: make sure they are executable
chmod +x ./bin/gophish ./bin/caddy || true

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
[ "${DB_NAME}" = "postgres" ] && echo "Using DATABASE_URL from env."

# ---------- CLEAN SHUTDOWN HANDLER ----------
GOPHISH_PID=""
cleanup() {
  if [ -n "${GOPHISH_PID}" ] && kill -0 "${GOPHISH_PID}" 2>/dev/null; then
    echo "Stopping gophish (pid ${GOPHISH_PID})..."
    kill "${GOPHISH_PID}" || true
    wait "${GOPHISH_PID}" 2>/dev/null || true
  fi
}
trap cleanup INT TERM

# ---------- START SERVICES ----------
# Start Gophish (background)
echo "Starting Gophish (admin at ${ADMIN_BIND}, phish at ${PHISH_BIND})..."
./bin/gophish --config /app.config.json &
GOPHISH_PID=$!

# Start Caddy reverse proxy on $PORT (foreground)
# Caddyfile must use :{$PORT}
echo "Starting Caddy on :${PORT} (proxying /admin -> ${ADMIN_BIND}, / -> ${PHISH_BIND})..."
exec ./bin/caddy run --config ./Caddyfile --adapter caddyfile
