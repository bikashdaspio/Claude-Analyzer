#!/bin/bash

# Claude-Analyzer Installation Script
# Downloads and installs Claude-Analyzer from GitHub into the current directory

set -e

# Configuration
REPO_URL="https://github.com/bikashdaspio/Claude-Analyzer"
REPO_RAW_URL="https://raw.githubusercontent.com/bikashdaspio/Claude-Analyzer"
REPO_NAME="Claude-Analyzer"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="$(pwd)"

# Files to download from bash/ directory
BASH_FILES=(
    "analyze.sh"
    "config.sh"
    "README.md"
    "CLAUDE.md"
)

# Files to download from repository root
ROOT_FILES=(
    "custom-reference.docx"
)

# Library files to download from bash/lib/
LIB_FILES=(
    "analysis.sh"
    "cli.sh"
    "config.sh"
    "conversion.sh"
    "json-utils.sh"
    "logging.sh"
    "parallel.sh"
    "prerequisites.sh"
    "validation.sh"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored messages
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    # Check for curl or wget
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        error "Neither curl nor wget is installed. Please install one of them."
    fi

    # Check for unzip
    if ! command -v unzip &> /dev/null; then
        error "unzip is not installed. Please install it first."
    fi

    success "All prerequisites met."
}

# Download a single file from the repository
download_file() {
    local remote_path="$1"
    local local_path="$2"
    local url="${REPO_RAW_URL}/${BRANCH}/${remote_path}"

    if command -v curl &> /dev/null; then
        curl -fsSL "$url" -o "$local_path" || return 1
    elif command -v wget &> /dev/null; then
        wget -q "$url" -O "$local_path" || return 1
    fi
    return 0
}

# Download bash scripts from repository
download_bash_files() {
    info "Downloading Claude-Analyzer bash scripts..."

    # Create lib directory
    mkdir -p "$INSTALL_DIR/lib"

    # Download main bash files
    for file in "${BASH_FILES[@]}"; do
        info "  Downloading $file..."
        if ! download_file "bash/$file" "$INSTALL_DIR/$file"; then
            error "Failed to download $file"
        fi
    done

    # Download lib files
    for file in "${LIB_FILES[@]}"; do
        info "  Downloading lib/$file..."
        if ! download_file "bash/lib/$file" "$INSTALL_DIR/lib/$file"; then
            error "Failed to download lib/$file"
        fi
    done

    # Download files from repository root
    for file in "${ROOT_FILES[@]}"; do
        info "  Downloading $file..."
        if ! download_file "$file" "$INSTALL_DIR/$file"; then
            error "Failed to download $file"
        fi
    done

    # Download .claude-config.zip from root
    info "  Downloading .claude-config.zip..."
    if ! download_file ".claude-config.zip" "$INSTALL_DIR/.claude-config.zip"; then
        warn "Failed to download .claude-config.zip (may not exist)"
    fi

    success "Bash scripts downloaded."
}

# Extract .claude-config.zip into .claude directory
extract_config() {
    local config_zip="$INSTALL_DIR/.claude-config.zip"
    local claude_dir="$INSTALL_DIR/.claude"

    if [ ! -f "$config_zip" ]; then
        warn ".claude-config.zip not found. Skipping config extraction."
        return 0
    fi

    info "Extracting .claude-config.zip into .claude directory..."
    mkdir -p "$claude_dir"
    unzip -q "$config_zip" -d "$claude_dir" || error "Failed to extract .claude-config.zip"
    success ".claude-config.zip extracted to .claude/"
}

# Set up permissions
setup_permissions() {
    info "Setting up permissions..."

    # Make scripts executable
    chmod +x "$INSTALL_DIR/analyze.sh" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/config.sh" 2>/dev/null || true

    # Make lib scripts executable
    if [ -d "$INSTALL_DIR/lib" ]; then
        chmod +x "$INSTALL_DIR/lib/"*.sh 2>/dev/null || true
    fi

    success "Permissions configured."
}

# Print usage instructions
print_usage() {
    echo ""
    echo "=========================================="
    success "Claude-Analyzer installed successfully!"
    echo "=========================================="
    echo ""
    echo "Files installed in: $INSTALL_DIR"
    echo ""
    echo "Usage:"
    echo "  ./analyze.sh <path-to-claude-config.zip>"
    echo ""
    echo "For help:"
    echo "  ./analyze.sh --help"
    echo ""
}

# Main installation flow
main() {
    echo ""
    echo "=========================================="
    echo "  Claude-Analyzer Installation Script"
    echo "=========================================="
    echo ""

    check_prerequisites
    download_bash_files
    extract_config
    setup_permissions
    print_usage
}

# Run main function
main "$@"
