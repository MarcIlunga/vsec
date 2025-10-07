#!/bin/bash

# Manual LSP test with proper timing

LSP_BIN="./src/_build/default/eclsp/ecLsp.exe"

echo "🧪 Testing LSP with Manual Commands"
echo "===================================="
echo ""

# Start LSP server
$LSP_BIN <<EOF
Content-Length: 130

{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":"file:///home/marcilunga/dev/vsec","capabilities":{}}}
Content-Length: 52

{"jsonrpc":"2.0","method":"initialized","params":{}}
Content-Length: 223

{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///test.ec","languageId":"easycrypt","version":1,"text":"lemma test_hyp (P Q : bool): P => Q => P /\\\\ Q.\\nproof.\\n  move=> H_P H_Q.\\nqed."}}}
EOF

echo ""
echo "Waiting 2 seconds for parsing to complete..."
sleep 2

$LSP_BIN <<EOF
Content-Length: 130

{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":"file:///home/marcilunga/dev/vsec","capabilities":{}}}
Content-Length: 52

{"jsonrpc":"2.0","method":"initialized","params":{}}
Content-Length: 223

{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///test.ec","languageId":"easycrypt","version":1,"text":"lemma test_hyp (P Q : bool): P => Q => P /\\\\ Q.\\nproof.\\n  move=> H_P H_Q.\\nqed."}}}
Content-Length: 107

{"jsonrpc":"2.0","method":"prover/stepForward","params":{"textDocument":{"uri":"file:///test.ec","version":1}}}
EOF

echo ""
echo "✅ Test complete"
