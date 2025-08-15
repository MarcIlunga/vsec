#!/usr/bin/env python3

"""
Debug script to capture both stdout and stderr from LSP server
to see if ExecutionManager debug messages are appearing
"""

import json
import subprocess
import sys
import time
import threading
import select
from pathlib import Path

def send_lsp_message(stdin, message):
    """Send an LSP message to the server"""
    content = json.dumps(message)
    header = f"Content-Length: {len(content)}\r\n\r\n"
    full_message = header + content
    
    print(f"📤 SENDING: {message}")
    stdin.write(full_message.encode())
    stdin.flush()

def read_output(pipe, label):
    """Read output from pipe and print with label"""
    while True:
        try:
            line = pipe.readline()
            if not line:
                break
            
            line = line.decode('utf-8', errors='ignore').strip()
            if line:
                print(f"[{label}] {line}")
                
                # Look for our ExecutionManager debug messages
                if '🚀 EasyCrypt: Executing' in line:
                    print(f"✅ FOUND EXECUTION DEBUG: {line}")
                elif 'EasyCrypt: Command executed' in line:
                    print(f"✅ FOUND SUCCESS DEBUG: {line}")
                elif 'EasyCrypt execution failed' in line:
                    print(f"❌ FOUND ERROR DEBUG: {line}")
                elif 'proofState' in line:
                    print(f"🎯 PROOF STATE: {line}")
                        
        except Exception as e:
            print(f"Error reading {label}: {e}")
            break

def test_with_debug():
    """Test with full debug output capture"""
    
    print("🚀 Starting VsEc LSP server with debug capture...")
    process = subprocess.Popen(
        ['/home/marcilunga/dev/vsec/src/_build/default/eclsp/ecLsp.exe'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, 
        stderr=subprocess.PIPE,
        cwd='/home/marcilunga/dev/vsec',
        bufsize=0  # Unbuffered
    )
    
    # Start reading both stdout and stderr
    stdout_thread = threading.Thread(target=read_output, args=(process.stdout, "STDOUT"))
    stderr_thread = threading.Thread(target=read_output, args=(process.stderr, "STDERR"))
    stdout_thread.daemon = True
    stderr_thread.daemon = True
    stdout_thread.start()
    stderr_thread.start()
    
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
        
        # Open a very simple test document
        print("📄 Opening simple test document...")
        simple_content = "require import AllCore."
        
        send_lsp_message(process.stdin, {
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": "file:///home/marcilunga/dev/vsec/simple_test.ec",
                    "languageId": "easycrypt",
                    "version": 1,
                    "text": simple_content
                }
            }
        })
        
        time.sleep(1)
        
        # Wait longer for parsing events to be processed
        print("⏳ Waiting for parsing events to complete...")
        time.sleep(3)
        
        # Send Step Forward command 
        print("⏩ Sending Step Forward command...")
        send_lsp_message(process.stdin, {
            "jsonrpc": "2.0",
            "method": "prover/stepForward",
            "params": {
                "textDocument": {
                    "uri": "file:///home/marcilunga/dev/vsec/simple_test.ec",
                    "version": 1
                }
            }
        })
        
        # Wait longer to see all debug output
        print("⏳ Waiting for execution results and debug messages...")
        time.sleep(5)
        
        print("🏁 Test completed - check output above for debug messages")
        
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
    # Create simple test file
    with open('/home/marcilunga/dev/vsec/simple_test.ec', 'w') as f:
        f.write('require import AllCore.')
    
    test_with_debug()