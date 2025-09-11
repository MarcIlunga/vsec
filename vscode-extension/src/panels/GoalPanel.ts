import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import { getNonce } from '../utilities/getNonce';
import { getUri } from '../utilities/getUri';

export class GoalPanel {
  public static currentPanel: GoalPanel | undefined;
  private readonly _panel: vscode.WebviewPanel;
  private _disposables: vscode.Disposable[] = [];

  private constructor(panel: vscode.WebviewPanel, extensionUri: vscode.Uri) {
    this._panel = panel;
    
    // Set the webview's initial html content
    this._panel.webview.html = this._getWebviewContent(this._panel.webview, extensionUri);
    
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
    // Send proof state update to the webview
    this._panel.webview.postMessage({
      type: 'proofView',
      textDocument: textDocument,
      proofState: proofState
    });
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
    const nonce = getNonce();

    // Read the HTML template file
    const templatePath = path.join(extensionUri.fsPath, 'src', 'templates', 'goalPanel.html');
    let htmlTemplate: string;
    
    try {
      htmlTemplate = fs.readFileSync(templatePath, 'utf8');
    } catch (error) {
      console.error('Failed to read HTML template:', error);
      // Fallback to inline HTML if template file is not found
      htmlTemplate = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src {{cspSource}} 'unsafe-inline'; script-src 'nonce-{{nonce}}';">
    <link rel="stylesheet" type="text/css" href="{{stylesUri}}">
    <title>EasyCrypt Goal View</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" nonce="{{nonce}}" src="{{scriptUri}}"></script>
  </body>
</html>`;
    }

    // Replace placeholders with actual values
    return htmlTemplate
      .replace(/{{cspSource}}/g, webview.cspSource)
      .replace(/{{nonce}}/g, nonce)
      .replace(/{{stylesUri}}/g, stylesUri.toString())
      .replace(/{{scriptUri}}/g, scriptUri.toString());
  }
}