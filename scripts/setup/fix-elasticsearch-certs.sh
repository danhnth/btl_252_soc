#!/usr/bin/env bash
# fix-elasticsearch-certs.sh
# Fixes SSL certificate permissions for Elasticsearch Docker container
# Run this on the Linux VM/host if Elasticsearch fails with:
#   "SslConfigException: not permitted to read the PEM private key file"
#
# Usage: sudo bash scripts/setup/fix-elasticsearch-certs.sh [cert-path]
#        If cert-path is omitted, attempts to auto-detect from .env or docker-compose.yml

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
ok()   { echo -e "  ${GREEN}✓ $*${NC}"; }
warn() { echo -e "  ${YELLOW}⚠ $*${NC}"; }
fail() { echo -e "  ${RED}✗ $*${NC}"; }
info() { echo -e "  ${BLUE}ℹ $*${NC}"; }

# Script directory (for relative path resolution)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SOC_PROJECT="${PROJECT_ROOT}/soc-project"

show_help() {
    cat << EOF
Usage: sudo $(basename "$0") [OPTIONS] [CERT-PATH]

Fix Elasticsearch SSL certificate permissions for Docker deployment.

OPTIONS:
    -h, --help      Show this help message
    -n, --no-restart    Don't restart containers after fixing permissions
    -y, --yes       Auto-confirm all prompts

CERT-PATH:
    Path to certificate directory. If not provided, attempts to detect from:
    1. TLS_CERT_PATH environment variable
    2. soc-project/.env file
    3. soc-project/docker-compose.yml

EXAMPLES:
    sudo $(basename "$0")                           # Auto-detect path
    sudo $(basename "$0") /opt/soc/certs            # Use specific path
    sudo $(basename "$0") -n /opt/soc/certs         # Fix only, don't restart

REQUIREMENTS:
    - Must run as root or with sudo
    - Docker and docker-compose must be installed
    - Certificates must exist at the target path

EXIT CODES:
    0   Success
    1   General error
    2   Not running as root
    3   Certificate path not found
    4   Certificate files missing
EOF
}

# Parse arguments
AUTO_CONFIRM=false
NO_RESTART=false
CERT_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--no-restart)
            NO_RESTART=true
            shift
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -*)
            fail "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            CERT_PATH="$1"
            shift
            ;;
    esac
done

echo "======================================"
echo "  Elasticsearch Cert Permission Fix"
echo "======================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    fail "This script must be run as root or with sudo"
    exit 2
fi

# Determine certificate path if not provided
if [ -z "$CERT_PATH" ]; then
    info "Cert path not provided, attempting auto-detection..."
    
    # Method 1: Check environment variable
    if [ -n "${TLS_CERT_PATH:-}" ]; then
        CERT_PATH="$TLS_CERT_PATH"
        ok "Found TLS_CERT_PATH environment variable: $CERT_PATH"
    # Method 2: Check .env file in soc-project
    elif [ -f "${SOC_PROJECT}/.env" ]; then
        ENV_PATH=$(grep -E '^TLS_CERT_PATH=' "${SOC_PROJECT}/.env" | cut -d'=' -f2 | tr -d '"' | head -1)
        if [ -n "$ENV_PATH" ]; then
            CERT_PATH="$ENV_PATH"
            ok "Found TLS_CERT_PATH in .env: $CERT_PATH"
        fi
    # Method 3: Check docker-compose.yml for volume mounts
    elif [ -f "${SOC_PROJECT}/docker-compose.yml" ]; then
        # Look for cert volume patterns
        COMPOSE_PATH=$(grep -oP 'TLS_CERT_PATH[^}]*\K[^\s]+' "${SOC_PROJECT}/docker-compose.yml" 2>/dev/null | head -1)
        if [ -z "$COMPOSE_PATH" ]; then
            # Try alternative pattern
            COMPOSE_PATH=$(grep -oE '/[^:]+/certs' "${SOC_PROJECT}/docker-compose.yml" | head -1)
        fi
        if [ -n "$COMPOSE_PATH" ]; then
            CERT_PATH="$COMPOSE_PATH"
            ok "Found potential path in docker-compose.yml: $CERT_PATH"
        fi
    fi
    
    # If still not found, prompt user
    if [ -z "$CERT_PATH" ]; then
        warn "Could not auto-detect certificate path"
        echo
        echo "Common locations:"
        echo "  - ./soc-project/certs"
        echo "  - /opt/soc/certs"
        echo "  - /etc/docker/certs"
        echo
        read -rp "Enter certificate directory path: " CERT_PATH
    fi
fi

# Resolve to absolute path
CERT_PATH=$(cd "$(dirname "$CERT_PATH")" 2>/dev/null && pwd)/$(basename "$CERT_PATH") || true

# Validate path exists
if [ ! -d "$CERT_PATH" ]; then
    fail "Certificate directory does not exist: $CERT_PATH"
    exit 3
fi

info "Working with certificate directory: $CERT_PATH"
echo

# Check for required certificate files
info "Checking for certificate files..."
MISSING_FILES=false

for file in elasticsearch.key elasticsearch.crt ca.crt; do
    if [ ! -f "$CERT_PATH/$file" ]; then
        warn "Missing: $file"
        MISSING_FILES=true
    else
        ok "Found: $file"
    fi
done

# Also check for .pem variants
if [ "$MISSING_FILES" = true ]; then
    info "Checking for .pem variants..."
    for file in key.pem cert.pem ca.pem; do
        if [ -f "$CERT_PATH/$file" ]; then
            ok "Found: $file"
        fi
    done
fi

echo
info "Current permissions:"
ls -la "$CERT_PATH"
echo

# Confirm before making changes
if [ "$AUTO_CONFIRM" = false ]; then
    echo -e "${YELLOW}This will:${NC}"
    echo "  1. Change ownership to UID 1000:1000 (elasticsearch user)"
    echo "  2. Set directory permissions to 755"
    echo "  3. Set private key permissions to 640 (owner read-only)"
    echo "  4. Set certificate permissions to 644"
    echo
    read -rp "Proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Aborted by user"
        exit 0
    fi
fi

# Apply fixes
echo
info "Applying permission fixes..."

# Change ownership to UID 1000 (elasticsearch user in container)
if chown -R 1000:1000 "$CERT_PATH"; then
    ok "Changed ownership to 1000:1000"
else
    fail "Failed to change ownership"
    exit 1
fi

# Set directory permissions
if chmod 755 "$CERT_PATH"; then
    ok "Set directory permissions to 755"
else
    fail "Failed to set directory permissions"
    exit 1
fi

# Set file permissions
FIXED_COUNT=0

# Standard filenames
if [ -f "$CERT_PATH/elasticsearch.key" ]; then
    chmod 640 "$CERT_PATH/elasticsearch.key" && ok "elasticsearch.key: 640" && ((FIXED_COUNT++))
fi

if [ -f "$CERT_PATH/elasticsearch.crt" ]; then
    chmod 644 "$CERT_PATH/elasticsearch.crt" && ok "elasticsearch.crt: 644" && ((FIXED_COUNT++))
fi

if [ -f "$CERT_PATH/ca.crt" ]; then
    chmod 644 "$CERT_PATH/ca.crt" && ok "ca.crt: 644" && ((FIXED_COUNT++))
fi

# Alternative .pem filenames
if [ -f "$CERT_PATH/key.pem" ]; then
    chmod 640 "$CERT_PATH/key.pem" && ok "key.pem: 640" && ((FIXED_COUNT++))
fi

if [ -f "$CERT_PATH/cert.pem" ]; then
    chmod 644 "$CERT_PATH/cert.pem" && ok "cert.pem: 644" && ((FIXED_COUNT++))
fi

if [ -f "$CERT_PATH/ca.pem" ]; then
    chmod 644 "$CERT_PATH/ca.pem" && ok "ca.pem: 644" && ((FIXED_COUNT++))
fi

if [ $FIXED_COUNT -eq 0 ]; then
    warn "No certificate files were found to fix"
    exit 4
fi

echo
ok "Fixed $FIXED_COUNT certificate file(s)"
echo

# Show new permissions
info "New permissions:"
ls -la "$CERT_PATH"
echo

# Restart containers if requested
if [ "$NO_RESTART" = false ]; then
    echo
    info "Restarting containers..."
    
    cd "$SOC_PROJECT" || {
        fail "Could not change to project directory: $SOC_PROJECT"
        exit 1
    }
    
    # Check if using docker-compose or docker compose
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        COMPOSE_CMD="docker compose"
    fi
    
    info "Using: $COMPOSE_CMD"
    
    # Stop containers
    if $COMPOSE_CMD down; then
        ok "Stopped containers"
    else
        warn "Some containers may not have stopped cleanly"
    fi
    
    # Start containers
    if $COMPOSE_CMD up -d; then
        ok "Started containers"
    else
        fail "Failed to start containers"
        exit 1
    fi
    
    echo
    info "Waiting for Elasticsearch to initialize (30s)..."
    sleep 30
    
    # Check Elasticsearch status
    echo
    info "Checking Elasticsearch status..."
    
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "soc-elasticsearch.*Up"; then
        ok "Elasticsearch container is running"
        
        # Check logs for SSL-related errors
        SSL_ERROR=$(docker logs soc-elasticsearch --tail 50 2>&1 | grep -i "ssl\|tls\|permission denied" || true)
        if [ -n "$SSL_ERROR" ]; then
            warn "SSL/TLS errors still present in logs:"
            echo "$SSL_ERROR"
        else
            ok "No SSL/TLS errors detected in recent logs"
        fi
    else
        fail "Elasticsearch container is not running"
        warn "Check logs with: docker logs soc-elasticsearch"
    fi
fi

echo
ok "Certificate permission fix complete!"
echo
echo "Verification commands:"
echo "  docker logs soc-elasticsearch --tail 50"
echo "  docker exec soc-elasticsearch curl -sk https://localhost:9200 -u elastic:PASSWORD"
echo
