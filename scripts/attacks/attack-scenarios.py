#!/usr/bin/env python3
"""
attack-scenarios.py
====================
Simulates diverse attack patterns to trigger Suricata IDS alerts.

IMPORTANT – Docker networking constraint:
  Traffic between host and containers does NOT traverse Suricata's eth0.
  Run this script **inside** the Suricata container for reliable detection:

      docker exec soc-suricata python3 /tmp/attack-scenarios.py

  Or use the shell wrapper:
      ./generate-alerts.sh

For Wazuh HIDS alerts (host-based detection), use:
      ./generate-wazuh-alerts.sh

Usage:
  python3 attack-scenarios.py [--scenario SCENARIO] [--list] [--count N]

  --scenario SCENARIO  Run only this scenario (see --list)
  --list               Print available scenarios and exit
  --count N            Repeat each scenario N times (default: 1)
"""

import argparse
import sys
import time
import urllib.request
import urllib.error

# ── Colour output ─────────────────────────────────────────────────────

def green(s):  return f"\033[92m{s}\033[0m"
def yellow(s): return f"\033[93m{s}\033[0m"
def red(s):    return f"\033[91m{s}\033[0m"
def cyan(s):   return f"\033[96m{s}\033[0m"


# ── Scenario definitions ──────────────────────────────────────────────

SCENARIOS = {
    "ids-test": {
        "description": "GPL ATTACK_RESPONSE – testmynids.org uid check",
        "requests": [
            {"url": "http://testmynids.org/uid/index.html",
             "headers": {"User-Agent": "curl/7.81.0"}},
        ],
    },
    "sqlmap": {
        "description": "ET SCAN – sqlmap scanner user-agent",
        "requests": [
            {"url": "http://testmynids.org/",
             "headers": {"User-Agent": "sqlmap/1.5.2-dev"}},
            {"url": "http://testmynids.org/?id=1%27%20OR%20%271%27%3D%271",
             "headers": {"User-Agent": "sqlmap/1.5.2-dev"}},
        ],
    },
    "nikto": {
        "description": "ET SCAN – Nikto web scanner user-agent",
        "requests": [
            {"url": "http://testmynids.org/",
             "headers": {"User-Agent": "Nikto/2.1.6"}},
            {"url": "http://testmynids.org/../../etc/passwd",
             "headers": {"User-Agent": "Nikto/2.1.6"}},
        ],
    },
    "nmap": {
        "description": "ET SCAN – Nmap Scripting Engine user-agent",
        "requests": [
            {"url": "http://testmynids.org/",
             "headers": {"User-Agent": "Mozilla/5.0 (compatible; Nmap Scripting Engine)"}},
        ],
    },
    "malware-dl": {
        "description": "ET MALWARE – terse executable downloader pattern",
        "requests": [
            {"url": "http://testmynids.org/uid/index.html",
             "headers": {"User-Agent": "Go-http-client/1.1"}},
        ],
    },
    "sql-injection": {
        "description": "ET WEB_SERVER – SQL injection in URL params",
        "requests": [
            {"url": "http://testmynids.org/?id=1%27%20UNION%20SELECT%201,2,3--",
             "headers": {"User-Agent": "Mozilla/5.0"}},
            {"url": "http://testmynids.org/?q=admin%27%20OR%201%3D1%3B--",
             "headers": {"User-Agent": "Mozilla/5.0"}},
        ],
    },
    "xss": {
        "description": "ET WEB_SERVER – Cross-Site Scripting pattern",
        "requests": [
            {"url": "http://testmynids.org/?q=%3Cscript%3Ealert%28%27XSS%27%29%3C%2Fscript%3E",
             "headers": {"User-Agent": "Mozilla/5.0"}},
        ],
    },
    "path-traversal": {
        "description": "ET WEB_SERVER – Directory/path traversal",
        "requests": [
            {"url": "http://testmynids.org/../../../etc/passwd",
             "headers": {"User-Agent": "Mozilla/5.0"}},
            {"url": "http://testmynids.org/%2e%2e/%2e%2e/etc/shadow",
             "headers": {"User-Agent": "Mozilla/5.0"}},
        ],
    },
    "policy-curl": {
        "description": "ET POLICY – curl outbound user-agent",
        "requests": [
            {"url": "http://detectportal.firefox.com/",
             "headers": {"User-Agent": "curl/7.81.0"}},
        ],
    },
    "burst": {
        "description": "Rapid burst – 10 requests in quick succession",
        "requests": [
            {"url": "http://testmynids.org/uid/index.html",
             "headers": {"User-Agent": "curl/7.81.0"}},
        ] * 10,
    },
}


# ── Runner ────────────────────────────────────────────────────────────

def run_request(req: dict) -> tuple[int, str]:
    """Fire a single HTTP request. Returns (status_code, error_message)."""
    try:
        request = urllib.request.Request(req["url"], headers=req.get("headers", {}))
        with urllib.request.urlopen(request, timeout=8) as resp:
            return resp.status, ""
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception as e:
        return 0, str(e)


def run_scenario(name: str, count: int = 1) -> bool:
    sc = SCENARIOS[name]
    print(cyan(f"\n[{name}] {sc['description']}"))
    success = True
    for iteration in range(count):
        if count > 1:
            print(f"  iteration {iteration + 1}/{count}")
        for req in sc["requests"]:
            label = req["url"][:70] + ("…" if len(req["url"]) > 70 else "")
            code, err = run_request(req)
            if err:
                print(f"  {yellow('→')} {label}  {yellow(f'[network error: {err}]')}")
                success = False
            else:
                status_str = green(str(code)) if 100 <= code < 500 else yellow(str(code))
                print(f"  {green('→')} {label}  [{status_str}]")
            time.sleep(0.3)
    return success


# ── CLI ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="SOC Attack Scenario Generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--scenario", help="Run a single scenario by name")
    parser.add_argument("--list",     action="store_true", help="List scenarios and exit")
    parser.add_argument("--count",    type=int, default=1, help="Repeat count per scenario")
    args = parser.parse_args()

    if args.list:
        print("Available scenarios:")
        for name, sc in SCENARIOS.items():
            print(f"  {name:<20} – {sc['description']}")
        sys.exit(0)

    print("=" * 60)
    print("  SOC Attack Scenario Generator")
    print("=" * 60)
    print("NOTE: Run this from inside soc-suricata for reliable alerts:")
    print("  docker exec soc-suricata python3 /tmp/attack-scenarios.py")
    print()

    targets = [args.scenario] if args.scenario else list(SCENARIOS)

    for name in targets:
        if name not in SCENARIOS:
            print(red(f"Unknown scenario: {name}"))
            sys.exit(1)
        run_scenario(name, args.count)

    print()
    print("=" * 60)
    print(green("All scenarios complete."))
    print("Check alerts with:")
    print("  bash scripts/setup/check-stack.sh")
    print("  Kibana → Discover → suricata-ids-*")
    print("=" * 60)


if __name__ == "__main__":
    main()
