#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# JSON Manipulation Functions (jq utilities)
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
[[ -n "${_JSON_UTILS_LOADED:-}" ]] && return 0
_JSON_UTILS_LOADED=1

# Initialize analysis state - add analyzed:false to all modules/submodules
initialize_analysis_state() {
    log_info "Initializing analysis state..."

    # Check if already initialized (any module has 'analyzed' field)
    local has_state
    has_state=$(jq '[.modules[].analyzed // null] | any(. != null)' "$MODULE_STRUCTURE_FILE")

    if [[ "$has_state" == "true" && "$RESET_STATE" != "true" ]]; then
        log_info "Analysis state already exists. Use --reset to reinitialize."
        return 0
    fi

    # Add analyzed:false to all modules and submodules
    local tmp_file="${MODULE_STRUCTURE_FILE}.tmp"
    jq '
        .modules = [.modules[] |
            .analyzed = false |
            if .subModules and (.subModules | length > 0) then
                .subModules = [.subModules[] | .analyzed = false]
            else
                .
            end
        ]
    ' "$MODULE_STRUCTURE_FILE" > "$tmp_file"

    mv "$tmp_file" "$MODULE_STRUCTURE_FILE"
    log_success "Analysis state initialized"
}

# Reset all analyzed flags to false
reset_analysis_state() {
    log_info "Resetting all analysis states to false..."

    local tmp_file="${MODULE_STRUCTURE_FILE}.tmp"
    jq '
        .modules = [.modules[] |
            .analyzed = false |
            if .subModules and (.subModules | length > 0) then
                .subModules = [.subModules[] | .analyzed = false]
            else
                .
            end
        ]
    ' "$MODULE_STRUCTURE_FILE" > "$tmp_file"

    mv "$tmp_file" "$MODULE_STRUCTURE_FILE"

    # Clear failed modules file
    > "$FAILED_FILE" 2>/dev/null || true

    log_success "All analysis states reset"
}

# Mark a module as analyzed
# Usage: set_module_analyzed "ModuleName" [parent_module]
set_module_analyzed() {
    local module_name="$1"
    local parent_module="${2:-}"

    local tmp_file="${MODULE_STRUCTURE_FILE}.tmp"

    if [[ -n "$parent_module" ]]; then
        # It's a submodule
        jq --arg parent "$parent_module" --arg name "$module_name" '
            .modules = [.modules[] |
                if .name == $parent then
                    .subModules = [.subModules[] |
                        if .name == $name then
                            .analyzed = true
                        else
                            .
                        end
                    ]
                else
                    .
                end
            ]
        ' "$MODULE_STRUCTURE_FILE" > "$tmp_file"
    else
        # It's a parent module
        jq --arg name "$module_name" '
            .modules = [.modules[] |
                if .name == $name then
                    .analyzed = true
                else
                    .
                end
            ]
        ' "$MODULE_STRUCTURE_FILE" > "$tmp_file"
    fi

    mv "$tmp_file" "$MODULE_STRUCTURE_FILE"
    log_debug "Marked $module_name as analyzed"
}

# Check if a module is already analyzed
# Usage: is_module_analyzed "ModuleName" [parent_module]
# Returns: 0 if analyzed, 1 if not
is_module_analyzed() {
    local module_name="$1"
    local parent_module="${2:-}"

    local result

    if [[ -n "$parent_module" ]]; then
        # Check submodule
        result=$(jq -r --arg parent "$parent_module" --arg name "$module_name" '
            .modules[] |
            select(.name == $parent) |
            .subModules[] |
            select(.name == $name) |
            .analyzed // false
        ' "$MODULE_STRUCTURE_FILE")
    else
        # Check parent module
        result=$(jq -r --arg name "$module_name" '
            .modules[] |
            select(.name == $name) |
            .analyzed // false
        ' "$MODULE_STRUCTURE_FILE")
    fi

    [[ "$result" == "true" ]]
}

# Get complexity of a module
# Usage: get_module_complexity "ModuleName" [parent_module]
get_module_complexity() {
    local module_name="$1"
    local parent_module="${2:-}"

    local result

    if [[ -n "$parent_module" ]]; then
        result=$(jq -r --arg parent "$parent_module" --arg name "$module_name" '
            .modules[] |
            select(.name == $parent) |
            .subModules[] |
            select(.name == $name) |
            .metrics.complexity // "medium"
        ' "$MODULE_STRUCTURE_FILE")
    else
        result=$(jq -r --arg name "$module_name" '
            .modules[] |
            select(.name == $name) |
            .metrics.complexity // "medium"
        ' "$MODULE_STRUCTURE_FILE")
    fi

    echo "$result"
}

# Build the analysis queue in correct order
# Order: submodules first (sorted by complexity), then parents (sorted by complexity)
build_analysis_queue() {
    log_info "Building analysis queue..."

    local queue=()

    # Phase 1: All submodules sorted by complexity (low, medium, high)
    # Format: "SubmoduleName|ParentName|complexity"
    local submodules_low
    local submodules_medium
    local submodules_high

    submodules_low=$(jq -r '
        .modules[] |
        select(.subModules and (.subModules | length > 0)) |
        .name as $parent |
        .subModules[] |
        select(.metrics.complexity == "low") |
        "\(.name)|\($parent)|low"
    ' "$MODULE_STRUCTURE_FILE" | sort)

    submodules_medium=$(jq -r '
        .modules[] |
        select(.subModules and (.subModules | length > 0)) |
        .name as $parent |
        .subModules[] |
        select(.metrics.complexity == "medium") |
        "\(.name)|\($parent)|medium"
    ' "$MODULE_STRUCTURE_FILE" | sort)

    submodules_high=$(jq -r '
        .modules[] |
        select(.subModules and (.subModules | length > 0)) |
        .name as $parent |
        .subModules[] |
        select(.metrics.complexity == "high") |
        "\(.name)|\($parent)|high"
    ' "$MODULE_STRUCTURE_FILE" | sort)

    # Phase 2: Parent modules sorted by complexity
    # Format: "ModuleName||complexity"
    local parents_low
    local parents_medium
    local parents_high

    parents_low=$(jq -r '
        .modules[] |
        select(.metrics.complexity == "low") |
        "\(.name)||low"
    ' "$MODULE_STRUCTURE_FILE" | sort)

    parents_medium=$(jq -r '
        .modules[] |
        select(.metrics.complexity == "medium") |
        "\(.name)||medium"
    ' "$MODULE_STRUCTURE_FILE" | sort)

    parents_high=$(jq -r '
        .modules[] |
        select(.metrics.complexity == "high") |
        "\(.name)||high"
    ' "$MODULE_STRUCTURE_FILE" | sort)

    # Build queue file
    {
        # Submodules first (low -> medium -> high)
        echo "# Phase 1: Submodules (LOW complexity)"
        echo "$submodules_low" | grep -v '^$' || true
        echo "# Phase 1: Submodules (MEDIUM complexity)"
        echo "$submodules_medium" | grep -v '^$' || true
        echo "# Phase 1: Submodules (HIGH complexity)"
        echo "$submodules_high" | grep -v '^$' || true

        # Parent modules (low -> medium -> high)
        echo "# Phase 2: Parent Modules (LOW complexity)"
        echo "$parents_low" | grep -v '^$' || true
        echo "# Phase 2: Parent Modules (MEDIUM complexity)"
        echo "$parents_medium" | grep -v '^$' || true
        echo "# Phase 2: Parent Modules (HIGH complexity)"
        echo "$parents_high" | grep -v '^$' || true
    } > "$QUEUE_FILE"

    # Count total items
    TOTAL_COUNT=$(grep -v '^#' "$QUEUE_FILE" | grep -v '^$' | wc -l)

    log_success "Built analysis queue with $TOTAL_COUNT items"
}

# Get items from failed modules file for retry
get_failed_modules() {
    if [[ -f "$FAILED_FILE" ]]; then
        cat "$FAILED_FILE"
    fi
}
