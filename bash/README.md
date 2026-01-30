# Claude Analyzer - Bash Edition

Bash-based automation tool that iteratively analyzes software modules using Claude CLI. This version provides module analysis with parallel processing, markdown validation, and DOCX conversion for Linux and macOS systems.

## Prerequisites

- **Bash** 4.0+
- **jq** - JSON processing (`apt install jq` or `brew install jq`)
- **claude** CLI - Anthropic's Claude CLI tool
- **pandoc** (optional) - For DOCX conversion (`apt install pandoc` or `brew install pandoc`)
- **curl** or **wget** - For downloading files
- **unzip** - For configuration extraction

## Installation

### Option 1: Run the installer

```bash
curl -fsSL https://raw.githubusercontent.com/bikashdaspio/Claude-Analyzer/main/bash/install.sh | bash
```

### Option 2: Manual download

```bash
# Clone or download the repository
git clone https://github.com/bikashdaspio/Claude-Analyzer.git
cd Claude-Analyzer/bash
chmod +x analyze.sh config.sh lib/*.sh
```

## Quick Start

```bash
# 1. Initialize Claude skills/agents from .claude-config.zip
./config.sh init

# 2. Create module-structure.json (run in Claude CLI)
claude "/module-discovery"

# 3. Run analysis
./analyze.sh
```

## Common Commands

### Running Analysis

```bash
# Preview what will be analyzed (dry-run)
./analyze.sh --dry-run

# Analyze all modules sequentially
./analyze.sh

# Analyze with parallel processing (4 jobs)
./analyze.sh --parallel 4

# Analyze a single module
./analyze.sh --module ModuleName

# Retry only failed modules
./analyze.sh --retry-failed

# Reset all state and start fresh
./analyze.sh --reset
```

### Phase Control

```bash
# Run only validation phase (parallel)
./analyze.sh --validation-only -p 4

# Run only DOCX conversion phase
./analyze.sh --conversion-only

# Skip validation phase
./analyze.sh --skip-validation

# Skip conversion phase
./analyze.sh --skip-conversion
```

### Configuration Setup

```bash
# Initialize Claude skills/agents from .claude-config.zip
./config.sh init

# Force overwrite existing config
./config.sh init --force

# Verify installation
./config.sh verify

# Pack current .claude directory into ZIP
./config.sh pack
```

## Architecture

The project follows a modular pattern:

```
analyze.sh           # Main entry point - orchestrates all phases
config.sh            # Skills/agents initialization script
install.sh           # Download and install script
lib/
├── config.sh        # Global configuration variables
├── logging.sh       # Logging utilities (info, success, warn, error, debug)
├── prerequisites.sh # Validates jq, claude CLI, pandoc
├── json-utils.sh    # JSON manipulation using jq
├── analysis.sh      # Core module analysis functions
├── parallel.sh      # Parallel job orchestration (GNU parallel or background jobs)
├── validation.sh    # Markdown validation and auto-fix (Phase 3)
├── conversion.sh    # DOCX conversion via pandoc (Phase 4)
└── cli.sh           # CLI argument parsing and help
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

- Uses GNU parallel when available, falls back to background jobs with `&`
- Up to 8 concurrent jobs (`-p 8`)

## Key Configuration

### Timeouts (lib/config.sh)

```bash
TIMEOUT_LOW=300     # 5 min for low complexity
TIMEOUT_MEDIUM=600  # 10 min for medium complexity
TIMEOUT_HIGH=900    # 15 min for high complexity
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

## Troubleshooting

### Permission Denied

Make scripts executable:

```bash
chmod +x analyze.sh config.sh lib/*.sh
```

### jq Not Found

Install jq using your package manager:

```bash
# Debian/Ubuntu
sudo apt install jq

# macOS
brew install jq

# RHEL/CentOS
sudo yum install jq
```

### Claude CLI Not Found

Ensure Claude CLI is installed and in your PATH:

```bash
which claude
claude --version
```

### Timeout Issues

For complex modules, disable or increase timeouts:

```bash
./analyze.sh --no-timeout
# or
./analyze.sh --timeout 7200  # 2 hours
```

## License

Same license as the main project.
