#!/usr/bin/env bash
# ============================================================
# Spaceship Bulk NS Change
# Version: 1.1.0
# Repo: AnonymousVS/Spaceship-Bulk-NS-Change
# Description: เปลี่ยน Nameservers ของโดเมนใน Spaceship
#              แบบ Bulk ผ่าน API โดยไม่ต้องเข้าหน้าเว็บ
# ============================================================

set -euo pipefail

VERSION="1.1.1"
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

    echo -e "  📥 Fetching ${desc}..."

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
    eval "$api_conf"

    # 2) Fetch public config (NS, delay, Telegram)
    local pub_conf
    pub_conf=$(fetch_github "${PUBLIC_REPO}/config.conf" "config.conf (public)" "")
    eval "$pub_conf"

    # 3) Fetch domains list
    local domains_raw
    domains_raw=$(fetch_github "${PUBLIC_REPO}/domains.txt" "domains.txt (public)" "")
    echo "$domains_raw" > "${WORK_DIR}/domains.txt"

    # Validate required fields
    [[ -z "${SPACESHIP_API_KEY:-}" ]]    && die "SPACESHIP_API_KEY is empty in spaceship-api.conf"
    [[ -z "${SPACESHIP_API_SECRET:-}" ]] && die "SPACESHIP_API_SECRET is empty in spaceship-api.conf"
    [[ -z "${NS1:-}" ]]                  && die "NS1 is empty in config.conf"
    [[ -z "${NS2:-}" ]]                  && die "NS2 is empty in config.conf"

    # Defaults
    DELAY="${DELAY:-2}"
    TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
    TG_CHAT_ID="${TG_CHAT_ID:-}"

    echo -e "${GREEN}  ✅ Config loaded successfully${NC}\n"
}

# ── Spaceship API: Update Nameservers ──
update_ns() {
    local domain="$1"
    local response

    response=$(curl -s -w "\n%{http_code}" \
        -X PUT "${API_BASE}/domains/${domain}/nameservers" \
        -H "X-Api-Key: ${SPACESHIP_API_KEY}" \
        -H "X-Api-Secret: ${SPACESHIP_API_SECRET}" \
        -H "Content-Type: application/json" \
        -d "{\"provider\":\"custom\",\"hosts\":[\"${NS1}\",\"${NS2}\"]}" \
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

# ── Smart Delay ──
smart_delay() {
    local attempt="$1"
    local base_delay="${DELAY}"

    if [[ "$attempt" -gt 0 ]]; then
        local backoff=$(( base_delay * (2 ** attempt) ))
        [[ "$backoff" -gt 60 ]] && backoff=60
        echo -e "${YELLOW}  ⏳ Rate limited — waiting ${backoff}s (retry ${attempt}/3)${NC}"
        log "Rate limited — backoff ${backoff}s (retry ${attempt}/3)"
        sleep "$backoff"
    else
        sleep "$base_delay"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    print_banner
    check_dependencies
    load_config_from_github

    # ── Read domains ──
    local input_file="${WORK_DIR}/domains.txt"
    mapfile -t domains < <(grep -v '^\s*$' "$input_file" | grep -v '^\s*#' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    local total=${#domains[@]}

    if [[ "$total" -eq 0 ]]; then
        die "No domains found in domains.txt"
    fi

    # ── แสดงรายชื่อโดเมนทั้งหมด ──
    echo -e "NS1:     ${CYAN}${NS1}${NC}"
    echo -e "NS2:     ${CYAN}${NS2}${NC}"
    echo -e "Delay:   ${CYAN}${DELAY}s${NC}"
    echo ""
    echo -e "── Domains (${CYAN}${total}${NC} total) ──────────────────────"
    for i in "${!domains[@]}"; do
        printf "  ${CYAN}%3d${NC}. %s\n" "$((i + 1))" "${domains[$i]}"
    done
    echo -e "──────────────────────────────────────────────"
    echo ""

    # ── Confirm ──
    echo -ne "${YELLOW}เปลี่ยน NS ทั้ง ${total} โดเมนนี้? (y/n): ${NC}"
    read -r confirm </dev/tty
    if [[ "${confirm,,}" != "y" ]]; then
        echo -e "${RED}Cancelled.${NC}"
        exit 0
    fi
    echo ""

    log "=== Spaceship Bulk NS Change v${VERSION} ==="
    log "Server: $(hostname) | Domains: ${total} | NS: ${NS1}, ${NS2} | Delay: ${DELAY}s"

    local success=0
    local failed=0
    local failed_list=""

    for i in "${!domains[@]}"; do
        local domain="${domains[$i]}"
        local num=$((i + 1))
        local retry=0
        local max_retry=3
        local done_flag=0

        while [[ "$retry" -le "$max_retry" && "$done_flag" -eq 0 ]]; do
            if [[ "$retry" -gt 0 ]]; then
                smart_delay "$retry"
            fi

            local result
            result=$(update_ns "$domain")
            local code="${result%%|*}"
            local body="${result#*|}"

            case "$code" in
                200|204)
                    echo -e "[${num}/${total}] ${GREEN}✅ ${domain}${NC} → OK"
                    log "OK: ${domain} (HTTP ${code})"
                    ((success++))
                    done_flag=1
                    ;;
                429)
                    if [[ "$retry" -ge "$max_retry" ]]; then
                        echo -e "[${num}/${total}] ${RED}❌ ${domain}${NC} → FAILED (429 rate limited after ${max_retry} retries)"
                        log "FAILED: ${domain} (429 rate limited after ${max_retry} retries)"
                        ((failed++))
                        failed_list+="${domain}\n"
                        done_flag=1
                    fi
                    ((retry++))
                    ;;
                *)
                    local err_msg
                    err_msg=$(echo "$body" | jq -r '.detail // .message // .title // empty' 2>/dev/null || echo "$body")
                    [[ -z "$err_msg" ]] && err_msg="HTTP ${code}"

                    echo -e "[${num}/${total}] ${RED}❌ ${domain}${NC} → FAILED (${err_msg})"
                    log "FAILED: ${domain} (HTTP ${code}: ${err_msg})"
                    ((failed++))
                    failed_list+="${domain}\n"
                    done_flag=1
                    ;;
            esac
        done

        # Normal delay between domains (skip after last one)
        if [[ "$done_flag" -eq 1 && "$num" -lt "$total" ]]; then
            sleep "$DELAY"
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
    local tg_msg="<b>🚀 Spaceship Bulk NS Change</b>
<b>Server:</b> $(hostname)
<b>Total:</b> ${total}
<b>✅ Success:</b> ${success}
<b>❌ Failed:</b> ${failed}
<b>NS:</b> ${NS1}, ${NS2}"

    if [[ "$failed" -gt 0 ]]; then
        tg_msg+="\n\n<b>Failed:</b>\n$(echo -e "$failed_list")"
    fi

    send_telegram "$tg_msg"

    echo -e "\n${GREEN}Done!${NC} (temp files cleaned automatically)"
}

main "$@"
