#!/bin/bash
set -euo pipefail

echo "🚀 Starting TLS Notary Service Setup and Execution..."

# Verify prerequisites
echo "🔍 Verifying prerequisites..."
if [ ! -f "/home/livy/src/tlsn/target/release/notary-server" ]; then
  echo "❌ TLS Notary server binary not found. Run install.sh first."
  exit 1
fi

if [ ! -f "/home/livy/tls-notary-config/config.toml" ]; then
  echo "❌ TLS Notary configuration not found. Run install.sh first."
  exit 1
fi

# Create systemd service for TLS Notary server
echo "⚙️ Creating systemd service..."
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
echo "✅ TLS Notary systemd service created"
'

# Reload systemd and enable service
echo "🔄 Reloading systemd and enabling service..."
systemctl daemon-reload
systemctl enable tls-notary-server

# Stop service if running (for idempotency)
echo "🛑 Stopping existing service (if running)..."
systemctl stop tls-notary-server || true

# Start TLS Notary server service
echo "▶️ Starting TLS Notary server service..."
systemctl start tls-notary-server
echo "✅ TLS Notary server service started"

# Wait for service to start
echo "⏳ Waiting for service to initialize..."
sleep 10

# Test TLS Notary server
echo "🧪 Testing TLS Notary server..."
sudo -u livy bash -c '
echo "🔧 Testing TLS Notary server health..."
if curl -s http://localhost:7047/healthcheck > /dev/null; then
  echo "✅ TLS Notary server is responding to health checks"
else
  echo "❌ TLS Notary server health check failed"
  echo "📋 Service status:"
  systemctl status tls-notary-server --no-pager -l
  exit 1
fi

# Show service status
echo "📋 Service status:"
systemctl status tls-notary-server --no-pager -l
'

# Show service logs for debugging
echo "📋 Recent service logs:"
journalctl -u tls-notary-server --no-pager -l -n 20

echo "✅ TLS Notary Service Setup and Execution Complete!"
echo "🌐 TLS Notary server is running on http://localhost:7047"

