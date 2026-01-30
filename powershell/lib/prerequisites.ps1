# ═══════════════════════════════════════════════════════════════════════════════
# Prerequisite Checks
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
if ($script:_PREREQUISITES_LOADED) { return }
$script:_PREREQUISITES_LOADED = $true

function Test-Prerequisites {
    $errors = 0

    # Check module-structure.json exists - generate if missing
    if (-not (Test-Path $script:MODULE_STRUCTURE_FILE)) {
        Write-LogWarn "module-structure.json not found at $script:MODULE_STRUCTURE_FILE"
        Write-LogInfo "Invoking Claude to discover module structure..."
        Write-Host ""

        # Run claude with /module-discovery skill, output to stdout
        & claude --dangerously-skip-permissions --print --output-format text "/module-discovery"
        if ($LASTEXITCODE -ne 0) {
            Write-LogError "Failed to run module discovery. Please check Claude CLI configuration."
            exit 1
        }

        Write-Host ""
        Write-LogSuccess "Module discovery completed."
        Write-LogInfo "Please review the generated module-structure.json and run analyze.ps1 again."
        exit 0
    }
    Write-LogDebug "Found module-structure.json"

    # Check jq is installed
    $jqCmd = Get-Command jq -ErrorAction SilentlyContinue
    if (-not $jqCmd) {
        Write-LogError "HARD STOP: jq is not installed. Please install jq for JSON manipulation."
        Write-Host "  Install with: choco install jq (Windows)"
        Write-Host "             or: winget install jqlang.jq"
        exit 1
    }
    $jqVersion = & jq --version 2>&1
    Write-LogDebug "Found jq: $jqVersion"

    # Check claude CLI is available
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        Write-LogError "HARD STOP: claude CLI is not available in PATH"
        exit 1
    }
    Write-LogDebug "Found claude CLI"

    # Create state directories if they don't exist
    if (-not (Test-Path $script:STATE_DIR)) {
        New-Item -ItemType Directory -Path $script:STATE_DIR -Force | Out-Null
    }
    if (-not (Test-Path $script:LOG_DIR)) {
        New-Item -ItemType Directory -Path $script:LOG_DIR -Force | Out-Null
    }

    Write-LogSuccess "All prerequisites satisfied"
}

# Check if pandoc is available (for DOCX conversion)
function Test-Pandoc {
    $pandocCmd = Get-Command pandoc -ErrorAction SilentlyContinue
    if (-not $pandocCmd) {
        Write-LogError "pandoc is not installed. Please install pandoc for DOCX conversion."
        Write-Host "  Install with: choco install pandoc (Windows)"
        Write-Host "             or: winget install JohnMacFarlane.Pandoc"
        return $false
    }
    $pandocVersion = & pandoc --version | Select-Object -First 1
    Write-LogDebug "Found pandoc: $pandocVersion"
    return $true
}
