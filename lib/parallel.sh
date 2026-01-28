#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Parallel Processing Functions
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
[[ -n "${_PARALLEL_LOADED:-}" ]] && return 0
_PARALLEL_LOADED=1

# Initialize parallel processing
init_parallel() {
    PARALLEL_RESULTS_DIR="$STATE_DIR/parallel_results_$$"
    mkdir -p "$PARALLEL_RESULTS_DIR"
    PARALLEL_PIDS=()
}

# Cleanup parallel processing
cleanup_parallel() {
    if [[ -n "$PARALLEL_RESULTS_DIR" && -d "$PARALLEL_RESULTS_DIR" ]]; then
        rm -rf "$PARALLEL_RESULTS_DIR"
    fi
}

# Wait for a slot to become available when running at max capacity
wait_for_slot() {
    while [[ ${#PARALLEL_PIDS[@]} -ge $PARALLEL_JOBS ]]; do
        # Check for completed jobs
        local new_pids=()
        for pid in "${PARALLEL_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                new_pids+=("$pid")
            else
                # Job completed, collect result
                wait "$pid" 2>/dev/null || true
                collect_parallel_result "$pid"
            fi
        done
        PARALLEL_PIDS=("${new_pids[@]}")

        # Still at capacity, wait a bit
        if [[ ${#PARALLEL_PIDS[@]} -ge $PARALLEL_JOBS ]]; then
            sleep 1
        fi
    done
}

# Wait for all parallel jobs to complete
wait_for_all_jobs() {
    log_info "Waiting for ${#PARALLEL_PIDS[@]} remaining jobs to complete..."
    for pid in "${PARALLEL_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
        collect_parallel_result "$pid"
    done
    PARALLEL_PIDS=()
}

# Collect result from a completed parallel job
collect_parallel_result() {
    local pid="$1"
    local result_file="$PARALLEL_RESULTS_DIR/result_$pid"

    if [[ -f "$result_file" ]]; then
        local status module_name parent_module
        read -r status module_name parent_module < "$result_file"

        case "$status" in
            success)
                ((SUCCESS_COUNT++)) || true
                ;;
            failed)
                ((FAILED_COUNT++)) || true
                ;;
            skipped)
                ((SKIPPED_COUNT++)) || true
                ;;
        esac
        rm -f "$result_file"
    fi
}

# Analyze a single module in background (for parallel mode)
# Usage: analyze_single_module_bg "ModuleName" "ParentModule" "complexity" "result_file"
analyze_single_module_bg() {
    local module_name="$1"
    local parent_module="$2"
    local complexity="$3"
    local result_file="$4"

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
        echo "skipped $module_name $parent_module" > "$result_file"
        log_info "[SKIP] $display_name (already analyzed)"
        exit 0
    fi

    local timeout_seconds
    timeout_seconds=$(get_timeout "$complexity")

    local timeout_msg="no timeout"
    if [[ "$timeout_seconds" -gt 0 ]]; then
        timeout_msg="timeout: ${timeout_seconds}s"
    fi
    log_info "[START] $display_name (complexity: $complexity, $timeout_msg)"

    # Run the analysis
    if run_claude_analysis "$display_name" "$log_file" "$timeout_seconds"; then
        # Mark as analyzed on success
        set_module_analyzed "$module_name" "$parent_module"
        log_success "[DONE] $display_name"
        echo "success $module_name $parent_module" > "$result_file"
        exit 0
    else
        # Add to failed list
        if [[ -n "$parent_module" ]]; then
            echo "${module_name}|${parent_module}|${complexity}" >> "$FAILED_FILE"
        else
            echo "${module_name}||${complexity}" >> "$FAILED_FILE"
        fi
        log_error "[FAIL] $display_name (see $log_file)"
        echo "failed $module_name $parent_module" > "$result_file"
        exit 1
    fi
}

# Launch a module analysis as a background job
launch_parallel_job() {
    local name="$1"
    local parent="$2"
    local complexity="$3"

    local result_file="$PARALLEL_RESULTS_DIR/result_$$_${RANDOM}"

    # Launch in background
    (analyze_single_module_bg "$name" "$parent" "$complexity" "$result_file") &
    local pid=$!
    PARALLEL_PIDS+=("$pid")

    log_debug "Launched job PID $pid for ${parent:+$parent/}$name"
}

# Parallel processing main loop
main_loop_parallel() {
    local queue_source="$1"

    log_info "Running in parallel mode with $PARALLEL_JOBS concurrent jobs"

    # Initialize parallel processing
    init_parallel
    trap cleanup_parallel EXIT

    local jobs_launched=0

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

        # Skip already analyzed in the parent process to avoid launching unnecessary jobs
        if is_module_analyzed "$name" "$parent" 2>/dev/null; then
            log_info "[SKIP] ${parent:+$parent/}$name (already analyzed)"
            ((SKIPPED_COUNT++)) || true
            continue
        fi

        # Wait for a slot if at capacity
        wait_for_slot

        # Launch the job
        launch_parallel_job "$name" "$parent" "$complexity"
        ((jobs_launched++)) || true

        # Small delay between launches to prevent overwhelming the system
        if [[ "$DELAY_SECONDS" -gt 0 && "$DRY_RUN" != "true" ]]; then
            sleep "$DELAY_SECONDS"
        fi

    done < "$queue_source"

    # Wait for all remaining jobs
    if [[ ${#PARALLEL_PIDS[@]} -gt 0 ]]; then
        wait_for_all_jobs
    fi

    log_info "Parallel processing complete. Launched $jobs_launched jobs."
}
