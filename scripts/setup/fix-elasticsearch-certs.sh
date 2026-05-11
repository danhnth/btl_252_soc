#!/usr/bin/env bash
# fix-elasticsearch-certs.sh
# Fixes SSL certificate and directory permissions for Elasticsearch Docker container
# Run this on the Linux VM/host if Elasticsearch fails with permission errors
#
# Usage: sudo bash scripts/setup/fix-elasticsearch-certs.sh [cert-path]
#        If cert-path is omitted, attempts to auto-detect from .env or docker-compose.yml
#
# Fixes:
#   - Certificate permissions (UID 1000:1000, 640 for keys, 644 for certs)
#   - Logs directory permissions (UID 1000:1000, 755)
#   - Data directory permissions (UID 1000:1000, 755)

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

# Helper function to fix directory permissions
fix_directory_permissions() {
    local dir_path="$1"
    local dir_name="$2"
    
    if [ ! -d "$dir_path" ]; then
        warn "$dir_name directory does not exist: $dir_path"
        return 1
    fi
    
    info "Fixing $dir_name directory: $dir_path"
    
    if chown -R 1000:1000 "$dir_path"; then
        ok "Changed ownership to 1000:1000"
    else
        fail "Failed to change ownership for $dir_name"
        return 1
    fi
    
    if chmod 755 "$dir_path"; then
        ok "Set permissions to 755"
    else
        fail "Failed to set permissions for $dir_name"
        return 1
    fi
    
    return 0
}

show_help() {
    cat << EOF
Usage: sudo $(basename "$0") [OPTIONS] [CERT-PATH]

Fix Elasticsearch SSL certificate and directory permissions for Docker deployment.

Fixes:
  - Certificate files: UID 1000:1000, keys 640, certs 644
  - Logs directory: UID 1000:1000, 755
  - Data directory: UID 1000:1000, 755

OPTIONS:
    -h, --help          Show this help message
    -n, --no-restart    Don't restart containers after fixing permissions
    -y, --yes           Auto-confirm all prompts

CERT-PATH:
    Path to certificate directory. If not provided, attempts to detect from:
    1. TLS_CERT_PATH environment variable
    2. soc-project/.env file
    3. soc-project/docker-compose.yml

EXAMPLES:
    sudo $(basename "$0")                           # Auto-detect and fix all
    sudo $(basename "$0") /opt/soc/certs            # Use specific cert path
    sudo $(basename "$0") -n                        # Fix only, don't restart
    sudo $(basename "$0") -y                        # Auto-confirm all prompts

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

# Preserve CERT_PATH if provided via command line
CERT_PATH_FROM_CLI="${CERT_PATH:-}"

# Auto-detect paths from .env
LOGS_PATH=""
DATA_PATH=""

if [ -f "${SOC_PROJECT}/.env" ]; then
    info "Loading paths from .env..."
    
    TLS_CERT_PATH_FROM_ENV=$(grep -E '^TLS_CERT_PATH=' "${SOC_PROJECT}/.env" | cut -d'=' -f2 | tr -d '"' | head -1)
    LOGS_PATH=$(grep -E '^LOGS_PATH=' "${SOC_PROJECT}/.env" | cut -d'=' -f2 | tr -d '"' | head -1)
    DATA_PATH=$(grep -E '^DATA_PATH=' "${SOC_PROJECT}/.env" | cut -d'=' -f2 | tr -d '"' | head -1)
    
    # Use CLI-provided cert path if available, otherwise use .env
    if [ -n "$CERT_PATH_FROM_CLI" ]; then
        CERT_PATH="$CERT_PATH_FROM_CLI"
        ok "Using command-line cert path: $CERT_PATH"
    elif [ -n "$TLS_CERT_PATH_FROM_ENV" ]; then
        # Convert relative paths to absolute paths (relative to SOC_PROJECT)
        if [[ "$TLS_CERT_PATH_FROM_ENV" == ./* ]]; then
            CERT_PATH="${SOC_PROJECT}/${TLS_CERT_PATH_FROM_ENV#./}"
        elif [[ "$TLS_CERT_PATH_FROM_ENV" == /* ]]; then
            CERT_PATH="$TLS_CERT_PATH_FROM_ENV"
        else
            CERT_PATH="${SOC_PROJECT}/${TLS_CERT_PATH_FROM_ENV}"
        fi
        ok "Found TLS_CERT_PATH in .env: $CERT_PATH"
    fi
    
    # Convert LOGS_PATH to absolute
    if [ -n "$LOGS_PATH" ]; then
        if [[ "$LOGS_PATH" == ./* ]]; then
            LOGS_PATH="${SOC_PROJECT}/${LOGS_PATH#./}"
        elif [[ "$LOGS_PATH" != /* ]]; then
            LOGS_PATH="${SOC_PROJECT}/${LOGS_PATH}"
        fi
        ok "Found LOGS_PATH: $LOGS_PATH"
    fi
    
    # Convert DATA_PATH to absolute
    if [ -n "$DATA_PATH" ]; then
        if [[ "$DATA_PATH" == ./* ]]; then
            DATA_PATH="${SOC_PROJECT}/${DATA_PATH#./}"
        elif [[ "$DATA_PATH" != /* ]]; then
            DATA_PATH="${SOC_PROJECT}/${DATA_PATH}"
        fi
        ok "Found DATA_PATH: $DATA_PATH"
    fi
fi

# Validate cert path
if [ -z "$CERT_PATH" ]; then
    fail "Could not determine certificate path"
    echo
    echo "Please provide the path to the certificate directory:"
    echo "  sudo $0 /path/to/certs"
    echo
    echo "Or set TLS_CERT_PATH in ${SOC_PROJECT}/.env"
    exit 3
fi

# Resolve to absolute path if relative
if [[ "$CERT_PATH" == ./* ]]; then
    CERT_PATH="${SOC_PROJECT}/${CERT_PATH#./}"
fi

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
    echo "  1. Change certificate ownership to UID 1000:1000"
    echo "  2. Set certificate directory permissions to 755"
    echo "  3. Set private key permissions to 640 (owner read-only)"
    echo "  4. Set certificate permissions to 644"
    if [ -n "$LOGS_PATH" ]; then
        echo "  5. Fix logs directory permissions: $LOGS_PATH/elasticsearch"
    fi
    if [ -n "$DATA_PATH" ]; then
        echo "  6. Fix data directory permissions: $DATA_PATH/elasticsearch"
    fi
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

# Fix logs and data directories
echo
info "Fixing Elasticsearch directories..."

# Fix logs directory
if [ -n "$LOGS_PATH" ]; then
    ES_LOGS="$LOGS_PATH/elasticsearch"
    info "Setting up Elasticsearch logs directory: $ES_LOGS"
    
    # Create parent directory if needed
    if [ ! -d "$LOGS_PATH" ]; then
        info "Creating logs parent directory: $LOGS_PATH"
        mkdir -p "$LOGS_PATH"
        chown 1000:1000 "$LOGS_PATH"
        chmod 755 "$LOGS_PATH"
        ok "Created and fixed permissions for $LOGS_PATH"
    fi
    
    # Create elasticsearch subdirectory
    if [ ! -d "$ES_LOGS" ]; then
        info "Creating Elasticsearch logs directory: $ES_LOGS"
        mkdir -p "$ES_LOGS"
    fi
    
    fix_directory_permissions "$ES_LOGS" "Elasticsearch logs" || true
fi

# Fix data directory  
if [ -n "$DATA_PATH" ]; then
    ES_DATA="$DATA_PATH/elasticsearch"
    info "Setting up Elasticsearch data directory: $ES_DATA"
    
    # Create parent directory if needed
    if [ ! -d "$DATA_PATH" ]; then
        info "Creating data parent directory: $DATA_PATH"
        mkdir -p "$DATA_PATH"
        chown 1000:1000 "$DATA_PATH"
        chmod 755 "$DATA_PATH"
        ok "Created and fixed permissions for $DATA_PATH"
    fi
    
    # Create elasticsearch subdirectory
    if [ ! -d "$ES_DATA" ]; then
        info "Creating Elasticsearch data directory: $ES_DATA"
        mkdir -p "$ES_DATA"
    fi
    
    fix_directory_permissions "$ES_DATA" "Elasticsearch data" || true
fi

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
