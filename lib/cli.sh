#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CLI Interface - Help and Argument Parsing
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
[[ -n "${_CLI_LOADED:-}" ]] && return 0
_CLI_LOADED=1

show_help() {
    cat << EOF
HRMS Module Analysis Script

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --dry-run           Show what would be analyzed without running
    --reset             Reset all 'analyzed' flags to false
    --module NAME       Analyze only the specified module (e.g., "Employee" or "Employee/Profile")
    --retry-failed      Retry only previously failed modules
    --delay SECONDS     Delay between module analyses (default: 5)
    --parallel N, -p N  Run N modules in parallel (default: 1, max: $MAX_PARALLEL)
    --no-timeout        Disable all timeouts (run until completion)
    --timeout SECONDS   Set a custom timeout for all modules (overrides complexity-based)
    --verbose           Enable verbose output
    --help              Show this help message

PHASE CONTROL:
    --skip-validation   Skip Phase 3 (markdown validation)
    --skip-conversion   Skip Phase 4 (DOCX conversion)
    --validation-only   Run only Phase 3 (markdown validation)
    --conversion-only   Run only Phase 4 (DOCX conversion)

WORKFLOW PHASES:
    Phase 1 & 2: Module Analysis (submodules first, then parent modules)
    Phase 3:     Markdown Validation (validate & auto-fix for pandoc compatibility)
    Phase 4:     DOCX Conversion (convert all markdown to Word documents)

TIMEOUT BEHAVIOR:
    By default, timeouts are based on module complexity:
      - Low complexity:    ${TIMEOUT_LOW}s ($(( TIMEOUT_LOW / 60 )) minutes)
      - Medium complexity: ${TIMEOUT_MEDIUM}s ($(( TIMEOUT_MEDIUM / 60 )) minutes)
      - High complexity:   ${TIMEOUT_HIGH}s ($(( TIMEOUT_HIGH / 60 )) minutes)

    Use --no-timeout to disable timeouts entirely (recommended for large modules).
    Use --timeout SECONDS to set a custom timeout for all modules.

EXAMPLES:
    $(basename "$0")                          # Full workflow: analyze, validate, convert
    $(basename "$0") --dry-run                # Preview the analysis queue
    $(basename "$0") --reset                  # Reset all progress and start fresh
    $(basename "$0") --module Employee        # Analyze only the Employee module
    $(basename "$0") --module Employee/Profile # Analyze only the Profile submodule
    $(basename "$0") --retry-failed           # Retry failed modules from previous run
    $(basename "$0") --delay 10               # Wait 10 seconds between modules
    $(basename "$0") --parallel 4             # Run 4 modules in parallel
    $(basename "$0") -p 4 --no-timeout        # Parallel with no timeout
    $(basename "$0") --timeout 3600           # Set 1-hour timeout for all modules
    $(basename "$0") -p 3 --timeout 1800      # 3 parallel jobs, 30-min timeout each
    $(basename "$0") --validation-only -p 4   # Only validate markdown files (4 parallel)
    $(basename "$0") --conversion-only        # Only convert to DOCX
    $(basename "$0") --skip-validation        # Skip validation, do analysis + conversion

OUTPUT:
    Documents/             Generated markdown files from analysis
    Documents/DOCX/        Converted Word documents

STATE FILES:
    module-structure.json     Source of modules (modified to track progress)
    .analyze-state/           State persistence directory
    .analyze-state/logs/      Per-module log files
    .analyze-state/analyze.log Main log file

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --reset)
                RESET_STATE=true
                shift
                ;;
            --module)
                if [[ -n "${2:-}" ]]; then
                    SINGLE_MODULE="$2"
                    shift 2
                else
                    log_error "--module requires a module name"
                    exit 1
                fi
                ;;
            --retry-failed)
                RETRY_FAILED=true
                shift
                ;;
            --delay)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    DELAY_SECONDS="$2"
                    shift 2
                else
                    log_error "--delay requires a numeric value"
                    exit 1
                fi
                ;;
            --parallel|-p)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    PARALLEL_JOBS="$2"
                    if [[ "$PARALLEL_JOBS" -lt 1 ]]; then
                        PARALLEL_JOBS=1
                    elif [[ "$PARALLEL_JOBS" -gt "$MAX_PARALLEL" ]]; then
                        log_warn "Limiting parallel jobs to $MAX_PARALLEL (requested: $PARALLEL_JOBS)"
                        PARALLEL_JOBS="$MAX_PARALLEL"
                    fi
                    shift 2
                else
                    log_error "--parallel requires a numeric value"
                    exit 1
                fi
                ;;
            --no-timeout)
                NO_TIMEOUT=true
                shift
                ;;
            --timeout)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    CUSTOM_TIMEOUT="$2"
                    shift 2
                else
                    log_error "--timeout requires a numeric value in seconds"
                    exit 1
                fi
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --skip-conversion)
                SKIP_CONVERSION=true
                shift
                ;;
            --validation-only)
                VALIDATION_ONLY=true
                shift
                ;;
            --conversion-only)
                CONVERSION_ONLY=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Print summary at the end
print_summary() {
    local total_modules
    local total_submodules
    local analyzed_modules
    local analyzed_submodules

    total_modules=$(jq '.modules | length' "$MODULE_STRUCTURE_FILE" 2>/dev/null || echo "0")
    total_submodules=$(jq '[.modules[].subModules // [] | length] | add' "$MODULE_STRUCTURE_FILE" 2>/dev/null || echo "0")
    analyzed_modules=$(jq '[.modules[] | select(.analyzed == true)] | length' "$MODULE_STRUCTURE_FILE" 2>/dev/null || echo "0")
    analyzed_submodules=$(jq '[.modules[].subModules // [] | .[] | select(.analyzed == true)] | length' "$MODULE_STRUCTURE_FILE" 2>/dev/null || echo "0")

    print_header "WORKFLOW COMPLETE"

    if [[ "$VALIDATION_ONLY" != "true" && "$CONVERSION_ONLY" != "true" ]]; then
        echo -e "  ${BOLD}Phase 1 & 2: Module Analysis${NC}"
        echo "    Modules:     $analyzed_modules / $total_modules analyzed"
        echo "    Sub-modules: $analyzed_submodules / $total_submodules analyzed"
        echo ""
        echo "    Results:"
        echo -e "      ${GREEN}Successful:${NC} $SUCCESS_COUNT"
        echo -e "      ${RED}Failed:${NC}     $FAILED_COUNT"
        echo -e "      ${YELLOW}Skipped:${NC}    $SKIPPED_COUNT"
        echo ""
    fi

    if [[ "$SKIP_VALIDATION" != "true" && "$CONVERSION_ONLY" != "true" ]]; then
        echo -e "  ${BOLD}Phase 3: Markdown Validation${NC}"
        echo -e "      ${GREEN}Validated:${NC}  $VALIDATION_SUCCESS"
        echo -e "      ${RED}Failed:${NC}     $VALIDATION_FAILED"
        echo ""
    fi

    if [[ "$SKIP_CONVERSION" != "true" && "$VALIDATION_ONLY" != "true" ]]; then
        echo -e "  ${BOLD}Phase 4: DOCX Conversion${NC}"
        echo -e "      ${GREEN}Converted:${NC}  $CONVERSION_SUCCESS"
        echo -e "      ${RED}Failed:${NC}     $CONVERSION_FAILED"
        echo ""
        if [[ "$CONVERSION_SUCCESS" -gt 0 ]]; then
            echo "    Output: $DOCX_OUTPUT_DIR"
            echo ""
        fi
    fi

    echo "  Logs directory: $LOG_DIR"

    if [[ -f "$FAILED_FILE" && -s "$FAILED_FILE" ]]; then
        echo ""
        echo -e "  ${YELLOW}Failed modules can be retried with:${NC} ./analyze.sh --retry-failed"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════"
}

# Trap for cleanup on exit
cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo ""
        log_warn "Script interrupted. Progress has been saved."
        log_info "Resume with: ./analyze.sh"
    fi

    print_summary
    exit $exit_code
}

# Show dry-run preview
show_dry_run_preview() {
    # Handle validation-only dry run
    if [[ "$VALIDATION_ONLY" == "true" ]]; then
        print_header "VALIDATION PREVIEW (DRY RUN)"
        echo "The following markdown files would be validated:"
        echo ""
        local md_files
        md_files=$(find_markdown_files 2>/dev/null)
        if [[ -z "$md_files" ]]; then
            log_warn "No markdown files found in $DOCS_DIR"
        else
            local counter=1
            while IFS= read -r file; do
                printf "  %2d. %s\n" "$counter" "$file"
                ((counter++)) || true
            done <<< "$md_files"
            echo ""
            log_info "Total: $((counter - 1)) files to validate"
        fi
        exit 0
    fi

    # Handle conversion-only dry run
    if [[ "$CONVERSION_ONLY" == "true" ]]; then
        print_header "CONVERSION PREVIEW (DRY RUN)"
        echo "The following markdown files would be converted to DOCX:"
        echo ""
        local md_files
        md_files=$(find_markdown_files 2>/dev/null)
        if [[ -z "$md_files" ]]; then
            log_warn "No markdown files found in $DOCS_DIR"
        else
            local counter=1
            while IFS= read -r file; do
                local docx_out
                docx_out=$(get_docx_output_path "$file")
                printf "  %2d. %s\n      -> %s\n" "$counter" "$file" "$docx_out"
                ((counter++)) || true
            done <<< "$md_files"
            echo ""
            log_info "Total: $((counter - 1)) files to convert"
        fi
        exit 0
    fi

    # Regular analysis dry run
    print_header "ANALYSIS QUEUE (DRY RUN)"
    echo "The following modules would be analyzed in order:"
    echo ""
    local counter=1
    while IFS= read -r line; do
        if [[ "$line" =~ ^#.* ]]; then
            echo ""
            echo -e "${CYAN}${line}${NC}"
            continue
        fi
        [[ -z "$line" ]] && continue

        IFS='|' read -r name parent complexity <<< "$line"
        local display_name
        if [[ -n "$parent" ]]; then
            display_name="${parent}/${name}"
        else
            display_name="$name"
        fi

        local status="pending"
        if is_module_analyzed "$name" "$parent" 2>/dev/null; then
            status="analyzed"
        fi

        printf "  %2d. %-35s [%s] (%s)\n" "$counter" "$display_name" "$complexity" "$status"
        ((counter++)) || true
    done < "$QUEUE_FILE"
    echo ""
    log_info "Total: $TOTAL_COUNT modules to analyze"
    echo ""
    log_info "After analysis, will also run:"
    echo "  - Phase 3: Markdown validation"
    echo "  - Phase 4: DOCX conversion"
    exit 0
}
