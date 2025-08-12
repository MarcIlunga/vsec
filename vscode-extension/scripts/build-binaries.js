#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const VSEC_ROOT = path.join(__dirname, '..', '..');
const BIN_DIR = path.join(__dirname, '..', 'bin');
const SRC_DIR = path.join(VSEC_ROOT, 'src');

// Ensure bin directory exists
if (!fs.existsSync(BIN_DIR)) {
    fs.mkdirSync(BIN_DIR, { recursive: true });
}

function buildBinary() {
    console.log('🔧 Building VsEc language server binary...');
    
    try {
        // Build the OCaml project
        const buildCmd = `nix --extra-experimental-features 'nix-command flakes' develop -c sh -c "cd ${SRC_DIR} && dune build"`;
        console.log('Running:', buildCmd);
        execSync(buildCmd, { stdio: 'inherit', cwd: VSEC_ROOT });
        
        // Copy binary to platform-specific names
        const sourceBinary = path.join(SRC_DIR, '_build', 'default', 'driver', 'ecLsp.exe');
        
        if (!fs.existsSync(sourceBinary)) {
            throw new Error(`Built binary not found at: ${sourceBinary}`);
        }
        
        // Detect current platform and copy binary
        const platform = process.platform;
        const arch = process.arch;
        
        let targetName;
        switch (platform) {
            case 'linux':
                targetName = arch === 'arm64' ? 'vsec-lsp-linux-arm64' : 'vsec-lsp-linux-x64';
                break;
            case 'darwin':
                targetName = arch === 'arm64' ? 'vsec-lsp-darwin-arm64' : 'vsec-lsp-darwin-x64';
                break;
            case 'win32':
                targetName = 'vsec-lsp.exe';
                break;
            default:
                throw new Error(`Unsupported platform: ${platform}`);
        }
        
        const targetPath = path.join(BIN_DIR, targetName);
        fs.copyFileSync(sourceBinary, targetPath);
        
        // Copy to extension root for VSCode best practice
        const rootPath = path.join(__dirname, '..', 'vsec-lsp');
        fs.copyFileSync(sourceBinary, rootPath);
        
        // Make executable on Unix systems
        if (platform !== 'win32') {
            fs.chmodSync(targetPath, 0o755);
            fs.chmodSync(rootPath, 0o755);
        }
        
        console.log(`✅ Binary built and copied to: ${targetPath}`);
        console.log(`✅ Binary also copied to extension root: ${rootPath}`);
        console.log(`📦 Platform: ${platform}-${arch}`);
        
    } catch (error) {
        console.error('❌ Failed to build binary:', error.message);
        process.exit(1);
    }
}

if (require.main === module) {
    buildBinary();
}

module.exports = { buildBinary };