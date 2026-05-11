# Security Operations Center (SOC)

Open-source SOC stack using Suricata IDS, Elasticsearch, Kibana, Wazuh SIEM, and Filebeat — fully containerised with Docker Compose.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Windows](#windows-docker-desktop)
  - [macOS](#macos-docker-desktop)
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

---

## Installation

### Windows (Docker Desktop)

#### Prerequisites

1. **Install Docker Desktop**
   - Download from <https://www.docker.com/products/docker-desktop/>
   - During install, enable the **WSL 2 backend** (recommended) or **Hyper-V**
   - After install, open Docker Desktop and wait for the engine to start (whale icon in taskbar turns steady)

2. **Set Docker memory to at least 8 GB**
   Docker Desktop → Settings → Resources → Memory → `8 GB`

3. **Enable WSL 2 integration** (if using WSL 2 backend)
   Docker Desktop → Settings → Resources → WSL Integration → enable your distro

#### Setup

Open **PowerShell** or **Windows Terminal**:

```powershell
# 1. Navigate to the project
cd C:\path\to\btl_252_soc\soc-project

# 2. Create Docker network
docker network create soc-net

# 3. Copy and edit the environment file
Copy-Item .env.example .env
notepad .env       # change all passwords

# 4. Start all services
docker-compose up -d

# 5. Wait ~3 minutes, then check status
docker-compose ps
```

**⚠️ Required bootstrap step (first-time only):** Once Elasticsearch is `healthy`, set the Kibana internal user password:

```powershell
# Replace the password value with whatever ELASTICSEARCH_PASSWORD you set in .env
docker exec soc-elasticsearch curl -sk -X POST `
  -u "elastic:changeme123" `
  "https://localhost:9200/_security/user/kibana_system/_password" `
  -H "Content-Type: application/json" `
  -d '{\"password\":\"changeme123"}'
```

Then restart Kibana so it picks up the new credentials:

```powershell
docker-compose restart kibana
```

Wait ~90 seconds for Kibana to become ready, then access it at <http://localhost:5601>

#### Running scripts on Windows

The `.sh` scripts require a bash shell. Use either:

- **Git Bash** (comes with Git for Windows) — right-click folder → *Git Bash Here*
- **WSL 2** terminal

```bash
# Git Bash or WSL:
bash scripts/setup/check-stack.sh
bash scripts/attacks/generate-alerts.sh
bash scripts/tests/verify-stack.sh
```

---

### macOS (Docker Desktop)

#### Prerequisites

1. **Install Docker Desktop**
   - Intel Mac or Apple Silicon: <https://docs.docker.com/desktop/install/mac-install/>
   - Open Docker Desktop and wait for it to finish initialising

2. **Set Docker memory to at least 8 GB**
   Docker Desktop → Settings → Resources → Memory → `8 GB`

#### Setup

Open **Terminal**:

```bash
# 1. Navigate to project
cd /path/to/btl_252_soc/soc-project

# 2. Create Docker network
docker network create soc-net

# 3. Copy and edit environment file
cp .env.example .env
nano .env    # or: open -e .env

# 4. Start all services
docker-compose up -d

# 5. Wait ~3 minutes, then check status
docker-compose ps
```

**⚠️ Required bootstrap step (first-time only):** Once Elasticsearch is `healthy`, set the Kibana internal user password:

```bash
docker exec soc-elasticsearch curl -sk -X POST \
  -u "elastic:ChangeMeElastic123!@#" \
  "https://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d '{"password":"ChangeMeKibanaSystem123!@#"}'
```

Then restart Kibana so it picks up the new credentials:

```bash
docker-compose restart kibana
```

Wait ~90 seconds for Kibana to become ready, then access it at <http://localhost:5601>

#### Running scripts

```bash
bash scripts/setup/setup-kibana.sh
bash scripts/setup/check-stack.sh
bash scripts/attacks/generate-alerts.sh
bash scripts/tests/verify-stack.sh
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
cd /path/to/btl_252_soc/soc-project

# 2. Fix directory ownership
sudo chown -R $USER:$USER data/ logs/ 2>/dev/null || true

# 3. Create Docker network
docker network create soc-net

# 4. Copy and edit environment file
cp .env.example .env
nano .env

# 5. Start all services (Docker Compose v2 uses 'docker compose', no hyphen)
docker compose up -d

# 6. Check status
docker compose ps
```

**⚠️ Required bootstrap step (first-time only):** Once Elasticsearch is `healthy`, set the Kibana internal user password:

```bash
docker exec soc-elasticsearch curl -sk -X POST \
  -u "elastic:ChangeMeElastic123!@#" \
  "https://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d '{"password":"ChangeMeKibanaSystem123!@#"}'
```

Then restart Kibana so it picks up the new credentials:

```bash
docker compose restart kibana
```

Wait ~90 seconds for Kibana to become ready, then access it at <http://localhost:5601>

#### Running scripts

```bash
chmod +x scripts/setup/*.sh scripts/attacks/*.sh scripts/tests/*.sh

bash scripts/setup/setup-kibana.sh
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
| `ELASTICSEARCH_PASSWORD` | `ChangeMeElastic123!@#` | Elastic superuser password |
| `KIBANA_SYSTEM_PASSWORD` | `ChangeMeKibanaSystem123!@#` | Kibana internal user |
| `WAZUH_ADMIN_PASSWORD` | `ChangeMeWazuh456!@#` | Wazuh API admin password |
| `KIBANA_ENCRYPTION_KEY` | *(random string)* | Encryption key for saved objects |
| `HMAC_SECRET` | `soc-hmac-secret-key-2024` | Signature service HMAC secret |
| `ES_JAVA_OPTS` | `-Xms1g -Xmx1g` | Elasticsearch JVM heap |
| `ELASTIC_VERSION` | `8.12.0` | ELK Stack version |

**Memory tuning:**
```env
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
docker-compose up -d

# Stop all services
docker-compose stop

# Restart a specific service
docker-compose restart kibana

# Tail logs
docker-compose logs -f filebeat

# Full reset (⚠ deletes all data)
docker-compose down -v
rm -rf soc-project/data/ soc-project/logs/
docker-compose up -d
```

---

## Scripts Reference

All scripts are in `scripts/` at the project root.

```
scripts/
├── setup/
│   ├── setup-kibana.sh              # Create Kibana data views (run once after stack start)
│   ├── check-stack.sh               # Print health summary of all services
│   └── fix-elasticsearch-certs.sh   # Fix SSL certificate permission errors
├── attacks/
│   ├── generate-alerts.sh   # Fire attack traffic from inside Suricata (shell)
│   └── attack-scenarios.py  # Python attack simulator with scenario selection
└── tests/
    └── verify-stack.sh      # Smoke test — exits non-zero on failure
```

### `scripts/setup/setup-kibana.sh`

Creates Kibana data views. Run once after the stack starts.

```bash
bash scripts/setup/setup-kibana.sh
```

### `scripts/setup/check-stack.sh`

Prints a health summary: container states, cluster health, alert counts, index status.

```bash
bash scripts/setup/check-stack.sh
```

### `scripts/setup/fix-elasticsearch-certs.sh`

Fixes SSL certificate permission errors when Elasticsearch fails to start with:
```
SslConfigException: not permitted to read the PEM private key file
```

Auto-detects certificate path from `.env` or `docker-compose.yml`.

```bash
# Auto-detect and fix
sudo bash scripts/setup/fix-elasticsearch-certs.sh

# Specify path manually
sudo bash scripts/setup/fix-elasticsearch-certs.sh /path/to/certs

# Fix only, don't restart containers
sudo bash scripts/setup/fix-elasticsearch-certs.sh -n /path/to/certs
```

### `scripts/attacks/generate-alerts.sh`

Generates IDS alert traffic by making outbound HTTP requests from inside the Suricata container. Waits 15 s then prints total alert count.

```bash
bash scripts/attacks/generate-alerts.sh           # full suite (~6 scenarios)
bash scripts/attacks/generate-alerts.sh --quick   # 2 fast scenarios only
```

### `scripts/attacks/attack-scenarios.py`

Fine-grained Python attack simulator. Can be run on the host or copied into the Suricata container for reliable detection.

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

End-to-end smoke test. Checks containers, Elasticsearch, Kibana, Suricata, Filebeat, Wazuh, and Signature Service. Exits `0` on pass.

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
docker-compose up -d

# 2. Wait ~3 minutes for initialisation
docker-compose ps

# 3. Set up Kibana data views
bash ../scripts/setup/setup-kibana.sh

# 4. Generate diverse alerts
bash ../scripts/attacks/generate-alerts.sh

# 5. Smoke test
bash ../scripts/tests/verify-stack.sh

# 6. Open Kibana → Discover → suricata-ids-*
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

This happens on a fresh install because the `kibana_system` password must be explicitly set via the Elasticsearch API. Run the bootstrap step from the Installation section:

```bash
docker exec soc-elasticsearch curl -sk -X POST \
  -u "elastic:changeme123" \
  "https://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d '{"password":"changeme123"}'
```

Then: `docker-compose restart kibana` (or `docker compose restart kibana` on Linux).

### Kibana shows "server is not ready yet"

Wait 3–5 minutes. If it persists:
```bash
docker-compose restart kibana
docker-compose logs kibana | tail -30
```

### Filebeat restarting in a loop

```bash
docker-compose logs filebeat | tail -20
# Check TLS cert path and ES connectivity:
docker exec soc-elasticsearch curl -sk -u elastic:$PASS https://localhost:9200
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
# Windows
netstat -ano | findstr :5601

# macOS / Linux
lsof -i :5601
```

Change the port in `docker-compose.yml` if needed:
```yaml
ports:
  - "5602:5601"   # host:container
```

### Full reset

```bash
docker-compose down -v
rm -rf soc-project/data/ soc-project/logs/
docker network rm soc-net
docker network create soc-net
docker-compose up -d
```

---

## Project Structure

```
btl_252_soc/
├── README.md                        # This file — start here
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
│   │   └── check-stack.sh           # Health summary
│   ├── attacks/
│   │   ├── generate-alerts.sh       # Shell-based alert generator
│   │   └── attack-scenarios.py      # Python attack simulator
│   └── tests/
│       └── verify-stack.sh          # Smoke test suite
│
└── soc-project/                     # Docker deployment root
    ├── docker-compose.yml
    ├── .env                         # Secrets — never commit
    ├── .env.example                 # Template for .env
    ├── certs/                       # TLS certificates
    ├── elk/config/                  # Filebeat & Kibana config
    ├── suricata/conf/               # Suricata config & rules
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

*Last updated: February 2026*
