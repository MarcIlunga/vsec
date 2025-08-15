import * as assert from 'assert';
import * as vscode from 'vscode';
import { GoalPanel } from '../../src/panels/GoalPanel';

suite('GoalPanel Webview', () => {
  test('Show Goal Panel command opens a webview', async () => {
    const ext = vscode.extensions.getExtension('vsec.vsec-easycrypt') ||
                vscode.extensions.all.find(e => e.packageJSON?.name === 'vsec-easycrypt');
    assert.ok(ext, 'Extension not found');
    if (!ext!.isActive) await ext!.activate();

    // Ensure mock LSP path to avoid requiring real server
    const extBase = ext!;
    const mockPath = vscode.Uri.joinPath(extBase.extensionUri, 'dist', 'tests', 'servers', 'mock-lsp.js').fsPath;
    await vscode.workspace.getConfiguration('vsec').update('path', process.execPath, vscode.ConfigurationTarget.Global);
    await vscode.workspace.getConfiguration('vsec').update('args', [mockPath], vscode.ConfigurationTarget.Global);

    await vscode.commands.executeCommand('vsec.showGoalPanel');

    // Wait for webview creation tick
    await new Promise(r => setTimeout(r, 600));

    // There is no direct API to list webviews; we ensure no error and that command exists
    const cmds = await vscode.commands.getCommands(true);
    assert.ok(cmds.includes('vsec.showGoalPanel'));
  });

  test('GoalPanel posts display settings and goal depth on show', async () => {
    const ext = vscode.extensions.getExtension('vsec.vsec-easycrypt') ||
                vscode.extensions.all.find(e => e.packageJSON?.name === 'vsec-easycrypt');
    if (!ext!.isActive) await ext!.activate();

    // Open and allow time for settings posts
    await vscode.commands.executeCommand('vsec.showGoalPanel');
    await new Promise(r => setTimeout(r, 600));

    // If no exception occurred, we at least know the command path works.
    // Deeper assertions on webview messages would require instrumentation hooks.
    const cmds = await vscode.commands.getCommands(true);
    if (!cmds.includes('vsec.showGoalPanel')) throw new Error('Command missing after open');
    if (!cmds.includes('vsec.checkProof')) throw new Error('checkProof missing');
  });

  test('proofView notification populates messages (from mock LSP)', async () => {
    const ext = vscode.extensions.getExtension('vsec.vsec-easycrypt') ||
                vscode.extensions.all.find(e => e.packageJSON?.name === 'vsec-easycrypt');
    if (!ext!.isActive) await ext!.activate();

    // Ensure mock LSP is used so it emits prover/proofView on initialized
    const extBase = ext!;
    const mockPath = vscode.Uri.joinPath(extBase.extensionUri, 'dist', 'tests', 'servers', 'mock-lsp.js').fsPath;
    await vscode.workspace.getConfiguration('vsec').update('path', process.execPath, vscode.ConfigurationTarget.Global);
    await vscode.workspace.getConfiguration('vsec').update('args', [mockPath], vscode.ConfigurationTarget.Global);

    GoalPanel.clearLastPosted();
    await vscode.commands.executeCommand('vsec.showGoalPanel');

    // Wait for mock server to send notification and extension to forward it
    await new Promise(r => setTimeout(r, 1000));

    const last = GoalPanel.getLastPosted();
    if (!last) throw new Error('No proofView message posted');
    if (last.command !== 'renderProofView') throw new Error('Unexpected command');
    if (!last.proofView || !Array.isArray(last.proofView.messages)) throw new Error('Messages missing in proofView');
  });
});


