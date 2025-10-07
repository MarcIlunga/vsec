import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import { getNonce } from '../utilities/getNonce';
import { getUri } from '../utilities/getUri';

export class GoalPanel {
  public static currentPanel: GoalPanel | undefined;
  private readonly _panel: vscode.WebviewPanel;
  private _disposables: vscode.Disposable[] = [];
  private _isReady: boolean = false;
  private _pendingMessages: any[] = [];

  private constructor(panel: vscode.WebviewPanel, extensionUri: vscode.Uri) {
    this._panel = panel;
    
    // Set the webview's initial html content
    this._panel.webview.html = this._getWebviewContent(this._panel.webview, extensionUri);
    
    // Bridge: receive messages from webview and dispatch VS Code commands
    this._panel.webview.onDidReceiveMessage(async (msg: any) => {
      if (!msg || typeof msg !== 'object') { return; }
      
      // CRITICAL FIX: Handle webview ready signal
      if (msg.type === 'webview-ready') {
        this._isReady = true;
        // Flush pending messages
        while (this._pendingMessages.length > 0) {
          const pending = this._pendingMessages.shift();
          if (pending) {
            this._panel.webview.postMessage(pending);
          }
        }
        return;
      }
      
      if (msg.type === 'command' && typeof msg.command === 'string') {
        const args = Array.isArray(msg.args) ? msg.args : (msg.args !== undefined ? [msg.args] : []);
        vscode.commands.executeCommand(msg.command, ...args).then(undefined, err => {
          console.error('[GoalPanel] Command failed:', msg.command, err);
        });
      } else if (msg.type === 'lspRequest') {
        // Handle LSP requests from webview
        try {
          const result = await this.handleLspRequest(msg.method, msg.params);
          this._panel.webview.postMessage({
            type: 'lspResponse',
            id: msg.id,
            result
          });
        } catch (error) {
          this._panel.webview.postMessage({
            type: 'lspResponse',
            id: msg.id,
            error: {
              code: -32603,
              message: error instanceof Error ? error.message : 'Internal error'
            }
          });
        }
      }
    }, null, this._disposables);
    
    // Listen for when the panel is disposed
    // This happens when the user closes the panel or when the panel is closed programmatically
    this._panel.onDidDispose(() => this.dispose(), null, this._disposables);
  }

  public static render(extensionUri: vscode.Uri) {
    if (GoalPanel.currentPanel) {
      // If we already have a panel, show it
      GoalPanel.currentPanel._panel.reveal(vscode.ViewColumn.Beside);
      return GoalPanel.currentPanel;
    } else {
      // If we don't have a panel, create a new one
      const panel = vscode.window.createWebviewPanel(
        'easycryptGoalView',
        'EasyCrypt Goals',
        vscode.ViewColumn.Beside,
        {
          enableScripts: true,
          retainContextWhenHidden: true,
          localResourceRoots: [
            vscode.Uri.joinPath(extensionUri, 'media')
          ]
        }
      );

      GoalPanel.currentPanel = new GoalPanel(panel, extensionUri);
      return GoalPanel.currentPanel;
    }
  }

  public updateProofState(proofState: any, textDocument: any) {
    // CRITICAL FIX: Queue messages until webview is ready
    const message = {
      type: 'proofView',
      textDocument: textDocument,
      proofState: proofState
    };
    if (this._isReady) {
      this._panel.webview.postMessage(message);
    } else {
      this._pendingMessages.push(message);
    }
  }

  public updateExecutionOverview(overview: any, textDocument: any) {
    const message = {
      type: 'executionOverview',
      textDocument,
      overview
    };
    if (this._isReady) {
      this._panel.webview.postMessage(message);
    } else {
      this._pendingMessages.push(message);
    }
  }

  public updateMessages(messages: any[], textDocument: any) {
    const message = {
      type: 'messages',
      textDocument,
      messages
    };
    if (this._isReady) {
      this._panel.webview.postMessage(message);
    } else {
      this._pendingMessages.push(message);
    }
  }

  private async handleLspRequest(method: string, params: any): Promise<any> {
    // Get the active text editor to access the LSP client
    const activeEditor = vscode.window.activeTextEditor;
    if (!activeEditor) {
      throw new Error('No active text editor');
    }

    // Get the LSP client from the extension context
    const lspClient = (vscode.extensions.getExtension('vsec.vsec-easycrypt') as any)?.exports?.client;
    if (!lspClient) {
      throw new Error('LSP client not available');
    }

    // Forward the LSP request to the language server
    switch (method) {
      case 'textDocument/semanticTokens/full':
        return lspClient.sendRequest('textDocument/semanticTokens/full', params);
      case 'textDocument/semanticTokens/range':
        return lspClient.sendRequest('textDocument/semanticTokens/range', params);
      case 'textDocument/hover':
        return lspClient.sendRequest('textDocument/hover', params);
      case 'textDocument/completion':
        return lspClient.sendRequest('textDocument/completion', params);
      default:
        throw new Error(`Unsupported LSP method: ${method}`);
    }
  }

  public dispose() {
    GoalPanel.currentPanel = undefined;

    // Clean up our resources
    this._panel.dispose();

    while (this._disposables.length) {
      const x = this._disposables.pop();
      if (x) {
        x.dispose();
      }
    }
  }

  private _getWebviewContent(webview: vscode.Webview, extensionUri: vscode.Uri) {
    const stylesUri = getUri(webview, extensionUri, ['media', 'goal-view', 'goal-view.css']);
    const scriptUri = getUri(webview, extensionUri, ['media', 'goal-view', 'goal-view.js']);
    const codiconsUri = getUri(webview, extensionUri, ['media', 'goal-view', 'codicon.css']);
    const nonce = getNonce();

    // Use inline HTML template (avoid reading from src/templates in packaged extension)
    const htmlTemplate = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src {{cspSource}} 'unsafe-inline'; script-src 'nonce-{{nonce}}';">
    <link rel="stylesheet" type="text/css" href="{{stylesUri}}">
    <link id="vscode-codicon-stylesheet" rel="stylesheet" type="text/css" href="{{codiconsUri}}">
    <title>EasyCrypt Goal View</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" nonce="{{nonce}}" src="{{scriptUri}}"></script>
  </body>
</html>`;

    // Replace placeholders with actual values
    // Inject acquireVsCodeApi shim for React app messaging
    const shim = `
      <script nonce="{{nonce}}">(function(){
        try { (window as any).vscode = acquireVsCodeApi(); } catch(_) {}
      })();</script>`;

    // Cache-bust webview resources to avoid stale bundles
    const versionParam = `?v=${nonce}`;
    let html = htmlTemplate
      .replace(/{{cspSource}}/g, webview.cspSource)
      .replace(/{{nonce}}/g, nonce)
      .replace(/{{stylesUri}}/g, stylesUri.toString() + versionParam)
      .replace(/{{scriptUri}}/g, scriptUri.toString() + versionParam)
      .replace(/{{codiconsUri}}/g, codiconsUri.toString() + versionParam);

    // Add shim before our main script tag
    html = html.replace('</head>', shim + '\n</head>');
    return html;
  }
}