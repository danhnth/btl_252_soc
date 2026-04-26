#!/usr/bin/env bash
# generate-alerts.sh
# Generates diverse IDS alert traffic by making outbound HTTP requests
# from inside the Suricata container (bypasses Docker bridge limitation).
#
# Usage:
#   ./generate-alerts.sh          # run all scenarios
#   ./generate-alerts.sh --quick  # run only the fastest 3 scenarios

set -uo pipefail

QUICK="${1:-}"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()    { echo -e "  ${GREEN}✓ $*${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $*${NC}"; }
fail()  { echo -e "  ${RED}✗ $*${NC}"; }
hdr()   { echo -e "\n${CYAN}$*${NC}"; }

run() {
  # $1 = label, $2..N = docker exec command
  local label="$1"; shift
  echo -n "  → $label … "
  if docker exec soc-suricata "$@" > /dev/null 2>&1; then
    echo -e "${GREEN}done${NC}"
  else
    echo -e "${YELLOW}skipped (network error)${NC}"
  fi
}

echo "======================================"
echo "  SOC Alert Generator"
echo "======================================"
echo "All requests run from inside soc-suricata so"
echo "Suricata can inspect its own outbound traffic."
echo ""

# ── Verify Suricata is running ───────────────────────────────────────
if ! docker inspect --format '{{.State.Status}}' soc-suricata 2>/dev/null | grep -q running; then
  echo -e "${RED}✗ soc-suricata is not running. Start the stack first.${NC}"
  exit 1
fi

# ── Scenario 1: IDS test (testmynids.org) ────────────────────────────
hdr "[1] IDS Detection Test  (GPL ATTACK_RESPONSE)"
run "testmynids.org – uid check" curl -s http://testmynids.org/uid/index.html
run "testmynids.org – repeat x3" sh -c "for i in 1 2 3; do curl -s http://testmynids.org/uid/index.html>/dev/null; sleep 1; done"

if [ "$QUICK" != "--quick" ]; then
  # ── Scenario 2: Malware / executable download ─────────────────────
  hdr "[2] Malware Download Simulation  (ET MALWARE)"
  run "Terse executable downloader" curl -s -A "Go-http-client/1.1" http://testmynids.org/uid/index.html
  run "Binary filename pattern"     curl -s "http://testmynids.org/a/b.exe" || true

  # ── Scenario 3: Scanner user-agents ──────────────────────────────
  hdr "[3] Security Scanner Detection  (ET SCAN)"
  run "sqlmap agent"  curl -s -A "sqlmap/1.5-dev" http://testmynids.org/
  run "Nikto agent"   curl -s -A "Nikto/2.1.6"    http://testmynids.org/
  run "Nmap NSE"      curl -s -A "Mozilla/5.0 (compatible; Nmap Scripting Engine)" http://testmynids.org/

  # ── Scenario 4: Known bad domains ────────────────────────────────
  hdr "[4] Known-Bad Domain Lookup  (ET DNS)"
  run "Possible C2 domain"  sh -c "nslookup irc.freenode.net > /dev/null 2>&1 || curl -s http://irc.freenode.net > /dev/null 2>&1 || true"

  # ── Scenario 5: Policy violations ─────────────────────────────────
  hdr "[5] Policy Violation  (ET POLICY)"
  run "Tor check.torproject.org"  curl -s https://check.torproject.org/ || true
  run "curl UA outbound"          curl -s http://detectportal.firefox.com/

  # ── Scenario 6: Repeat for volume ─────────────────────────────────
  hdr "[6] Burst traffic (5 rapid requests)"
  run "Burst x5" sh -c "for i in 1 2 3 4 5; do curl -s http://testmynids.org/uid/index.html>/dev/null; done"
fi

# ── Wait for Filebeat to ship ─────────────────────────────────────────
echo ""
echo "Waiting 15 s for Filebeat to ship alerts to Elasticsearch…"
sleep 15

# ── Final count ───────────────────────────────────────────────────────
echo ""
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-changeme123}"
count=$(docker exec soc-elasticsearch curl -s -k \
  -u "$ES_USER:$ES_PASS" \
  -X GET "https://localhost:9200/suricata-ids-*/_count" \
  -H 'Content-Type: application/json' \
  -d '{"query":{"match":{"event_type":"alert"}}}' \
  2>/dev/null | grep -o '"count":[0-9]*' | head -1 | sed 's/"count"://' || echo "?")

echo "======================================"
echo -e "  ${GREEN}Total alerts in Elasticsearch: $count${NC}"
echo "  View in Kibana → Discover → suricata-ids-*"
echo "======================================"
