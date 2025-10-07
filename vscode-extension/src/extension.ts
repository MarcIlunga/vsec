import {workspace, window, commands, languages, ExtensionContext, env,
  TextEditorSelectionChangeEvent,
  TextEditor,
  ViewColumn,
  TextEditorRevealType,
  Uri,
  StatusBarItem,
  extensions,
  StatusBarAlignment,
  MarkdownString,
  WorkspaceEdit,
  version
} from 'vscode';

import { GoalPanel } from './panels/GoalPanel';
import { ProofSearchProvider } from './commands/ProofSearchCommand';

import {
  LanguageClientOptions,
  RequestType,
  ServerOptions,
  TextDocumentIdentifier,
} from 'vscode-languageclient/node';

import Client from './client';
import VsEcToolchainManager, {ToolchainError, ToolChainErrorCode} from './toolchain';

let client: Client;

export function activate(context: ExtensionContext) {
    console.log('[Extension Host] VsEc EasyCrypt extension is activating...');

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
    
    function initializeExtension(serverOptions: ServerOptions, context: ExtensionContext) {
        console.log('[Extension Host] Initializing extension with server options:', serverOptions);
        
        const config = workspace.getConfiguration('vsec');

        let clientOptions: LanguageClientOptions = {
            documentSelector: [{ scheme: 'file', language: 'easycrypt' }],
            initializationOptions: config,
            synchronize: {
                configurationSection: 'vsec-language-server'
            }
            // outputChannelName defaults to the client name 'VsEc EasyCrypt'
        };

        console.log('[Extension Host] Creating Language Client...');
        
        // Create the language client (like VSCoq)
        client = new Client(serverOptions, clientOptions, context);
        
        // Rely on built-in LSP semantic tokens provider from the server initialize result
        Client.writeToVsEcChannel("🎨 EXTENSION: Using VS Code semantic tokens via LSP capabilities");
        
        // Now start the client (VSCoq pattern)
        console.log('[Extension Host] Starting Language Client...');
        Client.writeToVsEcChannel("🚀 EXTENSION: About to call client.start() - notifications already set up");
        
        client.start().then(() => {
            Client.writeToVsEcChannel("🎉 EXTENSION: client.start() SUCCESS - semantic highlighting ready!");
            console.log('[Extension Host] Language Client started successfully!');
            
            // Show success message
            window.showInformationMessage('VsEc EasyCrypt Language Server started successfully!');
            
            // 🎯 Register Interactive Proving Commands
            Client.writeToVsEcChannel("🪄 EXTENSION: Registering interactive proving commands...");
            
            // Command: Show Goal Panel
            const showGoalPanelCommand = commands.registerCommand('vsec.showGoalPanel', () => {
                Client.writeToVsEcChannel("🎯 Opening EasyCrypt goal panel...");
                GoalPanel.render(context.extensionUri);
            });
            context.subscriptions.push(showGoalPanelCommand);
            
            // Command: Step Forward
            const stepForwardCommand = commands.registerCommand('vsec.stepForward', () => {
                const activeEditor = window.activeTextEditor;
                if (activeEditor && activeEditor.document.languageId === 'easycrypt') {
                    Client.writeToVsEcChannel("▶️ Stepping forward (executeCommand)...");
                    client.sendRequest('workspace/executeCommand', {
                        command: 'easycrypt.stepForward',
                        arguments: [{
                            textDocument: { uri: activeEditor.document.uri.toString(), version: activeEditor.document.version }
                        }]
                    });
                } else {
                    window.showWarningMessage('Step forward is only available for EasyCrypt files');
                }
            });
            context.subscriptions.push(stepForwardCommand);
            
            // Command: Step Backward  
            const stepBackwardCommand = commands.registerCommand('vsec.stepBackward', () => {
                const activeEditor = window.activeTextEditor;
                if (activeEditor && activeEditor.document.languageId === 'easycrypt') {
                    Client.writeToVsEcChannel("◀️ Stepping backward (executeCommand)...");
                    client.sendRequest('workspace/executeCommand', {
                        command: 'easycrypt.stepBackward',
                        arguments: [{
                            textDocument: { uri: activeEditor.document.uri.toString(), version: activeEditor.document.version }
                        }]
                    });
                } else {
                    window.showWarningMessage('Step backward is only available for EasyCrypt files');
                }
            });
            context.subscriptions.push(stepBackwardCommand);
            
            // Command: Interpret to Point (cursor position)
            const interpretToPointCommand = commands.registerCommand('vsec.interpretToPoint', () => {
                const activeEditor = window.activeTextEditor;
                if (activeEditor && activeEditor.document.languageId === 'easycrypt') {
                    Client.writeToVsEcChannel("🎯 Interpreting to cursor position (executeCommand)...");
                    // Persist last proof position per document
                    context.workspaceState.update('vsec.lastProofPosition:' + activeEditor.document.uri.toString(), {
                        line: activeEditor.selection.active.line,
                        character: activeEditor.selection.active.character,
                        version: activeEditor.document.version
                    });
                    client.sendRequest('workspace/executeCommand', {
                        command: 'easycrypt.interpretToPoint',
                        arguments: [{
                            textDocument: { uri: activeEditor.document.uri.toString(), version: activeEditor.document.version },
                            position: { line: activeEditor.selection.active.line, character: activeEditor.selection.active.character }
                        }]
                    });
                } else {
                    window.showWarningMessage('Interpret to point is only available for EasyCrypt files');
                }
            });
            context.subscriptions.push(interpretToPointCommand);
            
            // Command: Interpret to End
            const interpretToEndCommand = commands.registerCommand('vsec.interpretToEnd', () => {
                const activeEditor = window.activeTextEditor;
                if (activeEditor && activeEditor.document.languageId === 'easycrypt') {
                    Client.writeToVsEcChannel("⏭️ Interpreting to end of document (executeCommand)...");
                    client.sendRequest('workspace/executeCommand', {
                        command: 'easycrypt.interpretToEnd',
                        arguments: [{
                            textDocument: { uri: activeEditor.document.uri.toString(), version: activeEditor.document.version }
                        }]
                    });
                } else {
                    window.showWarningMessage('Interpret to end is only available for EasyCrypt files');
                }
            });
            context.subscriptions.push(interpretToEndCommand);

            // Command: Cancel proof
            const cancelProofCommand = commands.registerCommand('vsec.cancelProof', () => {
                const activeEditor = window.activeTextEditor;
                if (activeEditor && activeEditor.document.languageId === 'easycrypt') {
                    Client.writeToVsEcChannel("🛑 Cancel proof (executeCommand)...");
                    client.sendRequest('workspace/executeCommand', {
                        command: 'easycrypt.cancel',
                        arguments: [{
                            textDocument: { uri: activeEditor.document.uri.toString(), version: activeEditor.document.version }
                        }]
                    });
                } else {
                    window.showWarningMessage('Cancel proof is only available for EasyCrypt files');
                }
            });
            context.subscriptions.push(cancelProofCommand);
            
            // Command: Proof Search & Discovery
            const proofSearchCommand = commands.registerCommand('vsec.proofSearch', () => {
                Client.writeToVsEcChannel("🔍 Opening proof search & discovery panel...");
                ProofSearchProvider.showProofSearchPanel(context.extensionUri);
            });
            context.subscriptions.push(proofSearchCommand);
            
            // 🔄 Listen for Proof View Updates from Server
            client.onNotification('prover/proofView', (params: any) => {
                Client.writeToVsEcChannel("🎯 Received proof view update from server");
                try {
                    const dbg = JSON.stringify({
                        goals: params?.proofState?.goals?.length ?? 0,
                        shelved: params?.proofState?.shelvedGoals?.length ?? 0,
                        givenUp: params?.proofState?.givenUpGoals?.length ?? 0,
                        uri: params?.textDocument?.uri
                    });
                    Client.writeToVsEcChannel("🧪 proofView payload: " + dbg);
                } catch {}
                console.log('[Extension Host] Proof view update:', params);
                
                // Auto-open goal panel on first proof state (like VSCoq)
                if (!GoalPanel.currentPanel) {
                    Client.writeToVsEcChannel("📋 Auto-opening goal panel for proof state");
                    GoalPanel.render(context.extensionUri);
                }
                
                // Update goal panel with proof state
                if (GoalPanel.currentPanel) {
                    GoalPanel.currentPanel.updateProofState(params.proofState, params.textDocument);
                    Client.writeToVsEcChannel("✅ Goal panel updated with new proof state");
                    // Restore cursor to last proof position if available
                    const uri = params.textDocument?.uri as string | undefined;
                    const active = window.activeTextEditor;
                    if (uri && active && active.document.uri.toString() === uri) {
                        const key = 'vsec.lastProofPosition:' + uri;
                        const saved = context.workspaceState.get<any>(key);
                        if (saved && typeof saved.line === 'number' && typeof saved.character === 'number') {
                            const newSel = new (window.activeTextEditor!.selection.constructor as any)(
                                active.selection.anchor.with(saved.line, saved.character),
                                active.selection.active.with(saved.line, saved.character)
                            );
                            active.selection = newSel;
                        }
                    }
                } else {
                    Client.writeToVsEcChannel("⚠️ Goal panel creation failed");
                }
            });
            
            // 🔄 Listen for Execution Overview Updates (prepared/processing/processed)
            client.onNotification('prover/executionOverview', (params: any) => {
                Client.writeToVsEcChannel("📦 Received execution overview update from server");
                try {
                    Client.writeToVsEcChannel("🧪 overview payload: " + JSON.stringify({
                        hasPrepared: !!params?.overview?.prepared,
                        hasProcessing: !!params?.overview?.processing,
                        hasProcessed: !!params?.overview?.processed,
                        uri: params?.textDocument?.uri
                    }));
                } catch {}
                if (GoalPanel.currentPanel) {
                    // Forward to webview to render range highlighting
                    GoalPanel.currentPanel['updateExecutionOverview']?.(params.overview, params.textDocument);
                }
            });

            // 🔔 Listen for server-side messages (errors/warnings/info) for webview display
            client.onNotification('prover/messages', (params: any) => {
                Client.writeToVsEcChannel(`🧭 Received ${params.messages?.length ?? 0} messages from server`);
                if (GoalPanel.currentPanel) {
                    GoalPanel.currentPanel['updateMessages']?.(params.messages, params.textDocument);
                }
            });
            
            Client.writeToVsEcChannel("✅ Interactive proving commands registered successfully!");
            
            // Create status bar item
            const statusBarItem = window.createStatusBarItem(StatusBarAlignment.Left, 100);
            statusBarItem.text = "$(check) VsEc";
            statusBarItem.tooltip = "VsEc EasyCrypt Language Server is running";
            statusBarItem.show();
            context.subscriptions.push(statusBarItem);
            
        }).catch((error) => {
            console.error('[Extension Host] Failed to start Language Client:', error);
            Client.writeToVsEcChannel("Failed to start Language Client: " + error);
            window.showErrorMessage('Failed to start VsEc EasyCrypt Language Server: ' + error);
        });

        // Add client to disposables
        context.subscriptions.push(client);
        
        console.log('[Extension Host] VsEc EasyCrypt extension activated successfully!');
    }
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}