/* Minimal LSP mock server for tests. Implements initialize/shutdown/exit and emits a prover/proofView notification once initialized. */

import * as readline from 'readline';

type JsonRpc = { jsonrpc: '2.0'; id?: number | string; method?: string; params?: any; result?: any; error?: any };

function writeMessage(msg: object) {
  const json = JSON.stringify(msg);
  process.stdout.write(`Content-Length: ${Buffer.byteLength(json, 'utf8')}\r\n\r\n${json}`);
}

let buffer = Buffer.alloc(0);

function processBuffer() {
  while (true) {
    const headerEnd = buffer.indexOf('\r\n\r\n');
    if (headerEnd === -1) return;
    const header = buffer.slice(0, headerEnd).toString('utf8');
    const match = /Content-Length:\s*(\d+)/i.exec(header);
    if (!match) {
      buffer = buffer.slice(headerEnd + 4);
      continue;
    }
    const length = parseInt(match[1], 10);
    const start = headerEnd + 4;
    if (buffer.length < start + length) return;
    const payload = buffer.slice(start, start + length).toString('utf8');
    buffer = buffer.slice(start + length);
    try {
      const msg = JSON.parse(payload) as JsonRpc;
      handleMessage(msg);
    } catch (e) {
      // ignore
    }
  }
}

function handleMessage(msg: JsonRpc) {
  if (msg.method === 'initialize' && msg.id !== undefined) {
    writeMessage({
      jsonrpc: '2.0',
      id: msg.id,
      result: {
        capabilities: {},
        serverInfo: { name: 'vsec-mock', version: '0.0.1' }
      }
    });
  } else if (msg.method === 'initialized') {
    // Emit a proof view notification once to drive UI
    const pv = { proofState: { goals: [{ id: 'g1', type: 'True' }], hyps: [] }, messages: [{ level: 'info', text: 'Mock server ready' }] };
    writeMessage({ jsonrpc: '2.0', method: 'prover/proofView', params: pv });
  } else if (msg.method === 'shutdown' && msg.id !== undefined) {
    writeMessage({ jsonrpc: '2.0', id: msg.id, result: null });
  } else if (msg.method === 'exit') {
    process.exit(0);
  }
}

process.stdin.on('data', (chunk: Buffer) => {
  buffer = Buffer.concat([buffer, chunk]);
  processBuffer();
});

process.stderr.write('vsec mock lsp started\n');


