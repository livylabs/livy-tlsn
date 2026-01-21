#!/bin/bash
set -euo pipefail

echo "🚀 Starting TLS Notary Installation..."

# Create TLS Notary configuration directory
echo "📁 Creating TLS Notary configuration directory..."
mkdir -p /home/livy/tls-notary-config
chown -R livy:livy /home/livy/tls-notary-config

# Generate TLS Notary signing key
echo "🔑 Generating TLS Notary signing key..."
sudo -u livy bash -c '
cd /home/livy/tls-notary-config
openssl genpkey -algorithm RSA -out notary-signing-key.pem -pass pass:
echo "✅ TLS Notary signing key generated"
'

# Create TLS Notary configuration file
echo "⚙️ Creating TLS Notary configuration file..."
sudo -u livy bash -c '
cd /home/livy/tls-notary-config
echo "[notary]" > config.toml
echo "host = \"0.0.0.0\"" >> config.toml
echo "port = 7047" >> config.toml
echo "" >> config.toml
echo "[notary.signing_key]" >> config.toml
echo "path = \"./notary-signing-key.pem\"" >> config.toml
echo "" >> config.toml
echo "[notary.attestation]" >> config.toml
echo "# Intel Trust Authority configuration will be added here" >> config.toml
echo "✅ TLS Notary configuration created"
'

# Download TLS Notary server from source
echo "📥 Downloading TLS Notary source code..."
sudo -u livy bash -c '
cd /home/livy
mkdir -p src
cd src
if [ ! -d "tlsn" ]; then
  git clone https://github.com/livylabs/tlsn.git
  cd tlsn
  # Use tee_dev branch from livylabs fork
  git checkout tee_dev
  echo "✅ Livy Labs TLS Notary source code downloaded"
else
  echo "✅ TLS Notary source code already exists, updating to livylabs fork..."
  cd tlsn
  git remote set-url origin https://github.com/livylabs/tlsn.git
  git fetch origin
  git checkout tee_dev
  git pull origin tee_dev
  echo "✅ Updated to livylabs/tlsn fork"
fi
'

# Build TLS Notary server
echo "🔨 Building TLS Notary server..."
sudo -u livy bash -c '
cd /home/livy/src/tlsn
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/home/livy/.cargo/bin:$PATH"
export CARGO_HOME="/home/livy/.cargo"
export RUSTUP_HOME="/home/livy/.rustup"
source /home/livy/.cargo/env

# Check if already built
if [ -f "target/release/notary-server" ]; then
  echo "✅ TLS Notary server already built, skipping build"
else
  cargo build --release --bin notary-server
  echo "✅ TLS Notary server built successfully"
fi
'

# Verify the build
echo "🧪 Verifying TLS Notary build..."
sudo -u livy bash -c '
if [ -f "/home/livy/src/tlsn/target/release/notary-server" ]; then
  echo "✅ TLS Notary server binary exists and is executable"
  ls -la /home/livy/src/tlsn/target/release/notary-server
else
  echo "❌ TLS Notary server binary not found"
  exit 1
fi
'

echo "✅ TLS Notary Installation Complete!"

