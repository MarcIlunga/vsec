#!/usr/bin/env python3

import json
import subprocess
import sys
import time

def send_lsp_message(process, message):
    """Send a JSON-RPC message to the LSP server"""
    json_message = json.dumps(message)
    content_length = len(json_message.encode('utf-8'))
    
    full_message = f"Content-Length: {content_length}\r\n\r\n{json_message}"
    
    print(f"SENDING: {full_message}", file=sys.stderr)
    process.stdin.write(full_message.encode('utf-8'))
    process.stdin.flush()

def read_lsp_response(process):
    """Read a JSON-RPC response from the LSP server"""
    # Read Content-Length header
    line = process.stdout.readline().decode('utf-8')
    if not line.startswith('Content-Length:'):
        return None
    
    content_length = int(line.split(':')[1].strip())
    
    # Read empty line
    process.stdout.readline()
    
    # Read the JSON content
    content = process.stdout.read(content_length).decode('utf-8')
    print(f"RECEIVED: {content}", file=sys.stderr)
    
    return json.loads(content)

def test_lsp_server():
    """Test the LSP server with a simple stepForward command"""
    
    # Start the LSP server
    lsp_path = "/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp"
    process = subprocess.Popen(
        [lsp_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False
    )
    
    try:
        # Send initialize request
        initialize_msg = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "processId": None,
                "clientInfo": {"name": "test-client"},
                "capabilities": {},
                "workspaceFolders": [{"uri": "file:///home/marcilunga/dev/vsec", "name": "test"}]
            }
        }
        
        send_lsp_message(process, initialize_msg)
        response = read_lsp_response(process)
        print(f"Initialize response: {response}")
        
        # Send initialized notification
        initialized_msg = {
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": {}
        }
        send_lsp_message(process, initialized_msg)
        
        # Send stepForward notification
        stepforward_msg = {
            "jsonrpc": "2.0",
            "method": "prover/stepForward",
            "params": {
                "textDocument": {
                    "uri": "file:///home/marcilunga/dev/vsec/test_fixed.ec",
                    "version": 1
                }
            }
        }
        
        send_lsp_message(process, stepforward_msg)
        
        # Wait for any notifications
        time.sleep(2)
        
        # Try to read any responses
        try:
            while True:
                response = read_lsp_response(process)
                if response is None:
                    break
                print(f"Response: {response}")
        except:
            pass
            
    finally:
        process.terminate()
        stderr_output = process.stderr.read().decode('utf-8')
        print(f"LSP STDERR: {stderr_output}", file=sys.stderr)

if __name__ == "__main__":
    test_lsp_server()