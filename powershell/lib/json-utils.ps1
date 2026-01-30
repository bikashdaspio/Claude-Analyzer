# ═══════════════════════════════════════════════════════════════════════════════
# JSON Manipulation Functions (jq utilities)
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
if ($script:_JSON_UTILS_LOADED) { return }
$script:_JSON_UTILS_LOADED = $true

# Initialize analysis state - add analyzed:false to all modules/submodules
function Initialize-AnalysisState {
    Write-LogInfo "Initializing analysis state..."

    # Check if already initialized (any module has 'analyzed' field)
    $hasState = & jq '[.modules[].analyzed // null] | any(. != null)' $script:MODULE_STRUCTURE_FILE 2>$null

    if ($hasState -eq "true" -and -not $script:RESET_STATE) {
        Write-LogInfo "Analysis state already exists. Use --reset to reinitialize."
        return
    }

    # Add analyzed:false to all modules and submodules
    $tmpFile = "$script:MODULE_STRUCTURE_FILE.tmp"
    $jqScript = @'
.modules = [.modules[] |
    .analyzed = false |
    if .subModules and (.subModules | length > 0) then
        .subModules = [.subModules[] | .analyzed = false]
    else
        .
    end
]
'@

    & jq $jqScript $script:MODULE_STRUCTURE_FILE | Out-File -FilePath $tmpFile -Encoding UTF8 -NoNewline
    Move-Item -Path $tmpFile -Destination $script:MODULE_STRUCTURE_FILE -Force

    Write-LogSuccess "Analysis state initialized"
}

# Reset all analyzed flags to false
function Reset-AnalysisState {
    Write-LogInfo "Resetting all analysis states to false..."

    $tmpFile = "$script:MODULE_STRUCTURE_FILE.tmp"
    $jqScript = @'
.modules = [.modules[] |
    .analyzed = false |
    if .subModules and (.subModules | length > 0) then
        .subModules = [.subModules[] | .analyzed = false]
    else
        .
    end
]
'@

    & jq $jqScript $script:MODULE_STRUCTURE_FILE | Out-File -FilePath $tmpFile -Encoding UTF8 -NoNewline
    Move-Item -Path $tmpFile -Destination $script:MODULE_STRUCTURE_FILE -Force

    # Clear failed modules file
    if (Test-Path $script:FAILED_FILE) {
        Clear-Content $script:FAILED_FILE -ErrorAction SilentlyContinue
    }

    Write-LogSuccess "All analysis states reset"
}

# Mark a module as analyzed
# Usage: Set-ModuleAnalyzed "ModuleName" [parent_module]
function Set-ModuleAnalyzed {
    param(
        [Parameter(Mandatory=$true)][string]$ModuleName,
        [string]$ParentModule = ""
    )

    $tmpFile = "$script:MODULE_STRUCTURE_FILE.tmp"

    if ($ParentModule) {
        # It's a submodule
        $jqScript = @"
.modules = [.modules[] |
    if .name == "$ParentModule" then
        .subModules = [.subModules[] |
            if .name == "$ModuleName" then
                .analyzed = true
            else
                .
            end
        ]
    else
        .
    end
]
"@
    } else {
        # It's a parent module
        $jqScript = @"
.modules = [.modules[] |
    if .name == "$ModuleName" then
        .analyzed = true
    else
        .
    end
]
"@
    }

    & jq $jqScript $script:MODULE_STRUCTURE_FILE | Out-File -FilePath $tmpFile -Encoding UTF8 -NoNewline
    Move-Item -Path $tmpFile -Destination $script:MODULE_STRUCTURE_FILE -Force

    Write-LogDebug "Marked $ModuleName as analyzed"
}

# Check if a module is already analyzed
# Usage: Test-ModuleAnalyzed "ModuleName" [parent_module]
# Returns: $true if analyzed, $false if not
function Test-ModuleAnalyzed {
    param(
        [Parameter(Mandatory=$true)][string]$ModuleName,
        [string]$ParentModule = ""
    )

    if ($ParentModule) {
        # Check submodule
        $result = & jq -r --arg parent $ParentModule --arg name $ModuleName '
            .modules[] |
            select(.name == $parent) |
            .subModules[] |
            select(.name == $name) |
            .analyzed // false
        ' $script:MODULE_STRUCTURE_FILE 2>$null
    } else {
        # Check parent module
        $result = & jq -r --arg name $ModuleName '
            .modules[] |
            select(.name == $name) |
            .analyzed // false
        ' $script:MODULE_STRUCTURE_FILE 2>$null
    }

    return ($result -eq "true")
}

# Get complexity of a module
# Usage: Get-ModuleComplexity "ModuleName" [parent_module]
function Get-ModuleComplexity {
    param(
        [Parameter(Mandatory=$true)][string]$ModuleName,
        [string]$ParentModule = ""
    )

    if ($ParentModule) {
        $result = & jq -r --arg parent $ParentModule --arg name $ModuleName '
            .modules[] |
            select(.name == $parent) |
            .subModules[] |
            select(.name == $name) |
            .metrics.complexity // "medium"
        ' $script:MODULE_STRUCTURE_FILE 2>$null
    } else {
        $result = & jq -r --arg name $ModuleName '
            .modules[] |
            select(.name == $name) |
            .metrics.complexity // "medium"
        ' $script:MODULE_STRUCTURE_FILE 2>$null
    }

    return $result
}

# Build the analysis queue in correct order
# Order: submodules first (sorted by complexity), then parents (sorted by complexity)
function Build-AnalysisQueue {
    Write-LogInfo "Building analysis queue..."

    # Phase 1: All submodules sorted by complexity (low, medium, high)
    # Format: "SubmoduleName|ParentName|complexity"
    $submodulesLow = & jq -r '
        .modules[] |
        select(.subModules and (.subModules | length > 0)) |
        .name as $parent |
        .subModules[] |
        select(.metrics.complexity == "low") |
        "\(.name)|\($parent)|low"
    ' $script:MODULE_STRUCTURE_FILE 2>$null | Sort-Object

    $submodulesMedium = & jq -r '
        .modules[] |
        select(.subModules and (.subModules | length > 0)) |
        .name as $parent |
        .subModules[] |
        select(.metrics.complexity == "medium") |
        "\(.name)|\($parent)|medium"
    ' $script:MODULE_STRUCTURE_FILE 2>$null | Sort-Object

    $submodulesHigh = & jq -r '
        .modules[] |
        select(.subModules and (.subModules | length > 0)) |
        .name as $parent |
        .subModules[] |
        select(.metrics.complexity == "high") |
        "\(.name)|\($parent)|high"
    ' $script:MODULE_STRUCTURE_FILE 2>$null | Sort-Object

    # Phase 2: Parent modules sorted by complexity
    # Format: "ModuleName||complexity"
    $parentsLow = & jq -r '
        .modules[] |
        select(.metrics.complexity == "low") |
        "\(.name)||low"
    ' $script:MODULE_STRUCTURE_FILE 2>$null | Sort-Object

    $parentsMedium = & jq -r '
        .modules[] |
        select(.metrics.complexity == "medium") |
        "\(.name)||medium"
    ' $script:MODULE_STRUCTURE_FILE 2>$null | Sort-Object

    $parentsHigh = & jq -r '
        .modules[] |
        select(.metrics.complexity == "high") |
        "\(.name)||high"
    ' $script:MODULE_STRUCTURE_FILE 2>$null | Sort-Object

    # Build queue file
    $queueContent = @()
    $queueContent += "# Phase 1: Submodules (LOW complexity)"
    if ($submodulesLow) { $queueContent += $submodulesLow | Where-Object { $_ -ne "" } }
    $queueContent += "# Phase 1: Submodules (MEDIUM complexity)"
    if ($submodulesMedium) { $queueContent += $submodulesMedium | Where-Object { $_ -ne "" } }
    $queueContent += "# Phase 1: Submodules (HIGH complexity)"
    if ($submodulesHigh) { $queueContent += $submodulesHigh | Where-Object { $_ -ne "" } }
    $queueContent += "# Phase 2: Parent Modules (LOW complexity)"
    if ($parentsLow) { $queueContent += $parentsLow | Where-Object { $_ -ne "" } }
    $queueContent += "# Phase 2: Parent Modules (MEDIUM complexity)"
    if ($parentsMedium) { $queueContent += $parentsMedium | Where-Object { $_ -ne "" } }
    $queueContent += "# Phase 2: Parent Modules (HIGH complexity)"
    if ($parentsHigh) { $queueContent += $parentsHigh | Where-Object { $_ -ne "" } }

    $queueContent | Out-File -FilePath $script:QUEUE_FILE -Encoding UTF8

    # Count total items
    $script:TOTAL_COUNT = ($queueContent | Where-Object { $_ -notmatch "^#" -and $_ -ne "" }).Count

    Write-LogSuccess "Built analysis queue with $script:TOTAL_COUNT items"
}

# Get items from failed modules file for retry
function Get-FailedModules {
    if (Test-Path $script:FAILED_FILE) {
        Get-Content $script:FAILED_FILE -ErrorAction SilentlyContinue
    }
}
