#!/bin/bash
set -euo pipefail

log() {
  printf 'run: %s\n' "$*"
}

fail() {
  printf 'run: error: %s\n' "$*" >&2
  exit 1
}

SERVER_BIN="/home/livy/src/tlsn/target/release/notary-server"
PROXY_BIN="/home/livy/src/tlsn/target/release/examples/proxy"
CONFIG_DIR="/home/livy/tls-notary-config"
JOBS_DIR="$CONFIG_DIR/jobs"

[ -x "$SERVER_BIN" ] || fail "missing $SERVER_BIN"
[ -x "$PROXY_BIN" ] || fail "missing $PROXY_BIN"
[ -f "$CONFIG_DIR/config.toml" ] || fail "missing $CONFIG_DIR/config.toml"

log "writing systemd units"
install -d -o livy -g livy "$JOBS_DIR"

cat > /etc/systemd/system/tls-notary-server.service <<EOF
[Unit]
Description=TLS Notary Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=livy
Group=livy
WorkingDirectory=$CONFIG_DIR
ExecStart=$SERVER_BIN
Restart=always
RestartSec=5
Environment=PATH=/home/livy/.cargo/bin:/usr/local/bin:/usr/bin:/bin
Environment=PATH_TEE_CONFIG=/home/livy/config.json
Environment=NS_TEE=true

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/tls-notary-proxy.service <<EOF
[Unit]
Description=TLS Notary TEE Proxy
After=network-online.target tls-notary-server.service
Wants=network-online.target
Requires=tls-notary-server.service

[Service]
Type=simple
User=livy
Group=livy
WorkingDirectory=$CONFIG_DIR
ExecStart=$PROXY_BIN
Restart=always
RestartSec=5
Environment=PATH=/home/livy/.cargo/bin:/usr/local/bin:/usr/bin:/bin
Environment=TLSN_PROXY_LISTEN=0.0.0.0:7048
Environment=TLSN_PROXY_UPSTREAM=http://127.0.0.1:7047
Environment=TLSN_PROXY_JOBS_DIR=$JOBS_DIR
Environment=TLSN_PROXY_MAX_BODY_BYTES=10485760
Environment="TLSN_PROXY_TDX_CMD=sudo /usr/bin/trustauthority-cli evidence --tdx -u {reportdata_b64} -c /home/livy/config.json > {output}"

[Install]
WantedBy=multi-user.target
EOF

log "starting services"
systemctl daemon-reload
systemctl enable tls-notary-server tls-notary-proxy >/dev/null
systemctl restart tls-notary-server
systemctl restart tls-notary-proxy

log "waiting for notary server"
for attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:7047/healthcheck >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    systemctl status tls-notary-server --no-pager -l >&2 || true
    fail "notary server did not become healthy"
  fi
  sleep 2
done

log "waiting for proxy"
for attempt in $(seq 1 15); do
  if curl -sS http://127.0.0.1:7048/ >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 15 ]; then
    systemctl status tls-notary-proxy --no-pager -l >&2 || true
    fail "proxy did not become reachable"
  fi
  sleep 2
done

systemctl is-active --quiet tls-notary-server || fail "tls-notary-server is not active"
systemctl is-active --quiet tls-notary-proxy || fail "tls-notary-proxy is not active"

log "complete"
