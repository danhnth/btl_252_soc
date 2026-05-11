#!/bin/bash
###############################################################################
# Demo Check Script
# Verifies everything is ready for the demo
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

check_mark="${GREEN}✓${NC}"
error_mark="${RED}✗${NC}"
warning_mark="${YELLOW}⚠${NC}"

print_header() {
    echo -e "${BLUE}"
    echo "============================================================"
    echo "              SOC DEMO - PRE-FLIGHT CHECK"
    echo "============================================================"
    echo -e "${NC}"
}

print_section() {
    echo ""
    echo -e "${CYAN}$1${NC}"
    echo "------------------------------------------------------------"
}

# Check Docker
check_docker() {
    print_section "Checking Docker"
    
    if command -v docker &> /dev/null; then
        echo -e "${check_mark} Docker is installed"
        docker --version
    else
        echo -e "${error_mark} Docker is not installed"
        return 1
    fi
    
    if docker info &> /dev/null; then
        echo -e "${check_mark} Docker daemon is running"
    else
        echo -e "${error_mark} Docker daemon is not running"
        echo "   Start Docker: sudo systemctl start docker"
        return 1
    fi
}

# Check Docker Compose
check_docker_compose() {
    print_section "Checking Docker Compose"
    
    if docker compose version &> /dev/null; then
        echo -e "${check_mark} Docker Compose is available"
        docker compose version
    else
        echo -e "${error_mark} Docker Compose is not available"
        return 1
    fi
}

# Check SOC containers
check_containers() {
    print_section "Checking SOC Containers"
    
    local required_containers=("soc-elasticsearch" "soc-kibana" "soc-suricata" "soc-wazuh-manager" "soc-filebeat")
    local all_running=true
    
    for container in "${required_containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            local status=$(docker ps --filter "name=${container}" --format "{{.Status}}")
            echo -e "${check_mark} ${container}: ${status}"
        else
            echo -e "${error_mark} ${container}: Not running"
            all_running=false
        fi
    done
    
    if [ "$all_running" = false ]; then
        echo ""
        echo -e "${YELLOW}To start containers:${NC}"
        echo "  cd ~/btl_252_soc/soc-project"
        echo "  docker compose up -d"
        return 1
    fi
}

# Check network connectivity
check_network() {
    print_section "Checking Network"
    
    # Get IP addresses
    echo "Network interfaces:"
    ip -4 addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print "  " $2}'
    
    echo ""
    echo "Open ports:"
    ss -tlnp | grep -E "(5601|9200|55000|22|80)" | awk '{print "  " $4}'
}

# Check Elasticsearch
check_elasticsearch() {
    print_section "Checking Elasticsearch"
    
    cd ~/btl_252_soc/soc-project
    local es_pass=$(grep ELASTICSEARCH_PASSWORD .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "changeme")
    
    if curl -sk -u "elastic:${es_pass}" "https://localhost:9200/_cluster/health" &> /dev/null; then
        local health=$(curl -sk -u "elastic:${es_pass}" "https://localhost:9200/_cluster/health" | grep -oP '"status":"[^"]+"' | cut -d'"' -f4)
        echo -e "${check_mark} Elasticsearch is accessible"
        echo "   Cluster status: ${health}"
    else
        echo -e "${error_mark} Elasticsearch is not responding"
        return 1
    fi
}

# Check indices
check_indices() {
    print_section "Checking Elasticsearch Indices"
    
    cd ~/btl_252_soc/soc-project
    local es_pass=$(grep ELASTICSEARCH_PASSWORD .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "changeme")
    
    echo "Available indices:"
    curl -sk -u "elastic:${es_pass}" "https://localhost:9200/_cat/indices?v&s=index" 2>/dev/null | grep -E "(suricata|wazuh|filebeat)" | awk '{print "  " $3 " (docs: " $7 ", size: " $10 ")"}' || echo "  No indices found"
}

# Check alert count
check_alerts() {
    print_section "Checking Current Alerts"
    
    cd ~/btl_252_soc/soc-project
    local es_pass=$(grep ELASTICSEARCH_PASSWORD .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "changeme")
    
    local suricata_count=$(curl -sk -u "elastic:${es_pass}" "https://localhost:9200/suricata-ids-*/_count?q=event_type:alert" 2>/dev/null | grep -oP '"count":\K\d+' || echo "0")
    
    echo "Suricata alerts: ${suricata_count}"
    
    if [ "$suricata_count" -gt "0" ]; then
        echo -e "${warning_mark} There are existing alerts"
        echo "   Run 'clear-alerts.sh' to reset if needed"
    else
        echo -e "${check_mark} Clean slate - ready for demo"
    fi
}

# Check Kibana
check_kibana() {
    print_section "Checking Kibana"
    
    if curl -s -I "http://localhost:5601" &> /dev/null | grep -q "200 OK\|302 Found"; then
        echo -e "${check_mark} Kibana is accessible"
        echo "   URL: http://localhost:5601"
    else
        echo -e "${error_mark} Kibana is not responding"
        return 1
    fi
}

# Check data views
check_data_views() {
    print_section "Checking Kibana Data Views"
    
    cd ~/btl_252_soc/soc-project
    local es_pass=$(grep ELASTICSEARCH_PASSWORD .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "changeme")
    
    echo "Data views (index patterns):"
    curl -sk -u "elastic:${es_pass}" "http://localhost:5601/api/saved_objects/_find?type=index-pattern" 2>/dev/null | grep -oP '"title":"[^"]+"' | sed 's/"title":"/  - /;s/"//' || echo "  No data views found"
    
    echo ""
    echo -e "${YELLOW}If data views are missing, run:${NC}"
    echo "  bash ~/btl_252_soc/scripts/setup/setup-kibana.sh"
}

# Check system resources
check_resources() {
    print_section "Checking System Resources"
    
    # Memory
    local total_mem=$(free -m | awk 'NR==2{printf "%.1f", $2/1024}')
    local used_mem=$(free -m | awk 'NR==2{printf "%.1f", ($2-$7)/1024}')
    local mem_percent=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    
    echo "Memory: ${used_mem}GB / ${total_mem}GB (${mem_percent}% used)"
    
    if [ "$mem_percent" -gt 90 ]; then
        echo -e "${warning_mark} Memory usage is high"
    else
        echo -e "${check_mark} Memory OK"
    fi
    
    # Disk
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    echo "Disk: ${disk_usage}% used"
    
    if [ "$disk_usage" -gt 90 ]; then
        echo -e "${warning_mark} Disk usage is high"
    else
        echo -e "${check_mark} Disk OK"
    fi
}

# Main
print_header

check_docker || exit 1
check_docker_compose || exit 1
check_containers || exit 1
check_network
check_elasticsearch || exit 1
check_indices
check_alerts
check_kibana || exit 1
check_data_views
check_resources

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}                    ALL CHECKS PASSED!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "Your SOC stack is ready for the demo!"
echo ""
echo "Next steps:"
echo "  1. Note your IP address from above"
echo "  2. Run attack script on Windows:"
echo "     python windows-attacker.py <YOUR_IP> --quick"
echo "  3. Watch alerts appear in Kibana:"
echo "     http://localhost:5601"
echo ""
