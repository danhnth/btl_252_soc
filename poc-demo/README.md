# 🎯 SOC Attack Demo - Proof of Concept

> **Professional demo-ready attack scenarios for testing your SOC stack**

This proof-of-concept provides a complete **Red Team vs Blue Team** demonstration environment where a Windows attacker machine triggers realistic attack scenarios against an Alma Linux victim running a full SOC stack (Suricata IDS, Wazuh SIEM, ELK).

---

## ⚠️ IMPORTANT: External Attack Architecture

**Direct attacks from Windows → Alma Linux don't trigger Suricata alerts** because Docker bridge networking isolates containers. 

### Solution: Attack Relay Architecture

We use a **relay** that receives commands from Windows, then executes attacks **from inside the Suricata container** so alerts are properly generated.

```
Windows ──Command──► Alma Linux Relay ──► Suricata Container ──► Internet
                              │                    │
                              │                    └── Sees traffic!
                              │
                              └── Runs: external-attack-relay.py
```

**See:** [EXTERNAL-ATTACKS.md](docs/EXTERNAL-ATTACKS.md) for detailed explanation.

---

## 📁 What's Included

```
poc-demo/
├── 📂 attacker-scripts/          # Attack scripts
│   ├── external-attack-relay.py      # Run on Alma Linux (victim) ⭐
│   ├── windows-attack-client.py      # Run on Windows (attacker) ⭐
│   ├── windows-attacker.py           # Alternative direct script
│   └── windows-attacker.ps1          # PowerShell version
│
├── 📂 docs/                      # Documentation
│   ├── EXTERNAL-ATTACKS.md       # Detailed architecture explanation
│   ├── QUICK-REFERENCE.md        # Command cheat sheet
│   └── README.md                 # Full documentation
│
├── 📂 demo-assets/               # Demo materials
│
├── run-attack-client.bat         # Windows launcher (NEW) ⭐
├── setup-external-attacks.sh     # Alma Linux setup helper (NEW) ⭐
├── QUICKSTART.md                 # 5-minute quick start guide ⭐
├── demo-orchestrator.sh          # Linux demo manager
├── demo-check.sh                 # Pre-flight check script
└── README.md                     # This file
```

**⭐ Recommended files for external attacks:**
- `setup-external-attacks.sh` - Run on Alma Linux
- `run-attack-client.bat` - Run on Windows
- `QUICKSTART.md` - Quick start guide

---

## 🚀 5-Minute Quick Start

### Terminal 1: Alma Linux (Victim)

```bash
cd ~/btl_252_soc/poc-demo
bash setup-external-attacks.sh
```

**Note the IP address shown!** Keep this terminal open.

### Terminal 2: Windows (Attacker)

Double-click: `run-attack-client.bat`

Or from PowerShell:
```powershell
python attacker-scripts\windows-attack-client.py <ALMA_LINUX_IP> --quick
```

### Step 3: View Alerts

Open **Kibana**: http://`<VICTIM_IP>`:5601

1. Analytics → Discover
2. Select **suricata-ids-***
3. Filter: `event_type : alert`
4. See your alerts! 🎉

**More details:** [QUICKSTART.md](QUICKSTART.md)

---

## 🎬 Demo Scenarios

| # | Attack Type | Tool/Method | Suricata Alert |
|---|-------------|-------------|----------------|
| 1 | **IDS Test** | testmynids.org | GPL ATTACK_RESPONSE |
| 2 | **Web Scanner** | SQLMap | ET SCAN sqlmap |
| 3 | **Web Scanner** | Nikto | ET SCAN Nikto |
| 4 | **Web Scanner** | Nmap NSE | ET SCAN Nmap Scripting Engine |
| 5 | **SQL Injection** | Payloads | ET WEB_SERVER SQL Injection |
| 6 | **XSS Attack** | Script injection | ET WEB_SERVER XSS |
| 7 | **Path Traversal** | `../../../etc/passwd` | ET WEB_SERVER Path Traversal |
| 8 | **Malware Pattern** | Download pattern | ET MALWARE |
| 9 | **Policy Violation** | curl user-agent | ET POLICY |
| 10 | **Burst Traffic** | Rapid requests | Various |

---

## 📊 What You'll See

### Windows Terminal
```
======================================================================
  WINDOWS ATTACK CLIENT - SURICATA DEMO
======================================================================

[INFO] Victim IP: 192.168.1.100
[INFO] Relay Port: 9999

[SUCCESS] Connected to attack relay

[*] QUICK DEMO MODE
------------------------------------------------------------
[INFO] Running 4 attack scenarios...

[SUCCESS] Executed: GPL ATTACK_RESPONSE - testmynids.org uid check
[SUCCESS] Executed: ET SCAN - sqlmap scanner user-agent
...
```

### Kibana Dashboard
- Real-time alert streaming
- Signatures like:
  - `GPL ATTACK_RESPONSE id check returned root`
  - `ET SCAN sqlmap SQL Injection Scanner User-Agent`
  - `ET SCAN Nikto Web Scanner User-Agent`

---

## 📖 Documentation

| Document | Purpose |
|----------|---------|
| [QUICKSTART.md](QUICKSTART.md) | **5-minute setup guide** - Start here! |
| [EXTERNAL-ATTACKS.md](docs/EXTERNAL-ATTACKS.md) | Why direct attacks don't work & relay architecture |
| [docs/QUICK-REFERENCE.md](docs/QUICK-REFERENCE.md) | Command cheat sheet |
| [docs/README.md](docs/README.md) | Original full documentation |

---

## 🔧 Troubleshooting

### "Cannot connect to relay"

```bash
# On Alma Linux - check relay is running
ps aux | grep external-attack-relay

# Check firewall
sudo firewall-cmd --add-port=9999/tcp

# Check port is listening
sudo ss -tlnp | grep 9999
```

### "No alerts appearing"

```bash
# On Alma Linux - check Suricata
docker exec soc-suricata sh -c "grep 'event_type.*alert' /var/log/suricata/eve.json | head -5"

# Wait 30 seconds for Filebeat
docker compose logs filebeat | tail -10
```

**See [QUICKSTART.md](QUICKSTART.md)** for more troubleshooting.

---

## 🎥 Demo Video Tips

### Screen Layout (Recommended)
```
┌─────────────────────┬─────────────────────┐
│                     │                     │
│   Windows Terminal  │   Kibana Dashboard  │
│   (Attacker)        │   (Alerts)          │
│                     │                     │
├─────────────────────┼─────────────────────┤
│                     │                     │
│   Attack Progress   │   Alert Details     │
│                     │                     │
└─────────────────────┴─────────────────────┘
```

### Timing Guide
| Phase | Duration | Action |
|-------|----------|--------|
| Setup | 30 sec | Start relay, show architecture |
| Attack | 60 sec | Run quick demo from Windows |
| Wait | 30 sec | Explain relay concept |
| Analysis | 60 sec | Review Kibana alerts |
| Summary | 30 sec | Key takeaways |
| **Total** | **~4 min** | |

### Narration Tips
1. **Explain the relay**: "Windows sends commands, relay executes from inside Suricata"
2. **Show cause-effect**: "We triggered SQLMap, now we see the alert"
3. **Zoom in**: On alert signatures in Kibana
4. **Keep it simple**: Focus on 3-4 key alerts for demo

---

## 🛠️ Advanced Usage

### List Available Scenarios
```powershell
python attacker-scripts\windows-attack-client.py <IP> --list
```

### Run Specific Scenario
```powershell
python attacker-scripts\windows-attack-client.py <IP> --scenario sqlmap
```

### Full Demo (All Scenarios)
```powershell
python attacker-scripts\windows-attack-client.py <IP> --all
```

### Custom Wait Time
```powershell
python attacker-scripts\windows-attack-client.py <IP> --quick --wait 30
```

---

## 📦 System Requirements

### Attacker (Windows)
- Python 3.7+ 
- Network access to victim port 9999
- 50 MB disk space

### Victim (Alma Linux)
- Docker & Docker Compose
- Python 3.7+ (for relay)
- 8 GB RAM (16 GB recommended)
- 50 GB disk space
- Port 9999 accessible from attacker

---

## 🎓 Learning Outcomes

This demo effectively demonstrates:

1. **IDS/IPS Functionality** - How Suricata detects network attacks
2. **Docker Networking** - Why container isolation affects monitoring
3. **Relay Architecture** - Workarounds for network visibility
4. **Attack Patterns** - Real-world attack signatures
5. **Log Aggregation** - How ELK stack collects and visualizes data

---

## 🤝 Support

**Attack relay not starting?**
```bash
# Check Suricata is running
docker ps | grep soc-suricata

# Check Python is installed
python3 --version
```

**Windows client can't connect?**
```bash
# On Alma Linux - test relay
curl http://localhost:9999/health

# Check firewall
sudo firewall-cmd --list-ports
```

**No alerts in Kibana?**
```bash
# Check SOC stack
bash demo-check.sh

# Check logs
docker compose logs filebeat
```

---

## 🎬 Ready to Demo?

```bash
# Alma Linux
bash setup-external-attacks.sh

# Windows
python attacker-scripts\windows-attack-client.py <IP> --quick

# Browser
http://<VICTIM_IP>:5601
```

**Good luck with your demo! 🚀**

---

*Created for educational purposes - SOC Attack Demo PoC*  
*Uses Attack Relay architecture to solve Docker networking constraints*
