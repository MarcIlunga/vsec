#!/usr/bin/env python3

"""
Debug script to test EasyCrypt proof state extraction
Creates a simple proof and checks what we can extract
"""

import json
import subprocess
import os
import time

def test_easycrypt_goal_extraction():
    """Test what we can extract from EasyCrypt proof states"""
    
    print("🔍 Testing EasyCrypt Goal Extraction")
    print("=" * 50)
    
    # Create a simple test file with a proof
    test_file = "debug_proof.ec"
    test_content = """
lemma simple_test: true.
proof.
  trivial.
qed.

lemma complex_test: forall (x: bool), x = x.
proof.
  intros x.
  (* We should be able to extract the goal here *)
"""
    
    with open(test_file, "w") as f:
        f.write(test_content)
    
    print(f"📄 Created test file: {test_file}")
    
    # Start LSP and open the document
    lsp_path = "/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp"
    
    try:
        lsp_process = subprocess.Popen(
            [lsp_path], 
            stdin=subprocess.PIPE, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE,
            cwd="/home/marcilunga/dev/vsec"
        )
        
        # Initialize LSP
        init_message = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "processId": None,
                "rootPath": "/home/marcilunga/dev/vsec",
                "capabilities": {}
            }
        }
        
        message_str = json.dumps(init_message)
        content_length = len(message_str.encode('utf-8'))
        lsp_input = f"Content-Length: {content_length}\r\n\r\n{message_str}"
        
        print("🚀 Starting LSP and initializing...")
        lsp_process.stdin.write(lsp_input.encode('utf-8'))
        lsp_process.stdin.flush()
        
        # Open document
        file_uri = f"file:///home/marcilunga/dev/vsec/{test_file}"
        open_message = {
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": file_uri,
                    "languageId": "easycrypt",
                    "version": 1,
                    "text": test_content
                }
            }
        }
        
        message_str = json.dumps(open_message)
        content_length = len(message_str.encode('utf-8'))
        lsp_input = f"Content-Length: {content_length}\r\n\r\n{message_str}"
        
        print("📄 Opening test document...")
        lsp_process.stdin.write(lsp_input.encode('utf-8'))
        lsp_process.stdin.flush()
        
        # Try to step to the point where we have a goal
        step_message = {
            "jsonrpc": "2.0",
            "method": "prover/stepForward",
            "params": {
                "textDocument": {"uri": file_uri},
                "position": {"line": 7, "character": 11}  # After "intros x."
            }
        }
        
        message_str = json.dumps(step_message)
        content_length = len(message_str.encode('utf-8'))
        lsp_input = f"Content-Length: {content_length}\r\n\r\n{message_str}"
        
        print("🎯 Stepping forward to create proof goal...")
        lsp_process.stdin.write(lsp_input.encode('utf-8'))
        lsp_process.stdin.flush()
        
        # Wait for processing
        print("⏳ Waiting for LSP processing...")
        time.sleep(3)
        
        # Read stderr for debug output
        print("\n📊 LSP Debug Output:")
        print("-" * 30)
        
        try:
            stderr_output = lsp_process.stderr.read(16384).decode('utf-8', errors='replace')
            if stderr_output:
                # Filter for our debug messages
                lines = stderr_output.split('\n')
                for line in lines:
                    if any(keyword in line for keyword in ['DEBUG:', 'Found extended goal', 'Successfully accessed', 'Goal extraction']):
                        print(line)
            else:
                print("No debug output captured")
        except:
            print("Could not read debug output")
            
        # Cleanup
        lsp_process.terminate()
        try:
            lsp_process.wait(timeout=2)
        except:
            lsp_process.kill()
            
        # Remove test file
        try:
            os.remove(test_file)
        except:
            pass
            
        print(f"\n✅ Debug test completed")
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        return False

if __name__ == "__main__":
    test_easycrypt_goal_extraction()