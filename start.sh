#!/usr/bin/env bash
set -euo pipefail

# 1) Render config from env -> /app/config.json
: "${ADMIN_BIND:=0.0.0.0:3333}"     # internal admin bind
: "${PHISH_BIND:=0.0.0.0:8081}"     # internal phish bind
: "${USE_TLS:=false}"               # Railway terminates TLS
: "${DB_NAME:=sqlite3}"             # sqlite3 by default
: "${DB_PATH:=/data/gophish.db}"    # put db on /data to persist with a Volume
: "${CONTACT_ADDRESS:=security@example.com}"

mkdir -p /data

envsubst < /app/config.template.json > /app/config.json
echo "Rendered /app/config.json:"
sed 's/"password": *".*"/"password":"********"/' /app/config.json | sed 's/"smtp" *: *{[^}]*}/"smtp":{...}/'

# 2) Start Gophish (background)
echo "Starting Gophish..."
/app/gophish --config /app/config.json &
GOPHISH_PID=$!

# 3) Start Caddy (foreground) as reverse proxy on :8080
echo "Starting Caddy reverse proxy on :8080 ..."
exec caddy run --config /app/Caddyfile --adapter caddyfile
