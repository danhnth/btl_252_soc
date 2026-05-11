# SOC Attack Demo - Proof of Concept

## Overview

This proof-of-concept demonstrates a **Red Team vs Blue Team** scenario where:
- **Attacker**: Windows machine running attack scripts
- **Victim**: Alma Linux with SOC stack (Suricata IDS + Wazuh SIEM + ELK)

The PoC triggers realistic security alerts visible in Kibana and Wazuh dashboards, perfect for educational demos and video presentations.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Windows Attacker                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Attack Scripts                                     │   │
│  │  • windows-attacker.py   (Python - Cross-platform)  │   │
│  │  • windows-attacker.ps1  (PowerShell - Native)      │   │
│  └─────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           │ Attacks
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  Alma Linux (Victim)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│  │  Suricata    │  │    Wazuh     │  │  Elasticsearch  │   │
│  │  IDS/IPS     │  │    SIEM      │  │    + Kibana     │   │
│  │              │  │              │  │                 │   │
│  │ • Web Attacks│  │ • SSH Brute  │  │ • Alert Storage │   │
│  │ • SQLi/XSS   │  │ • Port Scan  │  │ • Dashboards    │   │
│  │ • C2 Traffic │  │ • File Int.  │  │ • Analytics     │   │
│  └──────────────┘  └──────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Prerequisites

- **Windows Attacker**: Python 3.7+ or PowerShell 5.1+
- **Alma Linux Victim**: Docker & Docker Compose installed
- **Network**: Both machines on same network (attacker can reach victim)

### 1. Start the SOC Stack (on Alma Linux)

```bash
# On Alma Linux
sudo sysctl -w vm.max_map_count=262144
cd soc-project
docker network create soc-net
docker compose up -d

# Wait 3-5 minutes for services to start
docker compose ps

# Set up Kibana data views
bash ../scripts/setup/setup-kibana.sh
```

### 2. Find the Victim IP

```bash
# On Alma Linux
ip addr show | grep inet
```

### 3. Run the Attack (on Windows)

#### Option A: Python Script (Recommended)

```powershell
# Open PowerShell or CMD
python windows-attacker.py <VICTIM_IP> --all

# Example:
python windows-attacker.py 192.168.1.100 --all
```

#### Option B: PowerShell Script

```powershell
# Run as Administrator (for better network access)
.\windows-attacker.ps1 -TargetIP "192.168.1.100" -All
```

---

## Attack Scenarios

### Scenario 1: Web Scanner Detection (Suricata)

**Attacks triggered:**
- Nikto Web Scanner detection
- Nmap Scripting Engine detection
- SQLMap scanner detection

**Alerts in Kibana:**
```
et scan nikto web scanner user-agent
et scan nmap scripting engine user-agent
et scan sqlmap sql injection scanner
```

**Demo narrative:** *"The attacker is using automated scanning tools to probe for vulnerabilities..."*

---

### Scenario 2: SQL Injection (Suricata)

**Attacks triggered:**
- Classic SQL injection (`' OR '1'='1`)
- UNION-based SQL injection
- Time-based blind SQL injection

**Alerts in Kibana:**
```
et web_server sql injection in uri
et web_server sql injection attempt
```

**Demo narrative:** *"The attacker is attempting to extract data from the database through malicious SQL payloads..."*

---

### Scenario 3: Cross-Site Scripting - XSS (Suricata)

**Attacks triggered:**
- Basic XSS (`<script>alert('XSS')</script>`)
- Image-based XSS
- Event handler XSS

**Alerts in Kibana:**
```
et web_server possible cross-site scripting attempt
et web_server xss script tag in uri
```

**Demo narrative:** *"Cross-site scripting attempts to inject malicious JavaScript into web pages..."*

---

### Scenario 4: Path Traversal (Suricata)

**Attacks triggered:**
- Directory traversal (`../../../etc/passwd`)
- Double-encoded traversal
- Null byte injection

**Alerts in Kibana:**
```
et web_server directory traversal
et web_server path traversal attempt
```

**Demo narrative:** *"The attacker is trying to access files outside the web root directory..."*

---

### Scenario 5: SSH Brute Force (Wazuh)

**Attacks triggered:**
- Multiple failed SSH login attempts
- Authentication anomalies

**Alerts in Wazuh:**
```
Multiple authentication failures
SSHD brute force attack
Possible SSH brute force attack
```

**Demo narrative:** *"Host-based monitoring detects repeated failed login attempts to the SSH service..."*

---

### Scenario 6: Port Scanning (Both Suricata + Wazuh)

**Attacks triggered:**
- Reconnaissance on multiple ports
- Network scanning activity

**Alerts:**
```
# Suricata
et scan portscan

# Wazuh
Network scan detected
Multiple port scan attempts
```

**Demo narrative:** *"Network reconnaissance is often the first step before a targeted attack..."*

---

### Scenario 7: Malware C2 Simulation (Suricata)

**Attacks triggered:**
- Beaconing patterns
- Suspicious outbound connections
- Known malicious user-agents

**Alerts in Kibana:**
```
et malware terse executable downloader pattern
et policy suspicious user-agent
```

**Demo narrative:** *"Command and control traffic shows communication with external malicious infrastructure..."*

---

## Script Usage

### Python Script Options

```bash
# Full demo (all scenarios)
python windows-attacker.py <IP> --all

# Quick demo (3 scenarios)
python windows-attacker.py <IP> --quick

# Specific scenario
python windows-attacker.py <IP> --scenario web
python windows-attacker.py <IP> --scenario network
python windows-attacker.py <IP> --scenario brute-force

# Continuous mode (loop with interval)
python windows-attacker.py <IP> --all --continuous --interval 60

# Custom ports
python windows-attacker.py <IP> --all --http-port 8080 --ssh-port 2222

# Quiet mode (less output)
python windows-attacker.py <IP> --all --quiet
```

### PowerShell Script Options

```powershell
# Full demo
.\windows-attacker.ps1 -TargetIP "192.168.1.100" -All

# Quick demo
.\windows-attacker.ps1 -TargetIP "192.168.1.100" -Quick

# Continuous mode
.\windows-attacker.ps1 -TargetIP "192.168.1.100" -All -Continuous -Interval 30

# Custom ports
.\windows-attacker.ps1 -TargetIP "192.168.1.100" -All -HttpPort 8080 -SshPort 2222
```

---

## Viewing the Results

### Kibana Dashboard (Suricata Alerts)

1. Open browser: `http://<VICTIM_IP>:5601`
2. Login: `elastic` / `<password from .env>`
3. Navigate to: **Analytics → Discover**
4. Select index pattern: `suricata-ids-*`
5. Filter: `event_type : alert`
6. Sort by `@timestamp` descending

**Key fields to show:**
- `@timestamp`
- `alert.signature` (rule name)
- `alert.category`
- `src_ip` / `dest_ip`
- `alert.severity`

### Wazuh Dashboard (Host-based Alerts)

1. Open browser: `https://<VICTIM_IP>`
2. Login: `admin` / `<password from .env>`
3. Navigate to: **Security Events**
4. Filter: `rule.groups: "authentication_failure"`

---

## Demo Video Script

### Scene 1: Introduction (30 seconds)

**Narrator:** 
> "Today we're demonstrating a Security Operations Center stack detecting real attack scenarios. We have two machines: a Windows attacker and an Alma Linux victim running Suricata IDS, Wazuh SIEM, and the ELK stack."

**Visual:**
- Split screen showing both machines
- Show architecture diagram

---

### Scene 2: SOC Stack Overview (45 seconds)

**Narrator:**
> "The victim is running a comprehensive SOC stack. Suricata monitors network traffic for malicious patterns. Wazuh provides host-based intrusion detection. Elasticsearch stores all alerts, and Kibana visualizes them in real-time."

**Visual:**
- Show Kibana dashboard (empty)
- Show Wazuh dashboard (empty)
- Briefly show docker-compose services running

---

### Scene 3: Launch Attack (15 seconds)

**Narrator:**
> "Now we'll initiate attacks from our Windows machine. Watch as the alerts appear in real-time."

**Visual:**
- Terminal: `python windows-attacker.py 192.168.1.100 --quick`
- Press Enter to execute

---

### Scene 4: Web Attacks (60 seconds)

**Narrator:**
> "First, we see web scanning tools like Nikto and SQLMap being detected. These are common reconnaissance tools attackers use to find vulnerabilities. The IDS immediately flags suspicious user-agents."

**Visual:**
- Split screen: Attack terminal on left, Kibana on right
- Watch alerts populate in real-time
- Zoom in on specific alert signatures

**Key alerts to highlight:**
- `et scan nikto web scanner`
- `et scan sqlmap sql injection`

---

### Scene 5: Injection Attacks (60 seconds)

**Narrator:**
> "Next, we see injection attacks. SQL injection attempts to manipulate database queries, while XSS tries to inject malicious scripts. Suricata's ruleset identifies these patterns in the HTTP requests."

**Visual:**
- Show specific SQL injection payloads in terminal
- Show corresponding alerts in Kibana
- Highlight severity levels (1-3)

---

### Scene 6: SSH Brute Force (45 seconds)

**Narrator:**
> "Meanwhile, Wazuh is monitoring the host itself. Here we see brute force login attempts on SSH. Multiple failed authentication attempts from the same source trigger host-based alerts."

**Visual:**
- Switch to Wazuh dashboard
- Show authentication failure alerts
- Show source IP correlation

---

### Scene 7: Analysis & Summary (60 seconds)

**Narrator:**
> "Within minutes, we've detected scanning, injection attempts, and brute force attacks. The SOC stack successfully identified threats at both network and host levels. This demonstrates the power of layered security monitoring."

**Visual:**
- Show Kibana Discover with multiple alerts
- Show summary statistics
- Show timeline view

---

### Scene 8: Conclusion (30 seconds)

**Narrator:**
> "This proof-of-concept demonstrates how modern SOC tools can detect and alert on various attack vectors in real-time. The open-source stack provides enterprise-grade visibility without the enterprise price tag."

**Visual:**
- Final dashboard view
- Show alert counts
- Fade to end screen with architecture diagram

---

## Troubleshooting

### No alerts appearing

**Check:**
```bash
# On Alma Linux
docker compose ps  # Ensure all services healthy
docker compose logs filebeat  # Check log shipping
docker exec soc-suricata sh -c "grep 'event_type.*alert' /var/log/suricata/eve.json | wc -l"
```

**Solution:**
- Ensure attack traffic is reaching the victim
- Check firewall rules between attacker and victim
- Verify services are healthy: `bash scripts/setup/check-stack.sh`

### Windows script won't run

**PowerShell Execution Policy:**
```powershell
# Run as Administrator
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Python not found:**
```powershell
# Use full path or ensure Python is in PATH
py windows-attacker.py <IP> --all
```

### Connection timeouts

**Check network connectivity:**
```powershell
# From Windows
ping <VICTIM_IP>
telnet <VICTIM_IP> 80
telnet <VICTIM_IP> 22
```

---

## Files Reference

```
poc-demo/
├── attacker-scripts/
│   ├── windows-attacker.py    # Python attack script
│   └── windows-attacker.ps1   # PowerShell attack script
├── docs/
│   └── DEMO-SCRIPT.md         # Detailed demo script
└── demo-assets/
    └── architecture.png       # Architecture diagram (generate if needed)
```

---

## Tips for Demo Video

1. **Resolution**: Use 1920x1080 or higher for clear dashboard visibility
2. **Split Screen**: Show attacker terminal and Kibana side-by-side
3. **Zoom**: Zoom in on important alerts and terminal output
4. **Timing**: Allow 5-10 seconds between attack and alert explanation
5. **Narration**: Speak clearly and explain what each alert means
6. **Transitions**: Use smooth transitions between attack phases

---

## Customization

### Add Custom Attacks

Edit `windows-attacker.py` and add to `SCENARIOS` dictionary:

```python
"my-custom-attack": {
    "description": "ET WEB_SERVER - Custom payload",
    "requests": [
        {"url": f"http://{target}/custom?payload=test",
         "headers": {"User-Agent": "Custom/1.0"}},
    ],
},
```

### Change Alert Severity

Modify Suricata rules in:
```
soc-project/suricata/conf/rules/
```

---

## Next Steps

1. ✅ Start SOC stack on Alma Linux
2. ✅ Run attack scripts from Windows
3. ✅ Verify alerts in Kibana & Wazuh
4. 🎬 Record demo video
5. 📊 Create presentation slides
6. 📝 Write report

---

## Support

For issues with the SOC stack, refer to:
- `../../README.md` - Main project documentation
- `../../scripts/setup/check-stack.sh` - Health checks

For attack script issues:
- Ensure Python 3.7+ or PowerShell 5.1+
- Check network connectivity
- Verify target IP is correct

---

**Happy Demo! 🎥🔒**
