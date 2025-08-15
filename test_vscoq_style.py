#!/usr/bin/env python3

import json
import subprocess
import time
import os

# Test the VSCoq-style interpret command directly with the LSP server
def test_vscoq_style():
    # Start the LSP server
    lsp_path = "/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp"
    if not os.path.exists(lsp_path):
        print(f"LSP server not found at {lsp_path}")
        return
    
    # Create a simple test file
    test_file = "/home/marcilunga/dev/vsec/test.ec"
    test_uri = f"file://{test_file}"
    
    # LSP initialize request
    initialize_request = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "processId": os.getpid(),
            "rootUri": f"file://{os.path.dirname(test_file)}",
            "capabilities": {}
        }
    }
    
    # Text document did open
    did_open_notification = {
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
            "textDocument": {
                "uri": test_uri,
                "languageId": "easycrypt",
                "version": 1,
                "text": open(test_file).read()
            }
        }
    }
    
    # VSCoq-style Interpret to point notification 
    interpret_notification = {
        "jsonrpc": "2.0",
        "method": "prover/interpretToPoint",
        "params": {
            "textDocument": {
                "uri": test_uri,
                "version": 1
            },
            "position": {
                "line": 2,
                "character": 10
            }
        }
    }
    
    print("🚀 Testing VSCoq-style implementation...")
    
    try:
        # Start LSP server process
        process = subprocess.Popen([lsp_path], 
                                   stdin=subprocess.PIPE, 
                                   stdout=subprocess.PIPE, 
                                   stderr=subprocess.PIPE,
                                   text=True)
        
        # Send initialize
        msg = json.dumps(initialize_request)
        content_length = len(msg.encode('utf-8'))
        full_msg = f"Content-Length: {content_length}\r\n\r\n{msg}"
        
        print(f"📤 Sending initialize")
        process.stdin.write(full_msg)
        process.stdin.flush()
        
        # Read response
        time.sleep(1)
        
        # Send initialized notification
        initialized_notif = {
            "jsonrpc": "2.0", 
            "method": "initialized",
            "params": {}
        }
        msg = json.dumps(initialized_notif)
        content_length = len(msg.encode('utf-8'))
        full_msg = f"Content-Length: {content_length}\r\n\r\n{msg}"
        
        print(f"📤 Sending initialized")
        process.stdin.write(full_msg)
        process.stdin.flush()
        time.sleep(0.5)
        
        # Send did open
        msg = json.dumps(did_open_notification)
        content_length = len(msg.encode('utf-8'))
        full_msg = f"Content-Length: {content_length}\r\n\r\n{msg}"
        
        print(f"📤 Sending textDocument/didOpen")
        process.stdin.write(full_msg)
        process.stdin.flush()
        time.sleep(0.5)
        
        # Send interpret command
        msg = json.dumps(interpret_notification)
        content_length = len(msg.encode('utf-8'))
        full_msg = f"Content-Length: {content_length}\r\n\r\n{msg}"
        
        print(f"📤 Sending prover/interpretToPoint (VSCoq style)")
        process.stdin.write(full_msg)
        process.stdin.flush()
        
        # Wait for processing
        time.sleep(2)
        
        # Terminate and get stderr (where our debug output goes)
        process.terminate()
        stdout, stderr = process.communicate(timeout=5)
        
        print("\n🔍 VSCoq-style Debug output:")
        print("=" * 50)
        if stderr:
            print(stderr)
        else:
            print("(No debug output captured)")
        
        if stdout:
            print("\n📤 LSP server responses:")
            print("=" * 30)
            
            # Check if we get the proofView response
            if "prover/proofView" in stdout:
                print("✅ SUCCESS: Found prover/proofView notification!")
                # Extract and show the proof state
                lines = stdout.split('\n')
                for i, line in enumerate(lines):
                    if 'prover/proofView' in line:
                        print(f"Found at line {i}: {line}")
            else:
                print("❌ ERROR: No prover/proofView notification found")
            
            print(stdout)
            
    except Exception as e:
        print(f"❌ Error: {e}")
        if 'process' in locals():
            process.terminate()

if __name__ == "__main__":
    test_vscoq_style()