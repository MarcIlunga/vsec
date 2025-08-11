import { workspace, ExtensionContext } from 'vscode';
import { Disposable } from "vscode-languageclient";
import { exec } from 'child_process';
import { ServerOptions } from 'vscode-languageclient/node';
import Client from './client';
import which = require('which');
import * as path from 'path';
import * as fs from 'fs';

export enum ToolChainErrorCode {
    notFound = 1, 
    launchError = 2
}

export interface ToolchainError {
    status: ToolChainErrorCode; 
    message: string; 
}

export default class VsEcToolchainManager implements Disposable {

    private _vsecPath: string = "";
    private _easycryptVersion: string = "";
    private _versionFullOutput: string = "";
    private _easycryptPath: string = "";
    private _context: ExtensionContext;

    constructor(context: ExtensionContext) {
        this._context = context;
    }

    public dispose(): void {
        
    }

    public initialize() : Promise<void> {
        Client.writeToVsEcChannel("[Toolchain] Searching for vsec-lsp");
        return new Promise((resolve, reject: ((reason: ToolchainError) => void)) => {
            this.vsecPath().then(vsecPath => {
                if(vsecPath) {
                    Client.writeToVsEcChannel("[Toolchain] Found path: " + vsecPath);
                    this._vsecPath = vsecPath;
                    // For now, skip version checking and just resolve
                    // We can add EasyCrypt version checking later if needed
                    resolve();
                } else {
                    Client.writeToVsEcChannel("[Toolchain] Did not find vsec-lsp path");
                    reject({
                        status: ToolChainErrorCode.notFound, 
                        message: "VsEc couldn't launch because no language server was found. Make sure vsec-lsp is in your PATH or configure vsec.path setting."
                    });
                }
            });
        });
    }

    public getServerConfiguration() : ServerOptions {
        const config = workspace.getConfiguration('vsec');
        const serverOptions : ServerOptions = {
            command: this._vsecPath, 
            args: config.get('args', []),
            options: {
                cwd: workspace.workspaceFolders?.[0]?.uri.fsPath,
                shell: true,
            },
        };
        return serverOptions;
    }

    public getVsEcPath() : string {
        return this._vsecPath;
    }

    public getEasyCryptPath() : string {
        return this._easycryptPath;
    }

    public getEasyCryptVersion() : string {
        return this._easycryptVersion;
    }

    public getVersionFullOutput() : string {
        return this._versionFullOutput;
    }

    private async vsecPath () : Promise<string> {
        const vsecPath = workspace.getConfiguration('vsec').get('path') as string;
        if(vsecPath) {
            Client.writeToVsEcChannel("[Toolchain] Path set in user settings");
            return vsecPath; 
        }
        
        // First try bundled binary (following VSCoq pattern)
        const bundledPath = path.join(this._context.extensionPath, 'vsec-lsp');
        if (fs.existsSync(bundledPath)) {
            Client.writeToVsEcChannel("[Toolchain] Using bundled vsec-lsp");
            return bundledPath;
        }
        
        // Fallback to PATH search
        Client.writeToVsEcChannel("[Toolchain] Bundled binary not found, searching PATH");
        return await this.searchForVsecInPath();
    }

    private async searchForVsecInPath () : Promise<string> {        
        return await which("vsec-lsp", { nothrow: true }) ?? "";
    }
}