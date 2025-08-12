import * as vscode from 'vscode';

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

    private static _channel: any = vscode.window.createOutputChannel('VsEc EasyCrypt');
    private static _easycryptLog: any = vscode.window.createOutputChannel('EasyCrypt Log');
    
    // Decoration types for semantic highlighting
    private static decorationTypes = new Map<string, vscode.TextEditorDecorationType>();

    constructor(
        serverOptions: ServerOptions,
        clientOptions: LanguageClientOptions,
    ) {
        super(
            'vsec-language-server',
            'VsEc EasyCrypt Language Server',
            serverOptions,
            clientOptions
        );
        Client._channel.appendLine("VsEc EasyCrypt v0.1.18 - RED KEYWORDS + VARIED COLORS!");
    }

    public static writeToVsEcChannel(message: string) {
        Client._channel.appendLine(message);
    }

    public static writeEasyCryptMessageLog(message: string) {
        Client._easycryptLog.appendLine(message);
    }

    public static showLog() {
        Client._channel.show(true);
    }

}