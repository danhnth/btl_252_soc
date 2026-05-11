#!/bin/bash
###############################################################################
# SOC Demo Orchestrator
# Runs from Alma Linux to coordinate the full demo
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOC_PROJECT_DIR="${SCRIPT_DIR}/../soc-project"
ATTACKER_IP=""
VICTIM_IP=""

# Functions
print_banner() {
    echo -e "${BLUE}"
    echo "============================================================"
    echo "             SOC DEMO - ATTACK ORCHESTRATOR"
    echo "============================================================"
    echo -e "${NC}"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_soc_stack() {
    print_info "Checking SOC stack status..."
    
    if [ ! -d "$SOC_PROJECT_DIR" ]; then
        print_error "SOC project directory not found: $SOC_PROJECT_DIR"
        exit 1
    fi
    
    cd "$SOC_PROJECT_DIR"
    
    # Check if containers are running
    if ! docker compose ps | grep -q "soc-elasticsearch.*healthy"; then
        print_warning "SOC stack not fully healthy"
        print_info "Starting SOC stack..."
        docker compose up -d
        print_info "Waiting 60 seconds for services to initialize..."
        sleep 60
    fi
    
    print_success "SOC stack is running"
}

get_victim_ip() {
    print_info "Detecting victim IP address..."
    
    # Try to get IP from common interfaces
    VICTIM_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -1)
    
    if [ -z "$VICTIM_IP" ]; then
        print_warning "Could not auto-detect IP"
        read -p "Enter this machine's IP address: " VICTIM_IP
    else
        print_success "Detected IP: $VICTIM_IP"
        read -p "Is this correct? [Y/n]: " confirm
        if [[ $confirm =~ ^[Nn]$ ]]; then
            read -p "Enter correct IP address: " VICTIM_IP
        fi
    fi
}

show_dashboard_urls() {
    print_banner
    print_info "Dashboard URLs:"
    echo ""
    echo -e "  ${GREEN}Kibana (Suricata):${NC} http://${VICTIM_IP}:5601"
    echo -e "  ${GREEN}Wazuh Dashboard:${NC}   https://${VICTIM_IP}"
    echo ""
    print_info "Default credentials:"
    echo "  Kibana: elastic / [password from .env file]"
    echo "  Wazuh:  admin / [password from .env file]"
    echo ""
}

clear_alerts() {
    print_warning "This will clear existing alerts from Elasticsearch"
    read -p "Are you sure? [y/N]: " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        print_info "Clearing old alerts..."
        cd "$SOC_PROJECT_DIR"
        
        # Get password from .env
        ES_PASS=$(grep ELASTICSEARCH_PASSWORD .env | cut -d= -f2 | tr -d '"')
        
        # Delete and recreate indices
        curl -sk -u "elastic:${ES_PASS}" -X DELETE "https://localhost:9200/suricata-ids-*" 2>/dev/null || true
        curl -sk -u "elastic:${ES_PASS}" -X DELETE "https://localhost:9200/wazuh-alerts-*" 2>/dev/null || true
        
        print_success "Old alerts cleared"
    fi
}

monitor_mode() {
    print_banner
    print_info "Entering monitoring mode..."
    print_info "Watching for new alerts (Press Ctrl+C to stop)"
    echo ""
    
    cd "$SOC_PROJECT_DIR"
    ES_PASS=$(grep ELASTICSEARCH_PASSWORD .env | cut -d= -f2 | tr -d '"')
    
    local last_count=0
    while true; do
        clear
        echo -e "${BLUE}============================================================${NC}"
        echo -e "${BLUE}                    ALERT MONITOR${NC}"
        echo -e "${BLUE}============================================================${NC}"
        echo ""
        
        # Count alerts
        local alert_count=$(curl -sk -u "elastic:${ES_PASS}" "https://localhost:9200/suricata-ids-*/_count?q=event_type:alert" 2>/dev/null | grep -oP '"count":\K\d+' || echo "0")
        
        echo -e "Total Suricata Alerts: ${GREEN}${alert_count}${NC}"
        
        if [ "$alert_count" -gt "$last_count" ]; then
            local new_alerts=$((alert_count - last_count))
            echo -e "${GREEN}+${new_alerts} new alerts detected!${NC}"
        fi
        
        last_count=$alert_count
        
        echo ""
        echo "Recent alerts:"
        curl -sk -u "elastic:${ES_PASS}" "https://localhost:9200/suricata-ids-*/_search?q=event_type:alert&size=5&sort=@timestamp:desc" 2>/dev/null | grep -oP '"signature":"[^"]+"' | head -5 | sed 's/"signature":"/  - /;s/"//' || echo "  No alerts yet"
        
        echo ""
        echo -e "${YELLOW}Press Ctrl+C to exit monitoring${NC}"
        
        sleep 5
    done
}

generate_report() {
    print_banner
    print_info "Generating demo report..."
    
    cd "$SOC_PROJECT_DIR"
    ES_PASS=$(grep ELASTICSEARCH_PASSWORD .env | cut -d= -f2 | tr -d '"')
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local report_file="${SCRIPT_DIR}/demo-report-${timestamp}.txt"
    
    echo "SOC Demo Report" > "$report_file"
    echo "Generated: $(date)" >> "$report_file"
    echo "Victim IP: $VICTIM_IP" >> "$report_file"
    echo "========================================" >> "$report_file"
    echo "" >> "$report_file"
    
    # Get alert counts by category
    echo "Alert Summary:" >> "$report_file"
    curl -sk -u "elastic:${ES_PASS}" "https://localhost:9200/suricata-ids-*/_search" -H 'Content-Type: application/json' -d'{
        "size": 0,
        "aggs": {
            "by_category": {
                "terms": {"field": "alert.category.keyword", "size": 10}
            }
        }
    }' 2>/dev/null | grep -oP '"key":"[^"]+","doc_count":\d+' | sed 's/"key":"/Category: /;s/","doc_count":/ | Count: /' >> "$report_file" || echo "No alerts found" >> "$report_file"
    
    echo "" >> "$report_file"
    echo "Top 10 Alert Signatures:" >> "$report_file"
    curl -sk -u "elastic:${ES_PASS}" "https://localhost:9200/suricata-ids-*/_search" -H 'Content-Type: application/json' -d'{
        "size": 0,
        "aggs": {
            "by_signature": {
                "terms": {"field": "alert.signature.keyword", "size": 10}
            }
        }
    }' 2>/dev/null | grep -oP '"key":"[^"]+","doc_count":\d+' | sed 's/"key":"/  - /;s/","doc_count":/ (Count: /;s/$/)/' >> "$report_file" || echo "No alerts found" >> "$report_file"
    
    print_success "Report saved to: $report_file"
    cat "$report_file"
}

main_menu() {
    while true; do
        print_banner
        echo "Main Menu:"
        echo ""
        echo "  1. Check SOC Stack Status"
        echo "  2. Show Dashboard URLs"
        echo "  3. Clear Existing Alerts"
        echo "  4. Monitor Mode (Live Alert View)"
        echo "  5. Generate Demo Report"
        echo "  6. Full Demo Setup"
        echo "  0. Exit"
        echo ""
        read -p "Select option: " choice
        
        case $choice in
            1)
                check_soc_stack
                read -p "Press Enter to continue..."
                ;;
            2)
                get_victim_ip
                show_dashboard_urls
                read -p "Press Enter to continue..."
                ;;
            3)
                clear_alerts
                read -p "Press Enter to continue..."
                ;;
            4)
                monitor_mode
                ;;
            5)
                get_victim_ip
                generate_report
                read -p "Press Enter to continue..."
                ;;
            6)
                get_victim_ip
                check_soc_stack
                show_dashboard_urls
                print_success "Demo setup complete!"
                print_info "Ready to receive attacks from Windows machine"
                print_info "Run the attack script on Windows:"
                echo "  python windows-attacker.py ${VICTIM_IP} --all"
                read -p "Press Enter to continue..."
                ;;
            0)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Main
print_banner
print_info "SOC Demo Orchestrator"
print_info "Running from: $(hostname)"
echo ""

# Check if running on Alma Linux
if [ -f /etc/almalinux-release ] || [ -f /etc/rocky-release ] || [ -f /etc/redhat-release ]; then
    print_success "Alma Linux / RHEL detected"
else
    print_warning "This script is designed for Alma Linux / RHEL"
    read -p "Continue anyway? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

main_menu
