import * as vscode from 'vscode';
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
            vscode.Uri.joinPath(extensionUri, "out"), 
            vscode.Uri.joinPath(extensionUri, "goal-view-ui", "build")
          ]
        }
      );

      GoalPanel.currentPanel = new GoalPanel(panel, extensionUri);
      return GoalPanel.currentPanel;
    }
  }

  public updateProofState(proofState: any, textDocument: any) {
    // Debug: Log the proof state being sent
    console.log('GoalPanel: Sending proof state to webview:', JSON.stringify(proofState, null, 2));
    
    // Send proof state update to the webview (VSCoq protocol style)
    this._panel.webview.postMessage({
      "command": "renderProofView", 
      "proofView": proofState
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
    // The CSS file from the React build output (VSCoq style)
    const stylesUri = getUri(webview, extensionUri, ["goal-view-ui", "build", "assets", "index.css"]);
    // The JS file from the React build output (VSCoq style)
    const scriptUri = getUri(webview, extensionUri, ["goal-view-ui", "build", "assets", "index.js"]);
    const nonce = getNonce();

    return `
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource}; script-src 'nonce-${nonce}';">
          <link rel="stylesheet" type="text/css" nonce="${nonce}" href="${stylesUri}">
          <title>EasyCrypt Goal View</title>
        </head>
        <body>
          <div id="root"></div>
          <script type="module" nonce="${nonce}" src="${scriptUri}"></script>
        </body>
      </html>
    `;
  }
}