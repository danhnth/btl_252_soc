#!/usr/bin/env bash
# setup-kibana.sh
# Creates index patterns and data views in Kibana for the SOC stack.
# Run once after the stack is up.

set -euo pipefail

KIBANA_URL="${KIBANA_URL:-http://localhost:5601}"
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-changeme123}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
fail() { echo -e "${RED}✗ $*${NC}"; exit 1; }

echo "======================================"
echo "  SOC Kibana Setup"
echo "======================================"
echo "Kibana: $KIBANA_URL"
echo ""

# ── 1. Wait for Kibana ──────────────────────────────────────────────
echo "[1/3] Waiting for Kibana..."
for i in $(seq 1 30); do
  status=$(curl -s -u "$ES_USER:$ES_PASS" "$KIBANA_URL/api/status" 2>/dev/null || true)
  if echo "$status" | grep -q '"overall"'; then
    ok "Kibana is ready"; break
  fi
  [ "$i" -eq 30 ] && fail "Kibana did not become ready after 60 s"
  echo "  Attempt $i/30 – retrying in 2 s…"; sleep 2
done

# ── 2. Create data views ─────────────────────────────────────────────
echo ""
echo "[2/3] Creating data views..."

create_data_view() {
  local id="$1" title="$2" time_field="$3"
  echo ""
  echo "[2/3] Creating data view: $title"

  exists=$(curl -s -u "$ES_USER:$ES_PASS" \
    "$KIBANA_URL/api/data_views/data_view/$id" \
    -H "kbn-xsrf: true" 2>/dev/null || true)

  if echo "$exists" | grep -q "\"id\":\"$id\""; then
    warn "Data view '$title' already exists – skipping"; return
  fi

  result=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$ES_USER:$ES_PASS" \
    -X POST "$KIBANA_URL/api/data_views/data_view" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{\"data_view\":{\"id\":\"$id\",\"name\":\"$title\",\"title\":\"$title\",\"timeFieldName\":\"$time_field\"}}")

  [ "$result" = "200" ] && ok "Created: $title" || warn "HTTP $result for $title (may already exist)"
}

create_data_view "suricata-ids"    "suricata-ids-*"    "@timestamp"
create_data_view "wazuh-alerts"    "wazuh-alerts-*"    "@timestamp"
create_data_view "filebeat"        "filebeat-*"        "@timestamp"

# ── 3. Summary ───────────────────────────────────────────────────────
echo ""
echo "[3/3] Setup complete"
echo ""
echo "Open Kibana and navigate to:"
echo "  Analytics → Discover → select a data view"
echo ""
echo "Useful data views:"
echo "  suricata-ids-*  → Suricata IDS alerts"
echo "  wazuh-alerts-*  → Wazuh SIEM events"
echo "  filebeat-*      → All aggregated logs"
echo ""
echo "URL: $KIBANA_URL"