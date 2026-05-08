#!/bin/bash
set -euo pipefail

log() {
  printf 'install: %s\n' "$*"
}

fail() {
  printf 'install: error: %s\n' "$*" >&2
  exit 1
}

TLSN_REPO_URL="https://github.com/livylabs/tlsn.git"
TLSN_BRANCH="${1:-${TLSN_BRANCH:-tee_dev}}"
TLSN_DIR="/home/livy/src/tlsn"
CONFIG_DIR="/home/livy/tls-notary-config"

id livy >/dev/null 2>&1 || fail "user livy does not exist"

log "preparing directories"
install -d -o livy -g livy "$CONFIG_DIR" /home/livy/src

log "preparing notary configuration"
sudo -u livy env HOME=/home/livy CONFIG_DIR="$CONFIG_DIR" bash -c '
  set -euo pipefail
  cd "$CONFIG_DIR"
  if [ ! -s notary-signing-key.pem ]; then
    openssl genpkey -algorithm RSA -out notary-signing-key.pem -pass pass:
  fi
  cat > config.toml <<'"'"'EOF'"'"'
[notary]
host = "0.0.0.0"
port = 7047

[notary.signing_key]
path = "./notary-signing-key.pem"
EOF
'

log "syncing TLSN source from $TLSN_BRANCH"
sudo -u livy env HOME=/home/livy TLSN_REPO_URL="$TLSN_REPO_URL" TLSN_BRANCH="$TLSN_BRANCH" TLSN_DIR="$TLSN_DIR" bash -c '
  set -euo pipefail
  if [ ! -d "$TLSN_DIR/.git" ]; then
    git clone --branch "$TLSN_BRANCH" --single-branch "$TLSN_REPO_URL" "$TLSN_DIR"
  else
    cd "$TLSN_DIR"
    git remote set-url origin "$TLSN_REPO_URL"
    git fetch origin "$TLSN_BRANCH"
    git checkout -B "$TLSN_BRANCH" FETCH_HEAD
    git reset --hard FETCH_HEAD
  fi
'

log "building TLSN binaries"
sudo -u livy env HOME=/home/livy TLSN_DIR="$TLSN_DIR" bash -c '
  set -euo pipefail
  export CARGO_HOME=/home/livy/.cargo
  export RUSTUP_HOME=/home/livy/.rustup
  export PATH=/home/livy/.cargo/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
  source /home/livy/.cargo/env
  cd "$TLSN_DIR"
  cargo build --release -p notary-server --features tee_quote --bin notary-server
  cargo build --release -p notary-tee --example proxy
'

log "verifying binaries"
[ -x "$TLSN_DIR/target/release/notary-server" ] || fail "missing $TLSN_DIR/target/release/notary-server"
[ -x "$TLSN_DIR/target/release/examples/proxy" ] || fail "missing $TLSN_DIR/target/release/examples/proxy"

log "complete"
