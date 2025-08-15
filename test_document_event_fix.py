#!/usr/bin/env python3
"""Test the DocumentEvent handler fix for ParseEvent processing"""

import subprocess
import json
import time
import sys

def send_lsp_request(lsp_process, request):
    """Send a JSON-RPC request to LSP server"""
    message = json.dumps(request)
    content_length = len(message.encode('utf-8'))
    full_message = f"Content-Length: {content_length}\r\n\r\n{message}"
    
    print(f">> SENDING: {full_message}", file=sys.stderr)
    lsp_process.stdin.write(full_message.encode('utf-8'))
    lsp_process.stdin.flush()
    return True

def read_lsp_response(lsp_process):
    """Read a JSON-RPC response from LSP server"""
    try:
        # Read headers
        headers = {}
        while True:
            line = lsp_process.stdout.readline().decode('utf-8')
            if line == '\r\n':
                break
            if ':' in line:
                key, value = line.strip().split(':', 1)
                headers[key] = value.strip()
        
        # Read content
        if 'Content-Length' in headers:
            content_length = int(headers['Content-Length'])
            content = lsp_process.stdout.read(content_length).decode('utf-8')
            print(f"<< RECEIVED: Content-Length: {content_length}\\r\\n\\r\\n{content}", file=sys.stderr)
            return json.loads(content)
    except Exception as e:
        print(f"Error reading response: {e}", file=sys.stderr)
        return None

def test_document_event_processing():
    """Test that DocumentEvents (specifically ParseEvents) are now processed"""
    
    # Start LSP server
    lsp_binary = "/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp"
    print(f"🚀 Testing DocumentEvent processing with: {lsp_binary}", file=sys.stderr)
    
    lsp_process = subprocess.Popen(
        [lsp_binary],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False
    )
    
    try:
        # Initialize
        initialize_request = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "processId": None,
                "capabilities": {},
                "workspaceFolders": None
            }
        }
        
        if not send_lsp_request(lsp_process, initialize_request):
            return False
            
        # Read initialize response
        response = read_lsp_response(lsp_process)
        print(f"Initialize response: {response}", file=sys.stderr)
        
        # Send initialized notification
        initialized_request = {
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": {}
        }
        send_lsp_request(lsp_process, initialized_request)
        
        # Open document with EasyCrypt content
        test_content = """lemma test : forall (x : bool), x \/ !x.
proof.
  trivial.
qed."""
        
        text_document_open = {
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": "file:///test.ec",
                    "languageId": "easycrypt",
                    "version": 1,
                    "text": test_content
                }
            }
        }
        
        print("📝 Opening document to trigger parsing...", file=sys.stderr)
        send_lsp_request(lsp_process, text_document_open)
        
        # Wait for parsing to complete
        time.sleep(2)
        
        # Now test Step Forward - this should work if ParseEvents are processed
        step_forward_notification = {
            "jsonrpc": "2.0",
            "method": "prover/stepForward",
            "params": {
                "textDocument": {
                    "uri": "file:///test.ec",
                    "version": 1
                }
            }
        }
        
        print("🎯 Sending Step Forward command...", file=sys.stderr)
        send_lsp_request(lsp_process, step_forward_notification)
        
        # Give time for processing and look for expected debug messages
        time.sleep(3)
        
        print("✅ Test completed - check debug output for ParseEvent processing", file=sys.stderr)
        return True
        
    except Exception as e:
        print(f"❌ Test failed: {e}", file=sys.stderr)
        return False
    finally:
        lsp_process.terminate()
        stderr_output = lsp_process.stderr.read().decode('utf-8')
        print(f"LSP stderr output:\n{stderr_output}", file=sys.stderr)

if __name__ == "__main__":
    test_document_event_processing()