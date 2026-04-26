#!/usr/bin/env bash
# verify-stack.sh
# End-to-end smoke test for the SOC stack.
# Exits 0 on full pass, non-zero on any failure.

set -uo pipefail

ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-changeme123}"
ES_URL="https://localhost:9200"
KIBANA_URL="${KIBANA_URL:-http://localhost:5601}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

PASS=0; FAIL=0; WARN=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; ((WARN++)); }

es() { docker exec soc-elasticsearch curl -s -k -u "$ES_USER:$ES_PASS" "$@" 2>/dev/null; }

echo "======================================"
echo "  SOC Stack – Smoke Test"
echo "======================================"

# ── T1: Containers running ────────────────────────────────────────────
echo ""
echo "T1: Containers"
for svc in soc-elasticsearch soc-kibana soc-suricata soc-filebeat soc-wazuh-manager soc-signature-service; do
  state=$(docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null || echo "missing")
  if [ "$state" = "running" ]; then pass "$svc running"
  else fail "$svc not running ($state)"; fi
done

# ── T2: Elasticsearch reachable ──────────────────────────────────────
echo ""
echo "T2: Elasticsearch"
cluster_status=$(es -X GET "$ES_URL/_cluster/health" 2>/dev/null \
  | grep -o '"status":"[^"]*"' | head -1 | sed 's/"status":"//;s/"//' || echo "error")
case "$cluster_status" in
  green)  pass "Cluster health: green" ;;
  yellow) warn "Cluster health: yellow (acceptable for single-node)" ;;
  *)      fail "Cluster health: $cluster_status" ;;
esac

# ── T3: Kibana reachable ──────────────────────────────────────────────
echo ""
echo "T3: Kibana"
kibana_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$ES_USER:$ES_PASS" \
  "$KIBANA_URL/api/status" 2>/dev/null || echo 0)
if [ "$kibana_code" = "200" ]; then pass "Kibana API responding (HTTP 200)"
else fail "Kibana API returned HTTP $kibana_code"; fi

# ── T4: Suricata rules loaded ─────────────────────────────────────────
echo ""
echo "T4: Suricata"
rule_count=$(docker exec soc-suricata \
  sh -c "ls /etc/suricata/rules/*.rules 2>/dev/null | wc -l" 2>/dev/null || echo 0)
if [ "$rule_count" -gt 0 ] 2>/dev/null; then
  pass "Suricata rules loaded ($rule_count rule files)"
else
  fail "No Suricata rule files found"
fi

log_exists=$(docker exec soc-suricata \
  sh -c "[ -f /var/log/suricata/eve.json ] && echo yes || echo no" 2>/dev/null || echo no)
if [ "$log_exists" = "yes" ]; then pass "eve.json exists"
else warn "eve.json not yet created (Suricata may still be starting)"; fi

# ── T5: Filebeat shipping logs ────────────────────────────────────────
echo ""
echo "T5: Filebeat → Elasticsearch"
fb_index=$(es -X GET "$ES_URL/_cat/indices/filebeat-*?h=index,docs.count" 2>/dev/null | head -1)
if [ -n "$fb_index" ]; then pass "Filebeat index exists: $fb_index"
else warn "No filebeat-* index yet (logs may not have shipped)"; fi

# ── T6: Suricata alerts in ES ─────────────────────────────────────────
echo ""
echo "T6: Suricata Alerts"
alert_count=$(es -X GET "$ES_URL/suricata-ids-*/_count" \
  -H 'Content-Type: application/json' \
  -d '{"query":{"match":{"event_type":"alert"}}}' \
  2>/dev/null | grep -o '"count":[0-9]*' | head -1 | sed 's/"count"://' || echo 0)

if [ "$alert_count" -gt 0 ] 2>/dev/null; then
  pass "Suricata alerts in Elasticsearch: $alert_count"
else
  warn "No alerts yet – run: bash scripts/attacks/generate-alerts.sh"
fi

# ── T7: Wazuh index ──────────────────────────────────────────────────
echo ""
echo "T7: Wazuh"
wazuh_index=$(es -X GET "$ES_URL/_cat/indices/wazuh-alerts-*?h=index,docs.count" 2>/dev/null | head -1)
if [ -n "$wazuh_index" ]; then pass "Wazuh index exists: $wazuh_index"
else warn "No wazuh-alerts-* index yet"; fi

# ── T8: Signature Service ─────────────────────────────────────────────
echo ""
echo "T8: Signature Service"
sig_code=$(curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:5000/health 2>/dev/null || echo 0)
if [ "$sig_code" = "200" ]; then pass "Signature service health OK"
else warn "Signature service returned HTTP $sig_code (may not be exposed)"; fi

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "======================================"
echo -e "  Results: ${GREEN}$PASS passed${NC}  ${YELLOW}$WARN warned${NC}  ${RED}$FAIL failed${NC}"
echo "======================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}Some tests failed. Check 'docker-compose logs <service>' for details.${NC}"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo -e "${YELLOW}All critical tests passed. Warnings are informational.${NC}"
  exit 0
else
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
