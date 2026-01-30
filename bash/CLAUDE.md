# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Analyzer is a bash-based automation tool that iteratively analyzes software modules using Claude CLI. It supports parallel processing, markdown validation, and DOCX conversion. The tool uses the `/analyze` skill via MCP to process modules defined in `module-structure.json`.

## Common Commands

### Running Analysis

```bash
# Preview what will be analyzed (dry-run)
./analyze.sh --dry-run

# Analyze all modules sequentially
./analyze.sh

# Analyze with parallel processing (4 jobs)
./analyze.sh -p 4

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

# Create module-structure.json (run in Claude)
claude "/module-discovery"
```

## Architecture

The project follows a modular monolith pattern:

```
analyze.sh          # Main entry point - orchestrates all phases
config.sh           # Skills/agents initialization script
lib/
├── config.sh       # Global configuration variables
├── logging.sh      # Logging utilities (info, success, warn, error, debug)
├── prerequisites.sh # Validates jq, claude CLI, pandoc
├── json-utils.sh   # JSON manipulation using jq
├── analysis.sh     # Core module analysis functions
├── parallel.sh     # Parallel job orchestration (PID tracking, result files)
├── validation.sh   # Markdown validation and auto-fix (Phase 3)
├── conversion.sh   # DOCX conversion via pandoc (Phase 4)
└── cli.sh          # CLI argument parsing and help
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

- Uses native bash job control (`&`, `wait`, PID arrays)
- Background jobs communicate via result files in `parallel_results_$$/`
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

### Prerequisites

- `bash` 4.0+
- `jq` - JSON processing
- `claude` CLI with Playwright MCP configured
- `pandoc` (optional, for DOCX conversion)

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

## Shell Scripting Conventions

- All scripts use `set -euo pipefail`
- Guard clauses prevent multiple sourcing: `[[ -n "${_LOADED:-}" ]] && return 0`
- Function names: `snake_case`
- Global variables: `SCREAMING_SNAKE_CASE`
- Functions return exit codes; callers check with `if` statements
