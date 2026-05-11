# Security Operations Center (SOC)

🌐 **Languages:** [English](README.md) | [Tiếng Việt](README-vi.md)

SOC stack mã nguồn mở sử dụng Suricata IDS, Elasticsearch, Kibana, Wazuh SIEM và Filebeat - triển khai hoàn toàn bằng Docker Compose.”

---

## Table of Contents

- [Tổng quan](#tổng-quan)
- [Kiến trúc](#kiến-trúc)
- [Yêu cầu hệ thống](#yêu-cầu-hệ-thống)
- [Bắt đầu nhanh](#bắt-đầu-nhanh)
- [Cài đặt](#cài-đặt)
  - [Windows](#windows-docker-desktop)
  - [Linux](#linux-docker-engine)
- [Cấu hình](#cấu-hình)
- [Sử dụng](#sử-dụng)
- [Tham khảo Script](#tham-khảo-script)
- [Kịch bản tấn công & Kiểm thử](#kịch-bản-tấn-công--kiểm-thử)
- [Xử lý sự cố](#xử-lý-sự-cố)
- [Cấu trúc dự án](#cấu-trúc-dự-án)

---

## Tổng quan

| Thành phần | Vai trò |
|---|---|
| **Suricata** | Hệ thống phát hiện xâm nhập mạng (IDS) — 31.800+ quy tắc ET |
| **Elasticsearch** | Lưu trữ và tìm kiếm log |
| **Kibana** | Bảng điều khiển và trực quan hóa |
| **Wazuh** | SIEM dựa trên host |
| **Filebeat** | Vận chuyển log |
| **Signature Service** | Xác minh tính toàn vẹn log bằng HMAC/RSA |

---

## Kiến trúc

```
Suricata (IDS) ──► eve.json ──►┐
                               Filebeat ──► Elasticsearch ──► Kibana
Wazuh (SIEM)  ──► alerts  ──►┘
                               Signature Service (tính toàn vẹn HMAC)
```

Tất cả các dịch vụ giao tiếp qua mạng bridge Docker `soc-net` với TLS 1.3.

---

## Yêu cầu hệ thống

| | Tối thiểu | Khuyến nghị |
|---|---|---|
| CPU | 4 nhân | 8 nhân |
| RAM | 8 GB | 16 GB |
| Ổ đĩa | 50 GB | 100 GB SSD |

**Phần mềm:**
- Docker Desktop (Windows) hoặc Docker Engine (Linux)
- Git Bash hoặc WSL 2 (chỉ Windows)

---

## Bắt đầu nhanh

```bash
cd soc-project
bash setup.sh
```

Script `setup.sh` sẽ:
1. Tạo `.env` từ `.env.example` (nếu chưa có)
2. Tạo chứng chỉ TLS cho Elasticsearch
3. Tạo mạng Docker
4. Khởi động tất cả dịch vụ
5. Tự động thiết lập thông tin xác thực Kibana

Chờ ~60 giây, sau đó truy cập Kibana tại http://localhost:5601

---

## Cài đặt

### Windows (Docker Desktop)

#### Điều kiện tiên quyết

1. **Cài đặt Docker Desktop**
   - Tải từ <https://www.docker.com/products/docker-desktop/>
   - Trong quá trình cài đặt, bật **WSL 2 backend** (khuyến nghị)
   - Sau khi cài đặt, mở Docker Desktop và đợi engine khởi động

2. **Thiết lập bộ nhớ Docker tối thiểu 8 GB**
   Docker Desktop → Settings → Resources → Memory → `8 GB`

3. **Cài đặt Git Bash** (để chạy script `.sh`)
   - Đi kèm với [Git for Windows](https://git-scm.com/download/win)
   - Hoặc sử dụng terminal WSL 2

#### Cài đặt

Mở **Git Bash** hoặc **WSL 2** terminal:

```bash
# 1. Chuyển đến thư mục dự án
cd /c/path/to/btl_252_soc

# 2. Chạy script thiết lập tự động
bash soc-project/setup.sh
```

Script thiết lập tự động xử lý mọi thứ:
- Tạo `.env` từ template
- Tạo chứng chỉ TLS
- Tạo mạng Docker
- Khởi động stack
- Thiết lập thông tin xác thực Kibana

Chờ ~60 giây sau khi thiết lập hoàn tất, sau đó truy cập:
- **Kibana**: http://localhost:5601 (elastic / mật khẩu từ `.env`)

#### Chạy script trên Windows

Tất cả script yêu cầu shell bash. Sử dụng:

- **Git Bash** — click chuột phải thư mục → *Git Bash Here*
- **WSL 2** terminal

```bash
# Từ thư mục gốc dự án
bash scripts/setup/check-stack.sh      # Kiểm tra sức khỏe
bash scripts/attacks/generate-alerts.sh # Tạo cảnh báo thử nghiệm
bash scripts/tests/verify-stack.sh      # Kiểm thử khói
```

---

### Linux (Docker Engine)

#### Điều kiện tiên quyết

**Ubuntu / Debian:**
```bash
# Gỡ bỏ phiên bản cũ
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Cài đặt Docker Engine
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Chạy Docker không cần sudo
sudo usermod -aG docker $USER && newgrp docker
```

**RHEL / Rocky / AlmaLinux:**
```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER && newgrp docker
```

**Điều chỉnh kernel** (Elasticsearch cần):
```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

#### Cài đặt

```bash
# 1. Chuyển đến dự án
cd /path/to/btl_252_soc

# 2. Sửa quyền sở hữu thư mục
sudo chown -R $USER:$USER soc-project/data/ soc-project/logs/ 2>/dev/null || true

# 3. Chạy thiết lập tự động
bash soc-project/setup.sh
```

Chờ ~60 giây sau khi thiết lập hoàn tất, sau đó truy cập:
- **Kibana**: http://localhost:5601

#### Chạy script

```bash
chmod +x scripts/setup/*.sh scripts/attacks/*.sh scripts/tests/*.sh

bash scripts/setup/check-stack.sh
bash scripts/attacks/generate-alerts.sh
bash scripts/tests/verify-stack.sh
```

---

## Cấu hình

Chỉnh sửa `soc-project/.env`.  
**Không bao giờ commit file này** — nó chứa thông tin bí mật.

| Biến | Mặc định | Mô tả |
|---|---|---|
| `ELASTICSEARCH_PASSWORD` | `changeme123` | Mật khẩu superuser Elastic |
| `KIBANA_SYSTEM_PASSWORD` | `changeme123` | Người dùng nội bộ Kibana |
| `WAZUH_ADMIN_PASSWORD` | `ChangeMeWazuh123#` | Mật khẩu admin API Wazuh |
| `KIBANA_ENCRYPTION_KEY` | *(chuỗi ngẫu nhiên)* | Khóa mã hóa đối tượng đã lưu |
| `HMAC_SECRET` | `soc-hmac-secret-key-2024-production-change-me` | Khóa bí mật HMAC dịch vụ chữ ký |
| `ES_JAVA_OPTS` | `-Xms512m -Xmx512m` | Heap JVM Elasticsearch |
| `ELASTIC_VERSION` | `8.12.0` | Phiên bản ELK Stack |

**Điều chỉnh bộ nhớ:**
```env
ES_JAVA_OPTS=-Xms1g -Xmx1g   # Hệ thống 8 GB
ES_JAVA_OPTS=-Xms2g -Xmx2g   # Hệ thống 16 GB
ES_JAVA_OPTS=-Xms4g -Xmx4g   # Hệ thống 32 GB
```

---

## Sử dụng

### URL Dịch vụ

| Dịch vụ | URL | Thông tin xác thực |
|---|---|---|
| Kibana | http://localhost:5601 | `elastic` / `ELASTICSEARCH_PASSWORD` |
| Elasticsearch | https://localhost:9200 | `elastic` / `ELASTICSEARCH_PASSWORD` |
| Wazuh API | https://localhost:55000 | `admin` / `WAZUH_ADMIN_PASSWORD` |
| Signature Service | http://localhost:5000/health | — |

### Thiết lập Kibana lần đầu

```bash
# Tự động — tạo tất cả data view:
bash scripts/setup/setup-kibana.sh
```

Hoặc thủ công trong giao diện Kibana:  
☰ → **Stack Management** → **Data Views** → **Create data view**

| Data View | Mẫu index | Trường thời gian |
|---|---|---|
| Suricata IDS | `suricata-ids-*` | `@timestamp` |
| Wazuh Alerts | `wazuh-alerts-*` | `@timestamp` |
| Filebeat Logs | `filebeat-*` | `@timestamp` |

### Xem cảnh báo

1. Mở Kibana → ☰ → **Analytics** → **Discover**
2. Chọn index pattern `suricata-ids-*`
3. Lọc: `event_type : alert`

### Thao tác thường dùng

```bash
# Khởi động tất cả dịch vụ
cd soc-project && docker-compose up -d

# Dừng tất cả dịch vụ
docker-compose stop

# Khởi động lại dịch vụ cụ thể
docker-compose restart kibana

# Xem log theo thời gian thực
docker-compose logs -f filebeat

# Xóa hoàn toàn (⚠ xóa toàn bộ dữ liệu)
docker-compose down -v
rm -rf soc-project/data/ soc-project/logs/
bash soc-project/setup.sh
```

---

## Tham khảo Script

Tất cả script nằm trong `scripts/` tại thư mục gốc dự án.

```
scripts/
├── setup/
│   ├── setup-kibana.sh              # Tạo data view Kibana
│   ├── check-stack.sh               # Tóm tắt sức khỏe có màu
│   └── fix-elasticsearch-certs.sh   # Sửa quyền chứng chỉ SSL
├── attacks/
│   ├── generate-alerts.sh           # Tạo cảnh báo IDS với output có màu
│   └── attack-scenarios.py          # Mô phỏng tấn công Python (10 kịch bản)
└── tests/
    └── verify-stack.sh              # Kiểm thử khói — exit 0 khi pass
```

### `soc-project/setup.sh`

**Thiết lập một lệnh** — tạo chứng chỉ, tạo mạng, khởi động stack, thiết lập Kibana.

```bash
cd soc-project
bash setup.sh
```

### `scripts/setup/setup-kibana.sh`

Tạo data view Kibana. Chạy một lần sau khi stack khởi động.

```bash
bash scripts/setup/setup-kibana.sh
```

### `scripts/setup/check-stack.sh`

Tóm tắt sức khỏe có màu hiển thị:
- Trạng thái container với chỉ báo sức khỏe
- Sức khỏe cluster Elasticsearch
- Số lượng cảnh báo Suricata
- Top 5 chữ ký cảnh báo
- Sức khỏe index

```bash
bash scripts/setup/check-stack.sh
```

### `scripts/setup/fix-elasticsearch-certs.sh`

Sửa lỗi quyền chứng chỉ SSL:
```
SslConfigException: not permitted to read the PEM private key file
```

```bash
# Tự động phát hiện và sửa
sudo bash scripts/setup/fix-elasticsearch-certs.sh

# Chỉ định đường dẫn thủ công
sudo bash scripts/setup/fix-elasticsearch-certs.sh /path/to/certs
```

### `scripts/attacks/generate-alerts.sh`

Tạo cảnh báo IDS với **output có màu** và chỉ báo tiến trình.

```bash
bash scripts/attacks/generate-alerts.sh           # Toàn bộ (~6 kịch bản)
bash scripts/attacks/generate-alerts.sh --quick   # Chỉ kịch bản nhanh
```

Các kịch bản bao gồm:
- Kiểm tra phát hiện IDS (GPL ATTACK_RESPONSE)
- Mô phỏng tải xuống malware (ET MALWARE)
- Phát hiện trình quét bảo mật (sqlmap, Nikto, Nmap)
- Tra cứu domain xấu
- Vi phạm chính sách
- Lưu lượng burst

### `scripts/attacks/attack-scenarios.py`

Mô phỏng tấn công Python chi tiết với 10 kịch bản.

```bash
# Liệt kê tất cả kịch bản
python3 scripts/attacks/attack-scenarios.py --list

# Chạy một kịch bản
python3 scripts/attacks/attack-scenarios.py --scenario sqlmap

# Chạy tất cả, 3 lần mỗi kịch bản
python3 scripts/attacks/attack-scenarios.py --count 3

# Chạy từ trong Suricata (khuyến nghị)
docker cp scripts/attacks/attack-scenarios.py soc-suricata:/tmp/
docker exec soc-suricata python3 /tmp/attack-scenarios.py
```

Các kịch bản khả dụng: `ids-test`, `sqlmap`, `nikto`, `nmap`, `malware-dl`, `sql-injection`, `xss`, `path-traversal`, `policy-curl`, `burst`

### `scripts/tests/verify-stack.sh`

Kiểm thử khói end-to-end. Kiểm tra tất cả dịch vụ và exit `0` khi pass.

```bash
bash scripts/tests/verify-stack.sh
```

---

## Kịch bản tấn công & Kiểm thử

### Tại sao lưu lượng phải xuất phát từ trong Suricata

Mạng bridge Docker cấp cho mỗi container namespace mạng riêng. Suricata chỉ thấy gói tin trên `eth0` của nó — **không** thấy lưu lượng giữa các container khác trên cùng bridge.

**Giải pháp**: tạo yêu cầu HTTP outbound **từ bên trong** container Suricata. Các gói tin đi qua `eth0`, Suricata kiểm tra chúng theo thời gian thực, và cảnh báo được ghi vào `eve.json`, vận chuyển bởi Filebeat đến Elasticsearch.

### Demo nhanh

```bash
# 1. Khởi động stack
cd soc-project
bash setup.sh

# 2. Chờ ~60s để khởi tạo, sau đó kiểm tra
bash ../scripts/setup/check-stack.sh

# 3. Thiết lập data view Kibana
bash ../scripts/setup/setup-kibana.sh

# 4. Tạo các cảnh báo đa dạng
bash ../scripts/attacks/generate-alerts.sh

# 5. Chạy kiểm thử khói
bash ../scripts/tests/verify-stack.sh

# 6. Kiểm tra tóm tắt cảnh báo
bash ../scripts/setup/check-stack.sh

# 7. Mở Kibana → Discover → suricata-ids-*
```

### Mức độ nghiêm trọng cảnh báo

| Mức độ | Cấp độ | Ví dụ |
|---|---|---|
| 1 | Nghiêm trọng | Malware C2, exploit kit |
| 2 | Cao | Phát hiện trình quét, phản hồi tấn công |
| 3 | Trung bình | Vi phạm chính sách, user-agent đáng ngờ |

---

## Xử lý sự cố

### Elasticsearch không khởi động (exit code 137 / OOM)

Giảm heap JVM trong `soc-project/.env`:
```env
ES_JAVA_OPTS=-Xms512m -Xmx512m
```

### Elasticsearch không khởi động — Lỗi quyền SSL

```bash
sudo bash scripts/setup/fix-elasticsearch-certs.sh
```

### Linux: `max virtual memory areas too low`

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### Kibana không healthy — "unable to authenticate kibana_system"

Chạy thiết lập bootstrap thủ công:

```bash
cd soc-project
source .env

docker exec soc-elasticsearch curl -sk -X POST \
  -u "elastic:${ELASTICSEARCH_PASSWORD}" \
  "https://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${KIBANA_SYSTEM_PASSWORD}\"}"

docker-compose restart kibana
```

### Kibana hiển thị "server is not ready yet"

Chờ 3–5 phút. Nếu vẫn lỗi:
```bash
docker-compose restart kibana
docker-compose logs kibana | tail -30
```

### Filebeat khởi động lại liên tục

```bash
docker-compose logs filebeat | tail -20
```

Kiểm tra đường dẫn chứng chỉ TLS và kết nối ES:
```bash
cd soc-project && source .env
docker exec soc-elasticsearch curl -sk -u "elastic:${ELASTICSEARCH_PASSWORD}" https://localhost:9200
```

### Không có cảnh báo trong Kibana

```bash
# 1. Tạo lưu lượng thử nghiệm
bash scripts/attacks/generate-alerts.sh

# 2. Kiểm tra eve.json
docker exec soc-suricata sh -c "grep '\"event_type\":\"alert\"' /var/log/suricata/eve.json | wc -l"

# 3. Kiểm tra Filebeat đang gửi
docker-compose logs filebeat | grep -i "Events published"
```

### Cổng đã được sử dụng

```bash
# Windows (PowerShell)
netstat -ano | findstr :5601

# Linux
sudo lsof -i :5601
```

Thay đổi cổng trong `docker-compose.yml`:
```yaml
ports:
  - "5602:5601"   # host:container
```

### Xóa hoàn toàn

```bash
cd soc-project
docker-compose down -v
rm -rf data/ logs/
docker network rm soc-net
bash setup.sh
```

---

## Cấu trúc dự án

```
btl_252_soc/
├── README.md                        # File này
├── README-vi.md                     # Bản tiếng Việt
├── assignment.md                    # Bài tập gốc (tiếng Việt)
│
├── docs/
│   ├── Architecture-Diagram.md      # Kiến trúc hệ thống chi tiết
│   ├── SOC-Concept.md               # Lý thuyết và cơ bản SOC
│   └── Tool-Comparison.md           # Lý do chọn các công cụ
│
├── scripts/
│   ├── setup/
│   │   ├── setup-kibana.sh          # Tạo data view Kibana
│   │   ├── check-stack.sh           # Tóm tắt sức khỏe có màu
│   │   └── fix-elasticsearch-certs.sh  # Sửa quyền SSL
│   ├── attacks/
│   │   ├── generate-alerts.sh       # Tạo cảnh báo bằng shell
│   │   └── attack-scenarios.py      # Mô phỏng tấn công Python
│   └── tests/
│       └── verify-stack.sh          # Bộ kiểm thử khói
│
└── soc-project/                     # Thư mục triển khai Docker
    ├── setup.sh                     # ⭐ Thiết lập tự động một lệnh
    ├── docker-compose.yml
    ├── .env                         # Bí mật — không bao giờ commit
    ├── .env.example                 # Template cho .env
    ├── certs/                       # Chứng chỉ TLS (tự động tạo)
    ├── elk/config/                  # Cấu hình Filebeat & Kibana
    ├── suricata/conf/               # Cấu hình Suricata & 31k+ quy tắc
    ├── wazuh/conf/                  # Cấu hình Wazuh SIEM
    ├── signature-service/           # Dịch vụ toàn vẹn log
    └── config/                      # Cấu hình OpenSearch dashboard
```

---

## Hạn chế đã biết

**Mạng bridge Docker** — Suricata không thể giám sát thụ động lưu lượng giữa các container. Đây là hạn chế kiến trúc Docker. Script `generate-alerts.sh` khắc phục bằng cách tạo lưu lượng từ bên trong container Suricata.

Trong production, triển khai Suricata với network TAP, SPAN port, hoặc host-network mode (chỉ Linux).

**Wazuh Dashboard** — Wazuh Dashboard (cổng 443) có thể hiển thị unhealthy do không tương thích phiên bản với Elasticsearch 8.x. Sử dụng Kibana cổng 5601 thay thế — hiển thị đầy đủ dữ liệu Wazuh.

---

## Hỗ trợ

- 🇬🇧 [View English version](README.md)
- 📁 [Tài liệu dự án](docs/)
- 🐛 [Báo cáo vấn đề](../../issues)

---

*Cập nhật lần cuối: Tháng 5/2026*
