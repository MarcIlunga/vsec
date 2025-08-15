import { Disposable, Webview, WebviewPanel, window, workspace, Uri, ViewColumn, TextEditor, Position, commands } from "vscode";
import { getUri } from "../utilities/getUri";
import { getNonce } from "../utilities/getNonce";
import Client from "../client";

/**
 * This class manages the state and behavior of Goal webview panels.
 *
 * It contains all the data and methods for:
 *
 * - Creating and rendering Goal webview panels
 * - Properly cleaning up and disposing of webview resources when the panel is closed
 * - Setting the HTML (and by proxy CSS/JavaScript) content of the webview panel
 * - Setting message listeners so data can be passed between the webview and extension
 */
export class GoalPanel {

  public static currentPanel: GoalPanel | undefined;
  public static currentPv: any | undefined;
  public static lastPostedProofView: any | undefined;
  private static lastPostedAtMs: number = 0;
  private readonly _panel: WebviewPanel;
  private _disposables: Disposable[] = [];


  /**
   * The GoalPanel class private constructor (called only from the render method).
   *
   * @param panel A reference to the webview panel
   * @param extensionUri The URI of the directory containing the extension
   */
  private constructor(panel: WebviewPanel, extensionUri: Uri) {
    this._panel = panel;

    // Set an event listener to listen for when the panel is disposed (i.e. when the user closes
    // the panel or when the panel is closed programmatically)
    this._panel.onDidDispose(() => this.dispose(), null, this._disposables);

    // Set the HTML content for the webview panel
    this._panel.webview.html = this._getWebviewContent(this._panel.webview, extensionUri);

    // Set an event listener to listen for messages passed from the webview context
    this._setWebviewMessageListener(this._panel.webview);

    //init the app settings
    this._updateDisplaySettings(this._panel.webview);
    this._updateGoalDepth(this._panel.webview);
  }

  /**
   * Renders the current webview panel if it exists otherwise a new webview panel
   * will be created and displayed.
   *
   * @param extensionUri The URI of the directory containing the extension.
   */
  public static render(editor: TextEditor, extensionUri: Uri, callback?: (goalPanel: GoalPanel) => void): GoalPanel {
    if (GoalPanel.currentPanel) {
      // If we already have a panel, show it.
      GoalPanel.currentPanel._panel.reveal(ViewColumn.Two);
      return GoalPanel.currentPanel;
    } else {
      // If we don't have a panel, create a new one.
      const panel = window.createWebviewPanel(
        "goalPanel",
        "EasyCrypt Goals",
        ViewColumn.Two,
        {
          enableScripts: true,
          retainContextWhenHidden: true,
          localResourceRoots: [
            Uri.joinPath(extensionUri, "out"), 
            Uri.joinPath(extensionUri, "goal-view-ui", "build")
          ]
        }
      );

      GoalPanel.currentPanel = new GoalPanel(panel, extensionUri);
      if (callback) {
        callback(GoalPanel.currentPanel);
      }
      return GoalPanel.currentPanel;
    }
  }

  public static updateSettingsForCurrentPanel() {
    if (GoalPanel.currentPanel) {
      GoalPanel.currentPanel._updateDisplaySettings(GoalPanel.currentPanel._panel.webview);
      GoalPanel.currentPanel._updateGoalDepth(GoalPanel.currentPanel._panel.webview);
    }
  }

  public static proofViewNotification(extensionUri: Uri, editor: TextEditor, pv: any, autoDisplay: boolean) {
    
    Client.writeToVsEcChannel("[GoalPanel] Received proofview notification");

    if(!GoalPanel.currentPanel) {
        //If autoDisplay is set then render the proofview immediately
        if(autoDisplay) {
            GoalPanel.render(editor, extensionUri, (goalPanel) => {
                Client.writeToVsEcChannel("[GoalPanel] Created new goal panel");
                goalPanel._handleProofViewResponseOrNotification(pv);
            });
        }
        //Otherwise record the current proofview notification to render on user prompt
        else {
            GoalPanel.currentPv = pv;
        }
    }
    else {
        Client.writeToVsEcChannel("[GoalPanel] Rendered in current panel");
        GoalPanel.currentPanel._handleProofViewResponseOrNotification(pv);
    }
  }

  public static displayProofView(extensionUri: Uri, editor: TextEditor) {
    if (GoalPanel.currentPv) {
        GoalPanel.proofViewNotification(extensionUri, editor, GoalPanel.currentPv, true);
    } else {
        // Show the panel with an empty-state banner
        const panel = GoalPanel.render(editor, extensionUri);
        const msg = { command: 'renderProofView', proofView: { proof: null, messages: [{ level: 'info', text: 'No proof state available. Use Step or Interpret to start.' }] } } as any;
        panel._panel.webview.postMessage(msg);
        GoalPanel.lastPostedProofView = msg;
        // Also send current display settings so UI initializes consistently
        panel._updateDisplaySettings(panel._panel.webview);
        panel._updateGoalDepth(panel._panel.webview);
    }
  }

  public static resetGoalPanel() {
    if (GoalPanel.currentPanel) {
      GoalPanel.currentPanel._reset();
    }
  }

  private _reset() {
    this._panel.webview.postMessage({ "command": "reset"});
  };

  private _handleProofViewResponseOrNotification(pv: any) {
    console.log('🔍 DEBUG: _handleProofViewResponseOrNotification called with:', JSON.stringify(pv, null, 2));
    
    // Extract the actual proof state from our notification structure
    const proofState = pv.proofState;  // Extract proofState from the notification
    let messages = Array.isArray(pv?.messages) ? pv.messages : [];

    // Extract progress if present
    let progress: number | undefined = undefined;
    if (proofState && typeof proofState === 'object') {
      const pp = (proofState as any).proof_progress;
      if (typeof pp === 'number' && !Number.isNaN(pp)) progress = pp;
    }

    // If goals exist, prefer not to show messages (server strives to do this already)
    try {
      const goalsLen = Array.isArray((proofState as any)?.goals) ? (proofState as any).goals.length : 0;
      if (goalsLen > 0) messages = [];
    } catch {}

    // Multi-goal rendering: add titles like "Goal #n" for each goal entry
    try {
      if (proofState && Array.isArray((proofState as any).goals)) {
        (proofState as any).goals = (proofState as any).goals.map((g: any, idx: number) => ({ ...g, title: `Goal #${idx + 1}` }));
      }
    } catch {}

    // Hide non-current goal groups (shelved/unfocused/given-up) in the UI
    try {
      if (proofState && typeof proofState === 'object') {
        (proofState as any).shelvedGoals = [];
        (proofState as any).unfocusedGoals = [];
        (proofState as any).givenUpGoals = [];
      }
    } catch {}

    // Simple client-side coalescing to avoid flooding the webview
    const throttleMs = workspace.getConfiguration('vsec.throttle').get<number>('proofViewMs', 50);
    const now = Date.now();
    if (now - GoalPanel.lastPostedAtMs < throttleMs) {
      // Skip overly rapid updates
      console.log('GoalPanel: coalescing rapid proofView update');
      return;
    }
    GoalPanel.lastPostedAtMs = now;
    
    // Transform to VSCoq-expected structure
    const vscoqMessage = {
      command: 'renderProofView',
      proofView: { proof: proofState, messages, progress }
    } as any;
    
    console.log('🔍 DEBUG: Posting VSCoq-format message to webview:', vscoqMessage);
    this._panel.webview.postMessage(vscoqMessage);
    GoalPanel.lastPostedProofView = vscoqMessage;
    console.log('🔍 DEBUG: VSCoq-format message posted to webview');
  };

  public updateProofState(proofState: any, textDocument: any) {
    // Debug: Log the proof state being sent
    console.log('GoalPanel: Sending proof state to webview:', JSON.stringify(proofState, null, 2));
    console.log('GoalPanel: Webview ready state:', this._panel.webview);
    
    const message = {
      "command": "renderProofView", 
      "proofView": proofState
    };
    
    console.log('GoalPanel: Posting message to webview:', message);
    
    // Send proof state update to the webview (VSCoq protocol style)
    this._panel.webview.postMessage(message);
    
    console.log('GoalPanel: Message posted to webview successfully');
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

  private _getWebviewContent(webview: Webview, extensionUri: Uri) {
    const stylesUri = getUri(webview, extensionUri, ["goal-view-ui", "build", "assets", "index.css"]);
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
          <style nonce="${nonce}">
            body, html { height: 100%; }
            .vsec-container { display: flex; flex-direction: column; height: 100%; }
            .vsec-root { flex: 1 1 auto; min-height: 0; }
            .vsec-console {
              flex: 0 0 auto;
              max-height: 30vh;
              border-top: 1px solid var(--vscode-panel-border);
              background: var(--vscode-panel-background);
              font-family: var(--vscode-font-family);
            }
            .vsec-console-header {
              display: flex; align-items: center; gap: 12px; padding: 6px 8px;
              color: var(--vscode-foreground);
            }
            .vsec-console-body {
              overflow: auto; padding: 6px 8px; font-size: 12px; line-height: 1.4;
            }
            .vsec-msg { margin: 2px 0; white-space: pre-wrap; }
            .vsec-msg.info { color: var(--vscode-descriptionForeground); }
            .vsec-msg.warning { color: var(--vscode-editorWarning-foreground, #b58900); }
            .vsec-msg.error { color: var(--vscode-editorError-foreground, #dc322f); }
            .vsec-badge { margin-left: auto; opacity: 0.8; font-size: 11px; }
            .vsec-filter label { margin-right: 10px; }
            .vsec-clear { margin-left: 8px; }
          </style>
        </head>
        <body>
          <div class="vsec-container">
            <div class="vsec-root" id="root"></div>
            <div class="vsec-console" id="vsec-console">
              <div class="vsec-console-header">
                <span>Proof Console</span>
                <span class="vsec-filter">
                  <label><input type="checkbox" id="vsec-filter-info" checked> info</label>
                  <label><input type="checkbox" id="vsec-filter-warn" checked> warning</label>
                  <label><input type="checkbox" id="vsec-filter-err" checked> error</label>
                </span>
                <button class="vsec-clear" id="vsec-clear">Clear</button>
                <span class="vsec-badge" id="vsec-count">0</span>
              </div>
              <div class="vsec-console-body" id="vsec-console-body"></div>
            </div>
          </div>
          <script type="module" nonce="${nonce}" src="${scriptUri}"></script>
          <script nonce="${nonce}">
            (function(){
              const MAX_KEEP = 200;
              const consoleBody = document.getElementById('vsec-console-body');
              const countBadge = document.getElementById('vsec-count');
              const fInfo = document.getElementById('vsec-filter-info');
              const fWarn = document.getElementById('vsec-filter-warn');
              const fErr = document.getElementById('vsec-filter-err');
              const btnClear = document.getElementById('vsec-clear');
              let buffer = [];
              const consoleContainer = document.getElementById('vsec-console');
              const updateVisibility = () => {
                if (!consoleContainer) return;
                if (buffer.length > 0) {
                  consoleContainer.style.display = '';
                } else {
                  consoleContainer.style.display = 'none';
                }
              };
              const passes = (m) => (
                (m.level === 'info' && fInfo.checked) ||
                (m.level === 'warning' && fWarn.checked) ||
                (m.level === 'error' && fErr.checked)
              );
              const render = () => {
                if (!consoleBody) return;
                consoleBody.innerHTML = '';
                const frag = document.createDocumentFragment();
                buffer.filter(passes).forEach(m => {
                  const div = document.createElement('div');
                  div.className = 'vsec-msg ' + (m.level || 'info');
                  div.textContent = m.text || '';
                  frag.appendChild(div);
                });
                consoleBody.appendChild(frag);
                if (countBadge) countBadge.textContent = String(buffer.length);
                updateVisibility();
              };
              const appendMessages = (messages) => {
                if (!Array.isArray(messages)) return;
                buffer = buffer.concat(messages).slice(-MAX_KEEP);
                render();
                consoleBody.scrollTop = consoleBody.scrollHeight;
              };
              btnClear && btnClear.addEventListener('click', () => { buffer = []; render(); });
              fInfo && fInfo.addEventListener('change', render);
              fWarn && fWarn.addEventListener('change', render);
              fErr && fErr.addEventListener('change', render);
              updateVisibility();
              window.addEventListener('message', (event) => {
                const msg = event.data || {};
                if (msg && msg.command === 'renderProofView' && msg.proofView) {
                  const messages = msg.proofView.messages || [];
                  if (Array.isArray(messages) && messages.length > 0) {
                    appendMessages(messages);
                  }
                  if (!messages || messages.length === 0) {
                    buffer = [];
                    render();
                  }
                }
              });
            })();
          </script>
        </body>
      </html>
    `;
  }

  private _setWebviewMessageListener(webview: Webview) {
    webview.onDidReceiveMessage(
      (message: any) => {
        const command = message.command;
        const text = message.text;

        switch (command) {
          case "hello":
            // Code that should run in response to the hello message command
            window.showInformationMessage(text);
            return;
          // Add more switch case statements here as more webview message commands
          // are created within the webview context (i.e. inside media/main.js)
        }
      },
      undefined,
      this._disposables
    );
  }

  private _updateDisplaySettings(webview: Webview) {
    const config = workspace.getConfiguration('vsec.goals');
    const displaySettings = {
      display: {
        abbreviated: config.get('display.abbreviated', false),
        compactGoals: config.get('display.compactGoals', false),
        compactHypotheses: config.get('display.compactHypotheses', false),
        expandDefault: config.get('display.expandDefault', 'smart-expand'),
        hideNotifications: config.get('display.hideNotifications', false),
        spaceBetweenHypotheses: config.get('display.spaceBetweenHypotheses', true),
      }
    };
    webview.postMessage({ command: 'displaySettings', displaySettings });
  }

  private _updateGoalDepth(webview: Webview) {
    const config = workspace.getConfiguration('vsec.goals');
    const goalDepth = config.get('display.maxGoalDepth', 2);
    webview.postMessage({ command: 'goalDepth', goalDepth });
  }

  public static getLastPosted(): any | undefined {
    return GoalPanel.lastPostedProofView;
  }

  public static clearLastPosted(): void {
    GoalPanel.lastPostedProofView = undefined;
  }
}