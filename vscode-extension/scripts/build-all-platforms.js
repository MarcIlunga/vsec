#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const VSEC_ROOT = path.join(__dirname, '..', '..');
const BIN_DIR = path.join(__dirname, '..', 'bin');
const SRC_DIR = path.join(VSEC_ROOT, 'src');

// Platform configurations for cross-compilation
const PLATFORMS = [
    { name: 'linux-x64', target: 'x86_64-unknown-linux-gnu' },
    { name: 'linux-arm64', target: 'aarch64-unknown-linux-gnu' },
    { name: 'darwin-x64', target: 'x86_64-apple-darwin' },
    { name: 'darwin-arm64', target: 'aarch64-apple-darwin' },
    { name: 'win32', target: 'x86_64-pc-windows-msvc', extension: '.exe' }
];

// Ensure bin directory exists
if (!fs.existsSync(BIN_DIR)) {
    fs.mkdirSync(BIN_DIR, { recursive: true });
}

function buildForAllPlatforms() {
    console.log('🔧 Building VsEc language server for all platforms...');
    
    // For now, we can only build for the current platform with OCaml/dune
    // In a full production setup, you'd need cross-compilation setup
    buildCurrentPlatform();
    
    console.log('📦 Note: Cross-platform binaries require specialized build setup.');
    console.log('💡 For production releases, build on each target platform or use CI/CD.');
}

function buildCurrentPlatform() {
    try {
        // Build the OCaml project
        const buildCmd = `nix --extra-experimental-features 'nix-command flakes' develop -c sh -c "cd ${SRC_DIR} && dune build"`;
        console.log('Building for current platform...');
        execSync(buildCmd, { stdio: 'inherit', cwd: VSEC_ROOT });
        
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
        
        // Make executable on Unix systems
        if (platform !== 'win32') {
            fs.chmodSync(targetPath, 0o755);
        }
        
        console.log(`✅ Binary built for ${platform}-${arch}: ${targetPath}`);
        
        // Create placeholder binaries for other platforms (for development)
        createPlaceholderBinaries(platform, arch);
        
    } catch (error) {
        console.error('❌ Failed to build binary:', error.message);
        process.exit(1);
    }
}

function createPlaceholderBinaries(currentPlatform, currentArch) {
    console.log('📝 Creating placeholder binaries for other platforms...');
    
    const platformBinaries = [
        'vsec-lsp-linux-x64',
        'vsec-lsp-linux-arm64', 
        'vsec-lsp-darwin-x64',
        'vsec-lsp-darwin-arm64',
        'vsec-lsp.exe'
    ];
    
    let currentBinary;
    if (currentPlatform === 'linux') {
        currentBinary = currentArch === 'arm64' ? 'vsec-lsp-linux-arm64' : 'vsec-lsp-linux-x64';
    } else if (currentPlatform === 'darwin') {
        currentBinary = currentArch === 'arm64' ? 'vsec-lsp-darwin-arm64' : 'vsec-lsp-darwin-x64';
    } else if (currentPlatform === 'win32') {
        currentBinary = 'vsec-lsp.exe';
    }
    
    const sourcePath = path.join(BIN_DIR, currentBinary);
    
    for (const binaryName of platformBinaries) {
        if (binaryName !== currentBinary) {
            const targetPath = path.join(BIN_DIR, binaryName);
            if (!fs.existsSync(targetPath)) {
                // Copy current binary as placeholder
                fs.copyFileSync(sourcePath, targetPath);
                console.log(`📋 Created placeholder: ${binaryName}`);
            }
        }
    }
}

if (require.main === module) {
    buildForAllPlatforms();
}

module.exports = { buildForAllPlatforms };