# ═══════════════════════════════════════════════════════════════════════════════
# Logging Functions
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
if ($script:_LOGGING_LOADED) { return }
$script:_LOGGING_LOADED = $true

function Write-LogInfo {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [INFO] $Message"
    Write-Host "$([char]0x2139) " -ForegroundColor Blue -NoNewline
    Write-Host $Message
    if ($script:MAIN_LOG) {
        try { Add-Content -Path $script:MAIN_LOG -Value $logMsg -ErrorAction SilentlyContinue } catch {}
    }
}

function Write-LogSuccess {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [SUCCESS] $Message"
    Write-Host "$([char]0x2713) " -ForegroundColor Green -NoNewline
    Write-Host $Message
    if ($script:MAIN_LOG) {
        try { Add-Content -Path $script:MAIN_LOG -Value $logMsg -ErrorAction SilentlyContinue } catch {}
    }
}

function Write-LogWarn {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [WARN] $Message"
    Write-Host "$([char]0x26A0) " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
    if ($script:MAIN_LOG) {
        try { Add-Content -Path $script:MAIN_LOG -Value $logMsg -ErrorAction SilentlyContinue } catch {}
    }
}

function Write-LogError {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [ERROR] $Message"
    Write-Host "$([char]0x2717) " -ForegroundColor Red -NoNewline
    Write-Host $Message -ForegroundColor Red
    if ($script:MAIN_LOG) {
        try { Add-Content -Path $script:MAIN_LOG -Value $logMsg -ErrorAction SilentlyContinue } catch {}
    }
}

function Write-LogDebug {
    param([string]$Message)
    if ($script:VERBOSE_MODE) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMsg = "[$timestamp] [DEBUG] $Message"
        Write-Host "$([char]0x2026) " -ForegroundColor Cyan -NoNewline
        Write-Host $Message
        if ($script:MAIN_LOG) {
            try { Add-Content -Path $script:MAIN_LOG -Value $logMsg -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "$([char]0x2550)" -NoNewline
    for ($i = 0; $i -lt 63; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host ""
    $padding = [math]::Floor((64 - $Title.Length) / 2)
    Write-Host (" " * $padding) -NoNewline
    Write-Host $Title
    Write-Host "$([char]0x2550)" -NoNewline
    for ($i = 0; $i -lt 63; $i++) { Write-Host "$([char]0x2550)" -NoNewline }
    Write-Host ""
    Write-Host ""
}
