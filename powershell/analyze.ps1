#Requires -Version 5.1
<#
.SYNOPSIS
    Project Module Analysis Script

.DESCRIPTION
    Iteratively analyzes all modules from module-structure.json using Claude CLI
    in bypass permission mode, tracking progress via an 'analyzed' property.

    This script sources modular components from the lib/ directory:
      - lib/config.ps1        - Configuration variables and constants
      - lib/logging.ps1       - Logging functions
      - lib/prerequisites.ps1 - Prerequisite checks
      - lib/json-utils.ps1    - JSON manipulation (jq utilities)
      - lib/analysis.ps1      - Core analysis functions
      - lib/parallel.ps1      - Parallel processing functions
      - lib/validation.ps1    - Markdown validation phase
      - lib/conversion.ps1    - DOCX conversion phase
      - lib/cli.ps1           - CLI interface and argument parsing

.EXAMPLE
    .\analyze.ps1 --dry-run
    Preview the analysis queue

.EXAMPLE
    .\analyze.ps1 --parallel 4
    Run analysis with 4 parallel jobs

.EXAMPLE
    .\analyze.ps1 --module Employee
    Analyze only the Employee module
#>

[CmdletBinding()]
param()

# Stop on errors
$ErrorActionPreference = "Stop"

# ═══════════════════════════════════════════════════════════════════════════════
# Determine script directory
# ═══════════════════════════════════════════════════════════════════════════════

$script:SCRIPT_DIR = $PSScriptRoot
$LIB_DIR = Join-Path $script:SCRIPT_DIR "lib"

# ═══════════════════════════════════════════════════════════════════════════════
# Source modular components (in order of dependencies)
# ═══════════════════════════════════════════════════════════════════════════════

. (Join-Path $LIB_DIR "config.ps1")
. (Join-Path $LIB_DIR "logging.ps1")
. (Join-Path $LIB_DIR "prerequisites.ps1")
. (Join-Path $LIB_DIR "json-utils.ps1")
. (Join-Path $LIB_DIR "parallel.ps1")
. (Join-Path $LIB_DIR "analysis.ps1")
. (Join-Path $LIB_DIR "validation.ps1")
. (Join-Path $LIB_DIR "conversion.ps1")
. (Join-Path $LIB_DIR "cli.ps1")

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

function Main {
    param([string[]]$Arguments)

    # Parse command line arguments
    Read-Arguments -Arguments $Arguments

    Write-Header "MODULE ANALYSIS"

    # Check prerequisites (creates state directories)
    Test-Prerequisites

    # Record session start
    try {
        Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Out-File -FilePath $script:SESSION_FILE -Encoding UTF8 -NoNewline
    } catch {}

    # Handle reset
    if ($script:RESET_STATE) {
        Reset-AnalysisState
        if (-not $script:DRY_RUN -and -not $script:SINGLE_MODULE -and -not $script:RETRY_FAILED) {
            # If only --reset was specified, exit after resetting
            $argCount = $Arguments.Count
            if ($argCount -eq 1 -or ($argCount -eq 2 -and $script:VERBOSE_MODE)) {
                Write-LogSuccess "Reset complete. Run without --reset to start analysis."
                exit 0
            }
        }
    }

    # Initialize state if needed
    Initialize-AnalysisState

    # Build analysis queue
    Build-AnalysisQueue

    # Show queue in dry-run mode
    if ($script:DRY_RUN) {
        Show-DryRunPreview
    }

    # Handle --validation-only mode
    if ($script:VALIDATION_ONLY) {
        Invoke-ValidationPhase
        exit 0
    }

    # Handle --conversion-only mode
    if ($script:CONVERSION_ONLY) {
        Invoke-ConversionPhase
        exit 0
    }

    # Run main analysis loop (Phase 1 & 2)
    Write-LogInfo "Starting analysis..."
    Invoke-MainLoop

    # Phase 3: Markdown Validation
    Invoke-ValidationPhase

    # Phase 4: DOCX Conversion
    Invoke-ConversionPhase

    # Print summary
    Write-Summary
}

# Run main with all arguments
try {
    Main -Arguments $args
} catch {
    Write-Host ""
    Write-LogWarn "Script interrupted. Progress has been saved."
    Write-LogInfo "Resume with: .\analyze.ps1"
    Write-Summary
    throw
}
