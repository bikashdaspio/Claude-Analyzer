# Claude Analyzer - PowerShell Edition

PowerShell counterpart of the bash-based Claude Analyzer automation tool. This version provides identical functionality with native PowerShell cmdlets, using `curl` for downloads while keeping `jq`, `claude`, and `pandoc` as external dependencies.

## Prerequisites

- **PowerShell** 5.1+ (Windows PowerShell) or PowerShell Core 7+
- **jq** - JSON processing (`choco install jq` or `winget install jqlang.jq`)
- **claude** CLI - Anthropic's Claude CLI tool
- **pandoc** (optional) - For DOCX conversion (`choco install pandoc` or `winget install JohnMacFarlane.Pandoc`)

## Installation

### Option 1: Run the installer

```powershell
# Download and run the installer
curl.exe -fsSL https://raw.githubusercontent.com/bikashdaspio/Claude-Analyzer/main/powershell/install.ps1 | powershell -
```

### Option 2: Manual download

```powershell
# Clone or download the repository
git clone https://github.com/bikashdaspio/Claude-Analyzer.git
cd Claude-Analyzer/powershell
```

## Quick Start

```powershell
# 1. Initialize Claude skills/agents from .claude-config.zip
.\config.ps1 init

# 2. Create module-structure.json (run in Claude CLI)
claude "/module-discovery"

# 3. Run analysis
.\analyze.ps1
```

## Common Commands

### Running Analysis

```powershell
# Preview what will be analyzed (dry-run)
.\analyze.ps1 --dry-run

# Analyze all modules sequentially
.\analyze.ps1

# Analyze with parallel processing (4 jobs)
.\analyze.ps1 --parallel 4

# Analyze a single module
.\analyze.ps1 --module ModuleName

# Retry only failed modules
.\analyze.ps1 --retry-failed

# Reset all state and start fresh
.\analyze.ps1 --reset
```

### Phase Control

```powershell
# Run only validation phase (parallel)
.\analyze.ps1 --validation-only -p 4

# Run only DOCX conversion phase
.\analyze.ps1 --conversion-only

# Skip validation phase
.\analyze.ps1 --skip-validation

# Skip conversion phase
.\analyze.ps1 --skip-conversion
```

### Configuration Setup

```powershell
# Initialize Claude skills/agents from .claude-config.zip
.\config.ps1 init

# Force overwrite existing config
.\config.ps1 init --force

# Verify installation
.\config.ps1 verify

# Pack current .claude directory into ZIP
.\config.ps1 pack
```

## Architecture

The project follows a modular pattern identical to the bash version:

```
analyze.ps1          # Main entry point - orchestrates all phases
config.ps1           # Skills/agents initialization script
install.ps1          # Download and install script
lib/
├── config.ps1       # Global configuration variables
├── logging.ps1      # Logging utilities (Info, Success, Warn, Error, Debug)
├── prerequisites.ps1 # Validates jq, claude CLI, pandoc
├── json-utils.ps1   # JSON manipulation using jq
├── analysis.ps1     # Core module analysis functions
├── parallel.ps1     # Parallel job orchestration (PowerShell Jobs)
├── validation.ps1   # Markdown validation and auto-fix (Phase 3)
├── conversion.ps1   # DOCX conversion via pandoc (Phase 4)
└── cli.ps1          # CLI argument parsing and help
```

### Execution Phases

1. **Phase 0**: Initialize state directories and session tracking
2. **Phase 1**: Analyze submodules (sorted by complexity: low → medium → high)
3. **Phase 2**: Analyze parent modules (sorted by complexity)
4. **Phase 3**: Validate markdown files for pandoc compatibility
5. **Phase 4**: Convert markdown to DOCX using `custom-reference.docx` template

### State Management

State persists in `.analyze-state/`:
- `analysis_queue.txt` - Modules pending analysis
- `failed_modules.txt` - Failed modules (for `--retry-failed`)
- `logs/` - Per-module analysis logs
- Progress is tracked in `module-structure.json` via `analyzed: true` property

### Parallel Processing

- Uses PowerShell Jobs (`Start-Job`, `Wait-Job`, `Receive-Job`)
- Background jobs communicate via result files in `parallel_results_$PID/`
- Up to 8 concurrent jobs (`-p 8`)

## Key Configuration

### Timeouts (lib/config.ps1)

```powershell
$script:TIMEOUT_LOW = 300     # 5 min for low complexity
$script:TIMEOUT_MEDIUM = 600  # 10 min for medium complexity
$script:TIMEOUT_HIGH = 900    # 15 min for high complexity
```

Override with `--timeout SECONDS` or disable with `--no-timeout`.

### Required Files

- `module-structure.json` - Module hierarchy (create via `/module-discovery` skill)
- `.claude/settings.local.json` - Environment variables for skills

## Output Structure

```
Documents/
├── BRD/           # Business Requirements
├── FRD/           # Functional Requirements
├── UserStories/
├── ProcessFlow/diagrams/
├── Modules/diagrams/
├── Security/
├── Migration Notes/
└── DOCX/          # Converted Word documents
```

## Differences from Bash Version

| Feature | Bash | PowerShell |
|---------|------|------------|
| HTTP Client | curl | curl.exe |
| Parallel Jobs | bash `&` + PIDs | PowerShell Jobs |
| Archive | zip/unzip | Compress-Archive/Expand-Archive |
| Script Extension | .sh | .ps1 |
| Sourcing | `source` / `.` | `. (dot-sourcing)` |

The behavior and output of both versions are identical.

## Troubleshooting

### Execution Policy

If you get an execution policy error:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### jq Not Found

Install jq using one of these methods:

```powershell
# Using Chocolatey
choco install jq

# Using winget
winget install jqlang.jq

# Using Scoop
scoop install jq
```

### TLS Errors

If you encounter TLS/SSL errors downloading files:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

## License

Same license as the main project.
