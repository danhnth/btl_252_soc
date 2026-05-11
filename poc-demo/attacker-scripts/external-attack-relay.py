#!/usr/bin/env python3
"""
external-attack-relay.py
========================
Run this ON THE ALMA LINUX VICTIM to relay external attacks through Suricata.

PROBLEM: When attacking from Windows → Alma Linux directly, Suricata (in Docker)
can't see the traffic because Docker bridge networking isolates containers.

SOLUTION: This relay script receives attack commands from Windows, then executes
the actual HTTP requests FROM INSIDE the Suricata container, so Suricata sees
the outbound traffic on its eth0 interface.

Architecture:
Windows Attacker → Alma Linux (this relay) → Suricata Container → Internet
                                      ↑
                                 Suricata sees this!

Usage on Alma Linux:
    python3 external-attack-relay.py
    
Usage on Windows:
    # The relay exposes an API that Windows can call to trigger attacks
    # See windows-attack-client.py for the client-side script
"""

import json
import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import threading

# Configuration
RELAY_PORT = 9999
SURICATA_CONTAINER = "soc-suricata"

# Attack scenarios that trigger Suricata alerts
ATTACK_SCENARIOS = {
    "ids-test": {
        "description": "GPL ATTACK_RESPONSE - testmynids.org uid check",
        "commands": [
            f"docker exec {SURICATA_CONTAINER} curl -s -A 'curl/7.81.0' http://testmynids.org/uid/index.html"
        ]
    },
    "sqlmap": {
        "description": "ET SCAN - sqlmap scanner user-agent",
        "commands": [
            f"docker exec {SURICATA_CONTAINER} curl -s -A 'sqlmap/1.5.2-dev' http://testmynids.org/",
            f"docker exec {SURICATA_CONTAINER} curl -s -A 'sqlmap/1.5.2-dev' 'http://testmynids.org/?id=1%27%20OR%20%271%27%3D%271'"
        ]
    },
    "nikto": {
        "description": "ET SCAN - Nikto web scanner user-agent",
        "commands": [
            f"docker exec {SURICATA_CONTAINER} curl -s -A 'Nikto/2.1.6' http://testmynids.org/",
            f"docker exec {SURICATA_CONTAINER} curl -s -A 'Nikto/2.1.6' 'http://testmynids.org/../../etc/passwd'"
        ]
    },
    "nmap": {
        "description": "ET SCAN - Nmap Scripting Engine user-agent",
        "commands": [
            f"docker exec {SURICATA_CONTAINER} curl -s -A 'Mozilla/5.0 (compatible; Nmap Scripting Engine)' http://testmynids.org/"
        ]
    },
    "malware-dl": {
        "description": "ET MALWARE - terse executable downloader pattern",
        "commands": [
            f"docker exec {SURICATA_CONTAINER} curl -s -A 'Go-http-client/1.1' http://testmynids.org/uid/index.html",
            f"docker exec {SURICATA_CONTAINER} curl -s http://testmynids.org/a/b.exe || true"
        ]
    },
    "sql-injection": {
        "description": "ET WEB_SERVER - SQL injection in URL params",
        "commands": [
            f"docker exec {SURICATA_CONTAINER} curl -s 'http://testmynids.org/?id=1%27%20UNION%20SELECT%201,2,3--'",
            f"docker exec {SURICATA_CONTAINER} curl -s 'http://testmynids.org/?q=admin%27%20OR%201%3D1%3B--'"
        ]
    },
    "xss": {
        "description": "ET WEB_SERVER - Cross-Site Scripting pattern",
        "commands": [
            f"docker exec {SURICATA_CONTAINER} curl -s 'http://testmynids.org/?q=%3Cscript%3Ealert%28%27XSS%27%29%3C%2Fscript%3E'"
        ]
    },
    "path-traversal": {
        "description": "ET WEB_SERVER - Directory/path traversal",
        "commands": [
            f"docker exec {SURICATA_CONTAINER} curl -s 'http://testmynids.org/../../../etc/passwd'",
            f"docker exec {SURICATA_CONTAINER} curl -s 'http://testmynids.org/%2e%2e/%2e%2e/etc/shadow'"
        ]
    },
    "policy-curl": {
        "description": "ET POLICY - curl outbound user-agent",
        "commands": [
            f"docker exec {SURICATA_CONTAINER} curl -s -A 'curl/7.81.0' http://detectportal.firefox.com/"
        ]
    },
    "burst": {
        "description": "Rapid burst - 10 requests in quick succession",
        "commands": [
            f"docker exec {SURICATA_CONTAINER} sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do curl -s http://testmynids.org/uid/index.html >/dev/null; done'"
        ]
    },
    "all": {
        "description": "Run all attack scenarios",
        "commands": []  # Special case handled separately
    }
}


class AttackRelayHandler(BaseHTTPRequestHandler):
    """HTTP handler for attack relay API"""
    
    def log_message(self, format, *args):
        """Suppress default logging"""
        pass
    
    def do_GET(self):
        """Handle GET requests - status check"""
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {"status": "ok", "service": "suricata-attack-relay"}
            self.wfile.write(json.dumps(response).encode())
            return
        
        if parsed_path.path == '/scenarios':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            scenarios = {k: v["description"] for k, v in ATTACK_SCENARIOS.items()}
            self.wfile.write(json.dumps(scenarios).encode())
            return
        
        self.send_response(404)
        self.end_headers()
    
    def do_POST(self):
        """Handle POST requests - execute attacks"""
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/attack':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            
            try:
                data = json.loads(post_data.decode('utf-8'))
                scenario = data.get('scenario', 'ids-test')
                client_ip = self.client_address[0]
                
                print(f"[RELAY] Received attack request from {client_ip}: {scenario}")
                
                if scenario == 'all':
                    results = self.run_all_scenarios()
                elif scenario in ATTACK_SCENARIOS:
                    results = self.run_scenario(scenario)
                else:
                    self.send_response(400)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": f"Unknown scenario: {scenario}"}).encode())
                    return
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(results).encode())
                return
                
            except json.JSONDecodeError:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Invalid JSON"}).encode())
                return
        
        self.send_response(404)
        self.end_headers()
    
    def run_scenario(self, scenario_name):
        """Execute a single attack scenario"""
        scenario = ATTACK_SCENARIOS[scenario_name]
        results = {
            "scenario": scenario_name,
            "description": scenario["description"],
            "commands_executed": [],
            "success": True
        }
        
        print(f"[RELAY] Executing: {scenario['description']}")
        
        for cmd in scenario["commands"]:
            try:
                print(f"[RELAY] Running: {cmd[:80]}...")
                result = subprocess.run(
                    cmd,
                    shell=True,
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                results["commands_executed"].append({
                    "command": cmd,
                    "returncode": result.returncode,
                    "success": result.returncode == 0
                })
            except subprocess.TimeoutExpired:
                results["commands_executed"].append({
                    "command": cmd,
                    "error": "Timeout",
                    "success": False
                })
            except Exception as e:
                results["commands_executed"].append({
                    "command": cmd,
                    "error": str(e),
                    "success": False
                })
        
        print(f"[RELAY] Completed: {scenario_name}")
        return results
    
    def run_all_scenarios(self):
        """Execute all attack scenarios"""
        results = {
            "scenario": "all",
            "description": "All attack scenarios",
            "scenarios": []
        }
        
        for scenario_name in ATTACK_SCENARIOS:
            if scenario_name != 'all':
                scenario_results = self.run_scenario(scenario_name)
                results["scenarios"].append(scenario_results)
        
        return results


def print_banner():
    """Print startup banner"""
    print("=" * 70)
    print("  SURICATA EXTERNAL ATTACK RELAY")
    print("=" * 70)
    print()
    print("This server receives attack requests from external attackers")
    print("and relays them through the Suricata container so alerts")
    print("are properly generated.")
    print()
    print(f"Listening on port: {RELAY_PORT}")
    print()
    print("Available scenarios:")
    for name, scenario in ATTACK_SCENARIOS.items():
        print(f"  - {name:20} : {scenario['description']}")
    print()
    print("=" * 70)


def check_suricata():
    """Check if Suricata container is running"""
    try:
        result = subprocess.run(
            f"docker inspect --format '{{{{.State.Status}}}}' {SURICATA_CONTAINER}",
            shell=True,
            capture_output=True,
            text=True
        )
        if result.returncode == 0 and "running" in result.stdout:
            return True
    except:
        pass
    return False


def main():
    print_banner()
    
    # Check if Suricata container is running
    if not check_suricata():
        print("[ERROR] Suricata container is not running!")
        print(f"[ERROR] Please start the SOC stack first:")
        print(f"        cd ~/btl_252_soc/soc-project && docker compose up -d")
        sys.exit(1)
    
    print("[OK] Suricata container is running")
    print()
    
    # Start HTTP server
    server = HTTPServer(('0.0.0.0', RELAY_PORT), AttackRelayHandler)
    print(f"[INFO] Starting relay server on port {RELAY_PORT}...")
    print(f"[INFO] Windows attackers can now connect to this machine on port {RELAY_PORT}")
    print()
    print("[INFO] Press Ctrl+C to stop")
    print()
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[INFO] Shutting down relay server...")
        server.shutdown()


if __name__ == '__main__':
    main()
