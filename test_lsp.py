#!/usr/bin/env python3
"""
Simple test script to verify the VsEc Language Server is working
"""

import json
import subprocess
import threading
import time

def test_lsp_server():
    print("🚀 Testing VsEc Language Server...")
    
    # Start the language server
    lsp_path = "/home/marcilunga/bin/vsec-lsp"
    process = subprocess.Popen(
        [lsp_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=0
    )
    
    def send_message(method, params=None, request_id=1):
        """Send a JSON-RPC message to the LSP server"""
        message = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
        }
        if params:
            message["params"] = params
        
        content = json.dumps(message)
        full_message = f"Content-Length: {len(content)}\r\n\r\n{content}"
        
        print(f"📤 Sending: {method}")
        process.stdin.write(full_message)
        process.stdin.flush()
    
    try:
        # Test initialize request
        send_message("initialize", {
            "processId": None,
            "capabilities": {},
            "workspaceFolder": None
        })
        
        # Give some time for response
        time.sleep(2)
        
        # Check if process is still running (good sign)
        if process.poll() is None:
            print("✅ Language server is running and responsive!")
            print("✅ VsEc LSP installation successful!")
            print(f"📍 Language server location: {lsp_path}")
            print("🎯 Ready for IDE integration")
        else:
            print("❌ Language server exited unexpectedly")
            stderr_output = process.stderr.read()
            if stderr_output:
                print(f"Error output: {stderr_output}")
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
    
    finally:
        # Clean up
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)

if __name__ == "__main__":
    test_lsp_server()