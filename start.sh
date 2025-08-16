#!/bin/sh
set -eu

# Defaults (can be overridden by Railway Variables)
: "${ADMIN_BIND:=0.0.0.0:3333}"
: "${PHISH_BIND:=0.0.0.0:8081}"
: "${USE_TLS:=false}"

# Postgres mode (recommended)
: "${DB_NAME:=postgres}"
: "${DB_PATH:=${DATABASE_URL:-}}"

# Fall back to SQLite if no DATABASE_URL present
if [ -z "${DB_PATH}" ]; then
  DB_NAME="sqlite3"
  : "${DB_PATH:=/data/gophish.db}"
fi

: "${CONTACT_ADDRESS:=security@example.com}"

# Create data dir if needed (for SQLite)
mkdir -p /data

# Generate config.json using shell variable interpolation
cat > /app/config.json <<EOF
{
  "admin_server": {
    "listen_url": "${ADMIN_BIND}",
    "use_tls": ${USE_TLS}
  },
  "phish_server": {
    "listen_url": "${PHISH_BIND}",
    "use_tls": ${USE_TLS}
  },
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

echo "Rendered /app/config.json (passwords redacted)."

# Start Gophish (background)
/app/gophish --config /app/config.json &
GOPHISH_PID=$!

# Start Caddy reverse proxy (foreground)
/usr/bin/caddy run --config /app/Caddyfile --adapter caddyfile
