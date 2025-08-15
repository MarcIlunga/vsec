#!/usr/bin/env python3

import json
import subprocess
import time
import threading
import sys

def send_lsp_message(process, method, params, id_=None):
    """Send an LSP message to the process"""
    message = {
        "jsonrpc": "2.0",
        "method": method,
    }
    if params is not None:
        message["params"] = params
    if id_ is not None:
        message["id"] = id_
    
    message_json = json.dumps(message)
    content_length = len(message_json.encode('utf-8'))
    
    full_message = f"Content-Length: {content_length}\r\n\r\n{message_json}"
    
    print(f"SEND: {method}")
    print(f"CONTENT: {message_json}")
    
    process.stdin.write(full_message.encode('utf-8'))
    process.stdin.flush()

def read_lsp_responses(process):
    """Read and print LSP responses"""
    buffer = ""
    
    while True:
        try:
            # Read character by character to handle LSP protocol
            char = process.stdout.read(1).decode('utf-8')
            if not char:
                break
                
            buffer += char
            
            # Look for complete messages
            while "\r\n\r\n" in buffer:
                header_end = buffer.index("\r\n\r\n")
                header = buffer[:header_end]
                
                # Parse Content-Length
                content_length = 0
                for line in header.split("\r\n"):
                    if line.startswith("Content-Length:"):
                        content_length = int(line.split(":")[1].strip())
                        break
                
                # Check if we have the full message
                message_start = header_end + 4
                if len(buffer) >= message_start + content_length:
                    # Extract the message
                    message_data = buffer[message_start:message_start + content_length]
                    buffer = buffer[message_start + content_length:]
                    
                    try:
                        message = json.loads(message_data)
                        print(f"RECV: {json.dumps(message, indent=2)}")
                        print("-" * 50)
                        
                        # Check for proof view notifications
                        if message.get("method") == "vsec/proofView":
                            proof_state = message.get("params", {}).get("proofState")
                            if proof_state:
                                print("🎯 PROOF STATE RECEIVED!")
                                goals = proof_state.get("goals", [])
                                print(f"   Goals count: {len(goals)}")
                                if goals:
                                    for i, goal in enumerate(goals):
                                        print(f"   Goal {i+1}: {goal.get('goal', 'Unknown')}")
                            else:
                                print("⚠️ PROOF STATE IS NULL")
                        
                    except json.JSONDecodeError:
                        print(f"Failed to parse message: {message_data}")
                else:
                    # Don't have full message yet
                    break
                    
        except Exception as e:
            print(f"Error reading response: {e}")
            break

def main():
    # Start the LSP server
    lsp_binary = "/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp"
    print(f"Starting LSP server: {lsp_binary}")
    
    process = subprocess.Popen(
        [lsp_binary],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False  # Work with bytes for precise control
    )
    
    # Start reading responses in a separate thread
    response_thread = threading.Thread(target=read_lsp_responses, args=(process,))
    response_thread.daemon = True
    response_thread.start()
    
    try:
        # Initialize LSP
        print("Initializing LSP...")
        send_lsp_message(process, "initialize", {
            "processId": None,
            "clientInfo": {"name": "test-client"},
            "rootUri": f"file:///home/marcilunga/dev/vsec",
            "capabilities": {}
        }, 1)
        
        time.sleep(1)
        
        # Send initialized notification
        send_lsp_message(process, "initialized", {})
        time.sleep(0.5)
        
        # Open test document
        test_file_uri = "file:///home/marcilunga/dev/vsec/test_timing_fix.ec"
        with open("/home/marcilunga/dev/vsec/test_timing_fix.ec", "r") as f:
            file_content = f.read()
        
        print("Opening test document...")
        send_lsp_message(process, "textDocument/didOpen", {
            "textDocument": {
                "uri": test_file_uri,
                "languageId": "easycrypt",
                "version": 1,
                "text": file_content
            }
        })
        time.sleep(1)
        
        # Test interpretToPoint to execute until after the proof command
        print("Testing interpretToPoint...")
        send_lsp_message(process, "prover/interpretToPoint", {
            "textDocument": {"uri": test_file_uri},
            "position": {"line": 2, "character": 0}  # After "proof."
        })
        
        # Wait for processing
        time.sleep(3)
        
        print("Test completed. Check output above for timing behavior.")
        
    except KeyboardInterrupt:
        print("Test interrupted by user")
    except Exception as e:
        print(f"Test error: {e}")
    finally:
        process.terminate()
        process.wait()

if __name__ == "__main__":
    main()