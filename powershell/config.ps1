#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Skills & Agents Initialization Script

.DESCRIPTION
    This script extracts and installs Claude Code skills, agents, commands,
    and settings from a ZIP archive to the .claude directory.

.PARAMETER Command
    The command to execute: init, pack, or verify

.PARAMETER Force
    Overwrite existing files (default: skip existing)

.PARAMETER DryRun
    Show what would be done without doing it

.PARAMETER Verbose
    Detailed output

.PARAMETER ZipPath
    Specify custom ZIP archive path

.EXAMPLE
    .\config.ps1 init
    Initialize everything from ZIP

.EXAMPLE
    .\config.ps1 init --force
    Initialize and force overwrite existing

.EXAMPLE
    .\config.ps1 pack
    Create ZIP from existing .claude directory

.EXAMPLE
    .\config.ps1 verify
    Verify current setup
#>

[CmdletBinding()]
param()

# Stop on errors
$ErrorActionPreference = "Stop"

# =============================================================================
# [1] HEADER & CONFIGURATION
# =============================================================================

$script:VERSION = "1.0.0"
$script:SCRIPT_NAME = $MyInvocation.MyCommand.Name
$script:SCRIPT_DIR = $PSScriptRoot

# Default paths
$script:DEFAULT_ZIP_PATH = Join-Path $script:SCRIPT_DIR ".claude-config.zip"
$script:CLAUDE_DIR = Join-Path $script:SCRIPT_DIR ".claude"

# Global flags (can be modified by arguments)
$script:COMMAND = ""
$script:FORCE = $false
$script:DRY_RUN = $false
$script:VERBOSE_MODE = $false
$script:ZIP_PATH = $script:DEFAULT_ZIP_PATH

# Counters
$script:INSTALLED_COUNT = 0
$script:SKIPPED_COUNT = 0

# =============================================================================
# [2] UTILITY FUNCTIONS
# =============================================================================

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK]   " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[SKIP] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERR]  " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Verbose-Log {
    param([string]$Message)
    if ($script:VERBOSE_MODE) {
        Write-Host "[DEBUG] " -ForegroundColor Blue -NoNewline
        Write-Host $Message
    }
}

function Write-ConfigHeader {
    Write-Host ""
    Write-Host "$([char]0x2554)" -NoNewline
    for ($i = 0; $i -lt 62; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host "$([char]0x2557)"
    Write-Host "$([char]0x2551)      Claude Code Skills & Agents Initialization Script        $([char]0x2551)"
    Write-Host "$([char]0x2551)                        Version $script:VERSION                          $([char]0x2551)"
    Write-Host "$([char]0x255A)" -NoNewline
    for ($i = 0; $i -lt 62; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host "$([char]0x255D)"
    Write-Host ""
}

function Ensure-Directory {
    param([string]$Path)
    if ($script:DRY_RUN) {
        Write-Verbose-Log "Would create directory: $Path"
    } else {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }
}

function Test-ConfigPrerequisites {
    Write-Info "Checking prerequisites..."

    # Check PowerShell version (need 5.1+)
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -lt 1)) {
        Write-Err "PowerShell version 5.1+ required (found: $psVersion)"
        return $false
    }
    Write-Success "PowerShell version $psVersion (required: 5.1+)"

    # Check if Expand-Archive is available (built into PowerShell 5+)
    if (-not (Get-Command Expand-Archive -ErrorAction SilentlyContinue)) {
        Write-Err "Expand-Archive cmdlet not found. Please use PowerShell 5.0+."
        return $false
    }
    Write-Success "Expand-Archive available"

    # Check if Compress-Archive is available
    if (-not (Get-Command Compress-Archive -ErrorAction SilentlyContinue)) {
        Write-Warn "Compress-Archive cmdlet not found. 'pack' command will not be available."
    } else {
        Write-Verbose-Log "Compress-Archive available"
    }

    return $true
}

# =============================================================================
# [3] CORE FUNCTIONS
# =============================================================================

function Expand-ConfigArchive {
    param([string]$ZipPathParam = $script:ZIP_PATH)

    if (-not (Test-Path $ZipPathParam)) {
        Write-Err "ZIP archive not found: $ZipPathParam"
        return $null
    }

    $tempDir = Join-Path $env:TEMP "claude-config-$(Get-Random)"

    Write-Info "Extracting archive: $ZipPathParam"

    if ($script:DRY_RUN) {
        Write-Verbose-Log "Would extract to: $tempDir"
        # Still extract for dry-run to list what would be installed
    }

    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Expand-Archive -Path $ZipPathParam -DestinationPath $tempDir -Force
    Write-Success "Extracted to temporary directory"
    Write-Host ""

    return $tempDir
}

function Install-ConfigFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    $displayName = $Destination.Replace($script:SCRIPT_DIR, "").TrimStart('\', '/')

    if ((Test-Path $Destination) -and -not $script:FORCE) {
        Write-Warn "Exists: $displayName"
        $script:SKIPPED_COUNT++
        return
    }

    if ($script:DRY_RUN) {
        if (Test-Path $Destination) {
            Write-Info "Would overwrite: $displayName"
        } else {
            Write-Info "Would install: $displayName"
        }
        $script:INSTALLED_COUNT++
        return
    }

    Ensure-Directory (Split-Path -Parent $Destination)
    Copy-Item -Path $Source -Destination $Destination -Force
    Write-Success "Installed: $displayName"
    $script:INSTALLED_COUNT++
}

function Install-ConfigDirectory {
    param(
        [string]$SourceDir,
        [string]$DestDir
    )

    if (-not (Test-Path $SourceDir)) {
        Write-Verbose-Log "Source directory not found: $SourceDir"
        return
    }

    # Find all files in source directory and install them
    Get-ChildItem -Path $SourceDir -File -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
        $destFile = Join-Path $DestDir $relativePath
        Install-ConfigFile -Source $_.FullName -Destination $destFile
    }
}

function New-DocumentsStructure {
    Write-Info "Creating Documents structure..."

    $dirs = @(
        "Documents\BRD",
        "Documents\FRD",
        "Documents\UserStories",
        "Documents\ProcessFlow\diagrams",
        "Documents\Modules\diagrams",
        "Documents\Security",
        "Documents\Migration Notes"
    )

    foreach ($dir in $dirs) {
        $fullPath = Join-Path $script:SCRIPT_DIR $dir
        if (Test-Path $fullPath) {
            Write-Verbose-Log "Directory exists: $dir"
        } else {
            Ensure-Directory $fullPath
            if (-not $script:DRY_RUN) {
                Write-Success "Created: $dir/"
            } else {
                Write-Info "Would create: $dir/"
            }
        }
    }
}

function Install-All {
    param([string]$TempDir)

    Write-Host ""
    Write-Info "Installing agents..."
    Install-ConfigDirectory -SourceDir (Join-Path $TempDir "agents") -DestDir (Join-Path $script:CLAUDE_DIR "agents")

    Write-Host ""
    Write-Info "Installing skills..."
    Install-ConfigDirectory -SourceDir (Join-Path $TempDir "skills") -DestDir (Join-Path $script:CLAUDE_DIR "skills")

    Write-Host ""
    Write-Info "Installing commands..."
    Install-ConfigDirectory -SourceDir (Join-Path $TempDir "commands") -DestDir (Join-Path $script:CLAUDE_DIR "commands")

    Write-Host ""
    Write-Info "Installing settings..."
    $settingsFile = Join-Path $TempDir "settings.local.json"
    if (Test-Path $settingsFile) {
        Install-ConfigFile -Source $settingsFile -Destination (Join-Path $script:CLAUDE_DIR "settings.local.json")
    }

    Write-Host ""
    New-DocumentsStructure
}

function New-ZipArchive {
    param([string]$Output = $script:DEFAULT_ZIP_PATH)

    if (-not (Get-Command Compress-Archive -ErrorAction SilentlyContinue)) {
        Write-Err "Compress-Archive cmdlet not found. Please use PowerShell 5.0+."
        return
    }

    if (-not (Test-Path $script:CLAUDE_DIR)) {
        Write-Err ".claude directory not found: $script:CLAUDE_DIR"
        return
    }

    Write-Info "Creating archive from .claude directory..."

    if ($script:DRY_RUN) {
        Write-Info "Would create: $Output"
        Write-Info "Contents:"
        Get-ChildItem -Path $script:CLAUDE_DIR -Recurse -File |
            Where-Object { $_.FullName -match "\\(agents|skills|commands)\\" -or $_.Name -eq "settings.local.json" } |
            ForEach-Object {
                $relativePath = $_.FullName.Substring($script:CLAUDE_DIR.Length).TrimStart('\', '/')
                Write-Info "  Would add: $relativePath"
            }
        return
    }

    # Remove existing archive if present
    if (Test-Path $Output) {
        Remove-Item $Output -Force
    }

    # Create ZIP with directory structure preserved
    $itemsToCompress = @()
    @("agents", "skills", "commands") | ForEach-Object {
        $subDir = Join-Path $script:CLAUDE_DIR $_
        if (Test-Path $subDir) {
            $itemsToCompress += $subDir
        }
    }
    $settingsFile = Join-Path $script:CLAUDE_DIR "settings.local.json"
    if (Test-Path $settingsFile) {
        $itemsToCompress += $settingsFile
    }

    # Use temporary directory for proper structure
    $tempPackDir = Join-Path $env:TEMP "claude-pack-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempPackDir -Force | Out-Null

    foreach ($item in $itemsToCompress) {
        $destPath = Join-Path $tempPackDir (Split-Path -Leaf $item)
        if (Test-Path $item -PathType Container) {
            Copy-Item -Path $item -Destination $destPath -Recurse
        } else {
            Copy-Item -Path $item -Destination $destPath
        }
    }

    Compress-Archive -Path (Join-Path $tempPackDir "*") -DestinationPath $Output -Force

    # Cleanup temp directory
    Remove-Item $tempPackDir -Recurse -Force

    $size = "{0:N2} KB" -f ((Get-Item $Output).Length / 1KB)

    Write-Host ""
    Write-Host "$([char]0x2550)" -NoNewline
    for ($i = 0; $i -lt 63; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host ""
    Write-Host "          " -NoNewline
    Write-Host "Archive created: $(Split-Path -Leaf $Output) ($size)" -ForegroundColor Green
    Write-Host "$([char]0x2550)" -NoNewline
    for ($i = 0; $i -lt 63; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host ""
}

# =============================================================================
# [4] VERIFICATION FUNCTIONS
# =============================================================================

function Test-Structure {
    Write-Info "Verifying .claude directory structure..."
    Write-Host ""

    $errors = 0
    $checks = 0

    # Check agents
    $agents = @("system-analysist.md", "react-vue-bridge.md", "ui-parity.md")
    foreach ($agent in $agents) {
        $checks++
        $agentPath = Join-Path $script:CLAUDE_DIR "agents" $agent
        if (Test-Path $agentPath) {
            Write-Success "agents/$agent"
        } else {
            Write-Err "Missing: agents/$agent"
            $errors++
        }
    }

    # Check skills
    $skills = @("brd", "frd", "process-flow", "security-document", "user-stories")
    foreach ($skill in $skills) {
        $checks++
        $skillPath = Join-Path $script:CLAUDE_DIR "skills" $skill "SKILL.md"
        if (Test-Path $skillPath) {
            Write-Success "skills/$skill/SKILL.md"
        } else {
            Write-Err "Missing: skills/$skill/SKILL.md"
            $errors++
        }

        # Check templates directory exists
        $checks++
        $templatesPath = Join-Path $script:CLAUDE_DIR "skills" $skill "templates"
        if (Test-Path $templatesPath) {
            $templateCount = (Get-ChildItem -Path $templatesPath -Filter "*.docx" -ErrorAction SilentlyContinue).Count
            if ($templateCount -gt 0) {
                Write-Success "skills/$skill/templates/ ($templateCount .docx files)"
            } else {
                Write-Warn "skills/$skill/templates/ (no .docx files)"
            }
        } else {
            Write-Err "Missing: skills/$skill/templates/"
            $errors++
        }
    }

    # Check commands
    $commands = @("analyze.md", "iterative-migrate.md")
    foreach ($cmd in $commands) {
        $checks++
        $cmdPath = Join-Path $script:CLAUDE_DIR "commands" $cmd
        if (Test-Path $cmdPath) {
            Write-Success "commands/$cmd"
        } else {
            Write-Err "Missing: commands/$cmd"
            $errors++
        }
    }

    # Check settings
    $checks++
    $settingsPath = Join-Path $script:CLAUDE_DIR "settings.local.json"
    if (Test-Path $settingsPath) {
        Write-Success "settings.local.json"
    } else {
        Write-Err "Missing: settings.local.json"
        $errors++
    }

    Write-Host ""
    Write-Host "$([char]0x2550)" -NoNewline
    for ($i = 0; $i -lt 63; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host ""
    if ($errors -eq 0) {
        Write-Host "          " -NoNewline
        Write-Host "Verification PASSED ($checks checks)" -ForegroundColor Green
    } else {
        Write-Host "          " -NoNewline
        Write-Host "Verification FAILED ($errors errors / $checks checks)" -ForegroundColor Red
    }
    Write-Host "$([char]0x2550)" -NoNewline
    for ($i = 0; $i -lt 63; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host ""

    return $errors
}

function Write-ConfigSummary {
    Write-Host ""
    Write-Host "$([char]0x2550)" -NoNewline
    for ($i = 0; $i -lt 63; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host ""
    if ($script:DRY_RUN) {
        Write-Host "                    " -NoNewline
        Write-Host "DRY RUN COMPLETE" -ForegroundColor Yellow
    } else {
        Write-Host "                    " -NoNewline
        Write-Host "INITIALIZATION COMPLETE" -ForegroundColor Green
    }
    Write-Host "$([char]0x2550)" -NoNewline
    for ($i = 0; $i -lt 63; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host ""
    $wouldBe = if ($script:DRY_RUN) { "would be " } else { "" }
    Write-Host "  Agents:    3 ${wouldBe}processed"
    Write-Host "  Skills:    5 ${wouldBe}processed (+ 5 templates)"
    Write-Host "  Commands:  2 ${wouldBe}processed"
    Write-Host "  Settings:  1 ${wouldBe}processed"
    Write-Host ""
    Write-Host "  Installed: $script:INSTALLED_COUNT"
    $skipMsg = if ($script:SKIPPED_COUNT -gt 0) { " (use --force to overwrite)" } else { "" }
    Write-Host "  Skipped:   $script:SKIPPED_COUNT$skipMsg"
    Write-Host "$([char]0x2550)" -NoNewline
    for ($i = 0; $i -lt 63; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host ""
}

# =============================================================================
# [5] MAIN ENTRY POINT
# =============================================================================

function Show-ConfigHelp {
    $helpText = @"
Claude Code Skills & Agents Initialization Script v$script:VERSION

USAGE:
    $script:SCRIPT_NAME <command> [options]

COMMANDS:
    init        Extract ZIP and install everything to .claude/
    pack        Create ZIP from existing .claude/
    verify      Verify setup completeness

OPTIONS:
    --force     Overwrite existing files (default: skip existing)
    --dry-run   Show what would be done without doing it
    --verbose   Detailed output
    --zip PATH  Specify custom ZIP archive path
    --help      Show this help message

EXAMPLES:
    # Initialize everything from ZIP (skips existing files)
    $script:SCRIPT_NAME init

    # Initialize and force overwrite existing
    $script:SCRIPT_NAME init --force

    # Dry run to see what would happen
    $script:SCRIPT_NAME init --dry-run

    # Create/update ZIP from current .claude directory
    $script:SCRIPT_NAME pack

    # Verify current setup
    $script:SCRIPT_NAME verify --verbose

    # Use custom ZIP path
    $script:SCRIPT_NAME init --zip C:\path\to\custom-config.zip

"@
    Write-Host $helpText
}

function Read-ConfigArguments {
    param([string[]]$Arguments)

    $i = 0
    while ($i -lt $Arguments.Count) {
        $arg = $Arguments[$i]

        switch -Regex ($arg) {
            "^(init|pack|verify)$" {
                $script:COMMAND = $arg
            }
            "^(--force|-f)$" {
                $script:FORCE = $true
            }
            "^(--dry-run|-n)$" {
                $script:DRY_RUN = $true
            }
            "^(--verbose|-v)$" {
                $script:VERBOSE_MODE = $true
            }
            "^--zip$" {
                $i++
                if ($i -lt $Arguments.Count) {
                    $script:ZIP_PATH = $Arguments[$i]
                } else {
                    Write-Err "--zip requires a path argument"
                    exit 2
                }
            }
            "^(--help|-h)$" {
                Show-ConfigHelp
                exit 0
            }
            default {
                Write-Err "Unknown argument: $arg"
                Write-Host "Use --help for usage information."
                exit 2
            }
        }
        $i++
    }
}

function Remove-TempDirectory {
    param([string]$TempDir)
    if ($TempDir -and (Test-Path $TempDir)) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Verbose-Log "Cleaned up temporary directory"
    }
}

function Main-Config {
    param([string[]]$Arguments)

    Read-ConfigArguments -Arguments $Arguments

    switch ($script:COMMAND) {
        "init" {
            Write-ConfigHeader
            if (-not (Test-ConfigPrerequisites)) { exit 1 }

            $tempDir = Expand-ConfigArchive -ZipPathParam $script:ZIP_PATH
            if (-not $tempDir) { exit 1 }

            try {
                Install-All -TempDir $tempDir
                Write-ConfigSummary
            } finally {
                Remove-TempDirectory -TempDir $tempDir
            }
        }
        "pack" {
            Write-ConfigHeader
            if (-not (Test-ConfigPrerequisites)) { exit 1 }
            New-ZipArchive -Output $script:ZIP_PATH
        }
        "verify" {
            Write-ConfigHeader
            $errors = Test-Structure
            exit $errors
        }
        "" {
            Write-Err "No command specified"
            Write-Host ""
            Show-ConfigHelp
            exit 2
        }
        default {
            Write-Err "Unknown command: $script:COMMAND"
            Show-ConfigHelp
            exit 2
        }
    }
}

# Run main with all arguments
Main-Config -Arguments $args
