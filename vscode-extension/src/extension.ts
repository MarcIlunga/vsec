import {workspace, window, commands, languages, ExtensionContext, env,
  TextEditorSelectionChangeEvent,
  TextEditor,
  ViewColumn,
  TextEditorRevealType,
  Selection,
  Uri,
  StatusBarItem,
  extensions,
  StatusBarAlignment,
  MarkdownString,
  WorkspaceEdit,
  version,
  Position
} from 'vscode';

import { GoalPanel } from './panels/GoalPanel';
import { ProofSearchProvider } from './commands/ProofSearchCommand';
import { 
    sendInterpretToPoint,
    sendInterpretToEnd,
    sendStepForward,
    sendStepBackward,
    sendCheckProof
} from './manualChecking';

import {
  LanguageClientOptions,
  RequestType,
  ServerOptions,
  TextDocumentIdentifier,
} from 'vscode-languageclient/node';

import Client from './client';
import VsEcToolchainManager, {ToolchainError, ToolChainErrorCode} from './toolchain';
import { ProofControlsViewProvider } from './views/ProofControlsView';
import { ToolsViewProvider } from './views/ToolsView';
import { ActionsViewProvider } from './views/ActionsView';
import { readdirSync, statSync, readFileSync } from 'fs';
import { join } from 'path';
import { createHash } from 'crypto';

let client: Client;
let globalActionsProvider: ActionsViewProvider | undefined;
let sbGoals: StatusBarItem | undefined;
let sbStepF: StatusBarItem | undefined;
let sbStepB: StatusBarItem | undefined;

export function activate(context: ExtensionContext) {
    const extSelf = extensions.getExtension('vsec.vsec-easycrypt');
    const extVersion = extSelf?.packageJSON?.version ?? 'unknown';
    console.log(`[VsEc] SanityCheck: Extension activating (version=${extVersion}, vscode=${version})`);
    // DEV: compute a build fingerprint and increment a counter when it changes
    try {
        const fingerprint = computeDevFingerprint(context);
        const lastFp = context.globalState.get<string>('vsec.dev.fp');
        let counter = context.globalState.get<number>('vsec.dev.counter') ?? 0;
        if (lastFp !== fingerprint) {
            counter = counter + 1;
            context.globalState.update('vsec.dev.fp', fingerprint);
            context.globalState.update('vsec.dev.counter', counter);
        }
        console.log(`[VsEc][DEV] BuildCounter=${counter} fp=${fingerprint.substring(0, 12)}`);
    } catch (e) {
        console.warn('[VsEc][DEV] Fingerprint failed:', e);
    }

    // Register sidebar view providers IMMEDIATELY on activation to avoid
    // "no data provider" errors, regardless of toolchain/LSP state.
    try {
        const earlyProofControls = new ProofControlsViewProvider(context.extensionUri);
        context.subscriptions.push(window.registerWebviewViewProvider(ProofControlsViewProvider.viewId, earlyProofControls));
        const earlyTools = new ToolsViewProvider(context.extensionUri);
        context.subscriptions.push(window.registerWebviewViewProvider(ToolsViewProvider.viewId, earlyTools));
        globalActionsProvider = new ActionsViewProvider();
        context.subscriptions.push(window.registerTreeDataProvider(ActionsViewProvider.viewId, globalActionsProvider));
        console.log('[VsEc] SanityCheck: Early view providers registered');
    } catch (e) {
        console.warn('[VsEc] Early view provider registration failed:', e);
    }

    // Early command registration so palette/shortcuts work even before LSP client starts
    const earlyGetActiveEditor = (): TextEditor | undefined => {
        const active = window.activeTextEditor;
        if (active && active.document.languageId === 'easycrypt') return active;
        return window.visibleTextEditors.find(e => e.document.languageId === 'easycrypt');
    };

    // Bridge commands used by ProofControls webview (call existing commands)
    context.subscriptions.push(commands.registerCommand('vsec.runStepForward', async () => {
        await commands.executeCommand('vsec.stepForward');
    }));
    context.subscriptions.push(commands.registerCommand('vsec.runInterpretToPoint', async () => {
        await commands.executeCommand('vsec.interpretToPoint');
    }));
    context.subscriptions.push(commands.registerCommand('vsec.runInterpretToEnd', async () => {
        await commands.executeCommand('vsec.interpretToEnd');
    }));
    context.subscriptions.push(commands.registerCommand('vsec.runCheckProof', async () => {
        await commands.executeCommand('vsec.checkProof');
    }));

    context.subscriptions.push(commands.registerCommand('vsec.showGoalPanel', () => {
        const editor = window.activeTextEditor ? window.activeTextEditor : window.visibleTextEditors[0];
        GoalPanel.displayProofView(context.extensionUri, editor);
    }));
    context.subscriptions.push(commands.registerCommand('vsec.runShowGoalPanel', () => {
        const editor = earlyGetActiveEditor();
        if (editor) GoalPanel.displayProofView(context.extensionUri, editor);
        else window.showInformationMessage('Open an EasyCrypt file to show the Goal Panel');
    }));
    context.subscriptions.push(commands.registerCommand('vsec.stepForward', () => {
        const editor = earlyGetActiveEditor();
        if (!editor) return window.showInformationMessage('Open an EasyCrypt file to Step Forward');
        if (!client) return window.showWarningMessage('VsEc language client not ready yet');
        return sendStepForward(editor, client);
    }));
    context.subscriptions.push(commands.registerCommand('vsec.stepBackward', () => {
        const editor = earlyGetActiveEditor();
        if (!editor) return window.showInformationMessage('Open an EasyCrypt file to Step Backward');
        if (!client) return window.showWarningMessage('VsEc language client not ready yet');
        return sendStepBackward(editor, client);
    }));
    context.subscriptions.push(commands.registerCommand('vsec.interpretToPoint', () => {
        const editor = earlyGetActiveEditor();
        if (!editor) return window.showInformationMessage('Open an EasyCrypt file to Interpret to Cursor');
        if (!client) return window.showWarningMessage('VsEc language client not ready yet');
        return sendInterpretToPoint(editor, client);
    }));
    context.subscriptions.push(commands.registerCommand('vsec.interpretToEnd', () => {
        const editor = earlyGetActiveEditor();
        if (!editor) return window.showInformationMessage('Open an EasyCrypt file to Interpret to End');
        if (!client) return window.showWarningMessage('VsEc language client not ready yet');
        return sendInterpretToEnd(editor, client);
    }));
    context.subscriptions.push(commands.registerCommand('vsec.checkProof', () => {
        const editor = earlyGetActiveEditor();
        if (!editor) return window.showInformationMessage('Open an EasyCrypt file to Check Proof');
        if (!client) return window.showWarningMessage('VsEc language client not ready yet');
        return sendCheckProof(editor, client);
    }));

    // Show status bar controls immediately (client may not be started yet)
    ensureStatusBar();
    updateStatusBarVisibility();
    context.subscriptions.push(window.onDidChangeActiveTextEditor(updateStatusBarVisibility));

    const easycryptTM = new VsEcToolchainManager(context);
    easycryptTM.initialize().then(
        () => {
            console.log('[Extension Host] Toolchain initialized successfully');
            const serverOptions = easycryptTM.getServerConfiguration(); 
            initializeExtension(serverOptions, context);
        }, 
        (err: ToolchainError) => {
            console.error('[Extension Host] Toolchain initialization failed:', err);
            switch(err.status) {
                case ToolChainErrorCode.notFound: 
                    window.showErrorMessage("No VsEc language server found", {modal: true, detail: err.message}, {title: "Check installation", id: 0})
                    .then(act => {
                        if(act?.id === 0) {
                            commands.executeCommand("vscode.open", Uri.parse('https://github.com/EasyCrypt/vsec'));
                        }
                    });
                    break;

                case ToolChainErrorCode.launchError: 
                    window.showErrorMessage("Could not launch VsEc language server", {modal: true, detail: err.message}, {title: "Check installation", id: 0})
                    .then(act => {
                        if(act?.id === 0) {
                            commands.executeCommand("vscode.open", Uri.parse('https://github.com/EasyCrypt/vsec'));
                        }
                    });
                    break;
            }
        }
    );
    
    function registerVsEcTextCommand(command: string, callback: (textEditor: TextEditor, ...args: any[]) => void) {
        context.subscriptions.push(commands.registerTextEditorCommand('vsec.' + command, callback));
    };

    function ensureStatusBar() {
        // Intentionally no status bar buttons; all actions live in the Actions pane.
        // Keep variables allocated to avoid undefined references elsewhere.
        if (!sbGoals) sbGoals = window.createStatusBarItem(StatusBarAlignment.Left, 100);
        if (!sbStepF) sbStepF = window.createStatusBarItem(StatusBarAlignment.Left, 99);
        if (!sbStepB) sbStepB = window.createStatusBarItem(StatusBarAlignment.Left, 98);
        // Do not set text/command; keep hidden.
        context.subscriptions.push(sbGoals, sbStepF, sbStepB);
    }

    function updateStatusBarVisibility() {
        // Always hide status bar items per request
        if (sbGoals) sbGoals.hide();
        if (sbStepF) sbStepF.hide();
        if (sbStepB) sbStepB.hide();
    }

    function initializeExtension(serverOptions: ServerOptions, context: ExtensionContext) {
        console.log(`[VsEc] SanityCheck: Initializing extension (version=${extVersion}) with server options:`, serverOptions);
        
        const config = workspace.getConfiguration('vsec');

        let clientOptions: LanguageClientOptions = {
            documentSelector: [{ scheme: 'file', language: 'easycrypt' }],
            initializationOptions: config,
            synchronize: {
                configurationSection: 'vsec-language-server'
            },
            outputChannelName: 'VsEc EasyCrypt Language Server'
        };

        console.log('[VsEc] SanityCheck: Creating Language Client...');
        
        // Create the language client (like VSCoq)
        client = new Client(serverOptions, clientOptions);

        // Avoid re-registering view providers here; they are created at activation time
        
        // Set up semantic highlighting BEFORE starting client (VSCoq pattern!)
        Client.writeToVsEcChannel("🎨 EXTENSION: Setting up semantic highlighting (BEFORE client.start - VSCoq pattern)");
        
        // VSCoq doesn't use custom semantic highlighting - they rely on TextMate grammar only
        // This prevents conflicts between TextMate and semantic coloring
        client.onNotification("vsec/semanticHighlighting", (notification: any) => {
            Client.writeToVsEcChannel(`🎯 EXTENSION: Received ${notification.tokens.length} semantic tokens (using TextMate only, like VSCoq)`);
            // Note: VSCoq uses only TextMate grammar for syntax highlighting to avoid conflicts
            // We follow the same pattern for compatibility
        });
        
        Client.writeToVsEcChannel("✅ EXTENSION: Semantic highlighting notifications registered (BEFORE start)!");
        
        // Now start the client (VSCoq pattern)
        console.log('[VsEc] SanityCheck: Starting Language Client...');
        Client.writeToVsEcChannel("🚀 EXTENSION: About to call client.start() - notifications already set up");
        
        client.start().then(() => {
            Client.writeToVsEcChannel("🎉 EXTENSION: client.start() SUCCESS - semantic highlighting ready!");
            console.log('[VsEc] SanityCheck: Language Client started successfully!');
            
            // Show success message
            window.showInformationMessage('VsEc EasyCrypt Language Server started successfully!');
            
            // Command: Proof Search & Discovery (unique)
            const proofSearchCommand = commands.registerCommand('vsec.proofSearch', () => {
                Client.writeToVsEcChannel("🔍 Opening proof search & discovery panel...");
                ProofSearchProvider.showProofSearchPanel(context.extensionUri);
            });
            context.subscriptions.push(proofSearchCommand);

            // Kill EasyCrypt process command
            const killEcCmd = commands.registerCommand('vsec.killEasyCrypt', () => {
                try {
                    (client as any).sendNotification({ method: 'vsec/killEasyCrypt', params: {} });
                    window.showInformationMessage('Sent request to kill EasyCrypt process');
                } catch (e) {
                    window.showErrorMessage('Failed to send kill request: ' + (e as any));
                }
            });
            context.subscriptions.push(killEcCmd);

            // Revert to previous successful step and execute
            const revertPrev = commands.registerCommand('vsec.revertToPrevious', () => {
                try {
                    (client as any).sendNotification({ method: 'vsec/revertToPrevious', params: {} });
                } catch (e) {
                    window.showErrorMessage('Failed to send revert request: ' + (e as any));
                }
            });
            context.subscriptions.push(revertPrev);
            
            // Proof view notification handler
            client.onNotification("prover/proofView", (proofView: any) => {
                try {
                    console.log('[VsEc] Notification prover/proofView params:', JSON.stringify(proofView));
                    const goalsLen = Array.isArray(proofView?.proofState?.goals) ? proofView.proofState.goals.length : 0;
                    const msgsLen = Array.isArray(proofView?.messages) ? proofView.messages.length : 0;
                    console.log(`[VsEc] prover/proofView: goals=${goalsLen}, messages=${msgsLen}`);
                } catch {}
                try { globalActionsProvider?.updateStatus(proofView); } catch {}
                const editor = window.activeTextEditor ? window.activeTextEditor : window.visibleTextEditors[0];
                const autoDisplay = workspace.getConfiguration('vsec.goals').get('auto', true);
                GoalPanel.proofViewNotification(context.extensionUri, editor, proofView, autoDisplay);
                // Update status bar tooltips
                if (sbStepF) sbStepF.tooltip = 'Step Forward' + (editor ? '' : ' (open an EasyCrypt file)');
                if (sbStepB) sbStepB.tooltip = 'Step Backward' + (editor ? '' : ' (open an EasyCrypt file)');
                // Refresh display settings in webview in case they changed
                GoalPanel.updateSettingsForCurrentPanel();
            });
            
            // Move cursor handler: reveal without disruptive jumps
            client.onNotification('prover/moveCursor', (params: any) => {
                try {
                    const editor = window.activeTextEditor ? window.activeTextEditor : window.visibleTextEditors[0];
                    if (!editor || !params?.position) return;
                    const pos = new Selection(new Position(params.position.line, params.position.character), new Position(params.position.line, params.position.character));
                    editor.selections = [pos];
                    editor.revealRange(new Selection(editor.selection.start, editor.selection.end), TextEditorRevealType.InCenterIfOutsideViewport);
                } catch {}
            });

            // Semantic highlighting for last executed (decoration lifecycle)
            client.onNotification('vsec/semanticHighlighting', (payload: any) => {
                try {
                    const editor = window.activeTextEditor ? window.activeTextEditor : window.visibleTextEditors[0];
                    if (!editor) return;
                    const enabled = workspace.getConfiguration('vsec').get<boolean>('proof.lastExecutedHighlight', true);
                    const deco = (Client as any).lastExecutedDecoration;
                    if (!deco) return;
                    if (!enabled) { editor.setDecorations(deco, []); return; }
                    const tokensRaw = Array.isArray(payload?.tokens) ? payload.tokens : [];
                    const tokens = tokensRaw.filter((t: any) => t?.tokenType === 'highlight' || t?.classification === 'last-executed');
                    if (tokens.length === 0) {
                        editor.setDecorations(deco, []);
                        return;
                    }
                    const ranges = tokens.map((t: any) => new Selection(new Position(t.line, t.startChar), new Position(t.line, t.startChar + t.length)));
                    editor.setDecorations(deco, ranges);
                } catch {}
            });

            // Status bar items
            ensureStatusBar();
            updateStatusBarVisibility();
            context.subscriptions.push(window.onDidChangeActiveTextEditor(updateStatusBarVisibility));

            // React to configuration changes (highlight toggle, throttle proofView)
            context.subscriptions.push(workspace.onDidChangeConfiguration(e => {
                try {
                    if (e.affectsConfiguration('vsec.proof.lastExecutedHighlight')) {
                        const editor = window.activeTextEditor ? window.activeTextEditor : window.visibleTextEditors[0];
                        const deco = (Client as any).lastExecutedDecoration;
                        if (editor && deco) {
                            const enabled = workspace.getConfiguration('vsec').get<boolean>('proof.lastExecutedHighlight', true);
                            if (!enabled) editor.setDecorations(deco, []);
                        }
                    }
                    if (e.affectsConfiguration('vsec.throttle.proofViewMs')) {
                        GoalPanel.updateSettingsForCurrentPanel();
                    }
                } catch {}
            }));
            
            // Sidebar view providers already registered above
            
        }).catch((error) => {
            console.error('[Extension Host] Failed to start Language Client:', error);
            Client.writeToVsEcChannel("Failed to start Language Client: " + error);
            window.showErrorMessage('Failed to start VsEc EasyCrypt Language Server: ' + error);
        });

        // Add client to disposables
        context.subscriptions.push(client);
        
        console.log('[VsEc] SanityCheck: Extension activated successfully');

        // Optional: expose a manual sanity-check command to print version info
        context.subscriptions.push(commands.registerCommand('vsec.sanityCheck', () => {
            const ext = extensions.getExtension('vsec.vsec-easycrypt');
            const v = ext?.packageJSON?.version ?? 'unknown';
            console.log(`[VsEc] SanityCheck: command invoked (version=${v}, vscode=${version})`);
            window.showInformationMessage(`VsEc SanityCheck: extension ${v}`);
        }));
    }
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}

function computeDevFingerprint(context: ExtensionContext): string {
    // Hash contents and mtimes of key output folders to reflect a rebuild
    const roots = [
        join(context.extensionPath, 'dist'),
        join(context.extensionPath, 'out'),
        join(context.extensionPath, 'goal-view-ui', 'build', 'assets')
    ];
    const hash = createHash('sha1');
    for (const root of roots) {
        try { walkHash(root, hash); } catch {}
    }
    return hash.digest('hex');
}

function walkHash(dir: string, hash: ReturnType<typeof createHash>) {
    try {
        const entries = readdirSync(dir, { withFileTypes: true } as any);
        for (const e of entries) {
            const full = join(dir, (e as any).name);
            const st = statSync(full);
            hash.update((e as any).name);
            hash.update(String(st.mtimeMs));
            hash.update(String(st.size));
            if ((e as any).isFile && (e as any).isFile()) {
                try { hash.update(readFileSync(full)); } catch {}
            } else if ((e as any).isDirectory && (e as any).isDirectory()) {
                walkHash(full, hash);
            }
        }
    } catch {}
}