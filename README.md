# Security Operations Center (SOC)

🌐 **Languages:** [English](README.md) | [Tiếng Việt](README-vi.md)

Open-source SOC stack using Suricata IDS, Elasticsearch, Kibana, Wazuh SIEM, and Filebeat - fully containerised with Docker Compose.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Installation](#installation)
  - [Windows](#windows-docker-desktop)
  - [Linux](#linux-docker-engine)
- [Configuration](#configuration)
- [Usage](#usage)
- [Scripts Reference](#scripts-reference)
- [Attack Scenarios & Testing](#attack-scenarios--testing)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)

---

## Overview

| Component | Role |
|---|---|
| **Suricata** | Network IDS — 31 800+ ET rules |
| **Elasticsearch** | Log storage & search |
| **Kibana** | Dashboards & visualisation |
| **Wazuh** | Host-based SIEM |
| **Filebeat** | Log shipper |
| **Signature Service** | HMAC/RSA log-integrity verification |

---

## Architecture

```
Suricata (IDS) ──► eve.json ──►┐
                               Filebeat ──► Elasticsearch ──► Kibana
Wazuh (SIEM)  ──► alerts  ──►┘
                               Signature Service (HMAC integrity)
```

All services communicate over the `soc-net` Docker bridge network with TLS 1.3.

---

## Requirements

| | Minimum | Recommended |
|---|---|---|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Disk | 50 GB | 100 GB SSD |

**Software:**
- Docker Desktop (Windows) or Docker Engine (Linux)
- Git Bash or WSL 2 (Windows only)

---

## Quick Start

```bash
cd soc-project
bash setup.sh
```

The `setup.sh` script will:
1. Create `.env` from `.env.example` (if missing)
2. Generate TLS certificates for Elasticsearch
3. Create the Docker network
4. Start all services
5. Bootstrap Kibana credentials automatically

Wait ~60 seconds, then access Kibana at http://localhost:5601

---

## Installation

### Windows (Docker Desktop)

#### Prerequisites

1. **Install Docker Desktop**
   - Download from <https://www.docker.com/products/docker-desktop/>
   - During install, enable the **WSL 2 backend** (recommended)
   - After install, open Docker Desktop and wait for the engine to start

2. **Set Docker memory to at least 8 GB**
   Docker Desktop → Settings → Resources → Memory → `8 GB`

3. **Install Git Bash** (for running `.sh` scripts)
   - Comes with [Git for Windows](https://git-scm.com/download/win)
   - Or use WSL 2 terminal

#### Setup

Open **Git Bash** or **WSL 2** terminal:

```bash
# 1. Navigate to the project
cd /c/path/to/btl_252_soc

# 2. Run the automated setup
bash soc-project/setup.sh
```

The setup script handles everything automatically:
- Creates `.env` from template
- Generates TLS certificates
- Creates Docker network
- Starts the stack
- Bootstraps Kibana credentials

Wait ~60 seconds after setup completes, then access:
- **Kibana**: http://localhost:5601 (elastic / password from `.env`)

#### Running scripts on Windows

All scripts require a bash shell. Use either:

- **Git Bash** — right-click folder → *Git Bash Here*
- **WSL 2** terminal

```bash
# From project root
bash scripts/setup/check-stack.sh      # Health check
bash scripts/attacks/generate-alerts.sh # Generate test alerts
bash scripts/tests/verify-stack.sh      # Smoke test
```

---

### Linux (Docker Engine)

#### Prerequisites

**Ubuntu / Debian:**
```bash
# Remove old versions
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Run Docker without sudo
sudo usermod -aG docker $USER && newgrp docker
```

**RHEL / Rocky / AlmaLinux:**
```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER && newgrp docker
```

**Required kernel tuning** (Elasticsearch needs this):
```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

#### Setup

```bash
# 1. Navigate to project
cd /path/to/btl_252_soc

# 2. Fix directory ownership
sudo chown -R $USER:$USER soc-project/data/ soc-project/logs/ 2>/dev/null || true

# 3. Run automated setup
bash soc-project/setup.sh
```

Wait ~60 seconds after setup completes, then access:
- **Kibana**: http://localhost:5601

#### Running scripts

```bash
chmod +x scripts/setup/*.sh scripts/attacks/*.sh scripts/tests/*.sh

bash scripts/setup/check-stack.sh
bash scripts/attacks/generate-alerts.sh
bash scripts/tests/verify-stack.sh
```

---

## Configuration

Edit `soc-project/.env`.  
**Never commit this file** — it contains secrets.

| Variable | Default | Description |
|---|---|---|
| `ELASTICSEARCH_PASSWORD` | `changeme123` | Elastic superuser password |
| `KIBANA_SYSTEM_PASSWORD` | `changeme123` | Kibana internal user |
| `WAZUH_ADMIN_PASSWORD` | `ChangeMeWazuh123#` | Wazuh API admin password |
| `KIBANA_ENCRYPTION_KEY` | *(random string)* | Encryption key for saved objects |
| `HMAC_SECRET` | `soc-hmac-secret-key-2024-production-change-me` | Signature service HMAC secret |
| `ES_JAVA_OPTS` | `-Xms512m -Xmx512m` | Elasticsearch JVM heap |
| `ELASTIC_VERSION` | `8.12.0` | ELK Stack version |

**Memory tuning:**
```env
ES_JAVA_OPTS=-Xms1g -Xmx1g   # 8 GB system
ES_JAVA_OPTS=-Xms2g -Xmx2g   # 16 GB system
ES_JAVA_OPTS=-Xms4g -Xmx4g   # 32 GB system
```

---

## Usage

### Service URLs

| Service | URL | Credentials |
|---|---|---|
| Kibana | <http://localhost:5601> | `elastic` / `ELASTICSEARCH_PASSWORD` |
| Elasticsearch | <https://localhost:9200> | `elastic` / `ELASTICSEARCH_PASSWORD` |
| Wazuh API | <https://localhost:55000> | `admin` / `WAZUH_ADMIN_PASSWORD` |
| Signature Service | <http://localhost:5000/health> | — |

### First-time Kibana setup

```bash
# Automated — creates all data views:
bash scripts/setup/setup-kibana.sh
```

Or manually in the Kibana UI:  
☰ → **Stack Management** → **Data Views** → **Create data view**

| Data View | Index pattern | Time field |
|---|---|---|
| Suricata IDS | `suricata-ids-*` | `@timestamp` |
| Wazuh Alerts | `wazuh-alerts-*` | `@timestamp` |
| Filebeat Logs | `filebeat-*` | `@timestamp` |

### Viewing alerts

1. Open Kibana → ☰ → **Analytics** → **Discover**
2. Select index pattern `suricata-ids-*`
3. Filter: `event_type : alert`

### Common operations

```bash
# Start all services
cd soc-project && docker-compose up -d

# Stop all services
docker-compose stop

# Restart a specific service
docker-compose restart kibana

# Tail logs
docker-compose logs -f filebeat

# Full reset (⚠ deletes all data)
docker-compose down -v
rm -rf soc-project/data/ soc-project/logs/
bash soc-project/setup.sh
```

---

## Scripts Reference

All scripts are in `scripts/` at the project root.

```
scripts/
├── setup/
│   ├── setup-kibana.sh              # Create Kibana data views
│   ├── check-stack.sh               # Colorful health summary
│   └── fix-elasticsearch-certs.sh   # Fix SSL certificate permissions
├── attacks/
│   ├── generate-alerts.sh           # Generate IDS alerts with colored output
│   └── attack-scenarios.py          # Python attack simulator (10 scenarios)
└── tests/
    └── verify-stack.sh              # Smoke test — exits 0 on pass
```

### `soc-project/setup.sh`

**One-command setup** — generates certificates, creates network, starts stack, bootstraps Kibana.

```bash
cd soc-project
bash setup.sh
```

### `scripts/setup/setup-kibana.sh`

Creates Kibana data views. Run once after the stack starts.

```bash
bash scripts/setup/setup-kibana.sh
```

### `scripts/setup/check-stack.sh`

Colorful health summary showing:
- Container status with health indicators
- Elasticsearch cluster health
- Suricata alert count
- Top 5 alert signatures
- Index health

```bash
bash scripts/setup/check-stack.sh
```

### `scripts/setup/fix-elasticsearch-certs.sh`

Fixes SSL certificate permission errors:
```
SslConfigException: not permitted to read the PEM private key file
```

```bash
# Auto-detect and fix
sudo bash scripts/setup/fix-elasticsearch-certs.sh

# Specify path manually
sudo bash scripts/setup/fix-elasticsearch-certs.sh /path/to/certs
```

### `scripts/attacks/generate-alerts.sh`

Generates IDS alerts with **colored output** and progress indicators.

```bash
bash scripts/attacks/generate-alerts.sh           # Full suite (~6 scenarios)
bash scripts/attacks/generate-alerts.sh --quick   # Fast scenarios only
```

Scenarios include:
- IDS Detection Test (GPL ATTACK_RESPONSE)
- Malware Download Simulation (ET MALWARE)
- Security Scanner Detection (sqlmap, Nikto, Nmap)
- Known-Bad Domain Lookup
- Policy Violations
- Burst traffic

### `scripts/attacks/attack-scenarios.py`

Fine-grained Python attack simulator with 10 scenarios.

```bash
# List all scenarios
python3 scripts/attacks/attack-scenarios.py --list

# Run one scenario
python3 scripts/attacks/attack-scenarios.py --scenario sqlmap

# Run all, 3 times each
python3 scripts/attacks/attack-scenarios.py --count 3

# Run from inside Suricata (recommended)
docker cp scripts/attacks/attack-scenarios.py soc-suricata:/tmp/
docker exec soc-suricata python3 /tmp/attack-scenarios.py
```

Available scenarios: `ids-test`, `sqlmap`, `nikto`, `nmap`, `malware-dl`, `sql-injection`, `xss`, `path-traversal`, `policy-curl`, `burst`

### `scripts/tests/verify-stack.sh`

End-to-end smoke test. Checks all services and exits `0` on pass.

```bash
bash scripts/tests/verify-stack.sh
```

---

## Attack Scenarios & Testing

### Why traffic must originate from inside Suricata

Docker bridge networking gives each container its own network namespace. Suricata only sees packets on its own `eth0` — **not** traffic between other containers on the same bridge.

**Solution**: generate outbound HTTP requests **from inside** the Suricata container. The packets traverse `eth0`, Suricata inspects them in real time, and alerts are written to `eve.json`, shipped by Filebeat to Elasticsearch.

### Quick demo walkthrough

```bash
# 1. Start the stack
cd soc-project
bash setup.sh

# 2. Wait ~60s for initialization, then verify
bash ../scripts/setup/check-stack.sh

# 3. Set up Kibana data views
bash ../scripts/setup/setup-kibana.sh

# 4. Generate diverse alerts
bash ../scripts/attacks/generate-alerts.sh

# 5. Run smoke test
bash ../scripts/tests/verify-stack.sh

# 6. Check alert summary
bash ../scripts/setup/check-stack.sh

# 7. Open Kibana → Discover → suricata-ids-*
```

### Alert severity levels

| Severity | Level | Examples |
|---|---|---|
| 1 | Critical | Known malware C2, exploit kits |
| 2 | High | Scanner detection, attack responses |
| 3 | Medium | Policy violations, suspicious user-agents |

---

## Troubleshooting

### Elasticsearch fails to start (exit code 137 / OOM)

Reduce JVM heap or increase Docker memory:
```env
# soc-project/.env
ES_JAVA_OPTS=-Xms512m -Xmx512m
```

### Elasticsearch fails to start — SSL permission error

If you see:
```
org.elasticsearch.common.ssl.SslConfigException: not permitted to read the PEM private key file
```

The certificate files have incorrect ownership. Fix with:
```bash
sudo bash scripts/setup/fix-elasticsearch-certs.sh
```

### Linux: `max virtual memory areas too low`

```bash
sudo sysctl -w vm.max_map_count=262144
```

### Kibana stays unhealthy — "unable to authenticate kibana_system"

Run the bootstrap step manually:

```bash
cd soc-project
source .env

docker exec soc-elasticsearch curl -sk -X POST \
  -u "elastic:${ELASTICSEARCH_PASSWORD}" \
  "https://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${KIBANA_SYSTEM_PASSWORD}\"}"

docker-compose restart kibana
```

### Kibana shows "server is not ready yet"

Wait 3–5 minutes. If it persists:
```bash
docker-compose restart kibana
docker-compose logs kibana | tail -30
```

### Filebeat restarting in a loop

```bash
docker-compose logs filebeat | tail -20
```

Check TLS cert path and ES connectivity:
```bash
cd soc-project && source .env
docker exec soc-elasticsearch curl -sk -u "elastic:${ELASTICSEARCH_PASSWORD}" https://localhost:9200
```

### No alerts appearing in Kibana

```bash
# 1. Generate test traffic
bash scripts/attacks/generate-alerts.sh

# 2. Check eve.json
docker exec soc-suricata sh -c "grep '\"event_type\":\"alert\"' /var/log/suricata/eve.json | wc -l"

# 3. Check Filebeat is publishing
docker-compose logs filebeat | grep -i "Events published"
```

### Port already in use

```bash
# Windows (PowerShell)
netstat -ano | findstr :5601

# Linux
sudo lsof -i :5601
```

Change the port in `docker-compose.yml` if needed:
```yaml
ports:
  - "5602:5601"   # host:container
```

### Full reset

```bash
cd soc-project
docker-compose down -v
rm -rf data/ logs/
docker network rm soc-net
bash setup.sh
```

---

## Project Structure

```
btl_252_soc/
├── README.md                        # This file
├── README-vi.md                     # Vietnamese version
├── assignment.md                    # Original assignment (Vietnamese)
│
├── docs/
│   ├── Architecture-Diagram.md      # Detailed system architecture
│   ├── SOC-Concept.md               # SOC theory and fundamentals
│   └── Tool-Comparison.md           # Why these tools were chosen
│
├── scripts/
│   ├── setup/
│   │   ├── setup-kibana.sh          # Create Kibana data views
│   │   ├── check-stack.sh           # Health summary with colors
│   │   └── fix-elasticsearch-certs.sh  # SSL permission fix
│   ├── attacks/
│   │   ├── generate-alerts.sh       # Shell-based alert generator
│   │   └── attack-scenarios.py      # Python attack simulator
│   └── tests/
│       └── verify-stack.sh          # Smoke test suite
│
└── soc-project/                     # Docker deployment root
    ├── setup.sh                     # ⭐ One-command automated setup
    ├── docker-compose.yml
    ├── .env                         # Secrets — never commit
    ├── .env.example                 # Template for .env
    ├── certs/                       # TLS certificates (auto-generated)
    ├── elk/config/                  # Filebeat & Kibana config
    ├── suricata/conf/               # Suricata config & 31k+ rules
    ├── wazuh/conf/                  # Wazuh SIEM config
    ├── signature-service/           # Log integrity service
    └── config/                      # OpenSearch dashboard config
```

---

## Known Limitations

**Docker bridge networking** — Suricata cannot passively monitor inter-container traffic. This is a Docker architecture constraint. The `generate-alerts.sh` script works around it by generating traffic from inside the Suricata container.

In production, deploy Suricata with a network TAP, SPAN port, or host-network mode (Linux only).

**Wazuh Dashboard** — The Wazuh Dashboard (port 443) may show as unhealthy due to a version mismatch with Elasticsearch 8.x. Use Kibana on port 5601 instead — it displays all Wazuh data with full functionality.

---

## Support

- 🇻🇳 [Xem bản tiếng Việt](README-vi.md)
- 📁 [Project documentation](docs/)
- 🐛 [Open an issue](../../issues)

---

*Last updated: May 2026*
