import urllib.request
import urllib.error
import socket
import time
import argparse

def print_status(msg, status="INFO"):
    colors = {
        "INFO": "\033[96m",   # Cyan
        "SUCCESS": "\033[92m",# Green
        "WARNING": "\033[93m",# Yellow
        "ERROR": "\033[91m"   # Red
    }
    reset = "\033[0m"
    print(f"{colors.get(status, '')}[{status}] {msg}{reset}")

def send_http_attack(target_ip, port, path, headers, description):
    url = f"http://{target_ip}:{port}{path}"
    print_status(f"Testing: {description}", "INFO")
    print_status(f"  -> Payload: {url}", "INFO")
    
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=5) as response:
            print_status(f"  -> Trạng thái: {response.status} (Gửi thành công)", "SUCCESS")
    except urllib.error.HTTPError as e:
        print_status(f"  -> Trạng thái: {e.code} (Máy chủ phản hồi lỗi - Bình thường)", "WARNING")
    except Exception as e:
        print_status(f"  -> Lỗi kết nối: {e}", "ERROR")
    time.sleep(0.5)

def simulate_ssh_bruteforce(target_ip):
    print_status("Testing: SSH Protocol Anomaly / Brute-force (Kích hoạt Wazuh)", "INFO")
    for i in range(5):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2)
            s.connect((target_ip, 22))
            # Gửi payload rác để tạo log lỗi xác thực trên Linux
            s.sendall(b"root\x00malicious_login_attempt\r\n")
            s.recv(1024)
            s.close()
            print_status(f"  -> [Lần {i+1}/5] Đã bơm payload rác vào cổng 22", "WARNING")
        except Exception as e:
            print_status(f"  -> [Lần {i+1}/5] Lỗi kết nối SSH: {e}", "ERROR")
        time.sleep(0.5)

def main():
    parser = argparse.ArgumentParser(description="Script giả lập tấn công từ Windows vào SOC VM")
    parser.add_argument("target_ip", help="Địa chỉ IP của máy ảo AlmaLinux")
    args = parser.parse_args()

    ip = args.target_ip
    
    print("=" * 60)
    print(f" BẮT ĐẦU TẤN CÔNG TỪ WINDOWS VÀO ALMALINUX ({ip})")
    print("=" * 60)

    # 1. Kích hoạt Suricata (HTTP Web Attacks nhắm vào cổng 5000)
    http_attacks = [
        {
            "desc": "ET SCAN - Quét bằng Nikto",
            "path": "/",
            "headers": {"User-Agent": "Nikto/2.1.6"}
        },
        {
            "desc": "ET SCAN - Quét bằng Nmap Scripting Engine",
            "path": "/",
            "headers": {"User-Agent": "Mozilla/5.0 (compatible; Nmap Scripting Engine)"}
        },
        {
            "desc": "ET WEB_SERVER - SQL Injection",
            "path": "/?id=1%27%20UNION%20SELECT%20NULL,NULL--",
            "headers": {"User-Agent": "Mozilla/5.0"}
        },
        {
            "desc": "ET WEB_SERVER - Cross-Site Scripting (XSS)",
            "path": "/?search=%3Cscript%3Ealert(1)%3C/script%3E",
            "headers": {"User-Agent": "Mozilla/5.0"}
        },
        {
            "desc": "ET WEB_SERVER - Path Traversal (Đọc file nhạy cảm)",
            "path": "/../../../etc/passwd",
            "headers": {"User-Agent": "Mozilla/5.0"}
        }
    ]

    for attack in http_attacks:
        send_http_attack(ip, 5000, attack["path"], attack["headers"], attack["desc"])

    print("\n")
    
    # 2. Kích hoạt Wazuh (SSH Brute Force)
    simulate_ssh_bruteforce(ip)

    print("=" * 60)
    print(" Hoàn tất! Hãy kiểm tra Kibana và Wazuh Dashboard trên AlmaLinux.")
    print("=" * 60)

if __name__ == "__main__":
    main()