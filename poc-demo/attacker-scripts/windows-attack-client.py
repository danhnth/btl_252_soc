#!/usr/bin/env python3
"""
windows-attack-client.py
=======================
Run this ON THE WINDOWS ATTACKER MACHINE.

This script connects to the attack relay running on the Alma Linux victim
and triggers attack scenarios that will generate Suricata alerts.

The attack flow:
1. You run this script on Windows
2. It sends attack commands to the relay on Alma Linux
3. The relay executes the attacks FROM INSIDE the Suricata container
4. Suricata sees the outbound traffic and generates alerts
5. Alerts appear in Kibana/Elasticsearch

Usage:
    python windows-attack-client.py <VICTIM_IP> [OPTIONS]

Examples:
    # Quick demo (few attacks)
    python windows-attack-client.py 192.168.1.100 --quick

    # Full demo (all attacks)
    python windows-attack-client.py 192.168.1.100 --all

    # Specific scenario
    python windows-attack-client.py 192.168.1.100 --scenario sqlmap

    # List available scenarios
    python windows-attack-client.py 192.168.1.100 --list

Prerequisites on Alma Linux:
    - SOC stack must be running
    - external-attack-relay.py must be running on the victim
"""

import argparse
import json
import sys
import time
import urllib.request
import urllib.error
from typing import Dict, List, Optional

# Colors for Windows terminal
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


def print_banner():
    """Print startup banner"""
    print(f"{Colors.CYAN}{Colors.BOLD}")
    print("=" * 70)
    print("  WINDOWS ATTACK CLIENT - SURICATA DEMO")
    print("=" * 70)
    print(f"{Colors.ENDC}")
    print()
    print("This script triggers attacks through the victim's relay")
    print("to generate Suricata alerts visible in Kibana.")
    print()


def print_success(msg: str):
    print(f"{Colors.GREEN}[SUCCESS]{Colors.ENDC} {msg}")


def print_info(msg: str):
    print(f"{Colors.CYAN}[INFO]{Colors.ENDC} {msg}")


def print_warning(msg: str):
    print(f"{Colors.YELLOW}[WARNING]{Colors.ENDC} {msg}")


def print_error(msg: str):
    print(f"{Colors.RED}[ERROR]{Colors.ENDC} {msg}")


def print_section(title: str):
    print()
    print(f"{Colors.YELLOW}{Colors.BOLD}[*] {title}{Colors.ENDC}")
    print(f"{Colors.YELLOW}{'-' * (len(title) + 4)}{Colors.ENDC}")


class AttackClient:
    """Client for communicating with the attack relay"""
    
    def __init__(self, victim_ip: str, relay_port: int = 9999):
        self.victim_ip = victim_ip
        self.relay_port = relay_port
        self.base_url = f"http://{victim_ip}:{relay_port}"
        self.scenarios = []
    
    def check_health(self) -> bool:
        """Check if the relay is accessible"""
        try:
            req = urllib.request.Request(
                f"{self.base_url}/health",
                method='GET'
            )
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    return True
        except Exception as e:
            print_error(f"Cannot connect to relay: {e}")
        return False
    
    def list_scenarios(self) -> Optional[Dict]:
        """Get list of available scenarios from relay"""
        try:
            req = urllib.request.Request(
                f"{self.base_url}/scenarios",
                method='GET'
            )
            with urllib.request.urlopen(req, timeout=10) as response:
                if response.status == 200:
                    return json.loads(response.read().decode('utf-8'))
        except Exception as e:
            print_error(f"Failed to get scenarios: {e}")
        return None
    
    def trigger_attack(self, scenario: str) -> Optional[Dict]:
        """Trigger an attack scenario"""
        try:
            data = json.dumps({"scenario": scenario}).encode('utf-8')
            req = urllib.request.Request(
                f"{self.base_url}/attack",
                data=data,
                headers={'Content-Type': 'application/json'},
                method='POST'
            )
            with urllib.request.urlopen(req, timeout=60) as response:
                if response.status == 200:
                    return json.loads(response.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            print_error(f"HTTP Error {e.code}: {e.read().decode('utf-8')}")
        except Exception as e:
            print_error(f"Failed to trigger attack: {e}")
        return None


def print_attack_results(results: Dict):
    """Print attack execution results"""
    if "scenario" in results:
        print_success(f"Executed: {results.get('description', results['scenario'])}")
        
        if "commands_executed" in results:
            success_count = sum(1 for cmd in results["commands_executed"] if cmd.get("success"))
            total_count = len(results["commands_executed"])
            print_info(f"Commands: {success_count}/{total_count} successful")
    
    if "scenarios" in results:
        print()
        print(f"{Colors.BOLD}Executed {len(results['scenarios'])} scenarios:{Colors.ENDC}")
        for scenario in results["scenarios"]:
            print(f"  - {scenario.get('description', scenario['scenario'])}")


def run_quick_demo(client: AttackClient):
    """Run a quick demo with key scenarios"""
    print_section("QUICK DEMO MODE")
    
    quick_scenarios = ["ids-test", "sqlmap", "nikto", "sql-injection"]
    
    print_info(f"Running {len(quick_scenarios)} attack scenarios...")
    print()
    
    for scenario in quick_scenarios:
        print_info(f"Triggering: {scenario}")
        results = client.trigger_attack(scenario)
        if results:
            print_attack_results(results)
        else:
            print_error(f"Failed to execute {scenario}")
        time.sleep(1)
    
    print()
    print_success("Quick demo completed!")


def run_full_demo(client: AttackClient):
    """Run all attack scenarios"""
    print_section("FULL DEMO MODE")
    
    print_info("Running ALL attack scenarios...")
    print_info("This will take approximately 2-3 minutes")
    print()
    
    results = client.trigger_attack("all")
    
    if results and "scenarios" in results:
        print()
        print_success(f"Completed {len(results['scenarios'])} scenarios")
        
        # Calculate totals
        total_commands = 0
        successful_commands = 0
        
        for scenario in results["scenarios"]:
            for cmd in scenario.get("commands_executed", []):
                total_commands += 1
                if cmd.get("success"):
                    successful_commands += 1
        
        print_info(f"Total commands executed: {successful_commands}/{total_commands}")
    else:
        print_error("Full demo failed")


def run_specific_scenario(client: AttackClient, scenario: str):
    """Run a specific attack scenario"""
    print_section(f"RUNNING SCENARIO: {scenario}")
    
    results = client.trigger_attack(scenario)
    
    if results:
        print_attack_results(results)
    else:
        print_error(f"Failed to execute scenario: {scenario}")


def check_alerts_elasticsearch(victim_ip: str):
    """Check Suricata alerts in Elasticsearch"""
    print_section("CHECKING SURICATA ALERTS")
    
    print_info("Note: It may take 15-30 seconds for alerts to appear in Elasticsearch")
    print_info("Checking Kibana at: " + f"{Colors.CYAN}http://{victim_ip}:5601{Colors.ENDC}")
    print()
    
    print("To view alerts manually:")
    print(f"  1. Open: http://{victim_ip}:5601")
    print("  2. Navigate to: Analytics → Discover")
    print("  3. Select: suricata-ids-*")
    print("  4. Filter: event_type : alert")


def main():
    parser = argparse.ArgumentParser(
        description='Windows Attack Client for Suricata Demo',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Quick demo (recommended for first run)
  python windows-attack-client.py 192.168.1.100 --quick
  
  # Full demo (all attack scenarios)
  python windows-attack-client.py 192.168.1.100 --all
  
  # Specific scenario
  python windows-attack-client.py 192.168.1.100 --scenario sqlmap
  
  # List available scenarios
  python windows-attack-client.py 192.168.1.100 --list
        """
    )
    
    parser.add_argument('victim_ip', help='IP address of the Alma Linux victim')
    parser.add_argument('--port', type=int, default=9999,
                        help='Relay port on victim (default: 9999)')
    parser.add_argument('--quick', action='store_true',
                        help='Quick demo with key scenarios')
    parser.add_argument('--all', action='store_true',
                        help='Run all attack scenarios')
    parser.add_argument('--scenario', type=str,
                        help='Run specific scenario by name')
    parser.add_argument('--list', action='store_true',
                        help='List available scenarios and exit')
    parser.add_argument('--wait', type=int, default=15,
                        help='Seconds to wait before checking alerts (default: 15)')
    
    args = parser.parse_args()
    
    print_banner()
    
    # Initialize client
    client = AttackClient(args.victim_ip, args.port)
    
    print_info(f"Victim IP: {args.victim_ip}")
    print_info(f"Relay Port: {args.port}")
    print()
    
    # Check if relay is accessible
    print_info("Checking connection to attack relay...")
    if not client.check_health():
        print()
        print_error("Cannot connect to attack relay!")
        print()
        print("Please ensure:")
        print(f"  1. The relay is running on the victim ({args.victim_ip})")
        print("  2. On Alma Linux, run: python3 external-attack-relay.py")
        print("  3. Firewall allows port 9999/tcp")
        print()
        print("To start the relay on Alma Linux:")
        print(f"  cd ~/btl_252_soc/poc-demo/attacker-scripts")
        print(f"  python3 external-attack-relay.py")
        sys.exit(1)
    
    print_success("Connected to attack relay")
    print()
    
    # List scenarios if requested
    if args.list:
        print_section("AVAILABLE ATTACK SCENARIOS")
        scenarios = client.list_scenarios()
        if scenarios:
            for name, description in scenarios.items():
                print(f"  {Colors.CYAN}{name:20}{Colors.ENDC} - {description}")
        else:
            print_error("Failed to retrieve scenario list")
        print()
        return
    
    # Run requested demo mode
    if args.quick:
        run_quick_demo(client)
    elif args.all:
        run_full_demo(client)
    elif args.scenario:
        run_specific_scenario(client, args.scenario)
    else:
        # Default to quick demo
        print_info("No mode specified, running quick demo...")
        run_quick_demo(client)
    
    print()
    print("=" * 70)
    print()
    
    # Wait and check for alerts
    print_info(f"Waiting {args.wait} seconds for alerts to be processed...")
    time.sleep(args.wait)
    
    check_alerts_elasticsearch(args.victim_ip)
    
    print()
    print(f"{Colors.GREEN}{Colors.BOLD}Demo completed successfully!{Colors.ENDC}")
    print()


if __name__ == '__main__':
    main()
