# ---- Build gophish binary ----
FROM golang:1.22 AS builder
WORKDIR /src
# If your repo already contains gophish sources, keep COPY . ./
# Otherwise clone; but copying your fork is preferred:
COPY . ./
# Build static
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /gophish ./...

# ---- Runtime with Caddy, no apk installs ----
FROM caddy:2.8.4-alpine
WORKDIR /app

# Copy gophish binary and runtime files
COPY --from=builder /gophish /app/gophish
COPY Caddyfile /app/Caddyfile
COPY start.sh  /app/start.sh

# Use POSIX sh; no bash/envsubst required
RUN chmod +x /app/start.sh

# Railway will route 443 -> 8080
EXPOSE 8080
CMD ["/app/start.sh"]
