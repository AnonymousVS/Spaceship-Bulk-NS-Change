#!/usr/bin/env bash
# ============================================================
# Spaceship Bulk NS Change
# Version: 2.0.0
# Repo: AnonymousVS/Spaceship-Bulk-NS-Change
# Description: เปลี่ยน Nameservers ของโดเมนใน Spaceship
#              แบบ Bulk ผ่าน API โดยไม่ต้องเข้าหน้าเว็บ
#              รองรับ CSV: Domain,Nameserver1,Nameserver2
# ============================================================

set -euo pipefail

VERSION="2.0.5"
TIMESTAMP="$(TZ='Asia/Bangkok' date '+%Y-%m-%d_%H-%M-%S')"

# ── GitHub Raw URLs ──
GITHUB_RAW="https://raw.githubusercontent.com/AnonymousVS"
PUBLIC_REPO="${GITHUB_RAW}/Spaceship-Bulk-NS-Change/main"
PRIVATE_REPO="${GITHUB_RAW}/config/main"
PRIVATE_CONF="spaceship-api.conf"

# ── Spaceship API ──
API_BASE="https://spaceship.dev/api/v1"

# ── Temp directory (ไม่ทิ้งไฟล์ค้างบนเซิร์ฟเวอร์) ──
WORK_DIR=$(mktemp -d "/tmp/spaceship-bulk-ns-XXXXXX")
LOG_FILE="${WORK_DIR}/bulk-ns-change_${TIMESTAMP}.log"
trap 'rm -rf "$WORK_DIR"' EXIT

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
# Functions
# ============================================================

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║   Spaceship Bulk NS Change  v${VERSION}          ║"
    echo "║   github.com/AnonymousVS                    ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log() {
    local msg="[$(TZ='Asia/Bangkok' date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
}

die() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    [[ -f "$LOG_FILE" ]] && log "ERROR: $1"
    exit 1
}

check_dependencies() {
    for cmd in curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            die "'$cmd' is required but not installed. Install it first."
        fi
    done
}

# ── Fetch file from GitHub ──
fetch_github() {
    local url="$1"
    local desc="$2"
    local auth_header="${3:-}"
    local content

    echo -e "  📥 Fetching ${desc}..." >&2

    if [[ -n "$auth_header" ]]; then
        content=$(curl -fsSL -H "Authorization: token ${auth_header}" "$url" 2>/dev/null) || {
            die "Failed to fetch ${desc} from ${url}\n  → Check GitHub Token and repo access."
        }
    else
        content=$(curl -fsSL "$url" 2>/dev/null) || {
            die "Failed to fetch ${desc} from ${url}"
        }
    fi

    echo "$content"
}

# ── Load config from GitHub repos ──
load_config_from_github() {
    echo -e "${CYAN}── Loading config from GitHub ──${NC}"

    # 1) Fetch private config (API credentials) — requires GH_TOKEN
    if [[ -z "${GH_TOKEN:-}" ]]; then
        die "GH_TOKEN is not set.\nUsage: GH_TOKEN=ghp_xxxxx bash <(curl ...)"
    fi

    local api_conf
    api_conf=$(fetch_github "${PRIVATE_REPO}/${PRIVATE_CONF}" "spaceship-api.conf (private)" "$GH_TOKEN")
    echo "$api_conf" > "${WORK_DIR}/spaceship-api.conf"
    source "${WORK_DIR}/spaceship-api.conf"

    # 2) Fetch public config (delay, Telegram)
    local pub_conf
    pub_conf=$(fetch_github "${PUBLIC_REPO}/config.conf" "config.conf (public)" "")
    echo "$pub_conf" > "${WORK_DIR}/config.conf"
    source "${WORK_DIR}/config.conf"

    # 3) Fetch domains CSV
    local csv_raw
    csv_raw=$(fetch_github "${PUBLIC_REPO}/domains.csv" "domains.csv (public)" "")
    echo "$csv_raw" > "${WORK_DIR}/domains.csv"

    # Validate required fields
    [[ -z "${SPACESHIP_API_KEY:-}" ]]    && die "SPACESHIP_API_KEY is empty in spaceship-api.conf"
    [[ -z "${SPACESHIP_API_SECRET:-}" ]] && die "SPACESHIP_API_SECRET is empty in spaceship-api.conf"

    # Defaults (DELAY in milliseconds)
    DELAY_MS="${DELAY_MS:-500}"
    TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
    TG_CHAT_ID="${TG_CHAT_ID:-}"

    echo -e "${GREEN}  ✅ Config loaded successfully${NC}\n"
}

# ── Parse CSV → arrays ──
parse_csv() {
    local csv_file="${WORK_DIR}/domains.csv"

    DOMAINS=()
    NS1_LIST=()
    NS2_LIST=()

    while IFS=',' read -r domain ns1 ns2 _rest; do
        # ลบ spaces, \r, quotes
        domain=$(echo "$domain" | tr -d ' \r"')
        ns1=$(echo "$ns1" | tr -d ' \r"')
        ns2=$(echo "$ns2" | tr -d ' \r"')

        # ข้ามบรรทัดว่าง, comment, header
        [[ -z "$domain" ]] && continue
        [[ "$domain" == \#* ]] && continue
        [[ "${domain,,}" == "domain" ]] && continue

        # Validate
        if [[ -z "$ns1" || -z "$ns2" ]]; then
            echo -e "${YELLOW}  ⚠️  Skip: ${domain} — NS1 or NS2 is empty${NC}"
            log "SKIP: ${domain} — missing NS"
            continue
        fi

        DOMAINS+=("$domain")
        NS1_LIST+=("$ns1")
        NS2_LIST+=("$ns2")
    done < "$csv_file"
}

# ── Spaceship API: Update Nameservers ──
update_ns() {
    local domain="$1"
    local ns1="$2"
    local ns2="$3"
    local response

    response=$(curl -s -w "\n%{http_code}" \
        -X PUT "${API_BASE}/domains/${domain}/nameservers" \
        -H "X-Api-Key: ${SPACESHIP_API_KEY}" \
        -H "X-Api-Secret: ${SPACESHIP_API_SECRET}" \
        -H "Content-Type: application/json" \
        -d "{\"provider\":\"custom\",\"hosts\":[\"${ns1}\",\"${ns2}\"]}" \
        --connect-timeout 10 \
        --max-time 30 \
        2>&1) || true

    local http_code body
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    echo "${http_code}|${body}"
}

# ── Telegram Notification ──
send_telegram() {
    local message="$1"
    if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            -d chat_id="$TG_CHAT_ID" \
            -d parse_mode="HTML" \
            -d text="$message" \
            --connect-timeout 10 \
            --max-time 15 \
            >/dev/null 2>&1 || true
    fi
}

# ── Smart Delay (milliseconds) ──
smart_delay() {
    local attempt="$1"

    if [[ "$attempt" -gt 0 ]]; then
        local backoff_ms=$(( DELAY_MS * (2 ** attempt) ))
        [[ "$backoff_ms" -gt 60000 ]] && backoff_ms=60000
        local backoff_sec=$(awk "BEGIN{printf \"%.1f\", ${backoff_ms}/1000}")
        echo -e "${YELLOW}  ⏳ Rate limited — waiting ${backoff_ms}ms (retry ${attempt}/3)${NC}"
        log "Rate limited — backoff ${backoff_ms}ms (retry ${attempt}/3)"
        sleep "$backoff_sec"
    else
        sleep "$(awk "BEGIN{printf \"%.3f\", ${DELAY_MS}/1000}")"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    print_banner
    check_dependencies
    load_config_from_github

    # ── Parse CSV ──
    parse_csv
    local total=${#DOMAINS[@]}

    if [[ "$total" -eq 0 ]]; then
        die "No domains found in domains.csv"
    fi

    # ── แสดงรายชื่อโดเมนทั้งหมด ──
    echo -e "Delay: ${CYAN}${DELAY_MS}ms${NC}"
    echo ""
    printf "${BOLD}  %-4s %-30s %-35s %-35s${NC}\n" "#" "Domain" "NS1" "NS2"
    echo -e "  ──── ────────────────────────────── ─────────────────────────────────── ───────────────────────────────────"
    for i in "${!DOMAINS[@]}"; do
        printf "  ${CYAN}%-4d${NC} %-30s %-35s %-35s\n" "$((i + 1))" "${DOMAINS[$i]}" "${NS1_LIST[$i]}" "${NS2_LIST[$i]}"
    done
    echo ""

    # ── Confirm ──
    echo -ne "${YELLOW}เปลี่ยน NS ทั้ง ${total} โดเมนนี้? (y/n): ${NC}"
    read -r confirm </dev/tty
    # ตัด whitespace + รับทั้ง y, Y, ั (ภาษาไทยตำแหน่งปุ่ม y)
    confirm=$(echo "$confirm" | tr -d '[:space:]')
    if [[ "$confirm" != "y" && "$confirm" != "Y" && "$confirm" != "ั" ]]; then
        echo -e "${RED}Cancelled.${NC}"
        exit 0
    fi
    echo ""

    log "=== Spaceship Bulk NS Change v${VERSION} ==="
    log "Server: $(hostname) | Domains: ${total} | Delay: ${DELAY_MS}ms"

    local success=0
    local failed=0
    local failed_list=""

    for i in "${!DOMAINS[@]}"; do
        local domain="${DOMAINS[$i]}"
        local ns1="${NS1_LIST[$i]}"
        local ns2="${NS2_LIST[$i]}"
        local num=$((i + 1))
        local retry=0
        local max_retry=3
        local done_flag=0

        while [[ "$retry" -le "$max_retry" && "$done_flag" -eq 0 ]]; do
            if [[ "$retry" -gt 0 ]]; then
                smart_delay "$retry"
            fi

            local result
            result=$(update_ns "$domain" "$ns1" "$ns2")
            local code="${result%%|*}"
            local body="${result#*|}"

            case "$code" in
                200|204)
                    echo -e "[${num}/${total}] ${GREEN}✅ ${domain}${NC} → ${ns1}, ${ns2}"
                    log "OK: ${domain} → ${ns1}, ${ns2} (HTTP ${code})"
                    ((success++)) || true
                    done_flag=1
                    ;;
                429)
                    if [[ "$retry" -ge "$max_retry" ]]; then
                        echo -e "[${num}/${total}] ${RED}❌ ${domain}${NC} → FAILED (429 rate limited after ${max_retry} retries)"
                        log "FAILED: ${domain} (429 rate limited after ${max_retry} retries)"
                        ((failed++)) || true
                        failed_list+="${domain}\n"
                        done_flag=1
                    fi
                    ((retry++)) || true
                    ;;
                *)
                    local err_msg
                    err_msg=$(echo "$body" | jq -r '.detail // .message // .title // empty' 2>/dev/null || echo "$body")
                    [[ -z "$err_msg" ]] && err_msg="HTTP ${code}"

                    echo -e "[${num}/${total}] ${RED}❌ ${domain}${NC} → FAILED (${err_msg})"
                    log "FAILED: ${domain} (HTTP ${code}: ${err_msg})"
                    ((failed++)) || true
                    failed_list+="${domain}\n"
                    done_flag=1
                    ;;
            esac
        done

        # Normal delay between domains (skip after last one)
        if [[ "$done_flag" -eq 1 && "$num" -lt "$total" ]]; then
            sleep "$(awk "BEGIN{printf \"%.3f\", ${DELAY_MS}/1000}")"
        fi
    done

    # ── Summary ──
    echo ""
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  Total:    ${CYAN}${total}${NC}"
    echo -e "  Success:  ${GREEN}${success}${NC}"
    echo -e "  Failed:   ${RED}${failed}${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    log "=== DONE === Success: ${success} | Failed: ${failed} / ${total}"

    if [[ "$failed" -gt 0 ]]; then
        echo -e "\n${RED}Failed domains:${NC}"
        echo -e "$failed_list"
        log "Failed domains: $(echo -e "$failed_list" | tr '\n' ', ')"
    fi

    # ── Telegram ──
    local tg_msg="<b>🚀 Spaceship Bulk NS Change v${VERSION}</b>
<b>Server:</b> $(hostname)
<b>Total:</b> ${total}
<b>✅ Success:</b> ${success}
<b>❌ Failed:</b> ${failed}"

    if [[ "$failed" -gt 0 ]]; then
        tg_msg+="\n\n<b>Failed:</b>\n$(echo -e "$failed_list")"
    fi

    send_telegram "$tg_msg"

    echo -e "\n${GREEN}Done!${NC} (temp files cleaned automatically)"
}

main "$@"
