#!/bin/bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-livy-infra}"
ZONE="${ZONE:-us-central1-a}"
INSTANCE="${INSTANCE:-test-notary-instance}"
DOMAIN_NAME="${DOMAIN_NAME:-tlsn.livylabs.xyz}"

SSH_BASE=(
  gcloud compute ssh "$INSTANCE"
  --project="$PROJECT_ID"
  --zone="$ZONE"
  --quiet
)

REMOTE_PATH='export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/home/livy/.cargo/bin:$PATH'

pass_count=0
warn_count=0

log() {
  printf '%s\n' "$*"
}

pass() {
  pass_count=$((pass_count + 1))
  printf 'PASS: %s\n' "$*"
}

warn() {
  warn_count=$((warn_count + 1))
  printf 'WARN: %s\n' "$*" >&2
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

remote() {
  "${SSH_BASE[@]}" --command="$REMOTE_PATH; $*"
}

section() {
  printf '\n%s\n' "$*"
}

log "TLSN TDX deployment test"
log "project=$PROJECT_ID zone=$ZONE instance=$INSTANCE"

section "Infrastructure"
instance_status="$(gcloud compute instances describe "$INSTANCE" --project="$PROJECT_ID" --zone="$ZONE" --format='value(status)')"
[ "$instance_status" = "RUNNING" ] || fail "instance status is $instance_status"
pass "instance is RUNNING"

external_ip="$(gcloud compute instances describe "$INSTANCE" --project="$PROJECT_ID" --zone="$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
[ -n "$external_ip" ] || fail "instance has no external IP"
pass "external IP is $external_ip"

section "Cloud-init"
cloud_init_status="$(remote "sudo cloud-init status --long")"
printf '%s\n' "$cloud_init_status"
grep -q 'status: done' <<<"$cloud_init_status" || fail "cloud-init is not done"
grep -q 'errors: \[\]' <<<"$cloud_init_status" || fail "cloud-init reported errors"
pass "cloud-init completed without errors"

section "Services"
service_state="$(remote "systemctl is-active tls-notary-server tls-notary-proxy nginx")"
expected_services=$'active\nactive\nactive'
[ "$service_state" = "$expected_services" ] || fail "unexpected service state: $service_state"
pass "tls-notary-server, tls-notary-proxy, and nginx are active"

health_response="$(remote "curl -fsS http://127.0.0.1:7047/healthcheck")"
[ "$health_response" = "Ok" ] || fail "local notary healthcheck returned '$health_response'"
pass "local notary healthcheck returned Ok"

nginx_response="$(remote "curl -fsSk --resolve '$DOMAIN_NAME:443:127.0.0.1' 'https://$DOMAIN_NAME/healthcheck' 2>/dev/null || curl -fsS -H 'Host: $DOMAIN_NAME' http://127.0.0.1/healthcheck")"
[ "$nginx_response" = "Ok" ] || fail "local nginx healthcheck returned '$nginx_response'"
pass "local nginx healthcheck returned Ok"

section "TDX"
tdx_status="$(remote "sudo dmesg | grep -i 'Memory Encryption Features active' | tail -1")"
grep -q 'Intel TDX' <<<"$tdx_status" || fail "TDX memory encryption is not active"
pass "$tdx_status"

section "Binaries"
remote "test -x /home/livy/src/tlsn/target/release/notary-server"
pass "notary-server binary exists"

remote "test -x /home/livy/src/tlsn/target/release/examples/proxy"
pass "proxy binary exists"

process_line="$(remote "pgrep -a notary-server")"
grep -q '/home/livy/src/tlsn/target/release/notary-server' <<<"$process_line" || fail "notary-server process is not running from release binary"
pass "notary-server is running from release binary"

section "Intel Trust Authority"
cli_version="$(remote "trustauthority-cli version 2>/dev/null | head -1")"
grep -q 'Intel.*Trust Authority CLI' <<<"$cli_version" || fail "trustauthority-cli version check failed"
pass "$cli_version"

remote "test -f /home/livy/config.json"
pass "Intel Trust Authority config exists"

token="$(remote "sudo trustauthority-cli token --tdx -c /home/livy/config.json 2>/dev/null | tail -1")"
if [[ "$token" == eyJ* ]]; then
  pass "TDX token generated"
else
  warn "TDX token generation returned an unexpected response"
fi

evidence="$(remote "sudo trustauthority-cli evidence --tdx -u 'SGVsbG8gd29ybGQ=' -c /home/livy/config.json 2>/dev/null")"
grep -q '"tdx"' <<<"$evidence" || fail "TDX evidence output did not contain tdx object"
pass "TDX evidence generated"

userdata_evidence="$(remote "sudo trustauthority-cli evidence --tdx -u 'SGVsbG8gV29ybGQh' -c /home/livy/config.json 2>/dev/null")"
grep -q '"runtime_data"' <<<"$userdata_evidence" || fail "TDX evidence did not contain runtime_data"
grep -q 'SGVsbG8gV29ybGQh' <<<"$userdata_evidence" || fail "TDX evidence did not include supplied runtime_data"
pass "TDX evidence includes supplied runtime data"

section "Public endpoint"
if [ -n "$DOMAIN_NAME" ]; then
  resolved_ip="$(dig +short "$DOMAIN_NAME" | tail -1 || true)"
  if [ "$resolved_ip" = "$external_ip" ]; then
    pass "$DOMAIN_NAME resolves to $external_ip"
    public_https="$(curl -fsS --max-time 10 --resolve "$DOMAIN_NAME:443:$external_ip" "https://$DOMAIN_NAME/healthcheck" || true)"
    if [ "$public_https" = "Ok" ]; then
      pass "public HTTPS healthcheck returned Ok"
    else
      warn "public HTTPS healthcheck did not return Ok"
    fi
  else
    warn "$DOMAIN_NAME resolves to '${resolved_ip:-unresolved}', expected '$external_ip'"
  fi
fi

section "Summary"
log "passes=$pass_count warnings=$warn_count"

if [ "$warn_count" -gt 0 ]; then
  log "deployment tests passed with warnings"
else
  log "deployment tests passed"
fi
