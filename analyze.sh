#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Project Module Analysis Script
# ═══════════════════════════════════════════════════════════════════════════════
# Iteratively analyzes all modules from module-structure.json using Claude CLI
# in bypass permission mode, tracking progress via an 'analyzed' property.
#
# This script sources modular components from the lib/ directory:
#   - lib/config.sh        - Configuration variables and constants
#   - lib/logging.sh       - Logging functions
#   - lib/prerequisites.sh - Prerequisite checks
#   - lib/json-utils.sh    - JSON manipulation (jq utilities)
#   - lib/analysis.sh      - Core analysis functions
#   - lib/parallel.sh      - Parallel processing functions
#   - lib/validation.sh    - Markdown validation phase
#   - lib/conversion.sh    - DOCX conversion phase
#   - lib/cli.sh           - CLI interface and argument parsing
# ═══════════════════════════════════════════════════════════════════════════════

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# ═══════════════════════════════════════════════════════════════════════════════
# Source modular components
# ═══════════════════════════════════════════════════════════════════════════════

# Source in order of dependencies
source "$LIB_DIR/config.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/prerequisites.sh"
source "$LIB_DIR/json-utils.sh"
source "$LIB_DIR/parallel.sh"
source "$LIB_DIR/analysis.sh"
source "$LIB_DIR/validation.sh"
source "$LIB_DIR/conversion.sh"
source "$LIB_DIR/cli.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    parse_args "$@"

    print_header "HRMS MODULE ANALYSIS"

    # Check prerequisites (creates state directories)
    check_prerequisites

    # Record session start
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$SESSION_FILE" 2>/dev/null || true

    # Handle reset
    if [[ "$RESET_STATE" == "true" ]]; then
        reset_analysis_state
        if [[ "$DRY_RUN" != "true" && -z "$SINGLE_MODULE" && "$RETRY_FAILED" != "true" ]]; then
            # If only --reset was specified, exit after resetting
            if [[ "$#" -eq 1 || ("$#" -eq 2 && "$VERBOSE" == "true") ]]; then
                log_success "Reset complete. Run without --reset to start analysis."
                exit 0
            fi
        fi
    fi

    # Initialize state if needed
    initialize_analysis_state

    # Build analysis queue
    build_analysis_queue

    # Show queue in dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        show_dry_run_preview
    fi

    # Set up trap for cleanup
    trap cleanup EXIT INT TERM

    # Handle --validation-only mode
    if [[ "$VALIDATION_ONLY" == "true" ]]; then
        run_validation_phase
        exit 0
    fi

    # Handle --conversion-only mode
    if [[ "$CONVERSION_ONLY" == "true" ]]; then
        run_conversion_phase
        exit 0
    fi

    # Run main analysis loop (Phase 1 & 2)
    log_info "Starting analysis..."
    main_loop

    # Phase 3: Markdown Validation
    run_validation_phase

    # Phase 4: DOCX Conversion
    run_conversion_phase

    # Trap will call print_summary on exit
}

main "$@"
