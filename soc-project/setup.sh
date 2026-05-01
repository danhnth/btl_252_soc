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

# Load only the values needed for the bootstrap step.
get_env_value() {
    grep -E "^$1=" .env | head -n 1 | cut -d= -f2-
}

ELASTICSEARCH_PASSWORD="$(get_env_value ELASTICSEARCH_PASSWORD)"
KIBANA_SYSTEM_PASSWORD="$(get_env_value KIBANA_SYSTEM_PASSWORD)"

# Generate certificates if they don't exist
if [ ! -f "certs/ca.crt" ] || [ ! -f "certs/elasticsearch.crt" ]; then
    echo "[1/4] Generating TLS certificates..."
    mkdir -p certs
    cd certs

    # Create OpenSSL config for v3 extensions (required for ES 8.x)
    cat > cert_ext.cnf <<EOF
[req]
distinguished_name = dn
prompt = no

[dn]
C = US
ST = CA
L = SF
O = SOC
CN = elasticsearch

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, cRLSign, keyCertSign

[v3_server]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = elasticsearch
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

    # Generate CA
    openssl genrsa -out ca.key 4096
    MSYS2_ARG_CONV_EXCL='*' openssl req -x509 -new -nodes -key ca.key -sha256 -days 825 \
        -out ca.crt -config cert_ext.cnf -extensions v3_ca \
        -subj "/C=US/ST=CA/L=SF/O=SOC/CN=soc-ca"

    # Generate Elasticsearch cert
    openssl genrsa -out elasticsearch.key 4096
    openssl req -new -key elasticsearch.key -out elasticsearch.csr \
        -config cert_ext.cnf
    openssl x509 -req -in elasticsearch.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
        -out elasticsearch.crt -days 825 -sha256 \
        -extfile cert_ext.cnf -extensions v3_server

    rm -f elasticsearch.csr ca.srl
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
if command -v timeout >/dev/null 2>&1; then
    if timeout 60s docker-compose up -d; then
        echo "  Docker Compose finished starting."
    else
        compose_exit_code=$?
        if [ "$compose_exit_code" -eq 124 ]; then
            echo "  Docker Compose is still starting in the background."
        else
            echo "  Docker Compose returned $compose_exit_code; continuing with Kibana bootstrap."
        fi
    fi
else
    if docker-compose up -d; then
        echo "  Docker Compose finished starting."
    else
        echo "  Docker Compose returned a non-zero status; continuing with Kibana bootstrap."
    fi
fi

# Bootstrap Kibana's internal password once Elasticsearch is up.
echo "[4/4] Bootstrapping Kibana credentials..."
for attempt in $(seq 1 30); do
    if docker exec soc-elasticsearch curl -sk -u "elastic:${ELASTICSEARCH_PASSWORD}" \
        "https://localhost:9200/_cluster/health" >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

docker exec -i soc-elasticsearch curl -sk -X POST \
  -u "elastic:${ELASTICSEARCH_PASSWORD}" \
  "https://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  --data-binary @- <<EOF
{"password":"${KIBANA_SYSTEM_PASSWORD}"}
EOF

docker-compose restart kibana >/dev/null

echo ""
echo "=== Setup Complete ==="
echo "Wait ~60s for services to be healthy, then access:"
echo "  Kibana:     http://localhost:5601"
echo "  Wazuh API:  http://localhost:55000"
