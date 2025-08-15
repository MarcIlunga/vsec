import * as assert from 'assert';
import * as vscode from 'vscode';

suite('VsEc Extension Activation', () => {
  async function waitForCommand(cmd: string, timeoutMs = 15000) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const cmds = await vscode.commands.getCommands(true);
      if (cmds.includes(cmd)) return true;
      await new Promise(r => setTimeout(r, 200));
    }
    return false;
  }

  test('Extension activates and registers commands', async () => {
    // Ensure extension uses mock LSP binary
    const extBase = (vscode.extensions.getExtension('vsec.vsec-easycrypt') || vscode.extensions.all.find(e => e.packageJSON?.name === 'vsec-easycrypt'))!;
    const mockPath = vscode.Uri.joinPath(extBase.extensionUri, 'dist', 'tests', 'servers', 'mock-lsp.js').fsPath;
    await vscode.workspace.getConfiguration('vsec').update('path', process.execPath, vscode.ConfigurationTarget.Global);
    await vscode.workspace.getConfiguration('vsec').update('args', [mockPath], vscode.ConfigurationTarget.Global);
    const ext = vscode.extensions.getExtension('vsec.vsec-easycrypt') ||
                vscode.extensions.all.find(e => e.packageJSON?.name === 'vsec-easycrypt');
    assert.ok(ext, 'Extension not found by id vsec.vsec-easycrypt');
    if (!ext!.isActive) {
      await ext!.activate();
    }
    assert.ok(ext!.isActive, 'Extension did not activate');

    assert.ok(await waitForCommand('vsec.showGoalPanel'), 'vsec.showGoalPanel not registered');
    assert.ok(await waitForCommand('vsec.stepForward'), 'vsec.stepForward not registered');
    assert.ok(await waitForCommand('vsec.interpretToPoint'), 'vsec.interpretToPoint not registered');
    assert.ok(await waitForCommand('vsec.checkProof'), 'vsec.checkProof not registered');
  });
});


