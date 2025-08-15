#!/bin/bash

# VsEc EasyCrypt Extension Build Script
# This script systematically builds the extension without issues

set -e  # Exit on any error

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

cleanup() {
    log "Cleaning up build artifacts..."
    
    # Clean VSCode extension artifacts
    cd vscode-extension
    rm -f *.vsix
    rm -rf dist/
    rm -rf out/
    rm -rf goal-view-ui/build/
    rm -f vsec-lsp  # Remove LSP binary
    cd ..
    
    # Clean LSP build artifacts
    if [ -d "/home/marcilunga/dev/vsec/src/_build" ]; then
        log "Cleaning LSP build artifacts..."
        rm -rf "/home/marcilunga/dev/vsec/src/_build"
    fi
    
    success "Cleanup complete"
}

check_nix() {
    if ! command -v nix-shell &> /dev/null; then
        error "Nix is required but not installed. Please install Nix first."
        exit 1
    fi
    
    if [ ! -f "shell.nix" ]; then
        error "shell.nix not found. Please run from the project root directory."
        exit 1
    fi
    
    success "Nix environment available"
}

build_lsp_from_source() {
    log "Building LSP server from source..."
    
    # Check if we have OCaml/dune environment
    if ! command -v opam &> /dev/null; then
        error "OCaml/opam is required to build LSP server"
        error "Please install OCaml development environment first"
        exit 1
    fi
    
    # Build using opam/dune
    cd /home/marcilunga/dev/vsec/src
    log "Running: opam exec -- dune build"
    if ! opam exec -- dune build; then
        error "LSP server build failed"
        exit 1
    fi
    cd - > /dev/null
    
    success "LSP server built successfully"
}

clean_lsp_binary() {
    log "Cleaning existing LSP binary..."
    local DEST_BINARY="/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp"
    
    if [ -f "$DEST_BINARY" ]; then
        # Fix permissions first to ensure we can remove it
        chmod 755 "$DEST_BINARY" 2>/dev/null || true
        
        # Remove the binary
        if ! rm -f "$DEST_BINARY"; then
            error "Failed to remove existing LSP binary at $DEST_BINARY"
            error "Check file permissions and try again"
            exit 1
        fi
        
        # Verify removal
        if [ -f "$DEST_BINARY" ]; then
            error "LSP binary still exists after removal attempt"
            error "Please manually remove $DEST_BINARY and try again"
            exit 1
        fi
        
        success "Existing LSP binary removed"
    else
        log "No existing LSP binary to clean"
    fi
}

copy_lsp_binary() {
    local force_copy=${1:-false}
    
    log "Setting up LSP server binary..."
    
    # Source and destination paths (full paths as requested)
    local SOURCE_BINARY="/home/marcilunga/dev/vsec/src/_build/default/eclsp/ecLsp.exe"
    local DEST_BINARY="/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp"
    
    # Check if we already have a working LSP binary (unless forced)
    if [ "$force_copy" = false ] && [ -f "$DEST_BINARY" ] && [ -x "$DEST_BINARY" ]; then
        log "Using existing LSP server binary"
        success "LSP server binary ready"
        return 0
    fi
    
    # CRITICAL: Always remove existing binary first to avoid permission issues
    if [ -f "$DEST_BINARY" ]; then
        log "Removing existing LSP binary to ensure clean copy..."
        # Force remove with proper permissions
        chmod 755 "$DEST_BINARY" 2>/dev/null || true
        rm -f "$DEST_BINARY"
        if [ -f "$DEST_BINARY" ]; then
            error "Failed to remove existing LSP binary at $DEST_BINARY"
            error "Please manually remove it and try again"
            exit 1
        fi
        success "Existing LSP binary removed"
    fi
    
    # Try to find and copy the built binary
    if [ -f "$SOURCE_BINARY" ] && [ -x "$SOURCE_BINARY" ]; then
        log "Found LSP server at $SOURCE_BINARY"
        
        # Copy with error checking
        if ! cp "$SOURCE_BINARY" "$DEST_BINARY"; then
            error "Failed to copy LSP binary from $SOURCE_BINARY to $DEST_BINARY"
            error "Check permissions and disk space"
            exit 1
        fi
        
        # Set proper permissions
        if ! chmod +x "$DEST_BINARY"; then
            error "Failed to set executable permissions on $DEST_BINARY"
            exit 1
        fi
        
        # Verify the copy was successful
        if [ ! -f "$DEST_BINARY" ] || [ ! -x "$DEST_BINARY" ]; then
            error "LSP binary copy verification failed"
            exit 1
        fi
        
        success "LSP server copied from $SOURCE_BINARY"
        return 0
    fi
    
    # Try other possible locations
    local LSP_LOCATIONS=(
        "/home/marcilunga/dev/vsec/src/_build/install/default/bin/ecLsp"
        "/home/marcilunga/dev/vsec/_build/default/eclsp/ecLsp.exe"
        "/home/marcilunga/dev/vsec/vscode-extension/bin/vsec-lsp"
    )
    
    for location in "${LSP_LOCATIONS[@]}"; do
        if [ -f "$location" ] && [ -x "$location" ]; then
            log "Found LSP server at $location"
            
            # Copy with error checking
            if ! cp "$location" "$DEST_BINARY"; then
                error "Failed to copy LSP binary from $location to $DEST_BINARY"
                error "Check permissions and disk space"
                exit 1
            fi
            
            # Set proper permissions
            if ! chmod +x "$DEST_BINARY"; then
                error "Failed to set executable permissions on $DEST_BINARY"
                exit 1
            fi
            
            # Verify the copy was successful
            if [ ! -f "$DEST_BINARY" ] || [ ! -x "$DEST_BINARY" ]; then
                error "LSP binary copy verification failed"
                exit 1
            fi
            
            success "LSP server copied from $location"
            return 0
        fi
    done
    
    error "LSP server binary not found. Please build it first with:"
    error "  $0 --lsp-only"
    error "Or manually with: cd /home/marcilunga/dev/vsec/src && opam exec -- dune build"
    exit 1
}

build_lsp_server() {
    local force_rebuild=${1:-false}
    
    if [ "$force_rebuild" = true ]; then
        clean_lsp_binary
        build_lsp_from_source
    fi
    
    copy_lsp_binary "$force_rebuild"
}

build_react_ui() {
    log "Building React goal view UI..."
    
    cd vscode-extension/goal-view-ui
    
    # Check if package.json exists
    if [ ! -f "package.json" ]; then
        error "goal-view-ui package.json not found"
        exit 1
    fi
    
    # Build using Nix Node.js environment
    nix-shell ../../shell.nix --command "npm install" || {
        error "React UI npm install failed"
        exit 1
    }
    
    nix-shell ../../shell.nix --command "npm run build" || {
        error "React UI build failed"
        exit 1
    }
    
    # Verify build artifacts exist
    if [ ! -f "build/index.html" ] || [ ! -d "build/assets" ]; then
        error "React UI build artifacts not found"
        exit 1
    fi
    
    success "React UI built successfully"
    cd ../..
}

compile_typescript() {
    log "Compiling TypeScript extension..."
    
    cd vscode-extension
    
    # Check if package.json exists
    if [ ! -f "package.json" ]; then
        error "Extension package.json not found"
        exit 1
    fi
    
    # Install dependencies and compile using Nix Node.js environment
    nix-shell ../shell.nix --command "npm install" || {
        error "Extension npm install failed"
        exit 1
    }
    
    nix-shell ../shell.nix --command "npm run compile" || {
        error "TypeScript compilation failed"
        exit 1
    }
    
    # Verify compilation artifacts
    if [ ! -f "dist/extension.js" ]; then
        error "TypeScript compilation artifacts not found"
        exit 1
    fi
    
    success "TypeScript compiled successfully"
    cd ..
}

update_version() {
    local version=${1:-"0.1.0"}
    log "Setting version to $version..."
    
    cd vscode-extension
    
    # Update package.json version
    if command -v jq &> /dev/null; then
        jq ".version = \"$version\"" package.json > package.json.tmp && mv package.json.tmp package.json
    else
        sed -i "s/\"version\": \".*\"/\"version\": \"$version\"/" package.json
    fi
    
    success "Version set to $version"
    cd ..
}

package_extension() {
    log "Packaging VSIX extension..."
    
    cd vscode-extension
    
    # Ensure binary is in extension root for proper bundling (like VSCoq)
    if [ ! -f "vsec-lsp" ]; then
        error "LSP binary not found in extension root"
        exit 1
    fi
    
    log "Binary location verified: $(ls -la vsec-lsp | awk '{print $5" bytes, "$6" "$7" "$8}')"
    
    # Package using Nix Node.js environment with latest vsce
    log "Packaging VSIX with vsce@3.6.0..."
    nix-shell ../shell.nix --command "npx @vscode/vsce@3.6.0 package --allow-missing-repository" || {
        error "VSIX packaging failed"
        exit 1
    }
    
    # Verify VSIX was created
    VSIX_FILE=$(ls -t *.vsix 2>/dev/null | head -n1)
    if [ -z "$VSIX_FILE" ]; then
        error "VSIX file not found after packaging"
        exit 1
    fi
    
    VSIX_SIZE=$(du -h "$VSIX_FILE" | cut -f1)
    success "VSIX packaged: $VSIX_FILE ($VSIX_SIZE)"
    
    cd ..
}

verify_build() {
    log "Verifying build..."
    
    # Check LSP server
    if [ ! -x "vscode-extension/vsec-lsp" ]; then
        error "LSP server binary not found or not executable"
        exit 1
    fi
    
    # Check React UI build
    if [ ! -f "vscode-extension/goal-view-ui/build/index.html" ]; then
        error "React UI build not found"
        exit 1
    fi
    
    # Check TypeScript compilation
    if [ ! -f "vscode-extension/dist/extension.js" ]; then
        error "TypeScript extension not compiled"
        exit 1
    fi
    
    # Check VSIX package
    cd vscode-extension
    VSIX_FILE=$(ls -t *.vsix 2>/dev/null | head -n1)
    if [ -z "$VSIX_FILE" ]; then
        error "VSIX package not found"
        exit 1
    fi
    cd ..
    
    success "Build verification complete"
}

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --clean        Clean build artifacts before building"
    echo "  -v, --version VER  Set package version (default: 0.1.0)"
    echo "  -l, --lsp-only     Build LSP server only"
    echo "  -e, --ext-only     Build VSCode extension only (requires existing LSP binary)"
    echo "  -f, --full         Build everything (LSP + extension) [default]"
    echo "  -r, --rebuild-lsp  Force rebuild LSP server even if binary exists"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                 # Full build with default version 0.1.0"
    echo "  $0 -c              # Clean full build"
    echo "  $0 -l              # Build LSP server only"
    echo "  $0 -e              # Build extension only"
    echo "  $0 -r              # Force rebuild LSP server"
    echo "  $0 -v 0.2.0        # Full build with version 0.2.0"
    echo "  $0 -c -v 0.2.0     # Clean full build with version 0.2.0"
}

# Parse command line arguments
VERSION="0.1.0"
CLEAN=false
BUILD_MODE="full"  # full, lsp-only, ext-only
REBUILD_LSP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -l|--lsp-only)
            BUILD_MODE="lsp-only"
            shift
            ;;
        -e|--ext-only)
            BUILD_MODE="ext-only"
            shift
            ;;
        -f|--full)
            BUILD_MODE="full"
            shift
            ;;
        -r|--rebuild-lsp)
            REBUILD_LSP=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main build process
main() {
    echo "========================================"
    echo "  VsEc EasyCrypt Extension Builder"
    echo "========================================"
    echo ""
    
    log "Starting build process..."
    log "Build mode: $BUILD_MODE"
    log "Version: $VERSION"
    log "Clean: $CLEAN"
    log "Rebuild LSP: $REBUILD_LSP"
    
    # Step 1: Clean if requested
    if [ "$CLEAN" = true ]; then
        cleanup
    fi
    
    # Step 2: Handle different build modes
    case $BUILD_MODE in
        "lsp-only")
            log "Building LSP server only..."
            build_lsp_from_source
            copy_lsp_binary true
            
            echo ""
            echo "========================================"
            success "LSP server build completed successfully!"
            echo "========================================"
            echo ""
            echo "LSP binary location: /home/marcilunga/dev/vsec/vscode-extension/vsec-lsp"
            echo ""
            ;;
            
        "ext-only")
            log "Building VSCode extension only..."
            
            # Check prerequisites for extension build
            check_nix
            
            # Ensure LSP binary exists
            if [ ! -f "/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp" ]; then
                error "LSP server binary not found. Build LSP first with:"
                error "  $0 --lsp-only"
                exit 1
            fi
            
            # Update version
            update_version "$VERSION"
            
            # Build React UI
            build_react_ui
            
            # Compile TypeScript extension
            compile_typescript
            
            # Package VSIX
            package_extension
            
            # Show results
            echo ""
            echo "========================================"
            success "Extension build completed successfully!"
            echo "========================================"
            echo ""
            
            cd vscode-extension
            VSIX_FILE=$(ls -t *.vsix 2>/dev/null | head -n1)
            VSIX_SIZE=$(du -h "$VSIX_FILE" 2>/dev/null | cut -f1)
            FILE_COUNT=$(nix-shell ../shell.nix --command "npx vsce ls" 2>/dev/null | grep -oP '\(\K[0-9]+' | head -1)
            
            echo "📦 Package: $VSIX_FILE"
            echo "📊 Size: $VSIX_SIZE"
            echo "📄 Files: ${FILE_COUNT:-unknown}"
            echo ""
            echo "To install:"
            echo "  code --install-extension $VSIX_FILE"
            echo ""
            cd ..
            ;;
            
        "full")
            log "Building everything (LSP + extension)..."
            
            # Check prerequisites
            check_nix
            
            # Update version
            update_version "$VERSION"
            
            # Build LSP server
            build_lsp_server "$REBUILD_LSP"
            
            # Build React UI
            build_react_ui
            
            # Compile TypeScript extension
            compile_typescript
            
            # Package VSIX
            package_extension
            
            # Verify build
            verify_build
            
            echo ""
            echo "========================================"
            success "Full build completed successfully!"
            echo "========================================"
            echo ""
            
            cd vscode-extension
            VSIX_FILE=$(ls -t *.vsix 2>/dev/null | head -n1)
            VSIX_SIZE=$(du -h "$VSIX_FILE" 2>/dev/null | cut -f1)
            FILE_COUNT=$(nix-shell ../shell.nix --command "npx vsce ls" 2>/dev/null | grep -oP '\(\K[0-9]+' | head -1)
            
            echo "📦 Package: $VSIX_FILE"
            echo "📊 Size: $VSIX_SIZE" 
            echo "📄 Files: ${FILE_COUNT:-unknown}"
            echo ""
            echo "To install:"
            echo "  code --install-extension $VSIX_FILE"
            echo ""
            cd ..
            ;;
    esac
}

# Run main function
main "$@"