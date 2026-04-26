#!/bin/bash
# SOC Stack Setup Script
# Generates certificates and starts the stack

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== SOC Stack Setup ==="

# Generate certificates if they don't exist
if [ ! -f "certs/ca.crt" ] || [ ! -f "certs/elasticsearch.crt" ]; then
    echo "[1/3] Generating TLS certificates..."
    mkdir -p certs
    cd certs
    
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
        -extfile <(printf "subjectAltName=DNS:elasticsearch,DNS:localhost,IP:127.0.0.1") 2>/dev/null
    
    rm -f elasticsearch.csr ca.srl
    echo "  Certificates generated in certs/"
    cd ..
else
    echo "[1/3] Certificates already exist, skipping..."
fi

# Create network if needed
echo "[2/3] Creating Docker network..."
docker network create soc-net 2>/dev/null || echo "  Network already exists"

# Start the stack
echo "[3/3] Starting Docker Compose stack..."
docker-compose up -d

echo ""
echo "=== Setup Complete ==="
echo "Wait ~60s for services to be healthy, then access:"
echo "  Kibana:     http://localhost:5601"
echo "  Wazuh API:  http://localhost:55000"
