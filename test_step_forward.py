#!/usr/bin/env python3

"""
Test script to verify EasyCrypt interactive proving Step Forward functionality.
Tests the complete pipeline: TypeScript → LSP → DocumentManager → ExecutionManager → EcCommands
"""

import json
import subprocess
import sys
import time
import threading
from pathlib import Path

def send_lsp_message(stdin, message):
    """Send an LSP message to the server"""
    content = json.dumps(message)
    header = f"Content-Length: {len(content)}\r\n\r\n"
    full_message = header + content
    
    print(f"📤 SENDING: {message}")
    stdin.write(full_message.encode())
    stdin.flush()

def read_lsp_response(stdout):
    """Read LSP responses from stdout"""
    while True:
        try:
            line = stdout.readline()
            if not line:
                break
            
            line = line.decode('utf-8', errors='ignore').strip()
            if line:
                print(f"📥 RECEIVED: {line}")
                
                # Look for proof state responses
                if 'proofState' in line:
                    print(f"🎯 PROOF STATE FOUND: {line}")
                    if '"proofState": null' in line:
                        print("❌ PROOF STATE IS NULL - EXECUTION FAILED")
                    else:
                        print("✅ PROOF STATE HAS DATA - EXECUTION SUCCESS!")
                        
        except Exception as e:
            print(f"Error reading response: {e}")
            break

def test_step_forward():
    """Test Step Forward functionality end-to-end"""
    
    # Start the LSP server
    print("🚀 Starting VsEc LSP server...")
    process = subprocess.Popen(
        ['./vsec-lsp'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, 
        stderr=subprocess.PIPE,
        cwd='/home/marcilunga/dev/vsec/vscode-extension'
    )
    
    # Start reading responses in background
    response_thread = threading.Thread(target=read_lsp_response, args=(process.stdout,))
    response_thread.daemon = True
    response_thread.start()
    
    # Allow server to start
    time.sleep(1)
    
    try:
        # Initialize LSP
        print("📋 Initializing LSP...")
        send_lsp_message(process.stdin, {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "processId": None,
                "capabilities": {},
                "rootUri": f"file:///home/marcilunga/dev/vsec"
            }
        })
        
        time.sleep(0.5)
        
        # Send initialized notification
        send_lsp_message(process.stdin, {
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": {}
        })
        
        time.sleep(0.5)
        
        # Open test document
        print("📄 Opening test document...")
        test_file = "file:///home/marcilunga/dev/vsec/test_execution.ec"
        
        # Read file content
        with open('/home/marcilunga/dev/vsec/test_execution.ec', 'r') as f:
            file_content = f.read()
        
        send_lsp_message(process.stdin, {
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": test_file,
                    "languageId": "easycrypt",
                    "version": 1,
                    "text": file_content
                }
            }
        })
        
        time.sleep(1)
        
        # Send Step Forward command 
        print("⏩ Sending Step Forward command...")
        send_lsp_message(process.stdin, {
            "jsonrpc": "2.0",
            "method": "prover/stepForward",
            "params": {
                "textDocument": {
                    "uri": test_file,
                    "version": 1
                }
            }
        })
        
        # Wait for responses
        print("⏳ Waiting for execution results...")
        time.sleep(3)
        
        # Send a second Step Forward to test multiple steps
        print("⏩ Sending second Step Forward command...")
        send_lsp_message(process.stdin, {
            "jsonrpc": "2.0",
            "method": "prover/stepForward", 
            "params": {
                "textDocument": {
                    "uri": test_file,
                    "version": 1
                }
            }
        })
        
        time.sleep(3)
        
        print("✅ Test completed - check output above for execution results")
        
    except Exception as e:
        print(f"💥 Test failed: {e}")
    
    finally:
        # Cleanup
        try:
            process.terminate()
            process.wait(timeout=5)
        except:
            process.kill()

if __name__ == "__main__":
    test_step_forward()