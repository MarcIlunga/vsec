#!/bin/bash

# VsEc EasyCrypt Language Server Runner
# This script runs the VsEc language server in the proper Nix environment

VSEC_ROOT="/home/marcilunga/dev/vsec"

echo "🔧 Starting VsEc EasyCrypt Language Server..."
echo "📁 Project root: $VSEC_ROOT"
echo "🔥 Features: Code Completion, Go to Definition, Hover, Document Symbols, Find References"
echo ""

cd "$VSEC_ROOT" && nix --extra-experimental-features 'nix-command flakes' develop -c sh -c "cd src && _build/default/driver/ecLsp.exe"