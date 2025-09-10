#!/bin/bash

# Build script for EasyCrypt LSP Server
# Usage: ./build_lsp.sh [clean|install|package]

set -e  # Exit on any error

PROJECT_ROOT="/home/marcilunga/dev/vsec"
SRC_DIR="$PROJECT_ROOT/src"
EXTENSION_DIR="$PROJECT_ROOT/vscode-extension"
LSP_EXECUTABLE="$SRC_DIR/_build/default/eclsp/ecLsp.exe"
BUNDLED_LSP="$EXTENSION_DIR/vsec-lsp"

echo "🔨 EasyCrypt LSP Build Script"
echo "============================="
echo "Project root: $PROJECT_ROOT"
echo "Source dir: $SRC_DIR"

# Function to build LSP server
build_lsp() {
    echo "📦 Building LSP server..."
    cd "$SRC_DIR"
    opam exec -- dune build
    
    if [ -f "$LSP_EXECUTABLE" ]; then
        echo "✅ LSP server built successfully: $LSP_EXECUTABLE"
        ls -lh "$LSP_EXECUTABLE"
    else
        echo "❌ LSP server build failed - executable not found"
        exit 1
    fi
}

# Function to clean build artifacts
clean_build() {
    echo "🧹 Cleaning build artifacts..."
    cd "$SRC_DIR"
    opam exec -- dune clean
    echo "✅ Build artifacts cleaned"
}

# Function to install LSP server locally
install_lsp() {
    echo "📥 Installing LSP server locally..."
    cd "$SRC_DIR"
    opam exec -- dune install --prefix="$HOME/.local"
    
    if command -v vsec-lsp &> /dev/null; then
        BIN_PATH="$(which vsec-lsp)"
        echo "✅ LSP server installed: $BIN_PATH"
        # Do not execute the server here to avoid starting the event loop
        ls -lh "$BIN_PATH" || true
    else
        echo "❌ LSP server installation failed"
        exit 1
    fi
}

# Function to bundle LSP with VS Code extension
bundle_extension() {
    echo "📦 Bundling LSP server with VS Code extension..."
    
    # Ensure LSP server is built
    if [ ! -f "$LSP_EXECUTABLE" ]; then
        echo "LSP server not found, building first..."
        build_lsp
    fi
    
    # Remove old bundled LSP if it exists
    [ -f "$BUNDLED_LSP" ] && rm -f "$BUNDLED_LSP"
    
    # Copy to extension directory
    cp "$LSP_EXECUTABLE" "$BUNDLED_LSP"
    chmod +x "$BUNDLED_LSP"
    
    echo "✅ LSP server bundled: $BUNDLED_LSP"
    ls -lh "$BUNDLED_LSP"
}

# Function to package VS Code extension
package_extension() {
    echo "📦 Packaging VS Code extension..."
    bundle_extension
    
    cd "$EXTENSION_DIR"
    echo "🔧 Compiling TypeScript with webpack..."
    nix-shell "$PROJECT_ROOT/shell.nix" --command "npm run compile"
    echo "📦 Creating VSIX package..."
    # Remove old vsix to avoid picking the wrong artifact
    rm -f "$EXTENSION_DIR"/vsec-easycrypt-*.vsix || true
    nix-shell "$PROJECT_ROOT/shell.nix" --command "npm run package"
    
    if ls "$EXTENSION_DIR"/vsec-easycrypt-*.vsix 1> /dev/null 2>&1; then
        echo "✅ Extension packaged successfully:"
        ls -lh "$EXTENSION_DIR"/vsec-easycrypt-*.vsix
    else
        echo "❌ Extension packaging failed"
        exit 1
    fi
}

# Function to install the freshly built VSIX using code CLI
install_vsix() {
    echo "🧩 Installing VSIX into VS Code..."
    package_extension
    cd "$EXTENSION_DIR"
    # Pick the newest VSIX to avoid installing a stale one
    VSIX_FILE=$(ls -t vsec-easycrypt-*.vsix | head -n1)
    if [ -z "$VSIX_FILE" ]; then
        echo "❌ No VSIX found to install"
        exit 1
    fi
    echo "Installing: $VSIX_FILE"
    if command -v code &> /dev/null; then
        code --install-extension "$VSIX_FILE" --force
        echo "✅ Installed VSIX via 'code' CLI"
    elif command -v codium &> /dev/null; then
        codium --install-extension "$VSIX_FILE" --force
        echo "✅ Installed VSIX via 'codium' CLI"
    else
        echo "⚠️ Neither 'code' nor 'codium' found. Please install manually: $EXTENSION_DIR/$VSIX_FILE"
    fi
}

# Main script logic
case "${1:-build}" in
    "clean")
        clean_build
        ;;
    "install")
        build_lsp
        install_lsp
        ;;
    "bundle")
        build_lsp
        bundle_extension
        ;;
    "package")
        build_lsp
        package_extension
        ;;
    "install-vsix")
        build_lsp
        install_vsix
        ;;
    "build"|"")
        build_lsp
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  build     Build LSP server (default)"
        echo "  clean     Clean build artifacts"
        echo "  install   Build and install LSP server locally"
        echo "  bundle    Build and bundle LSP with VS Code extension"
        echo "  package   Build, bundle, and package complete extension"
        echo "  help      Show this help message"
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac

echo ""
echo "🎉 Build script completed successfully!"