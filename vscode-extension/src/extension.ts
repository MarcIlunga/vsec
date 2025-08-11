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
        
        // Create and start the language client
        client = new Client(serverOptions, clientOptions);
        
        console.log('[Extension Host] Starting Language Client...');
        client.start().then(() => {
            console.log('[Extension Host] Language Client started successfully!');
            Client.writeToVsEcChannel("VsEc EasyCrypt Language Server started successfully!");
            
            // Show success message
            window.showInformationMessage('VsEc EasyCrypt Language Server started successfully!');
            
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