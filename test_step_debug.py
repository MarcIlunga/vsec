#!/usr/bin/env python3

import json
import subprocess
import sys
import os

def send_lsp_message(proc, message):
    """Send a JSON-RPC message to the LSP server"""
    msg_json = json.dumps(message)
    msg_with_header = f"Content-Length: {len(msg_json)}\r\n\r\n{msg_json}"
    proc.stdin.write(msg_with_header.encode())
    proc.stdin.flush()
    print(f"SENT: {message['method']}")

def main():
    # Start LSP server
    proc = subprocess.Popen(
        ['./vscode-extension/vsec-lsp'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd='/home/marcilunga/dev/vsec'
    )
    
    # Initialize
    send_lsp_message(proc, {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "processId": None,
            "clientInfo": {"name": "test", "version": "1.0"},
            "rootUri": "file:///home/marcilunga/dev/vsec",
            "capabilities": {
                "textDocument": {
                    "synchronization": {"dynamicRegistration": False}
                }
            }
        }
    })
    
    # Wait a moment for initialization
    import time
    time.sleep(1)
    
    # Send initialized notification
    send_lsp_message(proc, {
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": {}
    })
    
    # Open document
    test_content = """lemma test_lemma : forall (x : bool), x = x.
proof.
trivial.
qed."""
    
    send_lsp_message(proc, {
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
            "textDocument": {
                "uri": "file:///home/marcilunga/dev/vsec/test_debug.ec",
                "languageId": "easycrypt",
                "version": 1,
                "text": test_content
            }
        }
    })
    
    # Wait for document to be processed
    time.sleep(2)
    
    # Send stepForward command
    print("🚀 SENDING STEP FORWARD COMMAND")
    send_lsp_message(proc, {
        "jsonrpc": "2.0",
        "method": "prover/stepForward",
        "params": {
            "textDocument": {
                "uri": "file:///home/marcilunga/dev/vsec/test_debug.ec",
                "version": 1
            }
        }
    })
    
    # Wait for processing
    time.sleep(3)
    
    # Send multiple stepForward commands to test proof mode
    for i in range(2, 6):
        print(f"🚀 SENDING STEP FORWARD COMMAND #{i}")
        send_lsp_message(proc, {
            "jsonrpc": "2.0", 
            "method": "prover/stepForward",
            "params": {
                "textDocument": {
                    "uri": "file:///home/marcilunga/dev/vsec/test_debug.ec",
                    "version": 1
                }
            }
        })
        time.sleep(1)  # Brief pause between commands
    
    # Wait and then terminate
    time.sleep(2)
    proc.terminate()
    
    # Read stderr for debugging output
    stderr_output = proc.stderr.read().decode()
    print("\n" + "="*50)
    print("STDERR OUTPUT (DEBUGGING):")
    print("="*50)
    print(stderr_output)

if __name__ == "__main__":
    main()