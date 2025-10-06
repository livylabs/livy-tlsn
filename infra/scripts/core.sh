#!/bin/bash
set -euo pipefail

echo "🚀 Starting Core Infrastructure Setup..."

# Update system packages
echo "📦 Updating system packages..."
apt-get update
apt-get install -y libclang-dev pkg-config build-essential libssl-dev git curl jq apt-transport-https ca-certificates gnupg lsb-release wget

# Set permissions for TDX device access
echo "🔧 Setting TDX device permissions..."
chmod 666 /dev/tdx_guest

# Install Rust as livy user
echo "🦀 Installing Rust for livy user..."
sudo -u livy bash -c '
curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
echo "✅ Rust installed for livy user"
'

# Install Intel Trust Authority CLI using official Intel script
echo "🔐 Installing Intel Trust Authority CLI..."
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH
curl -sL https://raw.githubusercontent.com/intel/trustauthority-client-for-go/main/release/install-tdx-cli.sh | bash -

# Test Intel Trust Authority CLI installation
echo "🧪 Testing Intel Trust Authority CLI..."
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH
if command -v trustauthority-cli >/dev/null 2>&1; then
  echo "✅ Intel Trust Authority CLI is available: $(trustauthority-cli version 2>&1 | head -1)"
else
  echo "❌ Intel Trust Authority CLI installation failed"
  exit 1
fi

# Verify TDX is active in kernel
echo "🔧 Verifying TDX kernel support..."
sudo -u livy bash -c '
if sudo dmesg | grep -i "Memory Encryption Features active: TDX" >/dev/null; then
  echo "✅ TDX memory encryption active in kernel"
else
  echo "❌ TDX memory encryption not active"
  exit 1
fi
'

# Create Intel Trust Authority config with environment variable
echo "⚙️ Creating Intel Trust Authority configuration..."
sudo -u livy bash -c '
cd /home/livy
echo "{" > config.json
echo "  \"trustauthority_api_key\": \"${trustauthority_api_key}\"," >> config.json
echo "  \"trustauthority_api_url\": \"https://api.trustauthority.intel.com\"" >> config.json
echo "}" >> config.json
echo "✅ Intel Trust Authority config created with environment variable"
'

echo "✅ Core Infrastructure Setup Complete!"

