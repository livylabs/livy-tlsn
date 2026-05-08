#!/bin/bash
set -euo pipefail

log() {
  printf 'https: %s\n' "$*"
}

fail() {
  printf 'https: error: %s\n' "$*" >&2
  exit 1
}

DOMAIN_NAME="${1:-}"
EMAIL="${2:-contact@livylabs.xyz}"
SERVER_NAME="${DOMAIN_NAME:-_}"

metadata_external_ip() {
  curl -fsS \
    -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null || true
}

resolve_domain() {
  getent ahostsv4 "$1" | awk 'NR == 1 { print $1 }' || true
}

wait_for_health() {
  local url="$1"
  local label="$2"

  for attempt in $(seq 1 30); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    if [ "$attempt" -eq 30 ]; then
      fail "$label did not become healthy"
    fi
    sleep 2
  done
}

log "installing nginx and certbot"
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx

log "writing nginx site"
cat > /etc/nginx/sites-available/tlsn <<EOF
server {
    listen 80;
    server_name ${SERVER_NAME};

    location /api/v1/prove {
        proxy_pass http://127.0.0.1:7048/api/v1/prove;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }

    location ~ ^/api/v1/jobs/[^/]+/(attestation|secrets)\$ {
        proxy_pass http://127.0.0.1:7048;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /healthcheck {
        proxy_pass http://127.0.0.1:7047/healthcheck;
        proxy_set_header Host \$host;
        access_log off;
    }

    location / {
        proxy_pass http://127.0.0.1:7047;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/tlsn /etc/nginx/sites-enabled/tlsn
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx >/dev/null
systemctl restart nginx

wait_for_health "http://127.0.0.1:7047/healthcheck" "local notary server"
wait_for_health "http://127.0.0.1/healthcheck" "local nginx proxy"

if [ -z "$DOMAIN_NAME" ] || [ "$DOMAIN_NAME" = "your-domain.com" ]; then
  log "domain_name is not configured; HTTP proxy is ready and certificate setup was skipped"
  exit 0
fi

INSTANCE_IP="$(metadata_external_ip)"
[ -n "$INSTANCE_IP" ] || fail "could not determine instance external IP from metadata"

RESOLVED_IP="$(resolve_domain "$DOMAIN_NAME")"
if [ "$RESOLVED_IP" != "$INSTANCE_IP" ]; then
  log "$DOMAIN_NAME resolves to '${RESOLVED_IP:-unresolved}', expected '$INSTANCE_IP'; certificate setup skipped"
  log "point DNS at $INSTANCE_IP before expecting HTTPS"
  exit 0
fi

log "requesting certificate for $DOMAIN_NAME"
certbot --nginx \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  --redirect \
  --keep-until-expiring \
  -d "$DOMAIN_NAME"

systemctl enable --now certbot.timer >/dev/null 2>&1 || true
systemctl restart nginx
wait_for_health "https://$DOMAIN_NAME/healthcheck" "public HTTPS endpoint"

log "complete"
