import { WebviewViewProvider, WebviewView, WebviewViewResolveContext, CancellationToken, Uri } from 'vscode';
import { getNonce } from '../utilities/getNonce';

export class ToolsViewProvider implements WebviewViewProvider {
  public static readonly viewId = 'vsec.tools';
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
  }

  private _getHtmlForWebview(webviewView: WebviewView) {
    const webview = webviewView.webview;
    const nonce = getNonce();
    const styles = `
      body { font-family: var(--vscode-font-family); padding: 8px; }
      .title { font-weight: 600; margin-bottom: 8px; }
      .desc { color: var(--vscode-descriptionForeground); }
    `;
    return `<!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>${styles}</style>
      <title>VsEc Tools</title>
    </head>
    <body>
      <div class="title">Tools</div>
      <div class="desc">Additional EasyCrypt features will appear here.</div>
    </body>
    </html>`;
  }
}


