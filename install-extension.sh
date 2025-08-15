#!/bin/bash

# VsEc Extension Installation Script
# This script helps properly install/update the extension

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Find the VSIX file
find_vsix() {
    cd vscode-extension
    VSIX_FILE=$(ls -t *.vsix 2>/dev/null | head -n1)
    if [ -z "$VSIX_FILE" ]; then
        error "No VSIX file found. Please run ./build-extension.sh first."
        exit 1
    fi
    VSIX_PATH="$PWD/$VSIX_FILE"
    cd ..
    echo "$VSIX_PATH"
}

show_manual_steps() {
    local vsix_path="$1"
    
    echo ""
    echo "========================================"
    echo "  MANUAL INSTALLATION STEPS"
    echo "========================================"
    echo ""
    echo "1. First, UNINSTALL the old extension:"
    echo "   - Open VS Code"
    echo "   - Go to Extensions (Ctrl+Shift+X)"
    echo "   - Search for 'VsEc' or 'EasyCrypt'"
    echo "   - Click the gear icon → Uninstall"
    echo "   - Reload VS Code window"
    echo ""
    echo "2. Install the new extension:"
    echo "   - Open VS Code"
    echo "   - Press Ctrl+Shift+P"
    echo "   - Type: 'Extensions: Install from VSIX'"
    echo "   - Select this file:"
    echo "     ${vsix_path}"
    echo ""
    echo "3. Verify installation:"
    echo "   - Check that version shows: 0.1.0"
    echo "   - Open an EasyCrypt file (.ec)"
    echo "   - Try: Ctrl+End (interpret to cursor)"
    echo ""
    echo "========================================"
    echo ""
}

show_debug_info() {
    local vsix_path="$1"
    
    echo ""
    echo "========================================"
    echo "  DEBUG INFORMATION"
    echo "========================================"
    echo ""
    echo "📦 VSIX File: $(basename "$vsix_path")"
    echo "📊 Size: $(du -h "$vsix_path" | cut -f1)"
    echo "📁 Location: $vsix_path"
    echo ""
    
    # Show package.json version
    cd vscode-extension
    if [ -f "package.json" ]; then
        VERSION=$(grep '"version"' package.json | sed 's/.*"version": "\([^"]*\)".*/\1/')
        echo "🔢 Package Version: $VERSION"
    fi
    cd ..
    
    echo ""
    echo "🔍 To check what version is actually running:"
    echo "   - Look at VS Code extension host console"
    echo "   - Should show: 'VsEc EasyCrypt v0.1.0'"
    echo "   - NOT: 'VsEc EasyCrypt v0.1.18'"
    echo ""
    echo "🐛 If still showing old version:"
    echo "   - VS Code is using cached extension"
    echo "   - Must fully uninstall old version first"
    echo "   - May need to restart VS Code completely"
    echo ""
}

show_troubleshooting() {
    echo ""
    echo "========================================"
    echo "  TROUBLESHOOTING"
    echo "========================================"
    echo ""
    echo "❌ Problem: Still showing old version (v0.1.18)"
    echo "✅ Solution:"
    echo "   1. Completely close VS Code"
    echo "   2. Remove extension manually:"
    echo "      rm -rf ~/.vscode-server/extensions/vsec.vsec-easycrypt-*"
    echo "   3. Restart VS Code"
    echo "   4. Install new VSIX"
    echo ""
    echo "❌ Problem: 'Interpret to current position doesn't work'"
    echo "✅ Solution:"
    echo "   1. Open goal panel first: Ctrl+Shift+P → 'VsEc: Show Goal Panel'"
    echo "   2. Then use: Ctrl+End (interpret to cursor)"
    echo "   3. Check VS Code Developer Console for debug messages"
    echo ""
    echo "❌ Problem: 'Black screen in goal panel'"
    echo "✅ Solution:"
    echo "   1. Check browser console in goal panel (F12)"
    echo "   2. Look for React error messages"
    echo "   3. Try refreshing the goal panel"
    echo ""
}

main() {
    echo "========================================"
    echo "  VsEc Extension Installation Helper"
    echo "========================================"
    echo ""
    
    log "Finding VSIX file..."
    VSIX_PATH=$(find_vsix)
    success "Found VSIX: $(basename "$VSIX_PATH")"
    
    show_debug_info "$VSIX_PATH"
    show_manual_steps "$VSIX_PATH"
    show_troubleshooting
    
    echo ""
    warning "IMPORTANT: You must manually uninstall the old extension first!"
    warning "VS Code will cache extensions and use the old version otherwise."
    echo ""
}

# Show usage
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage: $0"
    echo ""
    echo "This script provides instructions for manually installing the VsEc extension."
    echo "It cannot automatically install due to VS Code CLI limitations in this environment."
    echo ""
    exit 0
fi

main "$@"