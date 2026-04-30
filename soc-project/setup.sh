#!/bin/bash
# SOC Stack Setup Script
# Generates certificates and starts the stack

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== SOC Stack Setup ==="

# Ensure .env exists
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo "[0/4] Creating .env from .env.example..."
        cp .env.example .env
        echo "  Created .env — review and change passwords before production use"
    else
        echo "ERROR: .env.example not found. Cannot continue."
        exit 1
    fi
else
    echo "[0/4] .env already exists, skipping..."
fi

# Generate certificates if they don't exist
if [ ! -f "certs/ca.crt" ] || [ ! -f "certs/elasticsearch.crt" ]; then
    echo "[1/4] Generating TLS certificates..."
    mkdir -p certs
    cd certs

    # Write SAN config to a file (avoids process substitution which
    # breaks on Git Bash for Windows and other non-bash shells)
    cat > _san_ext.cnf <<EOF
subjectAltName=DNS:elasticsearch,DNS:localhost,IP:127.0.0.1
EOF

    # Generate CA
    openssl genrsa -out ca.key 4096 2>/dev/null
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 825 \
        -out ca.crt -subj "/C=US/ST=CA/L=SF/O=SOC/CN=soc-ca" 2>/dev/null

    # Generate Elasticsearch cert
    openssl genrsa -out elasticsearch.key 4096 2>/dev/null
    openssl req -new -key elasticsearch.key -out elasticsearch.csr \
        -subj "/C=US/ST=CA/L=SF/O=SOC/CN=elasticsearch" 2>/dev/null
    openssl x509 -req -in elasticsearch.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
        -out elasticsearch.crt -days 825 -sha256 \
        -extfile _san_ext.cnf 2>/dev/null

    rm -f elasticsearch.csr ca.srl _san_ext.cnf
    echo "  Certificates generated in certs/"
    cd ..
else
    echo "[1/4] Certificates already exist, skipping..."
fi

# Create network if needed
echo "[2/4] Creating Docker network..."
docker network create soc-net 2>/dev/null || echo "  Network already exists"

# Start the stack
echo "[3/4] Starting Docker Compose stack..."
docker-compose up -d

echo ""
echo "=== Setup Complete ==="
echo "Wait ~60s for services to be healthy, then access:"
echo "  Kibana:     http://localhost:5601"
echo "  Wazuh API:  http://localhost:55000"
