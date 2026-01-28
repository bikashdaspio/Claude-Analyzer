#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Logging Functions
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
[[ -n "${_LOGGING_LOADED:-}" ]] && return 0
_LOGGING_LOADED=1

log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${BLUE}ℹ${NC} $1"
    echo "$msg" >> "$MAIN_LOG" 2>/dev/null || true
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
    echo -e "${GREEN}✓${NC} $1"
    echo "$msg" >> "$MAIN_LOG" 2>/dev/null || true
}

log_warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"
    echo -e "${YELLOW}⚠${NC} $1"
    echo "$msg" >> "$MAIN_LOG" 2>/dev/null || true
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}✗${NC} $1" >&2
    echo "$msg" >> "$MAIN_LOG" 2>/dev/null || true
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1"
        echo -e "${CYAN}…${NC} $1"
        echo "$msg" >> "$MAIN_LOG" 2>/dev/null || true
    fi
}

print_header() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                    $1${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}
