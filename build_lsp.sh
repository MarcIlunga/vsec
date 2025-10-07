#!/bin/bash

# Build script for EasyCrypt LSP Server
# Usage: ./build_lsp.sh [clean|install|package]

set -e  # Exit on any error

PROJECT_ROOT="/home/marcilunga/dev/vsec"
SRC_DIR="$PROJECT_ROOT/src"
EXTENSION_DIR="$PROJECT_ROOT/vscode-extension"
LSP_EXECUTABLE="$SRC_DIR/_build/default/eclsp/ecLsp.exe"
ALT_LSP_EXECUTABLE="$SRC_DIR/_build/default/driver/ecLsp.exe"
BUNDLED_LSP="$EXTENSION_DIR/vsec-lsp"

echo "🔨 EasyCrypt LSP Build Script"
echo "============================="
echo "Project root: $PROJECT_ROOT"
echo "Source dir: $SRC_DIR"

# Function to build LSP server
build_lsp() {
    echo "📦 Generating AST tag mappings..."
    cd "$PROJECT_ROOT"
    python3 scripts/extract_easycrypt_pp.py
    
    echo "📦 Building LSP server and adapter..."
    cd "$SRC_DIR"
    # Build both the server and the adapter plugin
    opam exec -- dune build eclsp/ecLsp.exe dm/plugins/vsec_ec_adapter.cmxs
    
    if [ -f "$LSP_EXECUTABLE" ]; then
        echo "✅ LSP server built successfully: $LSP_EXECUTABLE"
        ls -lh "$LSP_EXECUTABLE"
    elif [ -f "$ALT_LSP_EXECUTABLE" ]; then
        echo "✅ LSP server built successfully (alt path): $ALT_LSP_EXECUTABLE"
        ls -lh "$ALT_LSP_EXECUTABLE"
        LSP_EXECUTABLE="$ALT_LSP_EXECUTABLE"
    else
        echo "❌ LSP server build failed - executable not found"
        exit 1
    fi
    
    # Copy adapter to extension resources
    ADAPTER_SOURCE="$SRC_DIR/_build/default/dm/plugins/vsec_ec_adapter.cmxs"
    ADAPTER_DEST="$EXTENSION_DIR/resources/adapters/linux-x64/vsec_ec_adapter.cmxs"
    if [ -f "$ADAPTER_SOURCE" ]; then
        echo "📦 Copying adapter to extension resources..."
        mkdir -p "$(dirname "$ADAPTER_DEST")"
        rm -f "$ADAPTER_DEST"  # Remove old version if exists
        cp "$ADAPTER_SOURCE" "$ADAPTER_DEST"
        echo "✅ Adapter copied: $ADAPTER_DEST"
        ls -lh "$ADAPTER_DEST"
    else
        echo "⚠️  Adapter not found at $ADAPTER_SOURCE"
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
    
    # Build first if needed
    if [ ! -f "$LSP_EXECUTABLE" ] && [ ! -f "$ALT_LSP_EXECUTABLE" ]; then
        echo "Building LSP server first..."
        build_lsp
    fi
    
    # Determine install directory
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
    
    # Copy binary
    if [ -f "$LSP_EXECUTABLE" ]; then
        cp "$LSP_EXECUTABLE" "$INSTALL_DIR/vsec-lsp"
    elif [ -f "$ALT_LSP_EXECUTABLE" ]; then
        cp "$ALT_LSP_EXECUTABLE" "$INSTALL_DIR/vsec-lsp"
    else
        echo "❌ LSP server binary not found"
        exit 1
    fi
    
    chmod +x "$INSTALL_DIR/vsec-lsp"
    
    echo "✅ LSP server installed: $INSTALL_DIR/vsec-lsp"
    ls -lh "$INSTALL_DIR/vsec-lsp"
    
    # Check if it's in PATH
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        echo ""
        echo "⚠️  Note: $HOME/.local/bin is not in your PATH"
        echo "   Add this line to your ~/.bashrc or ~/.zshrc:"
        echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# Build webview UI (goal-view-ui)
build_webview() {
    echo "🧱 Building webview UI (goal-view-ui)..."
    cd "$EXTENSION_DIR"
    npm --prefix goal-view-ui ci
    # Clean previous outDir to avoid stale assets
    rm -rf "$EXTENSION_DIR/media/goal-view" || true
    # Build with vite and force emptyOutDir
    npm --prefix goal-view-ui run build --silent -- --emptyOutDir
    echo "✅ Webview built: $EXTENSION_DIR/media/goal-view"
}

# Package with modern Node (prefer nvm Node 24)
package_with_modern_node() {
    echo "📦 Creating VSIX package (Node >= 20)..."
    # Try using nvm Node 24 if available
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        bash -lc 'source ~/.nvm/nvm.sh && nvm install 24 >/dev/null && nvm use 24 >/dev/null && node -v && cd '"$EXTENSION_DIR"' && echo "y" | npx --yes @vscode/vsce@latest package --allow-missing-repository --no-gitHubIssueLinking'
        return $?
    fi
    # Fallback: run the existing package script inside nix-shell (expects Node >= 20 there)
    nix-shell "$PROJECT_ROOT/shell.nix" --command "npm run package"
}

# Ensure required artifacts exist before packaging-only (no rebuilds)
check_artifacts_or_fail() {
    echo "🔎 Checking existing artifacts (no rebuild)..."
    # Check bundled LSP
    if [ ! -f "$BUNDLED_LSP" ]; then
        echo "❌ Missing bundled LSP at $BUNDLED_LSP"
        echo "   Run: $0 package    (to build and bundle first)"
        exit 1
    fi
    # Check that webview bundle exists
    if [ ! -d "$EXTENSION_DIR/media/goal-view" ]; then
        echo "❌ Missing webview bundle at $EXTENSION_DIR/media/goal-view"
        echo "   Run: $0 build ui   (to build UI) or $0 package (full rebuild)"
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
    # Use whichever path exists
    if [ -f "$LSP_EXECUTABLE" ]; then
        cp "$LSP_EXECUTABLE" "$BUNDLED_LSP"
    elif [ -f "$ALT_LSP_EXECUTABLE" ]; then
        cp "$ALT_LSP_EXECUTABLE" "$BUNDLED_LSP"
    else
        echo "❌ Could not find built LSP executable to bundle"
        exit 1
    fi
    chmod +x "$BUNDLED_LSP"
    
    echo "✅ LSP server bundled: $BUNDLED_LSP"
    ls -lh "$BUNDLED_LSP"
}

# Function to package VS Code extension
package_extension() {
    echo "📦 Packaging VS Code extension..."
    bundle_extension
    
    cd "$EXTENSION_DIR"
    echo "📦 Creating VSIX package..."
    # Remove old vsix to avoid picking the wrong artifact
    rm -f "$EXTENSION_DIR"/vsec-easycrypt-*.vsix || true
    # Use modern Node for vsce packaging when possible
    package_with_modern_node
    
    if ls "$EXTENSION_DIR"/vsec-easycrypt-*.vsix 1> /dev/null 2>&1; then
        echo "✅ Extension packaged successfully:"
        ls -lh "$EXTENSION_DIR"/vsec-easycrypt-*.vsix
    else
        echo "❌ Extension packaging failed"
        exit 1
    fi
}

# Function to build and package UI only (no LSP rebuild)
package_ui_only() {
    echo "🎨 Building UI only (no LSP rebuild)..."
    build_webview
    
    cd "$EXTENSION_DIR"
    echo "🔧 Compiling TypeScript with webpack..."
    nix-shell "$PROJECT_ROOT/shell.nix" --command "npm run compile"
    echo "📦 Creating VSIX package..."
    # Remove old vsix to avoid picking the wrong artifact
    rm -f "$EXTENSION_DIR"/vsec-easycrypt-*.vsix || true
    # Use modern Node for vsce packaging when possible
    package_with_modern_node
    
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
    cd "$EXTENSION_DIR"
    # Pick the newest VSIX to avoid installing a stale one
    VSIX_FILE=$(ls -t vsec-easycrypt-*.vsix 2>/dev/null | head -n1)
    if [ -z "$VSIX_FILE" ]; then
        echo "❌ No VSIX found. Run '$PROJECT_ROOT/build_lsp.sh package' first to create one."
        exit 1
    fi
    
    # Uninstall old extension first
    echo "🗑️ Uninstalling old extension..."
    if command -v code &> /dev/null; then
        code --uninstall-extension vsec.vsec-easycrypt || echo "⚠️ Extension not installed or already uninstalled"
    elif command -v codium &> /dev/null; then
        codium --uninstall-extension vsec.vsec-easycrypt || echo "⚠️ Extension not installed or already uninstalled"
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
case "${1:-}" in
    "clean")
        clean_build
        ;;
    "install")
        # Install the newest existing VSIX (no rebuild here)
        install_vsix
        ;;
    "install-lsp-only")
        build_lsp
        install_lsp
        ;;
    "bundle")
        build_lsp
        bundle_extension
        ;;
    "package")
        # Package into VSIX based on flag
        if [ "${2:-}" = "only" ]; then
            echo "📦 Packaging extension (no rebuild of server/UI/adapters)..."
            check_artifacts_or_fail
            cd "$EXTENSION_DIR"
            echo "📦 Creating VSIX package..."
            rm -f "$EXTENSION_DIR"/vsec-easycrypt-*.vsix || true
            # Skip prepublish hooks to avoid rebuilding
            export VSCE_SKIP_PREPUBLISH=1
            package_with_modern_node
            if ls "$EXTENSION_DIR"/vsec-easycrypt-*.vsix 1> /dev/null 2>&1; then
                echo "✅ Extension packaged successfully:"
                ls -lh "$EXTENSION_DIR"/vsec-easycrypt-*.vsix
            else
                echo "❌ Extension packaging failed"
                exit 1
            fi
        else
            echo "📦 Packaging extension (full rebuild)..."
            build_lsp
            package_extension
        fi
        ;;
    "install-vsix")
        install_vsix
        ;;
    "ui-only")
        package_ui_only
        ;;
    "install-ui")
        package_ui_only
        install_vsix
        ;;
    "build")
        if [ "${2:-}" = "ui" ]; then
            echo "🎨 Building UI only..."
            build_webview
        elif [ "${2:-}" = "server" ]; then
            echo "🔧 Building server only..."
            build_lsp
        else
            echo "🔨 Building server and UI..."
            build_lsp
            build_webview
        fi
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Primary Commands:"
        echo "  build [server|ui]   Build server and/or UI"
        echo "                      - build          Build both server and UI"
        echo "                      - build server   Build LSP server only"
        echo "                      - build ui       Build UI only"
        echo ""
        echo "  package [only]      Package extension into VSIX"
        echo "                      - package        Full rebuild + package"
        echo "                      - package only   Package without rebuilding"
        echo ""
        echo "  install             Install newest VSIX into VS Code (no rebuild)"
        echo "  clean               Clean build artifacts"
        echo ""
        echo "Common Workflows:"
        echo "  Fresh install:      ./build_lsp.sh package && ./build_lsp.sh install"
        echo "  Full rebuild:       ./build_lsp.sh package"
        echo "  Incremental:        ./build_lsp.sh build server | ui"
        echo "                      ./build_lsp.sh package only"
        echo "  Quick reinstall:    ./build_lsp.sh install"
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac

echo ""
echo "🎉 Build script completed successfully!"