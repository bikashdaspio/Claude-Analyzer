# ═══════════════════════════════════════════════════════════════════════════════
# CLI Interface - Help and Argument Parsing
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
if ($script:_CLI_LOADED) { return }
$script:_CLI_LOADED = $true

function Show-Help {
    $scriptName = $MyInvocation.ScriptName
    if (-not $scriptName) { $scriptName = "analyze.ps1" }

    $helpText = @"
Module Analysis Script

Usage: $scriptName [OPTIONS]

OPTIONS:
    --dry-run           Show what would be analyzed without running
    --reset             Reset all 'analyzed' flags to false
    --module NAME       Analyze only the specified module (e.g., "Employee" or "Employee/Profile")
    --retry-failed      Retry only previously failed modules
    --delay SECONDS     Delay between module analyses (default: 5)
    --parallel N, -p N  Run N modules in parallel (default: 1, max: $script:MAX_PARALLEL)
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
      - Low complexity:    $($script:TIMEOUT_LOW)s ($([math]::Floor($script:TIMEOUT_LOW / 60)) minutes)
      - Medium complexity: $($script:TIMEOUT_MEDIUM)s ($([math]::Floor($script:TIMEOUT_MEDIUM / 60)) minutes)
      - High complexity:   $($script:TIMEOUT_HIGH)s ($([math]::Floor($script:TIMEOUT_HIGH / 60)) minutes)

    Use --no-timeout to disable timeouts entirely (recommended for large modules).
    Use --timeout SECONDS to set a custom timeout for all modules.

EXAMPLES:
    $scriptName                          # Full workflow: analyze, validate, convert
    $scriptName --dry-run                # Preview the analysis queue
    $scriptName --reset                  # Reset all progress and start fresh
    $scriptName --module Employee        # Analyze only the Employee module
    $scriptName --module Employee/Profile # Analyze only the Profile submodule
    $scriptName --retry-failed           # Retry failed modules from previous run
    $scriptName --delay 10               # Wait 10 seconds between modules
    $scriptName --parallel 4             # Run 4 modules in parallel
    $scriptName -p 4 --no-timeout        # Parallel with no timeout
    $scriptName --timeout 3600           # Set 1-hour timeout for all modules
    $scriptName -p 3 --timeout 1800      # 3 parallel jobs, 30-min timeout each
    $scriptName --validation-only -p 4   # Only validate markdown files (4 parallel)
    $scriptName --conversion-only        # Only convert to DOCX
    $scriptName --skip-validation        # Skip validation, do analysis + conversion

OUTPUT:
    Documents/             Generated markdown files from analysis
    Documents/DOCX/        Converted Word documents

STATE FILES:
    module-structure.json     Source of modules (modified to track progress)
    .analyze-state/           State persistence directory
    .analyze-state/logs/      Per-module log files
    .analyze-state/analyze.log Main log file

"@
    Write-Host $helpText
}

function Read-Arguments {
    param([string[]]$Arguments)

    $i = 0
    while ($i -lt $Arguments.Count) {
        $arg = $Arguments[$i]

        switch -Regex ($arg) {
            "^--dry-run$" {
                $script:DRY_RUN = $true
            }
            "^--reset$" {
                $script:RESET_STATE = $true
            }
            "^--module$" {
                $i++
                if ($i -lt $Arguments.Count) {
                    $script:SINGLE_MODULE = $Arguments[$i]
                } else {
                    Write-LogError "--module requires a module name"
                    exit 1
                }
            }
            "^--retry-failed$" {
                $script:RETRY_FAILED = $true
            }
            "^--delay$" {
                $i++
                if ($i -lt $Arguments.Count -and $Arguments[$i] -match "^\d+$") {
                    $script:DELAY_SECONDS = [int]$Arguments[$i]
                } else {
                    Write-LogError "--delay requires a numeric value"
                    exit 1
                }
            }
            "^(--parallel|-p)$" {
                $i++
                if ($i -lt $Arguments.Count -and $Arguments[$i] -match "^\d+$") {
                    $script:PARALLEL_JOBS = [int]$Arguments[$i]
                    if ($script:PARALLEL_JOBS -lt 1) {
                        $script:PARALLEL_JOBS = 1
                    } elseif ($script:PARALLEL_JOBS -gt $script:MAX_PARALLEL) {
                        Write-LogWarn "Limiting parallel jobs to $script:MAX_PARALLEL (requested: $script:PARALLEL_JOBS)"
                        $script:PARALLEL_JOBS = $script:MAX_PARALLEL
                    }
                } else {
                    Write-LogError "--parallel requires a numeric value"
                    exit 1
                }
            }
            "^--no-timeout$" {
                $script:NO_TIMEOUT = $true
            }
            "^--timeout$" {
                $i++
                if ($i -lt $Arguments.Count -and $Arguments[$i] -match "^\d+$") {
                    $script:CUSTOM_TIMEOUT = [int]$Arguments[$i]
                } else {
                    Write-LogError "--timeout requires a numeric value in seconds"
                    exit 1
                }
            }
            "^--verbose$" {
                $script:VERBOSE_MODE = $true
            }
            "^--skip-validation$" {
                $script:SKIP_VALIDATION = $true
            }
            "^--skip-conversion$" {
                $script:SKIP_CONVERSION = $true
            }
            "^--validation-only$" {
                $script:VALIDATION_ONLY = $true
            }
            "^--conversion-only$" {
                $script:CONVERSION_ONLY = $true
            }
            "^(--help|-h)$" {
                Show-Help
                exit 0
            }
            default {
                Write-LogError "Unknown option: $arg"
                Show-Help
                exit 1
            }
        }
        $i++
    }
}

# Print summary at the end
function Write-Summary {
    $totalModules = & jq '.modules | length' $script:MODULE_STRUCTURE_FILE 2>$null
    if (-not $totalModules) { $totalModules = 0 }

    $totalSubmodules = & jq '[.modules[].subModules // [] | length] | add' $script:MODULE_STRUCTURE_FILE 2>$null
    if (-not $totalSubmodules) { $totalSubmodules = 0 }

    $analyzedModules = & jq '[.modules[] | select(.analyzed == true)] | length' $script:MODULE_STRUCTURE_FILE 2>$null
    if (-not $analyzedModules) { $analyzedModules = 0 }

    $analyzedSubmodules = & jq '[.modules[].subModules // [] | .[] | select(.analyzed == true)] | length' $script:MODULE_STRUCTURE_FILE 2>$null
    if (-not $analyzedSubmodules) { $analyzedSubmodules = 0 }

    Write-Header "WORKFLOW COMPLETE"

    if (-not $script:VALIDATION_ONLY -and -not $script:CONVERSION_ONLY) {
        Write-Host "  Phase 1 & 2: Module Analysis"
        Write-Host "    Modules:     $analyzedModules / $totalModules analyzed"
        Write-Host "    Sub-modules: $analyzedSubmodules / $totalSubmodules analyzed"
        Write-Host ""
        Write-Host "    Results:"
        Write-Host "      " -NoNewline
        Write-Host "Successful: " -ForegroundColor Green -NoNewline
        Write-Host $script:SUCCESS_COUNT
        Write-Host "      " -NoNewline
        Write-Host "Failed:     " -ForegroundColor Red -NoNewline
        Write-Host $script:FAILED_COUNT
        Write-Host "      " -NoNewline
        Write-Host "Skipped:    " -ForegroundColor Yellow -NoNewline
        Write-Host $script:SKIPPED_COUNT
        Write-Host ""
    }

    if (-not $script:SKIP_VALIDATION -and -not $script:CONVERSION_ONLY) {
        Write-Host "  Phase 3: Markdown Validation"
        Write-Host "      " -NoNewline
        Write-Host "Validated: " -ForegroundColor Green -NoNewline
        Write-Host $script:VALIDATION_SUCCESS
        Write-Host "      " -NoNewline
        Write-Host "Failed:    " -ForegroundColor Red -NoNewline
        Write-Host $script:VALIDATION_FAILED
        Write-Host ""
    }

    if (-not $script:SKIP_CONVERSION -and -not $script:VALIDATION_ONLY) {
        Write-Host "  Phase 4: DOCX Conversion"
        Write-Host "      " -NoNewline
        Write-Host "Converted: " -ForegroundColor Green -NoNewline
        Write-Host $script:CONVERSION_SUCCESS
        Write-Host "      " -NoNewline
        Write-Host "Failed:    " -ForegroundColor Red -NoNewline
        Write-Host $script:CONVERSION_FAILED
        Write-Host ""
        if ($script:CONVERSION_SUCCESS -gt 0) {
            Write-Host "    Output: $script:DOCX_OUTPUT_DIR"
            Write-Host ""
        }
    }

    Write-Host "  Logs directory: $script:LOG_DIR"

    if ((Test-Path $script:FAILED_FILE) -and (Get-Item $script:FAILED_FILE -ErrorAction SilentlyContinue).Length -gt 0) {
        Write-Host ""
        Write-Host "  " -NoNewline
        Write-Host "Failed modules can be retried with: " -ForegroundColor Yellow -NoNewline
        Write-Host "./analyze.ps1 --retry-failed"
    }

    Write-Host ""
    Write-Host "$([char]0x2550)" -NoNewline
    for ($i = 0; $i -lt 63; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host ""
}

# Show dry-run preview
function Show-DryRunPreview {
    # Handle validation-only dry run
    if ($script:VALIDATION_ONLY) {
        Write-Header "VALIDATION PREVIEW (DRY RUN)"
        Write-Host "The following markdown files would be validated:"
        Write-Host ""

        $mdFiles = Find-MarkdownFiles
        if ($mdFiles.Count -eq 0) {
            Write-LogWarn "No markdown files found in $script:DOCS_DIR"
        } else {
            $counter = 1
            foreach ($file in $mdFiles) {
                Write-Host ("  {0,2}. {1}" -f $counter, $file)
                $counter++
            }
            Write-Host ""
            Write-LogInfo "Total: $($mdFiles.Count) files to validate"
        }
        exit 0
    }

    # Handle conversion-only dry run
    if ($script:CONVERSION_ONLY) {
        Write-Header "CONVERSION PREVIEW (DRY RUN)"
        Write-Host "The following markdown files would be converted to DOCX:"
        Write-Host ""

        $mdFiles = Find-MarkdownFiles
        if ($mdFiles.Count -eq 0) {
            Write-LogWarn "No markdown files found in $script:DOCS_DIR"
        } else {
            $counter = 1
            foreach ($file in $mdFiles) {
                $docxOut = Get-DocxOutputPath -MdFile $file
                Write-Host ("  {0,2}. {1}" -f $counter, $file)
                Write-Host ("      -> {0}" -f $docxOut)
                $counter++
            }
            Write-Host ""
            Write-LogInfo "Total: $($mdFiles.Count) files to convert"
        }
        exit 0
    }

    # Regular analysis dry run
    Write-Header "ANALYSIS QUEUE (DRY RUN)"
    Write-Host "The following modules would be analyzed in order:"
    Write-Host ""

    $counter = 1
    $lines = Get-Content $script:QUEUE_FILE -ErrorAction SilentlyContinue

    foreach ($line in $lines) {
        if ($line -match "^#") {
            Write-Host ""
            Write-Host $line -ForegroundColor Cyan
            continue
        }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $parts = $line -split '\|'
        $name = $parts[0]
        $parent = if ($parts.Count -gt 1) { $parts[1] } else { "" }
        $complexity = if ($parts.Count -gt 2) { $parts[2] } else { "medium" }

        $displayName = if ($parent) { "$parent/$name" } else { $name }

        $status = "pending"
        if (Test-ModuleAnalyzed -ModuleName $name -ParentModule $parent) {
            $status = "analyzed"
        }

        Write-Host ("  {0,2}. {1,-35} [{2}] ({3})" -f $counter, $displayName, $complexity, $status)
        $counter++
    }

    Write-Host ""
    Write-LogInfo "Total: $script:TOTAL_COUNT modules to analyze"
    Write-Host ""
    Write-LogInfo "After analysis, will also run:"
    Write-Host "  - Phase 3: Markdown validation"
    Write-Host "  - Phase 4: DOCX conversion"
    exit 0
}
