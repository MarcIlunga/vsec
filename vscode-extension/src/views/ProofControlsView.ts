import { WebviewViewProvider, WebviewView, WebviewViewResolveContext, CancellationToken, Uri, window, commands } from 'vscode';
import { getNonce } from '../utilities/getNonce';

export class ProofControlsViewProvider implements WebviewViewProvider {
  public static readonly viewId = 'vsec.proofControls';
  private _view: WebviewView | undefined;
  private readonly _extensionUri: Uri;

  constructor(extensionUri: Uri) {
    this._extensionUri = extensionUri;
  }

  resolveWebviewView(webviewView: WebviewView, _context: WebviewViewResolveContext, _token: CancellationToken) {
    this._view = webviewView;
    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this._extensionUri]
    };
    webviewView.webview.html = this._getHtmlForWebview(webviewView);

    webviewView.webview.onDidReceiveMessage(async (msg: any) => {
      switch (msg.command) {
        case 'showGoals':
          await commands.executeCommand('vsec.runShowGoalPanel');
          break;
        case 'stepForward':
          await commands.executeCommand('vsec.runStepForward');
          break;
        case 'interpretToPoint':
          await commands.executeCommand('vsec.runInterpretToPoint');
          break;
        case 'interpretToEnd':
          await commands.executeCommand('vsec.runInterpretToEnd');
          break;
        case 'checkProof':
          await commands.executeCommand('vsec.runCheckProof');
          break;
      }
    });
  }

  private _getHtmlForWebview(webviewView: WebviewView) {
    const webview = webviewView.webview;
    const nonce = getNonce();
    const styles = `
      body { font-family: var(--vscode-font-family); padding: 8px; }
      .row { display: flex; flex-direction: column; gap: 6px; }
      .btn { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: none; padding: 6px 8px; border-radius: 4px; cursor: pointer; }
      .btn:hover { background: var(--vscode-button-hoverBackground); }
      .title { font-weight: 600; margin-bottom: 8px; }
    `;
    return `<!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ${webview.cspSource} https:; style-src ${webview.cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>${styles}</style>
      <title>VsEc Proof Controls</title>
    </head>
    <body>
      <div class="title">Proof Controls</div>
      <div class="row">
        <button class="btn" id="showGoals">Goals</button>
        <button class="btn" id="stepForward">Step Forward</button>
        <button class="btn" id="interpretToPoint">Interpret to Cursor</button>
        <button class="btn" id="interpretToEnd">Interpret to End</button>
        <button class="btn" id="checkProof">Check Proof</button>
      </div>
      <script nonce="${nonce}">
        const vscode = acquireVsCodeApi();
        const bind = (id, command) => {
          const el = document.getElementById(id);
          if (el) el.addEventListener('click', () => vscode.postMessage({ command }));
        };
        bind('showGoals', 'showGoals');
        bind('stepForward', 'stepForward');
        bind('interpretToPoint', 'interpretToPoint');
        bind('interpretToEnd', 'interpretToEnd');
        bind('checkProof', 'checkProof');
      </script>
    </body>
    </html>`;
  }
}


