#!/usr/bin/env bash
# ============================================================
# Spaceship Bulk NS Change
# Version: 1.0.0
# Repo: AnonymousVS/Spaceship-Bulk-NS-Change
# Description: เปลี่ยน Nameservers ของโดเมนใน Spaceship
#              แบบ Bulk ผ่าน API โดยไม่ต้องเข้าหน้าเว็บ
# ============================================================

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/config.conf"
TIMESTAMP="$(TZ='Asia/Bangkok' date '+%Y-%m-%d_%H-%M-%S')"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/bulk-ns-change_${TIMESTAMP}.log"

# ── Spaceship API ──
API_BASE="https://spaceship.dev/api/v1"

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
    log "ERROR: $1"
    exit 1
}

check_dependencies() {
    for cmd in curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            die "'$cmd' is required but not installed. Install it first."
        fi
    done
}

load_config() {
    if [[ ! -f "$CONF_FILE" ]]; then
        die "Config file not found: ${CONF_FILE}\nCopy config.conf.example → config.conf and fill in your credentials."
    fi
    # shellcheck source=/dev/null
    source "$CONF_FILE"

    # Validate required fields
    [[ -z "${SPACESHIP_API_KEY:-}" ]]    && die "SPACESHIP_API_KEY is empty in config.conf"
    [[ -z "${SPACESHIP_API_SECRET:-}" ]] && die "SPACESHIP_API_SECRET is empty in config.conf"
    [[ -z "${NS1:-}" ]]                  && die "NS1 is empty in config.conf"
    [[ -z "${NS2:-}" ]]                  && die "NS2 is empty in config.conf"

    # Defaults
    DELAY="${DELAY:-2}"
    TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
    TG_CHAT_ID="${TG_CHAT_ID:-}"
}

# ── Spaceship API: Update Nameservers ──
update_ns() {
    local domain="$1"
    local http_code body response

    response=$(curl -s -w "\n%{http_code}" \
        -X PUT "${API_BASE}/domains/${domain}/nameservers" \
        -H "X-Api-Key: ${SPACESHIP_API_KEY}" \
        -H "X-Api-Secret: ${SPACESHIP_API_SECRET}" \
        -H "Content-Type: application/json" \
        -d "{\"provider\":\"custom\",\"hosts\":[\"${NS1}\",\"${NS2}\"]}" \
        --connect-timeout 10 \
        --max-time 30 \
        2>&1) || true

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
# Spaceship rate limit: 5 req/domain/300s (ไม่มีปัญหาเพราะยิงโดเมนละ 1 ครั้ง)
# Global rate limit: ใช้ DELAY ป้องกัน + เพิ่ม delay ถ้าโดน 429
smart_delay() {
    local attempt="$1"
    local base_delay="${DELAY}"

    if [[ "$attempt" -gt 0 ]]; then
        # Exponential backoff: 5s, 10s, 20s
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
    load_config

    # ── Input file ──
    local input_file="${1:-}"
    if [[ -z "$input_file" ]]; then
        die "Usage: ./bulk-ns-change.sh <domains.txt>"
    fi
    if [[ ! -f "$input_file" ]]; then
        die "File not found: ${input_file}"
    fi

    # ── Prepare ──
    mkdir -p "$LOG_DIR"

    # Read domains (skip empty lines and comments)
    mapfile -t domains < <(grep -v '^\s*$' "$input_file" | grep -v '^\s*#' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    local total=${#domains[@]}

    if [[ "$total" -eq 0 ]]; then
        die "No domains found in ${input_file}"
    fi

    echo -e "Domains: ${CYAN}${total}${NC}"
    echo -e "NS1:     ${CYAN}${NS1}${NC}"
    echo -e "NS2:     ${CYAN}${NS2}${NC}"
    echo -e "Delay:   ${CYAN}${DELAY}s${NC}"
    echo -e "Log:     ${CYAN}${LOG_FILE}${NC}"
    echo ""

    log "=== Spaceship Bulk NS Change v${VERSION} ==="
    log "Domains: ${total} | NS: ${NS1}, ${NS2} | Delay: ${DELAY}s"

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
                    # Parse error message from JSON body if possible
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

    echo -e "\n${GREEN}Done!${NC} Log: ${LOG_FILE}"
}

main "$@"
