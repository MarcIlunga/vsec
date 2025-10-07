import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';

import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from 'vscode-languageclient/node';

// Custom semantic highlighting types
interface SemanticToken {
  line: number;
  startChar: number;
  length: number;
  tokenType: string;
  classification: string;
}

interface SemanticHighlightingParams {
  uri: string;
  tokens: SemanticToken[];
}

export default class Client extends LanguageClient {

    // Decoration types for semantic highlighting
    private static decorationTypes = new Map<string, vscode.TextEditorDecorationType>();

    constructor(
        serverOptions: ServerOptions,
        clientOptions: LanguageClientOptions,
        extensionContext: vscode.ExtensionContext,
    ) {
        super(
            'vsec-language-server',
            'VsEc EasyCrypt',
            serverOptions,
            clientOptions
        );
        
        // Read version from package.json and log to the LSP output channel
        const packageJsonPath = path.join(extensionContext.extensionPath, 'package.json');
        let version = '0.1.19'; // fallback
        try {
            const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
            version = packageJson.version || version;
        } catch (e) {
            // Use fallback version
        }
        
        this.info(`VsEc EasyCrypt v${version}`);
    }

    public static writeToVsEcChannel(message: string) {
        // Use the built-in LSP output channel
        console.log(message);
    }

    public static writeEasyCryptMessageLog(message: string) {
        // Use the built-in LSP output channel
        console.log(message);
    }

    public static showLog() {
        // The LSP channel is already available in the output panel
    }

}