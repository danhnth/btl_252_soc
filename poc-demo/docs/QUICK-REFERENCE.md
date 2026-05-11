# SOC Attack Demo - Quick Reference

## 🚀 Quick Start (5 minutes)

### Step 1: Start SOC Stack (Alma Linux)
```bash
cd ~/btl_252_soc/soc-project
docker compose up -d
bash ../scripts/setup/setup-kibana.sh
```

### Step 2: Get Victim IP
```bash
ip addr show | grep "inet " | grep -v 127
# Note the IP address (e.g., 192.168.1.100)
```

### Step 3: Run Attack (Windows)
```powershell
# Quick demo (~1 minute)
python windows-attacker.py <VICTIM_IP> --quick

# Full demo (~3 minutes)  
python windows-attacker.py <VICTIM_IP> --all
```

### Step 4: View Results
- **Kibana**: http://`<VICTIM_IP>`:5601
- **Wazuh**: https://`<VICTIM_IP>`

---

## 📊 Attack Scenarios Reference

| Scenario | Tool Detected | Suricata Alert | Wazuh Alert |
|----------|--------------|----------------|-------------|
| **Web Scanner** | Nikto, SQLMap, Nmap | `et scan * user-agent` | - |
| **SQL Injection** | SQL payloads | `et web_server sql injection` | - |
| **XSS Attack** | Script injection | `et web_server xss *` | - |
| **Path Traversal** | `../../../etc/passwd` | `et web_server directory traversal` | - |
| **SSH Brute Force** | Multiple failed logins | `et scan *` | `authentication_failure` |
| **Port Scan** | Multi-port probe | `et scan portscan` | `portscan` |
| **Malware C2** | Beaconing traffic | `et malware *` | - |

---

## 🔍 Finding Alerts in Kibana

### 1. Open Discover
```
☰ Menu → Analytics → Discover
```

### 2. Select Index Pattern
```
suricata-ids-*
```

### 3. Filter for Alerts
```kql
event_type : alert
```

### 4. Key Fields to Show
```
@timestamp
alert.signature (rule name)
alert.category (attack type)
src_ip (attacker)
dest_ip (victim)
alert.severity (1=Critical, 2=High, 3=Medium)
```

### 5. Useful KQL Queries
```kql
# High severity alerts only
alert.severity : 1

# Specific attack type
alert.category : "Attempted Administrator Privilege Gain"

# From specific IP
src_ip : "192.168.1.x"

# SQL injection attempts
alert.signature : "*sql*"

# Time range (last 15 minutes)
@timestamp >= now-15m
```

---

## 🖥️ Windows Commands

### Run with Python
```powershell
# Check Python version
python --version

# Install dependencies (if needed)
pip install requests urllib3

# Run attacks
python windows-attacker.py 192.168.1.100 --all

# Help
python windows-attacker.py --help
```

### Run with PowerShell
```powershell
# Check execution policy
Get-ExecutionPolicy

# Set policy (if needed)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run script
.\windows-attacker.ps1 -TargetIP "192.168.1.100" -All

# Get help
Get-Help .\windows-attacker.ps1 -Full
```

### Using Batch File
```batch
# Double-click run-demo.bat
# Or from command prompt:
run-demo.bat
```

---

## 🐧 Alma Linux Commands

### Check Stack Health
```bash
cd ~/btl_252_soc/soc-project

# View container status
docker compose ps

# Check logs
docker compose logs -f suricata
docker compose logs -f filebeat
docker compose logs -f wazuh-manager

# Check alert counts
docker exec soc-suricata sh -c "grep 'event_type.*alert' /var/log/suricata/eve.json | wc -l"
```

### Restart Services
```bash
# Restart single service
docker compose restart suricata

# Full restart
docker compose restart

# Reset everything (⚠️ deletes data)
docker compose down -v
docker compose up -d
```

### Monitor Alerts
```bash
# Real-time alert stream
docker exec soc-suricata tail -f /var/log/suricata/eve.json | grep '"event_type":"alert"'

# Count alerts by signature
docker exec soc-suricata cat /var/log/suricata/eve.json | jq -r '.alert.signature' | sort | uniq -c | sort -rn
```

---

## 🎬 Demo Video Tips

### Screen Layout (Recommended)
```
┌─────────────────────┬─────────────────────┐
│                     │                     │
│   Windows Terminal  │   Kibana Dashboard  │
│   (Attacker)        │   (Alerts)          │
│                     │                     │
├─────────────────────┼─────────────────────┤
│                     │                     │
│   Terminal          │   Wazuh Dashboard   │
│   (Command input)   │   (Host alerts)     │
│                     │                     │
└─────────────────────┴─────────────────────┘
```

### Timing Guide
| Phase | Duration | Action |
|-------|----------|--------|
| Setup | 30 sec | Show architecture, start SOC |
| Attack 1 | 60 sec | Web scanners, show alerts |
| Attack 2 | 60 sec | Injection attacks |
| Attack 3 | 45 sec | SSH brute force |
| Analysis | 60 sec | Review dashboards |
| Summary | 30 sec | Key takeaways |
| **Total** | **~5 min** | |

### Narration Tips
1. **Speak slowly** - Let viewers follow along
2. **Point to screen** - Use cursor to highlight alerts
3. **Explain context** - "This alert means..."
4. **Show cause-effect** - "We did X, now we see Y"
5. **Zoom in** - On important details

---

## 🐛 Troubleshooting

### No alerts appearing

**Check connectivity:**
```powershell
# From Windows
ping <VICTIM_IP>
telnet <VICTIM_IP> 80
```

**Check services:**
```bash
# On Alma Linux
docker compose ps
docker compose logs suricata | tail -20
docker compose logs filebeat | tail -20
```

**Verify rules:**
```bash
# Check Suricata is processing rules
docker exec soc-suricata suricata -T -c /etc/suricata/suricata.yaml
```

### Script errors on Windows

**Python not found:**
```powershell
# Use py launcher
py windows-attacker.py <IP> --all

# Or full path
C:\Python39\python.exe windows-attacker.py <IP> --all
```

**Permission denied (PowerShell):**
```powershell
# Check current policy
Get-ExecutionPolicy -List

# Set for current user
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Connection timeouts:**
- Check Windows Firewall
- Check Alma Linux firewall: `sudo firewall-cmd --list-all`
- Verify same network/subnet

### Elasticsearch issues

**Out of memory:**
```bash
# Increase Docker memory to 8GB+
# Or reduce JVM heap:
echo "ES_JAVA_OPTS=-Xms512m -Xmx512m" >> .env
docker compose restart elasticsearch
```

**Certificate errors:**
```bash
bash scripts/setup/fix-elasticsearch-certs.sh
```

---

## 📈 Expected Results

### Quick Demo Output
```
Attacks Executed: 8
Successful: 8
Failed: 0

Alerts Generated:
  - 3 Web Scanner Detection alerts
  - 2 SQL Injection alerts
  - 3 SSH Brute Force alerts (Wazuh)
```

### Full Demo Output
```
Attacks Executed: 25+
Successful: 25+
Failed: 0

Alerts Generated:
  - 8+ Network-based (Suricata)
  - 10+ Web attacks (Suricata)
  - 5+ Host-based (Wazuh)
```

---

## 📝 Customization

### Add New Attack

Edit `windows-attacker.py`:
```python
"my-attack": {
    "description": "Custom attack description",
    "requests": [
        {"url": f"http://{target}/test",
         "headers": {"User-Agent": "Custom/1.0"}},
    ],
},
```

### Change Ports

```bash
# Python
python windows-attacker.py <IP> --all --http-port 8080 --ssh-port 2222

# PowerShell
.\windows-attacker.ps1 -TargetIP "<IP>" -All -HttpPort 8080 -SshPort 2222
```

### Continuous Mode

```bash
# Attack every 30 seconds
python windows-attacker.py <IP> --all --continuous --interval 30

# Stop with Ctrl+C
```

---

## 🔗 Useful Links

- **Kibana Query Language (KQL)**: https://www.elastic.co/guide/en/kibana/current/kuery-query.html
- **Suricata Rules**: https://suricata.io/rules/
- **Wazuh Documentation**: https://documentation.wazuh.com/
- **MITRE ATT&CK**: https://attack.mitre.org/

---

## 📞 Support

**Issue with attack scripts?**
1. Check Python/PowerShell version
2. Verify network connectivity
3. Check firewall settings

**Issue with SOC stack?**
1. Run: `bash scripts/setup/check-stack.sh`
2. Check: `docker compose logs`
3. Refer to: `../../README.md`

---

**Quick Command Summary:**
```bash
# Start SOC
cd ~/btl_252_soc/soc-project && docker compose up -d

# Run attack (Windows)
python windows-attacker.py <IP> --quick

# View alerts
# http://<IP>:5601 → Discover → suricata-ids-*
```

**Happy Demo! 🎯**
