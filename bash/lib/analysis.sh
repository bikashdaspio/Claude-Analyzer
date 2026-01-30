#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Analysis Functions - Core module analysis logic
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
[[ -n "${_ANALYSIS_LOADED:-}" ]] && return 0
_ANALYSIS_LOADED=1

# Get timeout based on complexity
# Returns 0 if no timeout should be applied
get_timeout() {
    local complexity="$1"

    # No timeout mode
    if [[ "$NO_TIMEOUT" == "true" ]]; then
        echo "0"
        return
    fi

    # Custom timeout override
    if [[ "$CUSTOM_TIMEOUT" -gt 0 ]]; then
        echo "$CUSTOM_TIMEOUT"
        return
    fi

    # Complexity-based timeout
    case "$complexity" in
        low)    echo "$TIMEOUT_LOW" ;;
        medium) echo "$TIMEOUT_MEDIUM" ;;
        high)   echo "$TIMEOUT_HIGH" ;;
        *)      echo "$TIMEOUT_MEDIUM" ;;
    esac
}

# Run claude analysis for a module
# Usage: run_claude_analysis "ModuleName" "log_file" "timeout_seconds"
run_claude_analysis() {
    local module_name="$1"
    local log_file="$2"
    local timeout_seconds="$3"

    local timeout_msg="no timeout"
    if [[ "$timeout_seconds" -gt 0 ]]; then
        timeout_msg="timeout: ${timeout_seconds}s"
    fi
    log_debug "Running claude analysis for: $module_name ($timeout_msg)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would analyze: $module_name"
        return 0
    fi

    # Run claude with or without timeout
    local exit_code
    if [[ "$timeout_seconds" -eq 0 ]]; then
        # No timeout - run indefinitely
        claude \
            --dangerously-skip-permissions \
            --print \
            --output-format text \
            "/analyze $module_name" \
            > "$log_file" 2>&1
        exit_code=$?
    else
        # Run with timeout
        timeout "$timeout_seconds" claude \
            --dangerously-skip-permissions \
            --print \
            --output-format text \
            "/analyze $module_name" \
            > "$log_file" 2>&1
        exit_code=$?
    fi

    if [[ $exit_code -eq 0 ]]; then
        return 0
    elif [[ $exit_code -eq 124 ]]; then
        log_error "Timeout analyzing $module_name after ${timeout_seconds}s"
        return 1
    else
        log_error "Claude analysis failed for $module_name (exit code: $exit_code)"
        return 1
    fi
}

# Analyze a single module
# Usage: analyze_single_module "ModuleName" "ParentModule" "complexity"
analyze_single_module() {
    local module_name="$1"
    local parent_module="$2"
    local complexity="$3"

    local display_name
    local log_file

    if [[ -n "$parent_module" ]]; then
        display_name="${parent_module}/${module_name}"
        log_file="$LOG_DIR/${parent_module}_${module_name}.log"
    else
        display_name="$module_name"
        log_file="$LOG_DIR/${module_name}.log"
    fi

    # Check if already analyzed
    if is_module_analyzed "$module_name" "$parent_module"; then
        log_info "Skipping $display_name (already analyzed)"
        ((SKIPPED_COUNT++)) || true
        return 0
    fi

    local timeout_seconds
    timeout_seconds=$(get_timeout "$complexity")

    echo ""
    log_info "Analyzing: ${BOLD}$display_name${NC} (complexity: $complexity, timeout: ${timeout_seconds}s)"

    # Run the analysis
    if run_claude_analysis "$display_name" "$log_file" "$timeout_seconds"; then
        # Mark as analyzed on success
        set_module_analyzed "$module_name" "$parent_module"
        log_success "Completed: $display_name"
        ((SUCCESS_COUNT++)) || true
        return 0
    else
        # Add to failed list
        if [[ -n "$parent_module" ]]; then
            echo "${module_name}|${parent_module}|${complexity}" >> "$FAILED_FILE"
        else
            echo "${module_name}||${complexity}" >> "$FAILED_FILE"
        fi
        log_error "Failed: $display_name (see $log_file)"
        ((FAILED_COUNT++)) || true
        return 1
    fi
}

# Sequential processing main loop
main_loop_sequential() {
    local queue_source="$1"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.* ]] && continue
        [[ -z "$line" ]] && continue

        # Parse: name|parent|complexity
        IFS='|' read -r name parent complexity <<< "$line"

        # Single module mode
        if [[ -n "$SINGLE_MODULE" ]]; then
            local full_name
            if [[ -n "$parent" ]]; then
                full_name="${parent}/${name}"
            else
                full_name="$name"
            fi
            if [[ "$full_name" != "$SINGLE_MODULE" && "$name" != "$SINGLE_MODULE" ]]; then
                continue
            fi
        fi

        analyze_single_module "$name" "$parent" "$complexity"

        # Delay between modules
        if [[ "$DELAY_SECONDS" -gt 0 && "$DRY_RUN" != "true" ]]; then
            sleep "$DELAY_SECONDS"
        fi

    done < "$queue_source"
}

# Main analysis loop dispatcher
main_loop() {
    local queue_source="$QUEUE_FILE"

    if [[ "$RETRY_FAILED" == "true" ]]; then
        if [[ ! -f "$FAILED_FILE" || ! -s "$FAILED_FILE" ]]; then
            log_info "No failed modules to retry"
            return 0
        fi
        queue_source="$FAILED_FILE"
        # Clear the failed file as we're retrying
        local failed_modules
        failed_modules=$(cat "$FAILED_FILE")
        > "$FAILED_FILE"
        echo "$failed_modules" | while IFS='|' read -r name parent complexity; do
            [[ -z "$name" ]] && continue
            analyze_single_module "$name" "$parent" "$complexity"

            # Delay between modules
            if [[ "$DELAY_SECONDS" -gt 0 && "$DRY_RUN" != "true" ]]; then
                sleep "$DELAY_SECONDS"
            fi
        done
        return 0
    fi

    # Check if running in parallel mode
    if [[ "$PARALLEL_JOBS" -gt 1 ]]; then
        main_loop_parallel "$queue_source"
    else
        main_loop_sequential "$queue_source"
    fi
}
