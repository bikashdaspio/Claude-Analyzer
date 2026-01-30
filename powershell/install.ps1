#Requires -Version 5.1
<#
.SYNOPSIS
    Claude-Analyzer Installation Script

.DESCRIPTION
    Downloads and installs Claude-Analyzer from GitHub into the current directory.
    Uses curl for downloading files.

.PARAMETER Branch
    The branch to download from (default: main)

.EXAMPLE
    .\install.ps1
    Install from main branch

.EXAMPLE
    $env:BRANCH = "develop"; .\install.ps1
    Install from develop branch
#>

[CmdletBinding()]
param()

# Stop on errors
$ErrorActionPreference = "Stop"

# Configuration
$REPO_RAW_URL = "https://raw.githubusercontent.com/bikashdaspio/Claude-Analyzer/refs/heads"
$BRANCH = if ($env:BRANCH) { $env:BRANCH } else { "main" }
$INSTALL_DIR = Get-Location

# Files to download from powershell/ directory
$PS_FILES = @(
    "analyze.ps1",
    "config.ps1"
)

# Files to download from repository root
$ROOT_FILES = @(
    "custom-reference.docx"
)

# Library files to download from powershell/lib/
$LIB_FILES = @(
    "analysis.ps1",
    "cli.ps1",
    "config.ps1",
    "conversion.ps1",
    "json-utils.ps1",
    "logging.ps1",
    "parallel.ps1",
    "prerequisites.ps1",
    "validation.ps1"
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARNING] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Message
    exit 1
}

# =============================================================================
# CHECK PREREQUISITES
# =============================================================================

function Test-InstallPrerequisites {
    Write-Info "Checking prerequisites..."

    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -lt 1)) {
        Write-Err "PowerShell version 5.1+ required (found: $psVersion)"
    }

    # Check curl is available
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        Write-Err "curl is not available. Please install curl or use Windows 10+."
    }

    # Check Expand-Archive is available
    if (-not (Get-Command Expand-Archive -ErrorAction SilentlyContinue)) {
        Write-Err "Expand-Archive is not available. Please use PowerShell 5.0+."
    }

    Write-Success "All prerequisites met."
}

# =============================================================================
# DOWNLOAD FUNCTIONS
# =============================================================================

function Get-RemoteFile {
    param(
        [string]$RemotePath,
        [string]$LocalPath
    )

    $url = "$REPO_RAW_URL/$BRANCH/$RemotePath"

    try {
        # Ensure parent directory exists
        $parentDir = Split-Path -Parent $LocalPath
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }

        # Use curl.exe to avoid PowerShell's curl alias
        $result = & curl.exe -fsSL -o $LocalPath $url 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
        return $true
    } catch {
        return $false
    }
}

function Get-PowerShellFiles {
    Write-Info "Downloading Claude-Analyzer PowerShell scripts..."

    # Create lib directory
    $libDir = Join-Path $INSTALL_DIR "lib"
    if (-not (Test-Path $libDir)) {
        New-Item -ItemType Directory -Path $libDir -Force | Out-Null
    }

    # Download main PowerShell files
    foreach ($file in $PS_FILES) {
        Write-Info "  Downloading $file..."
        $localPath = Join-Path $INSTALL_DIR $file
        if (-not (Get-RemoteFile -RemotePath "powershell/$file" -LocalPath $localPath)) {
            Write-Err "Failed to download $file"
        }
    }

    # Download lib files
    foreach ($file in $LIB_FILES) {
        Write-Info "  Downloading lib/$file..."
        $localPath = Join-Path $libDir $file
        if (-not (Get-RemoteFile -RemotePath "powershell/lib/$file" -LocalPath $localPath)) {
            Write-Err "Failed to download lib/$file"
        }
    }

    # Download files from repository root
    foreach ($file in $ROOT_FILES) {
        Write-Info "  Downloading $file..."
        $localPath = Join-Path $INSTALL_DIR $file
        if (-not (Get-RemoteFile -RemotePath $file -LocalPath $localPath)) {
            Write-Err "Failed to download $file"
        }
    }

    # Download .claude-config.zip from root
    Write-Info "  Downloading .claude-config.zip..."
    $configZipPath = Join-Path $INSTALL_DIR ".claude-config.zip"
    if (-not (Get-RemoteFile -RemotePath ".claude-config.zip" -LocalPath $configZipPath)) {
        Write-Warn "Failed to download .claude-config.zip (may not exist)"
    }

    Write-Success "PowerShell scripts downloaded."
}

# =============================================================================
# EXTRACT CONFIG
# =============================================================================

function Expand-Config {
    $configZip = Join-Path $INSTALL_DIR ".claude-config.zip"
    $claudeDir = Join-Path $INSTALL_DIR ".claude"

    if (-not (Test-Path $configZip)) {
        Write-Warn ".claude-config.zip not found. Skipping config extraction."
        return
    }

    Write-Info "Extracting .claude-config.zip into .claude directory..."

    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    try {
        Expand-Archive -Path $configZip -DestinationPath $claudeDir -Force
        Write-Success ".claude-config.zip extracted to .claude/"
    } catch {
        Write-Err "Failed to extract .claude-config.zip: $_"
    }
}

# =============================================================================
# PRINT USAGE
# =============================================================================

function Write-Usage {
    Write-Host ""
    Write-Host "=========================================="
    Write-Success "Claude-Analyzer installed successfully!"
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "Files installed in: $INSTALL_DIR"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\analyze.ps1 <path-to-claude-config.zip>"
    Write-Host ""
    Write-Host "For help:"
    Write-Host "  .\analyze.ps1 --help"
    Write-Host ""
}

# =============================================================================
# MAIN
# =============================================================================

function Main {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "  Claude-Analyzer Installation Script"
    Write-Host "=========================================="
    Write-Host ""

    Test-InstallPrerequisites
    Get-PowerShellFiles
    Expand-Config
    Write-Usage
}

# Run main function
Main
