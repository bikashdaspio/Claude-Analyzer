#!/usr/bin/env bash
#
# config.sh - Claude Code Skills & Agents Initialization Script
# Version: 1.0.0
#
# This script extracts and installs Claude Code skills, agents, commands,
# and settings from a ZIP archive to the .claude directory.
#
# Usage:
#   ./config.sh init [--force] [--dry-run] [--verbose] [--zip PATH]
#   ./config.sh pack [--verbose]
#   ./config.sh verify [--verbose]
#   ./config.sh --help
#

set -euo pipefail

# =============================================================================
# [1] HEADER & CONFIGURATION
# =============================================================================

readonly VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default paths
readonly DEFAULT_ZIP_PATH="${SCRIPT_DIR}/.claude-config.zip"
readonly CLAUDE_DIR="${SCRIPT_DIR}/.claude"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Global flags (can be modified by arguments)
COMMAND=""
FORCE="false"
DRY_RUN="false"
VERBOSE="false"
ZIP_PATH="$DEFAULT_ZIP_PATH"

# Counters
INSTALLED_COUNT=0
SKIPPED_COUNT=0

# =============================================================================
# [2] UTILITY FUNCTIONS
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC}   $1"
}

log_warn() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERR]${NC}  $1" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

print_header() {
    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║      Claude Code Skills & Agents Initialization Script        ║${NC}"
    echo -e "${BOLD}║                        Version ${VERSION}                          ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

ensure_dir() {
    local dir="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_verbose "Would create directory: $dir"
    else
        mkdir -p "$dir"
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check bash version (need 4.0+)
    local bash_version="${BASH_VERSION%%.*}"
    if [[ "$bash_version" -lt 4 ]]; then
        log_error "bash version 4.0+ required (found: $BASH_VERSION)"
        return 1
    fi
    log_success "bash version $BASH_VERSION (required: 4.0+)"

    # Check unzip is available
    if ! command -v unzip &> /dev/null; then
        log_error "unzip command not found. Please install unzip."
        return 1
    fi
    log_success "unzip available"

    # Check zip for pack command
    if ! command -v zip &> /dev/null; then
        log_warn "zip command not found. 'pack' command will not be available."
    else
        log_verbose "zip available"
    fi

    return 0
}

# =============================================================================
# [3] CORE FUNCTIONS
# =============================================================================

extract_archive() {
    local zip_path="${1:-$ZIP_PATH}"

    if [[ ! -f "$zip_path" ]]; then
        log_error "ZIP archive not found: $zip_path"
        return 1
    fi

    local temp_dir
    temp_dir=$(mktemp -d)

    # Output to FD 3 which we'll redirect to stdout in main
    echo -e "${BLUE}[INFO]${NC} Extracting archive: $zip_path" >&3

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} Would extract to: $temp_dir" >&3
        # Still extract for dry-run to list what would be installed
    fi

    unzip -q "$zip_path" -d "$temp_dir"
    echo -e "${GREEN}[OK]${NC}   Extracted to temporary directory" >&3
    echo "" >&3

    echo "$temp_dir"
}

install_file() {
    local src="$1"
    local dst="$2"
    local display_name="${dst#$SCRIPT_DIR/}"

    if [[ -f "$dst" && "$FORCE" != "true" ]]; then
        log_warn "Exists: $display_name"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -f "$dst" ]]; then
            log_info "Would overwrite: $display_name"
        else
            log_info "Would install: $display_name"
        fi
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        return 0
    fi

    ensure_dir "$(dirname "$dst")"
    cp "$src" "$dst"
    log_success "Installed: $display_name"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
}

install_directory() {
    local src_dir="$1"
    local dst_dir="$2"

    if [[ ! -d "$src_dir" ]]; then
        log_verbose "Source directory not found: $src_dir"
        return 0
    fi

    # Find all files in source directory and install them
    while IFS= read -r -d '' src_file; do
        local relative_path="${src_file#$src_dir/}"
        local dst_file="$dst_dir/$relative_path"
        install_file "$src_file" "$dst_file"
    done < <(find "$src_dir" -type f -print0)
}

setup_documents_dir() {
    log_info "Creating Documents structure..."

    local dirs=(
        "Documents/BRD"
        "Documents/FRD"
        "Documents/UserStories"
        "Documents/ProcessFlow/diagrams"
        "Documents/Modules/diagrams"
        "Documents/Security"
        "Documents/Migration Notes"
    )

    for dir in "${dirs[@]}"; do
        local full_path="${SCRIPT_DIR}/${dir}"
        if [[ -d "$full_path" ]]; then
            log_verbose "Directory exists: $dir"
        else
            ensure_dir "$full_path"
            if [[ "$DRY_RUN" != "true" ]]; then
                log_success "Created: $dir/"
            else
                log_info "Would create: $dir/"
            fi
        fi
    done
}

install_all() {
    local temp_dir="$1"

    echo ""
    log_info "Installing agents..."
    install_directory "$temp_dir/agents" "$CLAUDE_DIR/agents"

    echo ""
    log_info "Installing skills..."
    install_directory "$temp_dir/skills" "$CLAUDE_DIR/skills"

    echo ""
    log_info "Installing commands..."
    install_directory "$temp_dir/commands" "$CLAUDE_DIR/commands"

    echo ""
    log_info "Installing settings..."
    if [[ -f "$temp_dir/settings.local.json" ]]; then
        install_file "$temp_dir/settings.local.json" "$CLAUDE_DIR/settings.local.json"
    fi

    echo ""
    setup_documents_dir
}

create_zip_archive() {
    local output="${1:-$DEFAULT_ZIP_PATH}"

    if ! command -v zip &> /dev/null; then
        log_error "zip command not found. Please install zip."
        return 1
    fi

    if [[ ! -d "$CLAUDE_DIR" ]]; then
        log_error ".claude directory not found: $CLAUDE_DIR"
        return 1
    fi

    log_info "Creating archive from .claude directory..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would create: $output"
        log_info "Contents:"
        (cd "$CLAUDE_DIR" && find agents skills commands -type f 2>/dev/null | while read -r f; do
            log_info "  Would add: $f"
        done)
        [[ -f "$CLAUDE_DIR/settings.local.json" ]] && log_info "  Would add: settings.local.json"
        return 0
    fi

    # Remove existing archive if present
    [[ -f "$output" ]] && rm -f "$output"

    # Create ZIP with directory structure preserved (quiet mode)
    (cd "$CLAUDE_DIR" && zip -rq "$output" \
        agents/ skills/ commands/ settings.local.json) || {
        log_error "Failed to create ZIP archive"
        return 1
    }

    local size
    size=$(du -h "$output" | cut -f1)

    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "          ${GREEN}Archive created: ${output##*/} ($size)${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# [4] VERIFICATION FUNCTIONS
# =============================================================================

verify_structure() {
    log_info "Verifying .claude directory structure..."
    echo ""

    local errors=0
    local checks=0

    # Check agents
    local agents=("system-analysist.md" "react-vue-bridge.md" "ui-parity.md")
    for agent in "${agents[@]}"; do
        checks=$((checks + 1))
        if [[ -f "$CLAUDE_DIR/agents/$agent" ]]; then
            log_success "agents/$agent"
        else
            log_error "Missing: agents/$agent"
            errors=$((errors + 1))
        fi
    done

    # Check skills
    local skills=("brd" "frd" "process-flow" "security-document" "user-stories")
    for skill in "${skills[@]}"; do
        checks=$((checks + 1))
        if [[ -f "$CLAUDE_DIR/skills/$skill/SKILL.md" ]]; then
            log_success "skills/$skill/SKILL.md"
        else
            log_error "Missing: skills/$skill/SKILL.md"
            errors=$((errors + 1))
        fi

        # Check templates directory exists
        checks=$((checks + 1))
        if [[ -d "$CLAUDE_DIR/skills/$skill/templates" ]]; then
            local template_count
            template_count=$(find "$CLAUDE_DIR/skills/$skill/templates" -name "*.docx" 2>/dev/null | wc -l)
            if [[ "$template_count" -gt 0 ]]; then
                log_success "skills/$skill/templates/ ($template_count .docx files)"
            else
                log_warn "skills/$skill/templates/ (no .docx files)"
            fi
        else
            log_error "Missing: skills/$skill/templates/"
            errors=$((errors + 1))
        fi
    done

    # Check commands
    local commands=("analyze.md" "iterative-migrate.md")
    for cmd in "${commands[@]}"; do
        checks=$((checks + 1))
        if [[ -f "$CLAUDE_DIR/commands/$cmd" ]]; then
            log_success "commands/$cmd"
        else
            log_error "Missing: commands/$cmd"
            errors=$((errors + 1))
        fi
    done

    # Check settings
    checks=$((checks + 1))
    if [[ -f "$CLAUDE_DIR/settings.local.json" ]]; then
        log_success "settings.local.json"
    else
        log_error "Missing: settings.local.json"
        errors=$((errors + 1))
    fi

    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    if [[ "$errors" -eq 0 ]]; then
        echo -e "          ${GREEN}Verification PASSED ($checks checks)${NC}"
    else
        echo -e "          ${RED}Verification FAILED ($errors errors / $checks checks)${NC}"
    fi
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"

    return "$errors"
}

print_summary() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "                    ${YELLOW}DRY RUN COMPLETE${NC}"
    else
        echo -e "                    ${GREEN}INITIALIZATION COMPLETE${NC}"
    fi
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo "  Agents:    3 $(if [[ $DRY_RUN == "true" ]]; then echo "would be "; fi)processed"
    echo "  Skills:    5 $(if [[ $DRY_RUN == "true" ]]; then echo "would be "; fi)processed (+ 5 templates)"
    echo "  Commands:  2 $(if [[ $DRY_RUN == "true" ]]; then echo "would be "; fi)processed"
    echo "  Settings:  1 $(if [[ $DRY_RUN == "true" ]]; then echo "would be "; fi)processed"
    echo ""
    echo "  Installed: $INSTALLED_COUNT"
    echo "  Skipped:   $SKIPPED_COUNT $(if [[ $SKIPPED_COUNT -gt 0 ]]; then echo "(use --force to overwrite)"; fi)"
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# [5] MAIN ENTRY POINT
# =============================================================================

show_help() {
    echo -e "${BOLD}Claude Code Skills & Agents Initialization Script v${VERSION}${NC}"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    $SCRIPT_NAME <command> [options]"
    echo ""
    echo -e "${BOLD}COMMANDS:${NC}"
    echo "    init        Extract ZIP and install everything to .claude/"
    echo "    pack        Create ZIP from existing .claude/"
    echo "    verify      Verify setup completeness"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    --force     Overwrite existing files (default: skip existing)"
    echo "    --dry-run   Show what would be done without doing it"
    echo "    --verbose   Detailed output"
    echo "    --zip PATH  Specify custom ZIP archive path"
    echo "    --help      Show this help message"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    # Initialize everything from ZIP (skips existing files)"
    echo "    $SCRIPT_NAME init"
    echo ""
    echo "    # Initialize and force overwrite existing"
    echo "    $SCRIPT_NAME init --force"
    echo ""
    echo "    # Dry run to see what would happen"
    echo "    $SCRIPT_NAME init --dry-run"
    echo ""
    echo "    # Create/update ZIP from current .claude directory"
    echo "    $SCRIPT_NAME pack"
    echo ""
    echo "    # Verify current setup"
    echo "    $SCRIPT_NAME verify --verbose"
    echo ""
    echo "    # Use custom ZIP path"
    echo "    $SCRIPT_NAME init --zip /path/to/custom-config.zip"
}

parse_arguments() {
    COMMAND=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            init|pack|verify)
                COMMAND="$1"
                shift
                ;;
            --force|-f)
                FORCE="true"
                shift
                ;;
            --dry-run|-n)
                DRY_RUN="true"
                shift
                ;;
            --verbose|-v)
                VERBOSE="true"
                shift
                ;;
            --zip)
                if [[ -n "${2:-}" ]]; then
                    ZIP_PATH="$2"
                    shift 2
                else
                    log_error "--zip requires a path argument"
                    exit 2
                fi
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                echo "Use --help for usage information."
                exit 2
                ;;
        esac
    done
}

cleanup() {
    local temp_dir="${1:-}"
    if [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
        log_verbose "Cleaned up temporary directory"
    fi
}

main() {
    parse_arguments "$@"

    case "$COMMAND" in
        init)
            print_header
            check_prerequisites || exit 1

            local temp_dir
            # Use FD 3 for extract_archive log output
            exec 3>&1
            temp_dir=$(extract_archive "$ZIP_PATH") || exit 1
            exec 3>&-

            # Set up trap for cleanup
            trap "cleanup '$temp_dir'" EXIT

            install_all "$temp_dir"
            print_summary
            ;;
        pack)
            print_header
            check_prerequisites || exit 1
            create_zip_archive "$ZIP_PATH"
            ;;
        verify)
            print_header
            verify_structure
            ;;
        "")
            log_error "No command specified"
            echo ""
            show_help
            exit 2
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 2
            ;;
    esac
}

# Run main with all arguments
main "$@"
