# External Attack Demo - Quick Start Guide

## ⚠️ Problem Statement

**Direct attacks from Windows → Alma Linux don't trigger Suricata alerts** because Docker bridge networking isolates containers.

**Solution**: Use the **Attack Relay** architecture (explained below).

---

## 🎯 Quick Start (5 Minutes)

### Terminal 1: Alma Linux (Victim)

```bash
# 1. Go to the demo directory
cd ~/btl_252_soc/poc-demo

# 2. Run setup helper (starts everything)
bash setup-external-attacks.sh
```

You'll see your IP address. **Note this down!**

Example output:
```
Your IP addresses:
  192.168.1.100/24

✓ SOC stack is running
✓ Attack relay is running on port 9999
✓ Firewall allows port 9999

Windows attacker should run:
  Double-click: poc-demo\run-attack-client.bat
  Enter your Alma Linux IP: 192.168.1.100
```

**Keep this terminal open!** It runs the relay server.

---

### Terminal 2: Windows (Attacker)

#### Option A: Batch File (Easiest)

1. Double-click: `poc-demo\run-attack-client.bat`
2. Enter the Alma Linux IP (e.g., `192.168.1.100`)
3. Select mode `1` for Quick Demo
4. Watch attacks execute!

#### Option B: Python Command

```powershell
# Quick demo (~1 minute)
python poc-demo\attacker-scripts\windows-attack-client.py 192.168.1.100 --quick

# Full demo (~3 minutes)
python poc-demo\attacker-scripts\windows-attack-client.py 192.168.1.100 --all
```

---

### Step 3: View Alerts

Wait 15-30 seconds, then open browser:

**Kibana**: http://`<VICTIM_IP>`:5601

1. Click ☰ → **Analytics** → **Discover**
2. Select **suricata-ids-***
3. In search box: `event_type : alert`
4. You should see alerts! 🎉

---

## 📊 What You Should See

### Windows Terminal
```
======================================================================
  WINDOWS ATTACK CLIENT - SURICATA DEMO
======================================================================

[INFO] Victim IP: 192.168.1.100
[INFO] Relay Port: 9999

[INFO] Checking connection to attack relay...
[SUCCESS] Connected to attack relay

[*] QUICK DEMO MODE
------------------------------------------------------------
[INFO] Running 4 attack scenarios...

[INFO] Triggering: ids-test
[SUCCESS] Executed: GPL ATTACK_RESPONSE - testmynids.org uid check
[INFO] Commands: 2/2 successful

[INFO] Triggering: sqlmap
[SUCCESS] Executed: ET SCAN - sqlmap scanner user-agent
...
```

### Kibana
- Multiple `suricata-ids-*` alerts
- Signatures like:
  - `GPL ATTACK_RESPONSE id check returned root`
  - `ET SCAN sqlmap SQL Injection Scanner`
  - `ET SCAN Nikto Web Scanner User-Agent`

---

## 🔧 Manual Setup (If Helper Script Fails)

### On Alma Linux:

```bash
# 1. Start SOC stack
cd ~/btl_252_soc/soc-project
docker compose up -d

# 2. Get your IP
ip addr show | grep "inet " | head -1

# 3. Open firewall
sudo firewall-cmd --add-port=9999/tcp

# 4. Start relay (in separate terminal)
cd ~/btl_252_soc/poc-demo/attacker-scripts
python3 external-attack-relay.py
```

### On Windows:

```powershell
# Run attack client
python poc-demo\attacker-scripts\windows-attack-client.py <ALMA_LINUX_IP> --quick
```

---

## 🐛 Troubleshooting

### "Cannot connect to relay"

**Check on Alma Linux:**
```bash
# Is relay running?
ps aux | grep external-attack-relay

# Is port 9999 open?
sudo ss -tlnp | grep 9999

# Check firewall
sudo firewall-cmd --list-ports
```

**Fix:**
```bash
# Open firewall
sudo firewall-cmd --add-port=9999/tcp

# Restart relay
cd ~/btl_252_soc/poc-demo/attacker-scripts
python3 external-attack-relay.py
```

### "No alerts in Kibana"

**Wait longer** (30-60 seconds)

**Check on Alma Linux:**
```bash
# Check if alerts are being generated
docker exec soc-suricata sh -c "grep 'event_type.*alert' /var/log/suricata/eve.json | wc -l"

# Should show a number > 0

# Check Filebeat
docker compose logs filebeat | tail -10
```

### "Python not found on Windows"

Download and install Python 3.7+ from https://python.org

Make sure to check "Add Python to PATH" during installation.

---

## 📚 Full Documentation

- **Detailed explanation**: `docs/EXTERNAL-ATTACKS.md`
- **Troubleshooting**: See detailed error messages in terminal
- **Architecture**: See diagram in EXTERNAL-ATTACKS.md

---

## 🎬 Demo Checklist

Before recording your video:

- [ ] SOC stack running on Alma Linux
- [ ] Relay running on Alma Linux (port 9999)
- [ ] Firewall open (port 9999)
- [ ] Note victim IP address
- [ ] Test attack from Windows
- [ ] Verify alerts appear in Kibana
- [ ] Close unnecessary applications
- [ ] Prepare split-screen recording setup

---

## 💡 Tips

1. **Split-screen recording**: Show Windows terminal + Kibana side-by-side
2. **Wait time**: Allow 15-30 seconds between attacks and alert check
3. **Narration**: Explain that the relay ensures Suricata sees the traffic
4. **Quick mode**: Use `--quick` for shorter demos

---

## 📞 Quick Commands Reference

**Alma Linux:**
```bash
# Start everything
bash setup-external-attacks.sh

# Check relay logs
ps aux | grep external-attack-relay

# Check Suricata alerts
docker exec soc-suricata sh -c "grep 'event_type.*alert' /var/log/suricata/eve.json | head -5"
```

**Windows:**
```powershell
# Quick demo
python attacker-scripts\windows-attack-client.py <IP> --quick

# List scenarios
python attacker-scripts\windows-attack-client.py <IP> --list

# Specific attack
python attacker-scripts\windows-attack-client.py <IP> --scenario sqlmap
```

---

**Ready? Let's demo! 🚀**

1. Start relay on Alma Linux
2. Run client on Windows
3. Watch the magic in Kibana!
