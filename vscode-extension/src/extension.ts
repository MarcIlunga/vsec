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
            },
            outputChannelName: 'VsEc EasyCrypt Language Server'
        };

        console.log('[Extension Host] Creating Language Client...');
        
        // Create the language client (like VSCoq)
        client = new Client(serverOptions, clientOptions);
        
        // Set up semantic highlighting BEFORE starting client (VSCoq pattern!)
        Client.writeToVsEcChannel("🎨 EXTENSION: Setting up semantic highlighting (BEFORE client.start - VSCoq pattern)");
        
        client.onNotification("vsec/semanticHighlighting", (notification: any) => {
            Client.writeToVsEcChannel(`🎯 EXTENSION: Received ${notification.tokens.length} semantic tokens`);
            
            // Apply decorations like VSCoq does
            const editors = window.visibleTextEditors.filter(editor => 
                editor.document.uri.toString() === notification.uri
            );
            
            if (editors.length > 0) {
                // Apply semantic highlighting decorations
                Client.writeToVsEcChannel(`✨ EXTENSION: Applying decorations to ${editors.length} editors`);
                
                // Create decoration types - red keywords + varied colors (Rust Analyzer inspired)
                const decorationTypes = new Map<string, any>();
                if (!decorationTypes.has('keyword')) {
                    decorationTypes.set('keyword', window.createTextEditorDecorationType({
                        color: '#ff6b6b', // Red for keywords (lemma, theorem, proof, qed)
                        fontWeight: 'bold'
                    }));
                    decorationTypes.set('tactic', window.createTextEditorDecorationType({
                        color: '#c586c0', // Purple for tactics (apply, rewrite, auto) - like VS Code functions
                        fontStyle: 'italic'
                    }));
                    decorationTypes.set('type', window.createTextEditorDecorationType({
                        color: '#4ec9b0', // Teal/cyan for types (bool, int, unit) - like Rust Analyzer
                        fontWeight: '500'
                    }));
                    decorationTypes.set('identifier', window.createTextEditorDecorationType({
                        color: '#9cdcfe', // Light blue for identifiers - like VS Code variables
                    }));
                    decorationTypes.set('module', window.createTextEditorDecorationType({
                        color: '#4fc1ff', // Bright blue for modules/theories - like VS Code namespaces
                        fontWeight: 'bold'
                    }));
                }
                
                // Group tokens by type for efficient decoration
                const tokensByType = new Map<string, any[]>();
                
                notification.tokens.forEach((token: any) => {
                    const startPos = {line: token.line, character: token.startChar};
                    const endPos = {line: token.line, character: token.startChar + token.length};
                    const range = new Selection(startPos.line, startPos.character, endPos.line, endPos.character);
                    
                    if (!tokensByType.has(token.tokenType)) {
                        tokensByType.set(token.tokenType, []);
                    }
                    tokensByType.get(token.tokenType)!.push(range);
                });
                
                // Apply decorations to all visible editors
                editors.forEach(editor => {
                    // Clear existing decorations first
                    decorationTypes.forEach((decorationType, _) => {
                        editor.setDecorations(decorationType, []);
                    });
                    
                    // Apply new decorations
                    tokensByType.forEach((ranges, tokenType) => {
                        const decorationType = decorationTypes.get(tokenType);
                        if (decorationType) {
                            editor.setDecorations(decorationType, ranges);
                            Client.writeToVsEcChannel(`🎨 Applied ${ranges.length} ${tokenType} decorations`);
                        }
                    });
                });
                
                Client.writeToVsEcChannel(`🎉 Semantic highlighting applied successfully!`);
            } else {
                Client.writeToVsEcChannel("⚠️ EXTENSION: No visible editors found for semantic highlighting");
            }
        });
        
        Client.writeToVsEcChannel("✅ EXTENSION: Semantic highlighting notifications registered (BEFORE start)!");
        
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
                    Client.writeToVsEcChannel("▶️ Stepping forward...");
                    client.sendNotification('prover/stepForward', {
                        textDocument: { uri: activeEditor.document.uri.toString() }
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
                    Client.writeToVsEcChannel("◀️ Stepping backward...");
                    client.sendNotification('prover/stepBackward', {
                        textDocument: { uri: activeEditor.document.uri.toString() }
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
                    Client.writeToVsEcChannel("🎯 Interpreting to cursor position...");
                    client.sendNotification('prover/interpretToPoint', {
                        textDocument: { 
                            uri: activeEditor.document.uri.toString(),
                            version: activeEditor.document.version 
                        },
                        position: {
                            line: activeEditor.selection.active.line,
                            character: activeEditor.selection.active.character
                        }
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
                    Client.writeToVsEcChannel("⏭️ Interpreting to end of document...");
                    client.sendNotification('prover/interpretToEnd', {
                        textDocument: { uri: activeEditor.document.uri.toString() }
                    });
                } else {
                    window.showWarningMessage('Interpret to end is only available for EasyCrypt files');
                }
            });
            context.subscriptions.push(interpretToEndCommand);
            
            // Command: Proof Search & Discovery
            const proofSearchCommand = commands.registerCommand('vsec.proofSearch', () => {
                Client.writeToVsEcChannel("🔍 Opening proof search & discovery panel...");
                ProofSearchProvider.showProofSearchPanel(context.extensionUri);
            });
            context.subscriptions.push(proofSearchCommand);
            
            // 🔄 Listen for Proof View Updates from Server
            client.onNotification('prover/proofView', (params: any) => {
                Client.writeToVsEcChannel("🎯 Received proof view update from server");
                console.log('[Extension Host] Proof view update:', params);
                
                // Update goal panel if it exists
                if (GoalPanel.currentPanel) {
                    GoalPanel.currentPanel.updateProofState(params.proofState, params.textDocument);
                    Client.writeToVsEcChannel("✅ Goal panel updated with new proof state");
                } else {
                    Client.writeToVsEcChannel("ℹ️ Goal panel not open, proof state received but not displayed");
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