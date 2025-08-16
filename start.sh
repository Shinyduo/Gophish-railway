#!/bin/sh
set -eu

# ---------- CONFIG FROM ENV ----------
: "${PORT:=8080}"                    # Railway routes 443 -> $PORT
: "${ADMIN_BIND:=127.0.0.1:3333}"    # Admin binds internally
: "${PHISH_BIND:=127.0.0.1:8081}"    # Phish binds internally
: "${USE_TLS:=false}"                # Railway terminates TLS
: "${CONTACT_ADDRESS:=security@example.com}"

# DB: prefer Postgres if DATABASE_URL is present, else SQLite
if [ -n "${DATABASE_URL:-}" ]; then
  DB_NAME="postgres"
  DB_PATH="${DATABASE_URL}"
else
  DB_NAME="sqlite3"
  : "${DB_PATH:=/data/gophish.db}"
fi

mkdir -p /data

# ---------- BUILD/VERIFY ARTIFACTS ----------
# If the gophish binary isn't present (first run), build it.
if [ ! -x ./gophish ]; then
  echo "Building gophish binary..."
  # Standard Go build; Railway's Go builder provides go toolchain
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o gophish ./...
fi

# Download Caddy (static binary) if not present
if [ ! -x ./caddy ]; then
  echo "Downloading Caddy..."
  # Minimal detection (linux amd64)
  CADDY_VER="v2.8.4"
  curl -fsSL -o /tmp/caddy.tar.gz "https://github.com/caddyserver/caddy/releases/download/${CADDY_VER}/caddy_${CADDY_VER}_linux_amd64.tar.gz"
  tar -C . -xzf /tmp/caddy.tar.gz caddy
  chmod +x ./caddy
fi

# ---------- RENDER GOPHISH CONFIG ----------
cat > /app.config.json <<EOF
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

echo "Rendered /app.config.json (secrets redacted)."

# ---------- START SERVICES ----------
# Start Gophish (background)
./gophish --config /app.config.json &
GOPHISH_PID=$!

# Start Caddy reverse proxy on $PORT (foreground)
/bin/sh -c "./caddy run --config ./Caddyfile --adapter caddyfile"
