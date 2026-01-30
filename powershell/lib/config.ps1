# ═══════════════════════════════════════════════════════════════════════════════
# Configuration - Global variables and constants
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
if ($script:_CONFIG_LOADED) { return }
$script:_CONFIG_LOADED = $true

# Script directory (should be set by main script before sourcing)
if (-not $script:SCRIPT_DIR) {
    $script:SCRIPT_DIR = Split-Path -Parent $PSScriptRoot
}

# File paths
$script:MODULE_STRUCTURE_FILE = if ($env:MODULE_STRUCTURE_FILE) { $env:MODULE_STRUCTURE_FILE } else { Join-Path $script:SCRIPT_DIR "module-structure.json" }
$script:STATE_DIR = if ($env:STATE_DIR) { $env:STATE_DIR } else { Join-Path $script:SCRIPT_DIR ".analyze-state" }
$script:LOG_DIR = if ($env:LOG_DIR) { $env:LOG_DIR } else { Join-Path $script:STATE_DIR "logs" }
$script:MAIN_LOG = if ($env:MAIN_LOG) { $env:MAIN_LOG } else { Join-Path $script:STATE_DIR "analyze.log" }
$script:QUEUE_FILE = if ($env:QUEUE_FILE) { $env:QUEUE_FILE } else { Join-Path $script:STATE_DIR "analysis_queue.txt" }
$script:FAILED_FILE = if ($env:FAILED_FILE) { $env:FAILED_FILE } else { Join-Path $script:STATE_DIR "failed_modules.txt" }
$script:SESSION_FILE = if ($env:SESSION_FILE) { $env:SESSION_FILE } else { Join-Path $script:STATE_DIR "session_start.txt" }

# Timeouts (in seconds) - 0 means no timeout
$script:TIMEOUT_LOW = if ($env:TIMEOUT_LOW) { [int]$env:TIMEOUT_LOW } else { 300 }       # 5 minutes
$script:TIMEOUT_MEDIUM = if ($env:TIMEOUT_MEDIUM) { [int]$env:TIMEOUT_MEDIUM } else { 600 } # 10 minutes
$script:TIMEOUT_HIGH = if ($env:TIMEOUT_HIGH) { [int]$env:TIMEOUT_HIGH } else { 900 }     # 15 minutes
$script:CUSTOM_TIMEOUT = if ($env:CUSTOM_TIMEOUT) { [int]$env:CUSTOM_TIMEOUT } else { 0 }   # Custom timeout override (0 = use complexity-based)
$script:NO_TIMEOUT = if ($env:NO_TIMEOUT -eq "true") { $true } else { $false }       # Disable all timeouts

# Counters
$script:SUCCESS_COUNT = 0
$script:FAILED_COUNT = 0
$script:SKIPPED_COUNT = 0
$script:TOTAL_COUNT = 0

# CLI Options
$script:DRY_RUN = $false
$script:RESET_STATE = $false
$script:SINGLE_MODULE = ""
$script:RETRY_FAILED = $false
$script:DELAY_SECONDS = 5
$script:VERBOSE_MODE = $false
$script:PARALLEL_JOBS = 1      # Number of parallel jobs (1 = sequential)
$script:MAX_PARALLEL = 8       # Maximum allowed parallel jobs
$script:SKIP_VALIDATION = $false
$script:SKIP_CONVERSION = $false
$script:VALIDATION_ONLY = $false
$script:CONVERSION_ONLY = $false

# Output directories
$script:DOCS_DIR = if ($env:DOCS_DIR) { $env:DOCS_DIR } else { Join-Path $script:SCRIPT_DIR "Documents" }
$script:DOCX_OUTPUT_DIR = if ($env:DOCX_OUTPUT_DIR) { $env:DOCX_OUTPUT_DIR } else { Join-Path (Join-Path $script:SCRIPT_DIR "Documents") "DOCX" }

# Validation counters
$script:VALIDATION_SUCCESS = 0
$script:VALIDATION_FAILED = 0
$script:VALIDATION_SKIPPED = 0

# Conversion counters
$script:CONVERSION_SUCCESS = 0
$script:CONVERSION_FAILED = 0

# Parallel processing state
$script:PARALLEL_RESULTS_DIR = ""
$script:PARALLEL_JOBS_LIST = [System.Collections.ArrayList]::new()
