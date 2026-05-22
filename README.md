# Spaceship Bulk NS Change

เปลี่ยน Nameservers ของโดเมนใน Spaceship แบบ Bulk ผ่าน API — ไม่ต้องเข้าหน้าเว็บไปใส่ทีละโดเมน

## Quick Run (ไม่ต้อง clone)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AnonymousVS/Spaceship-Bulk-NS-Change/main/bulk-ns-change.sh)
```

> ⚠️ ต้องมีไฟล์ `config.conf` และ `domains.txt` อยู่ใน directory ที่รันก่อน

## Installation

```bash
cd /usr/local/sbin/
git clone https://github.com/AnonymousVS/Spaceship-Bulk-NS-Change.git
cd Spaceship-Bulk-NS-Change
cp config.conf.example config.conf
chmod 600 config.conf
chmod +x bulk-ns-change.sh
```

แก้ไข `config.conf` ใส่ API Key:

```bash
nano config.conf
```

## Usage

**1. สร้างไฟล์โดเมน:**

```bash
nano domains.txt
```

ใส่โดเมน 1 ตัวต่อบรรทัด:

```
example1.com
example2.com
example3.com
```

**2. รัน:**

```bash
./bulk-ns-change.sh domains.txt
```

**Output:**

```
╔══════════════════════════════════════════════╗
║   Spaceship Bulk NS Change  v1.0.0          ║
╚══════════════════════════════════════════════╝

Domains: 24
NS1:     aria.ns.cloudflare.com
NS2:     bob.ns.cloudflare.com
Delay:   2s

[1/24]  ✅ example1.com → OK
[2/24]  ✅ example2.com → OK
[3/24]  ❌ example3.com → FAILED (domain not found)
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total:    24
  Success:  23
  Failed:   1
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Files

| File | Description |
|------|-------------|
| `bulk-ns-change.sh` | Script หลัก |
| `config.conf.example` | ตัวอย่าง config (copy → `config.conf`) |
| `domains.txt.example` | ตัวอย่างไฟล์โดเมน |
| `logs/` | Log ผลการทำงานแต่ละครั้ง |

## Config

| Key | Description |
|-----|-------------|
| `SPACESHIP_API_KEY` | API Key จาก [Spaceship API Manager](https://www.spaceship.com/application/api-manager/) |
| `SPACESHIP_API_SECRET` | API Secret |
| `NS1` | Nameserver ตัวที่ 1 |
| `NS2` | Nameserver ตัวที่ 2 |
| `DELAY` | Delay ระหว่างแต่ละโดเมน (วินาที, default: 2) |
| `TG_BOT_TOKEN` | Telegram Bot Token (optional) |
| `TG_CHAT_ID` | Telegram Chat ID (optional) |

## Spaceship API Key Setup

1. เข้า https://www.spaceship.com/application/api-manager/
2. กด **New API key**
3. Permissions ที่ต้องเปิด:
   - `domains:read`
   - `domains:write`
4. Copy API Key + Secret มาใส่ใน `config.conf`

## Rate Limit & Delay

Spaceship API มี rate limit:
- **5 requests ต่อโดเมน** ภายใน 300 วินาที (ไม่มีปัญหาเพราะยิงโดเมนละ 1 ครั้ง)
- **Global rate limit** — ป้องกันด้วย `DELAY` ระหว่างแต่ละโดเมน

Script มี **Smart Retry** ในตัว:
- ถ้าโดน HTTP 429 (rate limited) → รอแล้ว retry อัตโนมัติ สูงสุด 3 ครั้ง
- ใช้ Exponential Backoff: 4s → 8s → 16s → หยุด

## Requirements

- `curl`
- `jq`

ติดตั้ง jq (ถ้ายังไม่มี):

```bash
# AlmaLinux / RHEL
dnf install jq -y

# Ubuntu / Debian
apt install jq -y
```

## CHANGELOG

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-05-22 | Initial release |

## License

MIT
