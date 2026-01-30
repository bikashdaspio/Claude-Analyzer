#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Prerequisite Checks
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
[[ -n "${_PREREQUISITES_LOADED:-}" ]] && return 0
_PREREQUISITES_LOADED=1

check_prerequisites() {
    local errors=0

    # Check module-structure.json exists (HARD STOP)
    if [[ ! -f "$MODULE_STRUCTURE_FILE" ]]; then
        log_error "HARD STOP: module-structure.json not found at $MODULE_STRUCTURE_FILE"
        exit 1
    fi
    log_debug "Found module-structure.json"

    # Check jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "HARD STOP: jq is not installed. Please install jq for JSON manipulation."
        echo "  Install with: sudo apt-get install jq (Debian/Ubuntu)"
        echo "             or: brew install jq (macOS)"
        exit 1
    fi
    log_debug "Found jq: $(jq --version)"

    # Check claude CLI is available
    if ! command -v claude &> /dev/null; then
        log_error "HARD STOP: claude CLI is not available in PATH"
        exit 1
    fi
    log_debug "Found claude CLI"

    # Create state directories if they don't exist
    mkdir -p "$STATE_DIR" "$LOG_DIR"

    log_success "All prerequisites satisfied"
}

# Check if pandoc is available (for DOCX conversion)
check_pandoc() {
    if ! command -v pandoc &> /dev/null; then
        log_error "pandoc is not installed. Please install pandoc for DOCX conversion."
        echo "  Install with: sudo apt-get install pandoc (Debian/Ubuntu)"
        echo "             or: brew install pandoc (macOS)"
        return 1
    fi
    log_debug "Found pandoc: $(pandoc --version | head -1)"
    return 0
}
