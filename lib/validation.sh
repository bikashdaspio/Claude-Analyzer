#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Markdown Validation Phase
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
[[ -n "${_VALIDATION_LOADED:-}" ]] && return 0
_VALIDATION_LOADED=1

# Find all markdown files in Documents directory
find_markdown_files() {
    if [[ ! -d "$DOCS_DIR" ]]; then
        log_warn "Documents directory not found: $DOCS_DIR"
        return 1
    fi

    find "$DOCS_DIR" -name "*.md" -type f -not -name "*.backup.md" 2>/dev/null | sort
}

# Run markdown validation for a single file
# Usage: run_validation "file_path" "log_file"
run_validation() {
    local file_path="$1"
    local log_file="$2"

    log_debug "Running markdown validation for: $file_path"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate: $file_path"
        return 0
    fi

    local exit_code
    claude \
        --dangerously-skip-permissions \
        --print \
        --output-format text \
        "/validate-markdown $file_path --auto-fix" \
        > "$log_file" 2>&1
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        return 0
    else
        log_error "Validation failed for $file_path (exit code: $exit_code)"
        return 1
    fi
}

# Validate a single markdown file in background (for parallel mode)
validate_file_bg() {
    local file_path="$1"
    local result_file="$2"
    local log_file="$3"

    local file_name
    file_name=$(basename "$file_path")

    log_info "[START] Validating: $file_name"

    if run_validation "$file_path" "$log_file"; then
        log_success "[DONE] Validated: $file_name"
        echo "success $file_path" > "$result_file"
        exit 0
    else
        log_error "[FAIL] Validation failed: $file_name (see $log_file)"
        echo "failed $file_path" > "$result_file"
        exit 1
    fi
}

# Launch validation as a background job
launch_validation_job() {
    local file_path="$1"
    local file_name
    file_name=$(basename "$file_path" .md)

    local result_file="$PARALLEL_RESULTS_DIR/result_val_$$_${RANDOM}"
    local log_file="$LOG_DIR/validation_${file_name}.log"

    # Launch in background
    (validate_file_bg "$file_path" "$result_file" "$log_file") &
    local pid=$!
    PARALLEL_PIDS+=("$pid")

    log_debug "Launched validation job PID $pid for $file_name"
}

# Collect validation result from completed job
collect_validation_result() {
    local pid="$1"
    local result_file="$PARALLEL_RESULTS_DIR/result_val_$pid"

    # Try different result file patterns
    for rf in "$PARALLEL_RESULTS_DIR"/result_val_*; do
        if [[ -f "$rf" ]]; then
            local status file_path
            read -r status file_path < "$rf"

            case "$status" in
                success)
                    ((VALIDATION_SUCCESS++)) || true
                    ;;
                failed)
                    ((VALIDATION_FAILED++)) || true
                    ;;
            esac
            rm -f "$rf"
        fi
    done
}

# Main validation loop (parallel)
validation_loop_parallel() {
    local md_files=()
    while IFS= read -r file; do
        md_files+=("$file")
    done < <(find_markdown_files)

    if [[ ${#md_files[@]} -eq 0 ]]; then
        log_warn "No markdown files found to validate"
        return 0
    fi

    log_info "Found ${#md_files[@]} markdown files to validate"
    log_info "Running validation in parallel with $PARALLEL_JOBS concurrent jobs"

    # Initialize parallel processing
    init_parallel
    trap cleanup_parallel EXIT

    local jobs_launched=0

    for file_path in "${md_files[@]}"; do
        # Wait for a slot if at capacity
        wait_for_slot

        # Launch the job
        launch_validation_job "$file_path"
        ((jobs_launched++)) || true

        # Small delay between launches
        if [[ "$DELAY_SECONDS" -gt 0 && "$DRY_RUN" != "true" ]]; then
            sleep 1
        fi
    done

    # Wait for all remaining jobs
    if [[ ${#PARALLEL_PIDS[@]} -gt 0 ]]; then
        wait_for_all_jobs
    fi

    # Collect any remaining results
    for rf in "$PARALLEL_RESULTS_DIR"/result_val_*; do
        if [[ -f "$rf" ]]; then
            local status file_path
            read -r status file_path < "$rf"
            case "$status" in
                success) ((VALIDATION_SUCCESS++)) || true ;;
                failed) ((VALIDATION_FAILED++)) || true ;;
            esac
            rm -f "$rf"
        fi
    done

    log_info "Validation complete. Launched $jobs_launched jobs."
}

# Main validation loop (sequential)
validation_loop_sequential() {
    local md_files=()
    while IFS= read -r file; do
        md_files+=("$file")
    done < <(find_markdown_files)

    if [[ ${#md_files[@]} -eq 0 ]]; then
        log_warn "No markdown files found to validate"
        return 0
    fi

    log_info "Found ${#md_files[@]} markdown files to validate"

    for file_path in "${md_files[@]}"; do
        local file_name
        file_name=$(basename "$file_path" .md)
        local log_file="$LOG_DIR/validation_${file_name}.log"

        log_info "Validating: $file_name"

        if run_validation "$file_path" "$log_file"; then
            log_success "Validated: $file_name"
            ((VALIDATION_SUCCESS++)) || true
        else
            log_error "Failed: $file_name (see $log_file)"
            ((VALIDATION_FAILED++)) || true
        fi

        # Delay between validations
        if [[ "$DELAY_SECONDS" -gt 0 && "$DRY_RUN" != "true" ]]; then
            sleep "$DELAY_SECONDS"
        fi
    done
}

# Run the validation phase
run_validation_phase() {
    print_header "PHASE 3: MARKDOWN VALIDATION"

    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_info "Skipping validation phase (--skip-validation)"
        return 0
    fi

    if [[ "$PARALLEL_JOBS" -gt 1 ]]; then
        validation_loop_parallel
    else
        validation_loop_sequential
    fi

    echo ""
    log_info "Validation Results:"
    echo -e "    ${GREEN}Successful:${NC} $VALIDATION_SUCCESS"
    echo -e "    ${RED}Failed:${NC}     $VALIDATION_FAILED"
}
