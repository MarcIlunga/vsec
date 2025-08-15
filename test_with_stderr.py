#!/usr/bin/env python3

import json
import subprocess
import time
import threading
import sys
import select

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
    
    process.stdin.write(full_message.encode('utf-8'))
    process.stdin.flush()

def read_stderr(process):
    """Read stderr output"""
    while True:
        try:
            line = process.stderr.readline()
            if not line:
                break
            print(f"STDERR: {line.decode('utf-8').rstrip()}")
        except:
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
        text=False
    )
    
    # Start reading stderr in a separate thread
    stderr_thread = threading.Thread(target=read_stderr, args=(process,))
    stderr_thread.daemon = True
    stderr_thread.start()
    
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
        time.sleep(2)
        
        # Test interpretToPoint to execute until after the proof command
        print("Testing interpretToPoint...")
        send_lsp_message(process, "prover/interpretToPoint", {
            "textDocument": {"uri": test_file_uri, "version": 1},
            "position": {"line": 1, "character": 6}  # Right after "proof."
        })
        
        # Wait for processing and check stderr
        print("Waiting for processing...")
        time.sleep(5)
        
        print("Test completed. Check stderr output above.")
        
    except KeyboardInterrupt:
        print("Test interrupted by user")
    except Exception as e:
        print(f"Test error: {e}")
    finally:
        process.terminate()
        process.wait()

if __name__ == "__main__":
    main()