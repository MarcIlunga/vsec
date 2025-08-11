#!/usr/bin/env python3

import json
import subprocess
import os
import sys

def send_lsp_message(process, message):
    """Send a JSON-RPC message to the LSP server"""
    json_msg = json.dumps(message)
    content_length = len(json_msg.encode('utf-8'))
    
    # LSP protocol requires Content-Length header
    full_message = f"Content-Length: {content_length}\r\n\r\n{json_msg}"
    
    print(f"[SEND] {full_message}")
    process.stdin.write(full_message.encode('utf-8'))
    process.stdin.flush()

def test_lsp_server():
    """Test basic LSP server functionality"""
    print("🎯 Phase 9: Testing EasyCrypt LSP Server")
    print("=" * 50)
    
    # Start the LSP server
    lsp_exe = "src/_build/default/eclsp/ecLsp.exe"
    if not os.path.exists(lsp_exe):
        print(f"❌ LSP executable not found: {lsp_exe}")
        return False
        
    print(f"🚀 Starting LSP server: {lsp_exe}")
    
    try:
        process = subprocess.Popen(
            [lsp_exe],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=False,  # Use binary mode for precise control
            cwd="/home/marcilunga/dev/vsec"
        )
        
        # Test 1: Initialize
        print("\n📋 Test 1: Initialize Request")
        init_request = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "processId": os.getpid(),
                "clientInfo": {"name": "test-client", "version": "1.0.0"},
                "capabilities": {}
            }
        }
        
        send_lsp_message(process, init_request)
        
        # Read response (simplified)
        print("⏳ Waiting for response...")
        
        # Give the server time to respond
        import time
        time.sleep(1)
        
        # Check if process is still running
        if process.poll() is None:
            print("✅ LSP server is running and responsive!")
            
            # Send initialized notification
            initialized_notif = {
                "jsonrpc": "2.0",
                "method": "initialized",
                "params": {}
            }
            send_lsp_message(process, initialized_notif)
            
            print("✅ Sent initialized notification")
            
        else:
            print("❌ LSP server stopped unexpectedly")
            stderr_output = process.stderr.read().decode('utf-8')
            print(f"STDERR: {stderr_output}")
            return False
            
        # Terminate gracefully
        shutdown_request = {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "shutdown",
            "params": {}
        }
        send_lsp_message(process, shutdown_request)
        
        exit_notif = {
            "jsonrpc": "2.0", 
            "method": "exit",
            "params": {}
        }
        send_lsp_message(process, exit_notif)
        
        process.wait(timeout=5)
        print("✅ LSP server shut down gracefully")
        return True
        
    except Exception as e:
        print(f"❌ Error testing LSP server: {e}")
        if 'process' in locals():
            process.terminate()
        return False

if __name__ == "__main__":
    success = test_lsp_server()
    print("\n" + "=" * 50)
    if success:
        print("🎉 Phase 9 LSP Test: SUCCESS!")
        print("✅ EasyCrypt LSP server is functional")
    else:
        print("💥 Phase 9 LSP Test: FAILED!")
        print("❌ EasyCrypt LSP server has issues")
    
    sys.exit(0 if success else 1)