#!/bin/bash
set -euo pipefail

echo "Starting TLS Notary Service Setup and Execution..."

# Verify prerequisites
echo "Verifying prerequisites..."
if [ ! -f "/home/livy/src/tlsn/target/release/notary-server" ]; then
  echo "TLS Notary server binary not found. Run install.sh first."
  exit 1
fi

if [ ! -f "/home/livy/src/tlsn/target/release/examples/proxy" ]; then
  echo "TLS Notary proxy binary not found. Build it first:"
  echo "  cargo build --release -p notary-tee --example proxy"
  exit 1
fi

if [ ! -f "/home/livy/tls-notary-config/config.toml" ]; then
  echo "TLS Notary configuration not found. Run install.sh first."
  exit 1
fi

# Create systemd service for TLS Notary server
echo "Creating systemd service (notary-server)..."
sudo -u livy bash -c '
echo "[Unit]" > /tmp/tls-notary-server.service
echo "Description=TLS Notary Server" >> /tmp/tls-notary-server.service
echo "After=network.target" >> /tmp/tls-notary-server.service
echo "" >> /tmp/tls-notary-server.service
echo "[Service]" >> /tmp/tls-notary-server.service
echo "Type=simple" >> /tmp/tls-notary-server.service
echo "User=livy" >> /tmp/tls-notary-server.service
echo "Group=livy" >> /tmp/tls-notary-server.service
echo "WorkingDirectory=/home/livy/tls-notary-config" >> /tmp/tls-notary-server.service
echo "ExecStart=/home/livy/src/tlsn/target/release/notary-server" >> /tmp/tls-notary-server.service
echo "Restart=always" >> /tmp/tls-notary-server.service
echo "RestartSec=5" >> /tmp/tls-notary-server.service
echo "Environment=PATH=/home/livy/.cargo/bin:/usr/local/bin:/usr/bin:/bin" >> /tmp/tls-notary-server.service
echo "" >> /tmp/tls-notary-server.service
echo "[Install]" >> /tmp/tls-notary-server.service
echo "WantedBy=multi-user.target" >> /tmp/tls-notary-server.service
sudo mv /tmp/tls-notary-server.service /etc/systemd/system/
echo "TLS Notary systemd service created"
'

# Create systemd service for TLS Notary proxy
echo "Creating systemd service (proxy)..."
sudo -u livy bash -c '
echo "[Unit]" > /tmp/tls-notary-proxy.service
echo "Description=TLS Notary TEE Proxy" >> /tmp/tls-notary-proxy.service
echo "After=network.target tls-notary-server.service" >> /tmp/tls-notary-proxy.service
echo "Requires=tls-notary-server.service" >> /tmp/tls-notary-proxy.service
echo "" >> /tmp/tls-notary-proxy.service
echo "[Service]" >> /tmp/tls-notary-proxy.service
echo "Type=simple" >> /tmp/tls-notary-proxy.service
echo "User=livy" >> /tmp/tls-notary-proxy.service
echo "Group=livy" >> /tmp/tls-notary-proxy.service
echo "WorkingDirectory=/home/livy/tls-notary-config" >> /tmp/tls-notary-proxy.service
echo "ExecStart=/home/livy/src/tlsn/target/release/examples/proxy" >> /tmp/tls-notary-proxy.service
echo "Restart=always" >> /tmp/tls-notary-proxy.service
echo "RestartSec=5" >> /tmp/tls-notary-proxy.service
echo "Environment=PATH=/home/livy/.cargo/bin:/usr/local/bin:/usr/bin:/bin" >> /tmp/tls-notary-proxy.service
echo "Environment=TLSN_PROXY_LISTEN=0.0.0.0:7048" >> /tmp/tls-notary-proxy.service
echo "Environment=TLSN_PROXY_UPSTREAM=http://127.0.0.1:7047" >> /tmp/tls-notary-proxy.service
echo "Environment=TLSN_PROXY_JOBS_DIR=/home/livy/tls-notary-config/jobs" >> /tmp/tls-notary-proxy.service
echo "Environment=TLSN_PROXY_MAX_BODY_BYTES=10485760" >> /tmp/tls-notary-proxy.service
echo "Environment=TLSN_PROXY_TDX_CMD=/usr/local/bin/tdx-attest" >> /tmp/tls-notary-proxy.service
echo "" >> /tmp/tls-notary-proxy.service
echo "[Install]" >> /tmp/tls-notary-proxy.service
echo "WantedBy=multi-user.target" >> /tmp/tls-notary-proxy.service
sudo mv /tmp/tls-notary-proxy.service /etc/systemd/system/
echo "TLS Notary proxy systemd service created"
'

# Reload systemd and enable services
echo "Reloading systemd and enabling services..."
systemctl daemon-reload
systemctl enable tls-notary-server
systemctl enable tls-notary-proxy

# Stop services if running (for idempotency)
echo "Stopping existing services (if running)..."
systemctl stop tls-notary-proxy || true
systemctl stop tls-notary-server || true

# Start services
echo "Starting TLS Notary server service..."
systemctl start tls-notary-server
echo "Starting TLS Notary proxy service..."
systemctl start tls-notary-proxy

# Wait for service to start
echo "Waiting for service to initialize..."
sleep 10

# Test TLS Notary server
echo "Testing TLS Notary server..."
sudo -u livy bash -c '
echo "Testing TLS Notary server health..."
if curl -s http://localhost:7047/healthcheck > /dev/null; then
  echo "TLS Notary server is responding to health checks"
else
  echo "TLS Notary server health check failed"
  echo "Service status:"
  systemctl status tls-notary-server --no-pager -l
  exit 1
fi

# Show service status
echo "Service status:"
systemctl status tls-notary-server --no-pager -l
'

# Show service logs for debugging
echo "Recent service logs (server):"
journalctl -u tls-notary-server --no-pager -l -n 20
echo "Recent service logs (proxy):"
journalctl -u tls-notary-proxy --no-pager -l -n 20

echo "TLS Notary Service Setup and Execution Complete!"
echo "TLS Notary server is running on http://localhost:7047"
echo "TLS Notary proxy is running on http://localhost:7048"