#!/bin/bash

# This script tests the complete deployment to ensure everything is working correctly

set -e

echo "🚀 TLSn TDX Infrastructure Test Suite"
echo "===================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test functions
test_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
}

test_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    exit 1
}

test_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
}

# Test 1: Infrastructure Health
echo "🔍 Test 1: Infrastructure Health"
if gcloud compute instances describe test-notary-instance --zone=us-central1-a --format="value(status)" | grep -q "RUNNING"; then
    test_pass "Instance is RUNNING"
else
    test_fail "Instance is not running"
fi
echo ""

# Test 2: TLSn Service
echo "🔍 Test 2: TLSn Service Status"
if gcloud compute ssh test-notary-instance --zone=us-central1-a --command="export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\$PATH && sudo systemctl is-active tls-notary-server" | grep -q "active"; then
    test_pass "TLSn service is active"
else
    test_fail "TLSn service is not active"
fi
echo ""

# Test 3: Health Endpoint
echo "🔍 Test 3: Health Endpoint"
HEALTH_RESPONSE=$(gcloud compute ssh test-notary-instance --zone=us-central1-a --command="export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\$PATH && curl -s http://localhost:7047/healthcheck" 2>/dev/null)
if [[ "$HEALTH_RESPONSE" == *"Ok"* ]]; then
    test_pass "Health endpoint responding: $HEALTH_RESPONSE"
else
    test_fail "Health endpoint not responding correctly: $HEALTH_RESPONSE"
fi
echo ""

# Test 4: TDX Status
echo "🔍 Test 4: TDX Status"
TDX_STATUS=$(gcloud compute ssh test-notary-instance --zone=us-central1-a --command="export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\$PATH && sudo dmesg | grep -i 'Memory Encryption Features active'" 2>/dev/null)
if [[ "$TDX_STATUS" == *"Intel TDX"* ]]; then
    test_pass "TDX memory encryption active: $TDX_STATUS"
else
    test_fail "TDX memory encryption not active"
fi
echo ""

# Test 5: Native Binary
echo "🔍 Test 5: Native Binary"
BINARY_INFO=$(gcloud compute ssh test-notary-instance --zone=us-central1-a --command="export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\$PATH && sudo ls -la /home/livy/src/tlsn/target/release/notary-server" 2>/dev/null)
if [[ "$BINARY_INFO" == *"notary-server"* ]]; then
    test_pass "Native binary exists: $BINARY_INFO"
else
    test_fail "Native binary not found"
fi
echo ""

# Test 6: Process Memory Usage
echo "🔍 Test 6: Process Memory Usage"
PROCESS_INFO=$(gcloud compute ssh test-notary-instance --zone=us-central1-a --command="export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\$PATH && ps aux | grep notary-server | grep -v grep" 2>/dev/null)
if [[ "$PROCESS_INFO" == *"notary-server"* ]]; then
    test_pass "Process running natively: $PROCESS_INFO"
else
    test_fail "Process not running"
fi
echo ""

# Test 7: Service Logs (optional)
echo "🔍 Test 7: Service Logs Check"
RECENT_LOGS=$(gcloud compute ssh test-notary-instance --zone=us-central1-a --command="export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\$PATH && sudo journalctl -u tls-notary-server --since '5 minutes ago' --no-pager" 2>/dev/null | tail -3)
if [[ "$RECENT_LOGS" == *"Listening for TCP traffic"* ]] || [[ "$RECENT_LOGS" == *"notary-server"* ]]; then
    test_pass "Service logs show recent activity"
else
    test_warn "No recent service logs found (may be normal if service started earlier)"
fi
echo ""

# Test 8: Intel Trust Authority CLI
echo "🔍 Test 8: Intel Trust Authority CLI"

# Test 8.1: CLI Installation
echo "📋 Testing Intel Trust Authority CLI installation..."
CLI_VERSION=$(gcloud compute ssh test-notary-instance --zone=us-central1-a --command="export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\$PATH && trustauthority-cli version 2>/dev/null | head -1" 2>/dev/null)
if [[ "$CLI_VERSION" == *"Intel® Trust Authority CLI"* ]]; then
    test_pass "Intel Trust Authority CLI installed: $CLI_VERSION"
else
    test_fail "Intel Trust Authority CLI not found or not working"
fi

# Test 8.2: Config File
echo "📋 Testing Intel Trust Authority CLI configuration..."
CONFIG_TEST=$(gcloud compute ssh test-notary-instance --zone=us-central1-a --command="sudo test -f /home/livy/config.json && echo 'Config file exists'" 2>/dev/null)
if [[ "$CONFIG_TEST" == *"Config file exists"* ]]; then
    test_pass "Intel Trust Authority config file exists"
else
    test_fail "Intel Trust Authority config file missing"
fi

# Test 8.3: TDX Attestation
echo "📋 Testing Intel Trust Authority TDX attestation..."
ATTESTATION_RESULT=$(gcloud compute ssh test-notary-instance --zone=us-central1-a --command="export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\$PATH && sudo trustauthority-cli token --tdx -c /home/livy/config.json 2>/dev/null | tail -1" 2>/dev/null)

if [[ "$ATTESTATION_RESULT" == *"eyJ"* ]]; then
    # JWT tokens start with eyJ (base64 encoded header)
    test_pass "Intel Trust Authority TDX attestation successful - JWT token generated"
    echo "🔐 Token preview: ${ATTESTATION_RESULT:0:50}..."
else
    test_warn "Intel Trust Authority TDX attestation may have issues"
    echo "📄 Response: $ATTESTATION_RESULT"
fi

# Test 8.4: Evidence Generation
echo "📋 Testing Intel Trust Authority evidence generation..."
EVIDENCE_OUTPUT=$(gcloud compute ssh test-notary-instance --zone=us-central1-a --command="export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\$PATH && sudo trustauthority-cli evidence --tdx -u 'SGVsbG8gd29ybGQ=' -c /home/livy/config.json" 2>/dev/null)

if [[ "$EVIDENCE_OUTPUT" == *"tdx"* ]]; then
    test_pass "Intel Trust Authority evidence generation working"
    echo "📄 Evidence Output:"
    echo "$EVIDENCE_OUTPUT"
else
    test_warn "Intel Trust Authority evidence generation may have issues"
    echo "📄 Response: $EVIDENCE_OUTPUT"
fi

# Test 8.5: Evidence with User Data
echo "📋 Testing Intel Trust Authority evidence with user data 'Hello World!'..."
EVIDENCE_USERDATA=$(gcloud compute ssh test-notary-instance --zone=us-central1-a --command="export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\$PATH && sudo trustauthority-cli evidence --tdx -u 'SGVsbG8gV29ybGQh' -c /home/livy/config.json" 2>/dev/null)

if [[ "$EVIDENCE_USERDATA" == *"runtime_data"* ]] && [[ "$EVIDENCE_USERDATA" == *"SGVsbG8gV29ybGQh"* ]]; then
    test_pass "Intel Trust Authority evidence with user data 'Hello World!' working"
    echo "🔐 User data in evidence: Hello World!"
    echo "📄 Evidence snippet:"
    echo "$EVIDENCE_USERDATA" | grep -A 5 -B 5 '"runtime_data"'
else
    test_warn "Intel Trust Authority evidence with user data may have issues"
    echo "📄 Response: $EVIDENCE_USERDATA"
fi
