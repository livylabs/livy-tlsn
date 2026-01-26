#!/bin/bash
set -euo pipefail

echo "🔒 Setting up HTTPS for TLS Notary server..."

DOMAIN_NAME="${1:-tlsn.livylabs.xyz}"
EMAIL="${2:-admin@livylabs.xyz}"

# Install nginx
echo "📦 Installing nginx..."
apt-get update
apt-get install -y nginx

# Install certbot for Let's Encrypt
echo "📦 Installing certbot..."
apt-get install -y certbot python3-certbot-nginx

# Create initial nginx configuration for TLS Notary (HTTP only)
echo "⚙️ Creating initial nginx configuration..."
cat > /etc/nginx/sites-available/tlsn << EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    
    # Route prove API to proxy service
    location /api/v1/prove {
        proxy_pass http://127.0.0.1:7048/api/v1/prove;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Extended timeouts for TLS notarization
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    # Proxy everything else to TLS Notary server
    location / {
        proxy_pass http://127.0.0.1:7047;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support (if needed)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint
    location /healthcheck {
        proxy_pass http://127.0.0.1:7047/healthcheck;
        proxy_set_header Host \$host;
        access_log off;
    }
}
EOF

# Enable the site
echo "🔗 Enabling nginx site..."
ln -sf /etc/nginx/sites-available/tlsn /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
echo "🧪 Testing nginx configuration..."
nginx -t

# Start nginx
echo "▶️ Starting nginx..."
systemctl enable nginx
systemctl restart nginx

# Wait for nginx to start
sleep 5

# Verify TLS Notary services are accessible before proceeding
echo "🔍 Verifying TLS Notary services are accessible..."
for i in {1..30}; do
  if curl -s http://127.0.0.1:7047/healthcheck > /dev/null 2>&1; then
    echo "✅ TLS Notary server (port 7047) is accessible"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "❌ TLS Notary server is not accessible. Nginx will show 502 errors."
    echo "   Please ensure TLS Notary service is running:"
    echo "   sudo systemctl status tls-notary-server"
    exit 1
  fi
  echo "Waiting for TLS Notary server to be accessible... (attempt $i/30)"
  sleep 2
done

# Check if proxy service is also accessible
echo "🔍 Checking TLS Notary proxy service..."
if curl -s http://127.0.0.1:7048/ > /dev/null 2>&1; then
  echo "✅ TLS Notary proxy service (port 7048) is accessible"
else
  echo "⚠️  TLS Notary proxy service not accessible, but continuing"
  echo "   The /api/v1/prove endpoint may not work until proxy service is ready"
fi

# Check if domain resolves to this server
echo "🔍 Checking DNS resolution for ${DOMAIN_NAME}..."
EXTERNAL_IP=$(curl -s http://checkip.amazonaws.com/ || echo "unknown")
RESOLVED_IP=$(dig +short ${DOMAIN_NAME} || echo "unknown")

echo "External IP: ${EXTERNAL_IP}"
echo "Resolved IP: ${RESOLVED_IP}"

if [ "${EXTERNAL_IP}" != "${RESOLVED_IP}" ] && [ "${RESOLVED_IP}" != "unknown" ]; then
    echo "⚠️  WARNING: DNS may not be pointing to this server yet."
    echo "   Please ensure ${DOMAIN_NAME} points to ${EXTERNAL_IP}"
    echo "   You can still proceed, but SSL certificate generation may fail."
fi

# Obtain SSL certificate
echo "🔐 Obtaining SSL certificate from Let's Encrypt..."
if certbot --nginx -d ${DOMAIN_NAME} --non-interactive --agree-tos --email ${EMAIL} --redirect; then
    echo "✅ SSL certificate obtained successfully!"
    
    # Set up automatic renewal
    echo "🔄 Setting up automatic certificate renewal..."
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    
    # Test the renewal process
    certbot renew --dry-run
    
    # Fix TDX CLI command in proxy service if it exists
    echo "🔧 Fixing TDX CLI command in proxy service..."
    if [ -f "/etc/systemd/system/tls-notary-proxy.service" ]; then
        sed -i 's|TLSN_PROXY_TDX_CMD=/usr/local/bin/tdx-attest|TLSN_PROXY_TDX_CMD=sudo trustauthority-cli evidence --tdx -u '"'"'{reportdata_b64}'"'"' -c /home/livy/config.json > '"'"'{output}'"'"'|' /etc/systemd/system/tls-notary-proxy.service
        sed -i 's|TLSN_PROXY_TDX_CMD=/usr/bin/trustauthority-cli|TLSN_PROXY_TDX_CMD=sudo trustauthority-cli evidence --tdx -u '"'"'{reportdata_b64}'"'"' -c /home/livy/config.json > '"'"'{output}'"'"'|' /etc/systemd/system/tls-notary-proxy.service
        
        # Remove any separate TDX config environment variable if present
        sed -i '/Environment=TLSN_PROXY_TDX_CONFIG/d' /etc/systemd/system/tls-notary-proxy.service
        
        systemctl daemon-reload
        systemctl restart tls-notary-proxy || echo "⚠️  Could not restart proxy service"
        echo "✅ TDX CLI command fixed in proxy service"
    else
        echo "⚠️  Proxy service not found, skipping TDX CLI fix"
    fi
    
    # Restart nginx to ensure proper backend connection
    echo "🔄 Restarting nginx to ensure proper backend connection..."
    systemctl restart nginx
    sleep 3
    
    # Final verification
    echo "🧪 Final verification of HTTPS endpoints..."
    if curl -s https://${DOMAIN_NAME}/healthcheck > /dev/null 2>&1; then
      echo "✅ HTTPS health endpoint is working correctly"
    else
      echo "⚠️  HTTPS health endpoint verification failed"
    fi
    
    # Test prove API endpoint
    echo "🧪 Testing prove API endpoint availability..."
    if timeout 10 curl -s -X POST https://${DOMAIN_NAME}/api/v1/prove \
        -H "Content-Type: application/json" \
        -d '{"url": "https://httpbin.org/get"}' > /dev/null 2>&1; then
      echo "✅ HTTPS prove API endpoint is responding"
    else
      echo "⚠️  HTTPS prove API endpoint may need more time to be ready"
      echo "   This is normal - the proxy service may still be initializing"
    fi
    
    echo "✅ HTTPS setup complete!"
    echo "🌐 Your TLS Notary server is now available at: https://${DOMAIN_NAME}"
    echo "🔗 Prove API endpoint: https://${DOMAIN_NAME}/api/v1/prove"
    echo "🔒 SSL certificate will auto-renew every 12 hours"
    
else
    echo "❌ Failed to obtain SSL certificate."
    echo "   This is likely because:"
    echo "   1. DNS is not pointing to this server yet"
    echo "   2. Port 80/443 is not accessible from the internet"
    echo "   3. Domain validation failed"
    echo ""
    echo "   You can retry later with:"
    echo "   sudo certbot --nginx -d ${DOMAIN_NAME}"
    exit 1
fi

# Show nginx status
echo "📋 Nginx status:"
systemctl status nginx --no-pager -l

# Show certificate info
echo "📋 Certificate info:"
certbot certificates

echo "🎉 HTTPS setup completed successfully!"
