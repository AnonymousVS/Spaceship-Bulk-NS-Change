# Spaceship Bulk NS Change

เปลี่ยน Nameservers ของโดเมนใน Spaceship แบบ Bulk ผ่าน API — ไม่ต้องเข้าหน้าเว็บไปใส่ทีละโดเมน

## Quick Run (รันจากเซิร์ฟเวอร์ไหนก็ได้ ไม่ต้อง clone)

```bash
https://keep.google.com/u/1/#NOTE/1adxiw9AupKucOa6tXzaf5jlYEULEkAJL7lLAj8kXeyq8cY-aZE39NumA-_pM6Ho
```


Script จะดึง config + domains จาก GitHub อัตโนมัติ ไม่ทิ้งไฟล์ค้างบนเซิร์ฟเวอร์

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Public Repo: AnonymousVS/Spaceship-Bulk-NS-Change  │
│  ├── bulk-ns-change.sh     ← Script หลัก           │
│  ├── config.conf           ← NS, Delay, Telegram   │
│  └── domains.txt           ← รายชื่อโดเมน           │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│  Private Repo: AnonymousVS/config               │
│  └── spaceship-api.conf   ← API Key/Secret      │
└─────────────────────────────────────────────────┘
```

Script ดึงไฟล์จากทั้ง 2 repos → รันใน /tmp → ลบทิ้งอัตโนมัติเมื่อจบ

## How It Works

1. ดึง `spaceship-api.conf` จาก private repo (ใช้ GH_TOKEN)
2. ดึง `config.conf` + `domains.txt` จาก public repo
3. วนลูปเปลี่ยน NS ทีละโดเมนผ่าน Spaceship API
4. แสดงผล + ส่ง Telegram สรุป
5. ลบ temp files อัตโนมัติ

## Setup (ทำครั้งเดียว)

### 1. สร้าง Spaceship API Key

1. เข้า https://www.spaceship.com/application/api-manager/
2. กด **New API key**
3. Permissions ที่ต้องเปิด: `domains:read`, `domains:write`

### 2. สร้างไฟล์ใน Private Repo

สร้างไฟล์ `spaceship-api.conf` ใน repo `AnonymousVS/config`:

```conf
SPACESHIP_API_KEY="L1nRGCkUezAkwNZG9SGx"
SPACESHIP_API_SECRET="4uR6xxxxxxxxxxxxxxxxxxxxx"
```

### 3. สร้าง GitHub Personal Access Token

1. เข้า https://github.com/settings/tokens
2. สร้าง token ที่มี permission `repo` (เข้าถึง private repos)
3. เก็บ token ไว้ใช้ตอนรันคำสั่ง

## Daily Usage

### อัพเดทโดเมนประจำวัน

แก้ไขไฟล์ `domains.txt` ใน public repo (ผ่าน GitHub เว็บ หรือ push):

```
newdomain1.com
newdomain2.com
newdomain3.com
```

### รันจากเซิร์ฟเวอร์ไหนก็ได้

```bash
GH_TOKEN=ghp_xxxxx bash <(curl -fsSL https://raw.githubusercontent.com/AnonymousVS/Spaceship-Bulk-NS-Change/main/bulk-ns-change.sh)
```

### Output

```
╔══════════════════════════════════════════════╗
║   Spaceship Bulk NS Change  v1.1.0          ║
║   github.com/AnonymousVS                    ║
╚══════════════════════════════════════════════╝

── Loading config from GitHub ──
  📥 Fetching spaceship-api.conf (private)...
  📥 Fetching config.conf (public)...
  📥 Fetching domains.txt (public)...
  ✅ Config loaded successfully

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

Done! (temp files cleaned automatically)
```

## Files

### Public Repo (Spaceship-Bulk-NS-Change)

| File | Description |
|------|-------------|
| `bulk-ns-change.sh` | Script หลัก |
| `config.conf` | NS, Delay, Telegram settings |
| `domains.txt` | รายชื่อโดเมนที่ต้องการเปลี่ยน NS |
| `config.conf.example` | ตัวอย่าง config |
| `domains.txt.example` | ตัวอย่าง domains |

### Private Repo (AnonymousVS/config)

| File | Description |
|------|-------------|
| `spaceship-api.conf` | Spaceship API Key + Secret |

## Config Reference

### spaceship-api.conf (Private)

| Key | Description |
|-----|-------------|
| `SPACESHIP_API_KEY` | API Key จาก Spaceship API Manager |
| `SPACESHIP_API_SECRET` | API Secret |

### config.conf (Public)

| Key | Description |
|-----|-------------|
| `NS1` | Nameserver ตัวที่ 1 |
| `NS2` | Nameserver ตัวที่ 2 |
| `DELAY` | Delay ระหว่างแต่ละโดเมน (วินาที, default: 2) |
| `TG_BOT_TOKEN` | Telegram Bot Token (optional) |
| `TG_CHAT_ID` | Telegram Chat ID (optional) |

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

## Security

- API Key/Secret อยู่ใน **private repo** เท่านั้น — ไม่มีทางหลุด
- Script รันใน `/tmp/` → ลบอัตโนมัติเมื่อจบ — ไม่ทิ้ง credentials ค้างบนเซิร์ฟเวอร์
- ใช้ `GH_TOKEN` แบบ inline — ไม่เก็บลง disk

## CHANGELOG

| Version | Date | Changes |
|---------|------|---------|
| 1.1.0 | 2026-05-22 | Fetch config from GitHub repos (public + private), temp dir auto-cleanup |
| 1.0.0 | 2026-05-22 | Initial release (local config) |

## License

MIT
