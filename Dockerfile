# ---- Builder: build gophish ----
FROM golang:1.22 as builder
WORKDIR /src
# If you forked the official repo, keep the contents; otherwise pull it here:
# RUN git clone --depth=1 https://github.com/gophish/gophish ./
COPY . ./
# Build static binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /gophish ./...

# ---- Runtime: gophish + caddy ----
FROM alpine:3.20
WORKDIR /app

# Install Caddy (reverse proxy) + envsubst
RUN apk add --no-cache caddy bash curl ca-certificates gettext

# Copy gophish
COPY --from=builder /gophish /app/gophish

# Copy our config/template/proxy/entry
COPY config.template.json /app/config.template.json
COPY Caddyfile             /app/Caddyfile
COPY start.sh              /app/start.sh
RUN chmod +x /app/start.sh

# Listen on one public port in Railway (8080). Caddy fronts both admin & phish.
EXPOSE 8080

# Railway’s root runs this
CMD ["/app/start.sh"]
