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
    private static lastExecutedDecoration: vscode.TextEditorDecorationType | undefined;

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

        // Initialize a subtle decoration for last executed range
        if (!Client.lastExecutedDecoration) {
            Client.lastExecutedDecoration = vscode.window.createTextEditorDecorationType({
                isWholeLine: true,
                overviewRulerColor: new vscode.ThemeColor('editorOverviewRuler.findMatchForeground'),
                overviewRulerLane: vscode.OverviewRulerLane.Right,
                rangeBehavior: vscode.DecorationRangeBehavior.ClosedClosed,
                light: {
                    before: {
                        contentText: '▶',
                        color: new vscode.ThemeColor('editorCodeLens.foreground'),
                        margin: '0 6px 0 0'
                    }
                },
                dark: {
                    before: {
                        contentText: '▶',
                        color: new vscode.ThemeColor('editorCodeLens.foreground'),
                        margin: '0 6px 0 0'
                    }
                }
            });
        }
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