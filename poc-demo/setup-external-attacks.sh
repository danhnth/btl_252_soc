#!/bin/bash
###############################################################################
# External Attack Demo Setup Helper
# Run this on Alma Linux to prepare for Windows attacks
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOC_PROJECT_DIR="${SCRIPT_DIR}/../soc-project"
RELAY_PID=""

print_header() {
    echo -e "${BLUE}"
    echo "============================================================"
    echo "      EXTERNAL ATTACK DEMO - SETUP HELPER"
    echo "============================================================"
    echo -e "${NC}"
}

print_section() {
    echo ""
    echo -e "${CYAN}$1${NC}"
    echo "------------------------------------------------------------"
}

cleanup() {
    if [ -n "$RELAY_PID" ]; then
        echo ""
        echo -e "${YELLOW}Stopping relay server...${NC}"
        kill $RELAY_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT

check_soc_stack() {
    print_section "Checking SOC Stack"
    
    cd "$SOC_PROJECT_DIR"
    
    if ! docker compose ps | grep -q "soc-suricata"; then
        echo -e "${error_mark} SOC stack is not running"
        echo ""
        echo "Starting SOC stack..."
        docker compose up -d
        echo ""
        echo "Waiting 60 seconds for services to start..."
        sleep 60
    else
        echo -e "${check_mark} SOC stack is running"
    fi
}

get_ip_address() {
    print_section "Network Configuration"
    
    echo "Your IP addresses:"
    ip -4 addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print "  " $2}' | while read ip; do
        echo -e "  ${GREEN}$ip${NC}"
    done
    
    echo ""
    echo -e "${YELLOW}Provide this IP to the Windows attacker${NC}"
}

open_firewall() {
    print_section "Opening Firewall"
    
    if command -v firewall-cmd &> /dev/null; then
        echo "Opening port 9999/tcp for attack relay..."
        sudo firewall-cmd --add-port=9999/tcp 2>/dev/null || true
        echo -e "${check_mark} Port 9999 opened (temporary)"
        
        echo ""
        echo "To make permanent:"
        echo "  sudo firewall-cmd --add-port=9999/tcp --permanent"
        echo "  sudo firewall-cmd --reload"
    else
        echo -e "${YELLOW}firewall-cmd not found. Please manually open port 9999${NC}"
    fi
}

start_relay() {
    print_section "Starting Attack Relay"
    
    cd "$SCRIPT_DIR/attacker-scripts"
    
    if [ ! -f "external-attack-relay.py" ]; then
        echo -e "${error_mark} external-attack-relay.py not found"
        exit 1
    fi
    
    echo "Starting relay in background..."
    python3 external-attack-relay.py &
    RELAY_PID=$!
    
    # Wait for relay to start
    sleep 2
    
    # Check if relay is running
    if kill -0 $RELAY_PID 2>/dev/null; then
        echo -e "${check_mark} Relay is running (PID: $RELAY_PID)"
        echo -e "${check_mark} Listening on port 9999"
    else
        echo -e "${error_mark} Failed to start relay"
        exit 1
    fi
}

show_status() {
    print_section "Setup Complete!"
    
    echo -e "${GREEN}✓${NC} SOC stack is running"
    echo -e "${GREEN}✓${NC} Attack relay is running on port 9999"
    echo -e "${GREEN}✓${NC} Firewall allows port 9999"
    echo ""
    
    echo -e "${CYAN}Windows attacker should run:${NC}"
    echo "  1. Double-click: poc-demo\\run-attack-client.bat"
    echo "  2. Enter your Alma Linux IP"
    echo "  3. Select demo mode"
    echo ""
    
    echo -e "${CYAN}Or from PowerShell:${NC}"
    echo "  python poc-demo\\attacker-scripts\\windows-attack-client.py <YOUR_IP> --quick"
    echo ""
    
    echo -e "${YELLOW}Press Ctrl+C to stop the relay${NC}"
    echo ""
    
    # Keep script running
    wait $RELAY_PID
}

main() {
    print_header
    
    # Check if running as root for firewall
    if [ "$EUID" -eq 0 ]; then
        echo -e "${YELLOW}Warning: Running as root. Continuing...${NC}"
    fi
    
    check_soc_stack
    get_ip_address
    open_firewall
    start_relay
    show_status
}

main
