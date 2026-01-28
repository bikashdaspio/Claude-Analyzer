#!/bin/bash

# Claude-Analyzer Installation Script
# Downloads and installs Claude-Analyzer from GitHub into the current directory

set -e

# Configuration
REPO_URL="https://github.com/bikashdaspio/Claude-Analyzer"
REPO_NAME="Claude-Analyzer"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="$(pwd)"

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

# Download and extract the repository
download_repo() {
    info "Downloading Claude-Analyzer..."

    local zip_url="${REPO_URL}/archive/refs/heads/${BRANCH}.zip"
    local temp_zip="/tmp/${REPO_NAME}.zip"
    local temp_dir="/tmp/${REPO_NAME}-${BRANCH}"

    # Download zip archive
    if command -v curl &> /dev/null; then
        curl -fsSL "$zip_url" -o "$temp_zip" || error "Failed to download zip archive"
    elif command -v wget &> /dev/null; then
        wget -q "$zip_url" -O "$temp_zip" || error "Failed to download zip archive"
    fi

    info "Extracting archive..."
    unzip -q "$temp_zip" -d /tmp || error "Failed to extract zip archive"

    # Copy contents to current directory (including hidden files)
    cp -r "$temp_dir"/* "$INSTALL_DIR"/ || error "Failed to copy files"
    cp -r "$temp_dir"/.[!.]* "$INSTALL_DIR"/ 2>/dev/null || true

    # Clean up
    rm -f "$temp_zip"
    rm -rf "$temp_dir"

    success "Files downloaded and extracted."
}

# Extract .claude-config.zip into .claude directory
extract_config() {
    local config_zip="$INSTALL_DIR/.claude-config.zip"
    local claude_dir="$INSTALL_DIR/.claude"

    if [ -f "$config_zip" ]; then
        info "Extracting .claude-config.zip into .claude directory..."
        mkdir -p "$claude_dir"
        unzip -q "$config_zip" -d "$claude_dir" || error "Failed to extract .claude-config.zip"
        success ".claude-config.zip extracted to .claude/"
    else
        warn ".claude-config.zip not found in repository."
    fi
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
    download_repo
    extract_config
    setup_permissions
    print_usage
}

# Run main function
main "$@"
