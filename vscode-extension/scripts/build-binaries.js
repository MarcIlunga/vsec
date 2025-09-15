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
        // Build the OCaml project (prefer Nix flakes if available; otherwise try local dune; otherwise skip)
        const hasFlake = fs.existsSync(path.join(VSEC_ROOT, 'flake.nix'));
        let built = false;
        if (hasFlake) {
            const buildCmd = `nix --extra-experimental-features 'nix-command flakes' develop -c sh -c "cd ${SRC_DIR} && dune build"`;
            console.log('Running:', buildCmd);
            execSync(buildCmd, { stdio: 'inherit', cwd: VSEC_ROOT });
            built = true;
        } else {
            try {
                console.log('Nix flake not found. Trying local dune build...');
                execSync(`sh -c "cd ${SRC_DIR} && dune build"`, { stdio: 'inherit', cwd: VSEC_ROOT });
                built = true;
            } catch (e) {
                console.warn('⚠️  Dune build failed or dune not installed. Skipping binary build.');
            }
        }
        
        // Locate the built binary (support both historical and current paths)
        const candidatePaths = [
            path.join(SRC_DIR, '_build', 'default', 'eclsp', 'ecLsp.exe'),
            path.join(SRC_DIR, '_build', 'default', 'driver', 'ecLsp.exe')
        ];
        const sourceBinary = candidatePaths.find(p => fs.existsSync(p)) || candidatePaths[0];
        
        if (!fs.existsSync(sourceBinary)) {
            if (!built) {
                console.warn('⚠️  No language server binary found and build skipped. Continuing without updating binaries.');
                return;
            }
            throw new Error(`Built binary not found at: ${sourceBinary}`);
        }
        
        // Helper: robust copy with permission fixes
        function safeCopy(src, dest) {
            try {
                const dir = path.dirname(dest);
                if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
                if (fs.existsSync(dest)) {
                    try { fs.chmodSync(dest, 0o666); } catch (_) {}
                    try { fs.unlinkSync(dest); } catch (e) {
                        console.warn('⚠️  Failed to remove existing file, trying to overwrite anyway:', dest, e.message);
                    }
                }
                // Ensure source is readable
                try { fs.chmodSync(src, 0o755); } catch (_) {}
                fs.copyFileSync(src, dest);
                try { fs.chmodSync(dest, 0o755); } catch (_) {}
            } catch (e) {
                console.error('❌ Failed to copy', src, '->', dest, e.message);
                throw e;
            }
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
        safeCopy(sourceBinary, targetPath);
        
        // Copy to extension root for VSCode best practice
        const rootPath = path.join(__dirname, '..', 'vsec-lsp');
        safeCopy(sourceBinary, rootPath);
        
        // Make executable on Unix systems
        // (chmod handled in safeCopy)
        
        console.log(`✅ Binary built and copied to: ${targetPath}`);
        console.log(`✅ Binary also copied to extension root: ${rootPath}`);
        console.log(`📦 Platform: ${platform}-${arch}`);
        
    } catch (error) {
        console.error('❌ Failed to build binary:', error.message);
        // Allow packaging to continue without failing the entire process
        return;
    }
}

if (require.main === module) {
    buildBinary();
}

module.exports = { buildBinary };