#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# DOCX Conversion Phase
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
[[ -n "${_CONVERSION_LOADED:-}" ]] && return 0
_CONVERSION_LOADED=1

# Convert a single markdown file to DOCX
# Usage: convert_to_docx "md_file" "docx_output"
convert_to_docx() {
    local md_file="$1"
    local docx_output="$2"

    log_debug "Converting: $md_file -> $docx_output"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would convert: $md_file -> $docx_output"
        return 0
    fi

    # Ensure output directory exists
    mkdir -p "$(dirname "$docx_output")"

    # Run pandoc conversion
    local exit_code
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local ref_doc_path
    ref_doc_path="$(dirname "$script_dir")/custom-reference.docx"

    pandoc "$md_file" \
        -f markdown \
        -t docx \
        --wrap=auto \
        --reference-doc="$ref_doc_path" \
        -o "$docx_output" \
        2>"$LOG_DIR/conversion_$(basename "$md_file" .md).log"
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        return 0
    else
        log_error "Conversion failed for $md_file (exit code: $exit_code)"
        return 1
    fi
}

# Convert file in background (for parallel mode)
convert_file_bg() {
    local md_file="$1"
    local docx_output="$2"
    local result_file="$3"

    local file_name
    file_name=$(basename "$md_file" .md)

    log_info "[START] Converting: $file_name"

    if convert_to_docx "$md_file" "$docx_output"; then
        log_success "[DONE] Converted: $file_name -> $(basename "$docx_output")"
        echo "success $md_file" > "$result_file"
        exit 0
    else
        log_error "[FAIL] Conversion failed: $file_name"
        echo "failed $md_file" > "$result_file"
        exit 1
    fi
}

# Launch conversion as a background job
launch_conversion_job() {
    local md_file="$1"
    local docx_output="$2"

    local result_file="$PARALLEL_RESULTS_DIR/result_conv_$$_${RANDOM}"

    # Launch in background
    (convert_file_bg "$md_file" "$docx_output" "$result_file") &
    local pid=$!
    PARALLEL_PIDS+=("$pid")

    log_debug "Launched conversion job PID $pid for $(basename "$md_file")"
}

# Derive DOCX output path from markdown file
get_docx_output_path() {
    local md_file="$1"

    # Get relative path from Documents dir
    local rel_path="${md_file#$DOCS_DIR/}"
    local dir_part
    dir_part=$(dirname "$rel_path")
    local base_name
    base_name=$(basename "$md_file" .md)

    # Create output path: Documents/DOCX/{subdir}/{filename}.docx
    if [[ "$dir_part" == "." ]]; then
        echo "$DOCX_OUTPUT_DIR/${base_name}.docx"
    else
        echo "$DOCX_OUTPUT_DIR/${dir_part}/${base_name}.docx"
    fi
}

# Main conversion loop (parallel)
conversion_loop_parallel() {
    local md_files=()
    while IFS= read -r file; do
        md_files+=("$file")
    done < <(find_markdown_files)

    if [[ ${#md_files[@]} -eq 0 ]]; then
        log_warn "No markdown files found to convert"
        return 0
    fi

    log_info "Found ${#md_files[@]} markdown files to convert"
    log_info "Running conversion in parallel with $PARALLEL_JOBS concurrent jobs"

    # Create output directory
    mkdir -p "$DOCX_OUTPUT_DIR"

    # Initialize parallel processing
    init_parallel
    trap cleanup_parallel EXIT

    local jobs_launched=0

    for md_file in "${md_files[@]}"; do
        local docx_output
        docx_output=$(get_docx_output_path "$md_file")

        # Wait for a slot if at capacity
        wait_for_slot

        # Launch the job
        launch_conversion_job "$md_file" "$docx_output"
        ((jobs_launched++)) || true
    done

    # Wait for all remaining jobs
    if [[ ${#PARALLEL_PIDS[@]} -gt 0 ]]; then
        wait_for_all_jobs
    fi

    # Collect any remaining results
    for rf in "$PARALLEL_RESULTS_DIR"/result_conv_*; do
        if [[ -f "$rf" ]]; then
            local status file_path
            read -r status file_path < "$rf"
            case "$status" in
                success) ((CONVERSION_SUCCESS++)) || true ;;
                failed) ((CONVERSION_FAILED++)) || true ;;
            esac
            rm -f "$rf"
        fi
    done

    log_info "Conversion complete. Launched $jobs_launched jobs."
}

# Main conversion loop (sequential)
conversion_loop_sequential() {
    local md_files=()
    while IFS= read -r file; do
        md_files+=("$file")
    done < <(find_markdown_files)

    if [[ ${#md_files[@]} -eq 0 ]]; then
        log_warn "No markdown files found to convert"
        return 0
    fi

    log_info "Found ${#md_files[@]} markdown files to convert"

    # Create output directory
    mkdir -p "$DOCX_OUTPUT_DIR"

    for md_file in "${md_files[@]}"; do
        local file_name
        file_name=$(basename "$md_file" .md)
        local docx_output
        docx_output=$(get_docx_output_path "$md_file")

        log_info "Converting: $file_name"

        if convert_to_docx "$md_file" "$docx_output"; then
            log_success "Converted: $file_name -> $(basename "$docx_output")"
            ((CONVERSION_SUCCESS++)) || true
        else
            log_error "Failed: $file_name"
            ((CONVERSION_FAILED++)) || true
        fi
    done
}

# Run the conversion phase
run_conversion_phase() {
    print_header "PHASE 4: DOCX CONVERSION"

    if [[ "$SKIP_CONVERSION" == "true" ]]; then
        log_info "Skipping conversion phase (--skip-conversion)"
        return 0
    fi

    # Check pandoc is available
    if ! check_pandoc; then
        log_error "Cannot proceed with conversion without pandoc"
        return 1
    fi

    if [[ "$PARALLEL_JOBS" -gt 1 ]]; then
        conversion_loop_parallel
    else
        conversion_loop_sequential
    fi

    echo ""
    log_info "Conversion Results:"
    echo -e "    ${GREEN}Successful:${NC} $CONVERSION_SUCCESS"
    echo -e "    ${RED}Failed:${NC}     $CONVERSION_FAILED"
    echo ""
    log_info "DOCX files saved to: $DOCX_OUTPUT_DIR"
}
