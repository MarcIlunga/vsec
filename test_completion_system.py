#!/usr/bin/env python3

"""
Test script for VsEc enhanced completion system
Tests various completion contexts and logs the results
"""

import json
import subprocess
import os
import sys
from pathlib import Path

def send_lsp_message(lsp_process, method, params, message_id=1):
    """Send LSP message and return response"""
    message = {
        "jsonrpc": "2.0",
        "id": message_id,
        "method": method,
        "params": params
    }
    
    message_str = json.dumps(message)
    content_length = len(message_str.encode('utf-8'))
    
    # Send LSP message with proper headers
    lsp_input = f"Content-Length: {content_length}\r\n\r\n{message_str}"
    
    print(f"🔹 Sending {method}: {params}")
    lsp_process.stdin.write(lsp_input.encode('utf-8'))
    lsp_process.stdin.flush()
    
    return True

def test_completion_contexts():
    """Test various completion contexts"""
    
    print("🚀 Starting VsEc Enhanced Completion System Test")
    print("=" * 60)
    
    # Start LSP server
    lsp_path = "/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp"
    if not os.path.exists(lsp_path):
        print(f"❌ LSP server not found at {lsp_path}")
        return False
        
    try:
        lsp_process = subprocess.Popen(
            [lsp_path], 
            stdin=subprocess.PIPE, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE,
            cwd="/home/marcilunga/dev/vsec"
        )
        
        print("✅ LSP server started")
        
        # 1. Initialize LSP
        print("\n📋 Test 1: LSP Initialization")
        init_params = {
            "processId": None,
            "rootPath": "/home/marcilunga/dev/vsec",
            "capabilities": {
                "textDocument": {
                    "completion": {
                        "completionItem": {
                            "snippetSupport": True,
                            "documentationFormat": ["markdown", "plaintext"]
                        }
                    }
                }
            }
        }
        send_lsp_message(lsp_process, "initialize", init_params, 1)
        
        # 2. Open test document
        print("\n📋 Test 2: Document Opening")
        test_file_uri = f"file:///home/marcilunga/dev/vsec/test_completion.ec"
        with open("/home/marcilunga/dev/vsec/test_completion.ec", "r") as f:
            test_content = f.read()
            
        open_params = {
            "textDocument": {
                "uri": test_file_uri,
                "languageId": "easycrypt",
                "version": 1,
                "text": test_content
            }
        }
        send_lsp_message(lsp_process, "textDocument/didOpen", open_params, 2)
        
        # 3. Test completion in various contexts
        completion_tests = [
            {
                "name": "Basic keyword completion",
                "position": {"line": 10, "character": 2},
                "description": "Should suggest EasyCrypt keywords"
            },
            {
                "name": "After 'require' completion", 
                "position": {"line": 32, "character": 8},
                "description": "Should suggest import and module names"
            },
            {
                "name": "Proof tactic completion",
                "position": {"line": 20, "character": 2},
                "description": "Should suggest proof tactics with confidence scores"
            },
            {
                "name": "After 'apply' completion",
                "position": {"line": 23, "character": 6},
                "description": "Should suggest lemma applications"
            },
            {
                "name": "Qualified name completion",
                "position": {"line": 25, "character": 13},
                "description": "Should suggest module members after dot"
            },
        ]
        
        for i, test in enumerate(completion_tests, 3):
            print(f"\n📋 Test {i}: {test['name']}")
            print(f"   Position: line {test['position']['line']}, char {test['position']['character']}")
            print(f"   Expected: {test['description']}")
            
            completion_params = {
                "textDocument": {"uri": test_file_uri},
                "position": test['position']
            }
            send_lsp_message(lsp_process, "textDocument/completion", completion_params, i)
        
        # Wait a bit for all responses
        print("\n⏳ Waiting for LSP responses...")
        import time
        time.sleep(3)
        
        # Read stderr to see our enhanced completion logs
        print("\n📊 LSP Server Debug Output:")
        print("-" * 40)
        
        # Non-blocking read of stderr
        try:
            stderr_output = lsp_process.stderr.read(8192).decode('utf-8', errors='replace')
            if stderr_output:
                print(stderr_output)
            else:
                print("No debug output captured")
        except:
            print("Could not read debug output")
            
        # Cleanup
        lsp_process.terminate()
        lsp_process.wait(timeout=5)
        
        print("\n✅ Completion system test completed")
        print("   Check the debug output above for enhanced completion details")
        
        return True
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        try:
            lsp_process.terminate()
        except:
            pass
        return False

if __name__ == "__main__":
    success = test_completion_contexts()
    sys.exit(0 if success else 1)