# External Attack Relay - Solution for Suricata Alert Generation

## The Problem

When you try to attack from **Windows (external)** → **Alma Linux (victim)** directly, Suricata running in a Docker container **cannot see the traffic**.

### Why?

```
Windows Attacker ──► Alma Linux Host ──► Docker Container (Suricata)
         │                   │                    │
         │                   │                    └── Can't see traffic
         │                   │                       from Windows!
         │                   │
         │                   └── Docker forwards traffic
         │                       directly to container
         │                       (bypasses Suricata's eth0)
         │
         └── HTTP Request to port 80/5000
```

**The Docker Bridge Networking Issue:**
- Docker creates isolated network namespaces for containers
- Suricata monitors `eth0` inside its container
- Traffic from external hosts hitting container ports goes through Docker's bridge
- This traffic **never traverses** Suricata's monitored interface

### What Works

The existing scripts (`generate-alerts.sh`, `attack-scenarios.py`) work because they run **inside** the Suricata container:

```
Inside Suricata Container:
  curl http://testmynids.org/
         │
         └── Goes out through eth0
              └── Suricata sees it! ✓
```

## The Solution: Attack Relay

We use a **relay architecture** that allows external attacks while ensuring Suricata sees the traffic:

```
Windows Attacker ──► Alma Linux Relay ──► Suricata Container ──► Internet
         │                   │                    │
         │                   │                    └── Sees outbound traffic
         │                   │                        (monitors eth0)
         │                   │
         │                   └── Receives attack commands
         │                       Executes HTTP requests
         │                       from INSIDE container
         │
         └── Sends attack command:
             "Run sqlmap scenario"
```

### How It Works

1. **external-attack-relay.py** runs on Alma Linux (victim)
2. It exposes an HTTP API on port 9999
3. **windows-attack-client.py** on Windows connects to this API
4. Windows client sends attack scenario commands (e.g., "run sqlmap attack")
5. Relay executes the actual HTTP requests **from inside the Suricata container**
6. Suricata sees the outbound traffic and generates alerts ✓

## Quick Start

### Step 1: Start SOC Stack (Alma Linux)

```bash
# On Alma Linux victim
cd ~/btl_252_soc/soc-project
docker compose up -d

# Wait for services to be healthy
docker compose ps
```

### Step 2: Start Attack Relay (Alma Linux)

```bash
# On Alma Linux victim
cd ~/btl_252_soc/poc-demo/attacker-scripts
python3 external-attack-relay.py
```

You should see:
```
======================================================================
  SURICATA EXTERNAL ATTACK RELAY
======================================================================

This server receives attack requests from external attackers
and relays them through the Suricata container so alerts
are properly generated.

Listening on port: 9999

Available scenarios:
  - ids-test             : GPL ATTACK_RESPONSE - testmynids.org uid check
  - sqlmap               : ET SCAN - sqlmap scanner user-agent
  - nikto                : ET SCAN - Nikto web scanner user-agent
  ...

[OK] Suricata container is running
[INFO] Starting relay server on port 9999...
[INFO] Windows attackers can now connect to this machine on port 9999
```

### Step 3: Open Firewall (Alma Linux)

```bash
# Allow port 9999 for the relay
sudo firewall-cmd --add-port=9999/tcp --permanent
sudo firewall-cmd --reload

# Or temporarily (until reboot):
sudo firewall-cmd --add-port=9999/tcp
```

### Step 4: Run Attack Client (Windows)

**Option A: Using Batch File (Easiest)**

Double-click: `poc-demo\run-attack-client.bat`

Or from Command Prompt:
```batch
poc-demo\run-attack-client.bat
```

Then follow the prompts:
1. Enter Alma Linux IP address
2. Select demo mode (1-4)
3. Watch the attacks execute

**Option B: Using Python Directly**

```powershell
# Quick demo (4 attack scenarios, ~1 minute)
python poc-demo\attacker-scripts\windows-attack-client.py 192.168.1.100 --quick

# Full demo (all scenarios, ~3 minutes)
python poc-demo\attacker-scripts\windows-attack-client.py 192.168.1.100 --all

# List available scenarios
python poc-demo\attacker-scripts\windows-attack-client.py 192.168.1.100 --list

# Run specific scenario
python poc-demo\attacker-scripts\windows-attack-client.py 192.168.1.100 --scenario sqlmap
```

### Step 5: View Alerts

Wait 15-30 seconds for alerts to appear, then:

1. **Open Kibana**: http://`<VICTIM_IP>`:5601
2. **Navigate to**: Analytics → Discover
3. **Select index**: suricata-ids-*
4. **Filter**: `event_type : alert`

You should see alerts like:
- `GPL ATTACK_RESPONSE id check returned root`
- `ET SCAN sqlmap SQL Injection Scanner User-Agent`
- `ET SCAN Nikto Web Scanner User-Agent`
- `ET WEB_SERVER SQL Injection in URI`

## Available Attack Scenarios

| Scenario | Description | Suricata Alert |
|----------|-------------|----------------|
| `ids-test` | Basic IDS detection test | GPL ATTACK_RESPONSE |
| `sqlmap` | SQLMap scanner detection | ET SCAN sqlmap |
| `nikto` | Nikto scanner detection | ET SCAN Nikto |
| `nmap` | Nmap NSE detection | ET SCAN Nmap Scripting Engine |
| `malware-dl` | Malware download pattern | ET MALWARE |
| `sql-injection` | SQL injection payloads | ET WEB_SERVER SQL Injection |
| `xss` | Cross-site scripting | ET WEB_SERVER XSS |
| `path-traversal` | Directory traversal | ET WEB_SERVER Path Traversal |
| `policy-curl` | curl user-agent detection | ET POLICY curl |
| `burst` | Rapid request burst | Various |
| `all` | Run all scenarios | All of the above |

## Architecture Comparison

### ❌ Direct Attack (Doesn't Work)

```
Windows ──HTTP──► Alma Linux:80 ──Docker Bridge──► Container
                                        ↑
                              Suricata can't see this traffic
```

### ✅ Relay Attack (Works!)

```
Windows ──Command──► Alma Linux:9999 (Relay)
                           │
                           └── Docker exec ──► Suricata Container
                                                       │
                                                       └── HTTP Request
                                                            │
                                                       Suricata monitors eth0
                                                       (sees outbound traffic)
```

## Troubleshooting

### "Cannot connect to relay"

**Problem**: Windows client can't reach the relay on port 9999

**Solution**:
1. Check relay is running on Alma Linux:
   ```bash
   ps aux | grep external-attack-relay
   ```

2. Check firewall on Alma Linux:
   ```bash
   sudo firewall-cmd --list-ports
   # Should show: 9999/tcp
   ```

3. Test connectivity from Windows:
   ```powershell
   telnet <VICTIM_IP> 9999
   ```

4. Check if relay is listening:
   ```bash
   # On Alma Linux
   sudo ss -tlnp | grep 9999
   ```

### "No alerts appearing in Kibana"

**Problem**: Attacks run but no alerts visible

**Solution**:
1. Wait 15-30 seconds for Filebeat to ship logs
2. Check Suricata is generating alerts:
   ```bash
   # On Alma Linux
   docker exec soc-suricata sh -c "grep 'event_type.*alert' /var/log/suricata/eve.json | head -5"
   ```

3. Check Filebeat is working:
   ```bash
   docker compose logs filebeat | tail -20
   ```

4. Check Elasticsearch indices:
   ```bash
   curl -sk -u elastic:password https://localhost:9200/_cat/indices/suricata*
   ```

### "Relay says 'Suricata container is not running'"

**Solution**:
```bash
# Start the SOC stack
cd ~/btl_252_soc/soc-project
docker compose up -d

# Verify
docker compose ps
```

## Security Considerations

⚠️ **WARNING**: This relay is for **DEMONSTRATION PURPOSES ONLY**

- It exposes an unauthenticated API that can execute arbitrary commands
- Only run this in isolated lab environments
- Do NOT expose port 9999 to the public internet
- Consider adding authentication for production-like demos

### Recommended Security Measures

1. **Firewall**: Only allow port 9999 from your Windows machine's IP
   ```bash
   sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.1.X/32" port port=9999 protocol=tcp accept'
   ```

2. **Network Isolation**: Use a dedicated lab network

3. **Time Limits**: Don't leave the relay running indefinitely
   ```bash
   # Auto-stop after 1 hour
   timeout 3600 python3 external-attack-relay.py
   ```

## Alternative: Direct Suricata Monitoring

If you want Suricata to monitor actual traffic from Windows → Alma Linux without a relay, you need to change the Docker setup:

### Option 1: Host Network Mode

Modify `docker-compose.yml`:

```yaml
suricata:
  network_mode: host  # Add this
  # Remove the networks section
```

Then Suricata can monitor the host's network interfaces directly.

### Option 2: Pass-through Traffic

Set up a reverse proxy on Alma Linux that forwards traffic through Suricata:

```
Windows ──► Alma Linux:8080 (nginx) ──► Suricata Container:80
                                              │
                                              └── Suricata sees it
```

### Option 3: External Test Site

Attack external test sites that the victim will access:

```python
# On Windows, trigger victim to access test site
curl http://<VICTIM_IP>:5000/trigger?url=http://testmynids.org/
```

But this requires modifying the victim to have a web service.

## Summary

The **Attack Relay** solution:
- ✅ Allows Windows attackers to trigger Suricata alerts
- ✅ No changes needed to Docker networking
- ✅ Works with existing SOC stack configuration
- ✅ Provides immediate visual feedback
- ✅ Easy to set up and use

**Trade-off**: The attacks appear to come from the victim (outbound) rather than from the Windows machine (inbound), but this still demonstrates Suricata's detection capabilities effectively.

## Files Reference

```
poc-demo/
├── attacker-scripts/
│   ├── external-attack-relay.py      # Run on Alma Linux (victim)
│   ├── windows-attack-client.py      # Run on Windows (attacker)
│   ├── windows-attacker.py           # Alternative direct script
│   └── windows-attacker.ps1          # PowerShell version
├── run-attack-client.bat             # Windows batch launcher
└── docs/
    └── EXTERNAL-ATTACKS.md           # This file
```

## Next Steps

1. ✅ Start SOC stack on Alma Linux
2. ✅ Start relay on Alma Linux
3. ✅ Open firewall port 9999
4. ✅ Run client on Windows
5. ✅ View alerts in Kibana
6. 🎬 Record your demo video!

---

**Need Help?**

- Check relay logs on Alma Linux
- Run `demo-check.sh` to verify SOC stack health
- Ensure both machines are on the same network
- Verify Python 3.7+ is installed on Windows

Happy demo! 🎯
