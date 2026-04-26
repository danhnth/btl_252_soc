#!/usr/bin/env bash
# check-stack.sh
# Verifies that all SOC services are healthy and prints a status summary.

set -uo pipefail

ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-changeme123}"
ES_URL="https://localhost:9200"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓ $*${NC}"; }
warn() { echo -e "  ${YELLOW}⚠ $*${NC}"; }
fail() { echo -e "  ${RED}✗ $*${NC}"; }
hdr()  { echo -e "\n${BLUE}$*${NC}"; }

es() {
  docker exec soc-elasticsearch curl -s -k \
    -u "$ES_USER:$ES_PASS" "$@" 2>/dev/null
}

echo "======================================"
echo "  SOC Stack Health Check"
echo "======================================"

# ── 1. Container status ───────────────────────────────────────────────
hdr "[1] Container Status"
services=(soc-elasticsearch soc-kibana soc-suricata soc-filebeat soc-wazuh-manager soc-signature-service)
all_ok=true
for svc in "${services[@]}"; do
  state=$(docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null || echo "missing")
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$svc" 2>/dev/null || echo "")
  if [ "$state" = "running" ]; then
    ok "$svc  ($health)"
  else
    fail "$svc  ($state)"; all_ok=false
  fi
done

# ── 2. Elasticsearch cluster health ──────────────────────────────────
hdr "[2] Elasticsearch Cluster"
cluster=$(es -X GET "$ES_URL/_cluster/health" 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | sed 's/"status":"//;s/"//' || echo "unreachable")
case "$cluster" in
  green)  ok "Cluster status: green" ;;
  yellow) warn "Cluster status: yellow (normal for single-node)" ;;
  *)      fail "Cluster status: $cluster" ;;
esac

# ── 3. Suricata alert count ───────────────────────────────────────────
hdr "[3] Suricata Alerts"
count=$(es -X GET "$ES_URL/suricata-ids-*/_count" \
  -H 'Content-Type: application/json' \
  -d '{"query":{"match":{"event_type":"alert"}}}' \
  2>/dev/null | grep -o '"count":[0-9]*' | head -1 | sed 's/"count"://' || echo 0)

if [ "$count" -gt 0 ] 2>/dev/null; then
  ok "Total alerts in Elasticsearch: $count"
else
  warn "No alerts found yet – run scripts/attacks/generate-alerts.sh to generate some"
fi

# ── Top 5 alert signatures ────────────────────────────────────────────
hdr "[4] Top Alert Signatures"
sigs=$(es -X GET "$ES_URL/suricata-ids-*/_search?size=0" \
  -H 'Content-Type: application/json' \
  -d '{
    "query":{"match":{"event_type":"alert"}},
    "aggs":{"sigs":{"terms":{"field":"alert.signature.keyword","size":5}}}
  }' 2>/dev/null | grep -o '"key":"[^"]*","doc_count":[0-9]*' | \
  sed 's/"key":"//;s/","doc_count":/ x /' || true)
if [ -n "$sigs" ]; then
  echo "$sigs" | while IFS= read -r line; do echo "  • $line"; done
else
  echo "  (none yet)"
fi

# ── 5. Index health ───────────────────────────────────────────────────
hdr "[5] Index Health"
es -X GET "$ES_URL/_cat/indices/suricata-ids-*,wazuh-alerts-*?h=index,health,docs.count&s=index" \
  | while IFS= read -r line; do
      health=$(echo "$line" | awk '{print $2}')
      case "$health" in
        green)  ok "$line" ;;
        yellow) warn "$line  (normal – single-node)" ;;
        *)      fail "$line" ;;
      esac
    done

echo ""
echo "======================================"
echo "Kibana:  http://localhost:5601  (elastic / from .env)"
echo "======================================"
