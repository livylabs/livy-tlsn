#!/bin/bash
set -euo pipefail

log() {
  printf 'core: %s\n' "$*"
}

fail() {
  printf 'core: error: %s\n' "$*" >&2
  exit 1
}

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

log "installing host packages"
apt-get update
apt-get install -y \
  apt-transport-https \
  build-essential \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  libclang-dev \
  libssl-dev \
  lsb-release \
  pkg-config \
  wget

log "preparing livy user home"
id livy >/dev/null 2>&1 || fail "user livy does not exist"
install -d -o livy -g livy /home/livy
chown -R livy:livy /home/livy

log "checking TDX device"
[ -e /dev/tdx_guest ] || fail "/dev/tdx_guest is missing; verify the instance is a TDX confidential VM"
chmod 0666 /dev/tdx_guest

log "installing Rust toolchain"
sudo -u livy env HOME=/home/livy bash -c '
  set -euo pipefail
  export CARGO_HOME=/home/livy/.cargo
  export RUSTUP_HOME=/home/livy/.rustup
  curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
'

log "installing Intel Trust Authority CLI"
curl -fsSL https://raw.githubusercontent.com/intel/trustauthority-client-for-go/main/release/install-tdx-cli.sh | bash -
command -v trustauthority-cli >/dev/null 2>&1 || fail "trustauthority-cli is not on PATH after installation"

log "checking TDX kernel state"
DMESG_FILE=/tmp/livy-tdx-dmesg.log
dmesg > "$DMESG_FILE"
grep -Eiq "Memory Encryption Features active:.*TDX|tdx: Guest detected" "$DMESG_FILE" \
  || fail "kernel does not report active TDX memory encryption"

log "checking Intel Trust Authority config"
[ -f /home/livy/config.json ] || fail "/home/livy/config.json was not written by cloud-init"
jq -e '.trustauthority_api_key | strings | length > 0' /home/livy/config.json >/dev/null \
  || fail "/home/livy/config.json does not contain trustauthority_api_key"
chown livy:livy /home/livy/config.json
chmod 0640 /home/livy/config.json

log "configuring trustauthority-cli sudo access"
cat > /etc/sudoers.d/livy-trustauthority <<'EOF'
livy ALL=(ALL) NOPASSWD: /usr/bin/trustauthority-cli
EOF
chmod 0440 /etc/sudoers.d/livy-trustauthority
visudo -cf /etc/sudoers.d/livy-trustauthority >/dev/null

log "installing trustauthority-cli wrapper"
cat > /usr/local/bin/trustauthority-cli <<'EOF'
#!/bin/bash
exec sudo /usr/bin/trustauthority-cli "$@"
EOF
chmod 0755 /usr/local/bin/trustauthority-cli

log "complete"
