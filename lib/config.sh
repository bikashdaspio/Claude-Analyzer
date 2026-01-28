#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Configuration - Global variables and constants
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
[[ -n "${_CONFIG_LOADED:-}" ]] && return 0
_CONFIG_LOADED=1

# Script directory (should be set by main script before sourcing)
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# File paths
MODULE_STRUCTURE_FILE="${MODULE_STRUCTURE_FILE:-$SCRIPT_DIR/module-structure.json}"
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/.analyze-state}"
LOG_DIR="${LOG_DIR:-$STATE_DIR/logs}"
MAIN_LOG="${MAIN_LOG:-$STATE_DIR/analyze.log}"
QUEUE_FILE="${QUEUE_FILE:-$STATE_DIR/analysis_queue.txt}"
FAILED_FILE="${FAILED_FILE:-$STATE_DIR/failed_modules.txt}"
SESSION_FILE="${SESSION_FILE:-$STATE_DIR/session_start.txt}"

# Timeouts (in seconds) - 0 means no timeout
TIMEOUT_LOW="${TIMEOUT_LOW:-300}"       # 5 minutes
TIMEOUT_MEDIUM="${TIMEOUT_MEDIUM:-600}" # 10 minutes
TIMEOUT_HIGH="${TIMEOUT_HIGH:-900}"     # 15 minutes
CUSTOM_TIMEOUT="${CUSTOM_TIMEOUT:-0}"   # Custom timeout override (0 = use complexity-based)
NO_TIMEOUT="${NO_TIMEOUT:-false}"       # Disable all timeouts

# Counters
SUCCESS_COUNT="${SUCCESS_COUNT:-0}"
FAILED_COUNT="${FAILED_COUNT:-0}"
SKIPPED_COUNT="${SKIPPED_COUNT:-0}"
TOTAL_COUNT="${TOTAL_COUNT:-0}"

# CLI Options
DRY_RUN="${DRY_RUN:-false}"
RESET_STATE="${RESET_STATE:-false}"
SINGLE_MODULE="${SINGLE_MODULE:-}"
RETRY_FAILED="${RETRY_FAILED:-false}"
DELAY_SECONDS="${DELAY_SECONDS:-5}"
VERBOSE="${VERBOSE:-false}"
PARALLEL_JOBS="${PARALLEL_JOBS:-1}"     # Number of parallel jobs (1 = sequential)
MAX_PARALLEL="${MAX_PARALLEL:-8}"       # Maximum allowed parallel jobs
SKIP_VALIDATION="${SKIP_VALIDATION:-false}"
SKIP_CONVERSION="${SKIP_CONVERSION:-false}"
VALIDATION_ONLY="${VALIDATION_ONLY:-false}"
CONVERSION_ONLY="${CONVERSION_ONLY:-false}"

# Output directories
DOCS_DIR="${DOCS_DIR:-$SCRIPT_DIR/Documents}"
DOCX_OUTPUT_DIR="${DOCX_OUTPUT_DIR:-$SCRIPT_DIR/Documents/DOCX}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Validation counters
VALIDATION_SUCCESS="${VALIDATION_SUCCESS:-0}"
VALIDATION_FAILED="${VALIDATION_FAILED:-0}"
VALIDATION_SKIPPED="${VALIDATION_SKIPPED:-0}"

# Conversion counters
CONVERSION_SUCCESS="${CONVERSION_SUCCESS:-0}"
CONVERSION_FAILED="${CONVERSION_FAILED:-0}"

# Parallel processing state
PARALLEL_RESULTS_DIR=""
PARALLEL_PIDS=()
