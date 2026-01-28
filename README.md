# Claude Analyzer

A bash-based automation tool that iteratively analyzes software modules using Claude CLI, with support for parallel processing, markdown validation, and DOCX conversion.

## Features

- **Automated Module Analysis** - Analyzes modules defined in `module-structure.json` using Claude CLI
- **Parallel Processing** - Run multiple analyses concurrently (up to 8 jobs)
- **Progress Tracking** - Tracks analyzed modules via state files, allowing resume after interruption
- **Complexity-Based Timeouts** - Automatically adjusts timeouts based on module complexity
- **Markdown Validation** - Validates and auto-fixes markdown for pandoc compatibility
- **DOCX Conversion** - Converts generated markdown to Word documents
- **Modular Architecture** - Clean separation of concerns via library files

## Prerequisites

- **Bash 4.0+**
- **Claude CLI** - Anthropic's command-line interface (`claude` command)
- **jq** - JSON processor for parsing module structure
- **pandoc** (optional) - For DOCX conversion phase
- **unzip** - For configuration extraction

## Installation

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/bikashdaspio/Claude-Analyzer/main/install.sh | bash
```

### Manual Installation

```bash
git clone https://github.com/bikashdaspio/Claude-Analyzer.git
cd Claude-Analyzer
chmod +x analyze.sh config.sh lib/*.sh
```

## Configuration

### Initialize Claude Skills & Agents

The tool includes a configuration system for Claude Code skills and agents:

```bash
# Extract and install skills/agents from bundled ZIP
./config.sh init

# Force overwrite existing configuration
./config.sh init --force

# Preview what would be installed
./config.sh init --dry-run

# Verify installation
./config.sh verify
```

### Module Structure

Create a `module-structure.json` file defining your modules:

> In order to create the module-structure.json
> You are needed to run claude and invoke the
> the skill `/module-discovery` that will create acquire the context and create that file at the root directory of the project.

```json
{
  "modules": [
    {
      "name": "Employee",
      "complexity": "high",
      "subModules": [
        { "name": "Profile", "complexity": "medium" },
        { "name": "Documents", "complexity": "low" }
      ]
    },
    {
      "name": "Payroll",
      "complexity": "high"
    }
  ]
}
```

## Usage

### Basic Commands

```bash
# Run full analysis workflow (analyze → validate → convert)
./analyze.sh

# Preview what would be analyzed
./analyze.sh --dry-run

# Reset all progress and start fresh
./analyze.sh --reset

# Analyze a specific module
./analyze.sh --module Employee

# Analyze a specific submodule
./analyze.sh --module Employee/Profile

# Retry previously failed modules
./analyze.sh --retry-failed
```

### Parallel Processing

```bash
# Run 4 modules in parallel
./analyze.sh --parallel 4
./analyze.sh -p 4

# Parallel with no timeout
./analyze.sh -p 4 --no-timeout

# Parallel with custom timeout (30 minutes)
./analyze.sh -p 3 --timeout 1800
```

### Phase Control

The tool runs in 4 phases:
1. **Phase 1 & 2**: Module Analysis (submodules first, then parent modules)
2. **Phase 3**: Markdown Validation
3. **Phase 4**: DOCX Conversion

```bash
# Run only markdown validation
./analyze.sh --validation-only

# Run only DOCX conversion
./analyze.sh --conversion-only

# Skip validation phase
./analyze.sh --skip-validation

# Skip conversion phase
./analyze.sh --skip-conversion
```

### Timeout Configuration

Default timeouts are complexity-based:
- **Low complexity**: 10 minutes
- **Medium complexity**: 20 minutes
- **High complexity**: 30 minutes

```bash
# Disable all timeouts
./analyze.sh --no-timeout

# Set custom timeout (1 hour) for all modules
./analyze.sh --timeout 3600
```

### Other Options

```bash
# Verbose output
./analyze.sh --verbose

# Custom delay between modules (10 seconds)
./analyze.sh --delay 10

# Show help
./analyze.sh --help
```

## Output Structure

```
Documents/
├── BRD/                    # Business Requirements Documents
├── FRD/                    # Functional Requirements Documents
├── UserStories/            # User story documents
├── ProcessFlow/
│   └── diagrams/           # Process flow diagrams
├── Modules/
│   └── diagrams/           # Module diagrams
├── Security/               # Security documentation
├── Migration Notes/        # Migration notes
└── DOCX/                   # Converted Word documents

.analyze-state/
├── queue.txt               # Analysis queue
├── failed.txt              # Failed modules list
├── session                 # Session tracking
├── logs/                   # Per-module log files
└── analyze.log             # Main log file
```

## Project Structure

```
.
├── analyze.sh              # Main analysis script
├── config.sh               # Configuration/setup script
├── install.sh              # Installation script
├── lib/
│   ├── config.sh           # Configuration variables
│   ├── logging.sh          # Logging functions
│   ├── prerequisites.sh    # Prerequisite checks
│   ├── json-utils.sh       # JSON manipulation utilities
│   ├── analysis.sh         # Core analysis functions
│   ├── parallel.sh         # Parallel processing
│   ├── validation.sh       # Markdown validation
│   ├── conversion.sh       # DOCX conversion
│   └── cli.sh              # CLI argument parsing
├── .claude/                # Claude skills & agents
│   ├── agents/             # Custom agents
│   ├── skills/             # Custom skills
│   ├── commands/           # Custom commands
│   └── settings.local.json # Local settings
└── .claude-config.zip      # Bundled configuration
```

## Examples

### Full Workflow

```bash
# Initialize configuration
./config.sh init

# Run complete analysis with 4 parallel jobs
./analyze.sh -p 4

# Check results
ls Documents/
ls Documents/DOCX/
```

### Resuming After Interruption

```bash
# Analysis was interrupted
# Simply run again - it will skip completed modules
./analyze.sh

# Or retry only failed modules
./analyze.sh --retry-failed
```

### Development Workflow

```bash
# Preview analysis queue
./analyze.sh --dry-run

# Analyze single module for testing
./analyze.sh --module Employee/Profile --verbose

# Validate markdown files only
./analyze.sh --validation-only -p 4

# Convert to DOCX only
./analyze.sh --conversion-only
```

## Troubleshooting

### Claude CLI Not Found

Ensure Claude CLI is installed and available in your PATH:

```bash
which claude
claude --version
```

### Permission Denied

Make scripts executable:

```bash
chmod +x analyze.sh config.sh lib/*.sh
```

### Module Not Found

Check your `module-structure.json` syntax:

```bash
jq . module-structure.json
```

### Timeout Issues

For complex modules, disable or increase timeouts:

```bash
./analyze.sh --no-timeout
# or
./analyze.sh --timeout 7200  # 2 hours
```

## License

MIT License

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request
