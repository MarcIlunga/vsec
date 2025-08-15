#!/usr/bin/env python3
import json
import subprocess
import time
import os

# Test the VSCoq-style implementation
def test():
    lsp_path = "/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp" 
    test_file = "/home/marcilunga/dev/vsec/test.ec"
    test_uri = f"file://{test_file}"
    
    print("🚀 Testing VSCoq-style implementation...")
    
    try:
        process = subprocess.Popen([lsp_path], 
                                   stdin=subprocess.PIPE, 
                                   stdout=subprocess.PIPE, 
                                   stderr=subprocess.PIPE, text=True)
        
        # Initialize
        init_req = {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":os.getpid(),"rootUri":f"file://{os.path.dirname(test_file)}","capabilities":{}}}
        msg = json.dumps(init_req)
        process.stdin.write(f"Content-Length: {len(msg.encode())}\r\n\r\n{msg}")
        process.stdin.flush()
        time.sleep(0.5)
        
        # Initialized
        init_notif = {"jsonrpc":"2.0","method":"initialized","params":{}}
        msg = json.dumps(init_notif)  
        process.stdin.write(f"Content-Length: {len(msg.encode())}\r\n\r\n{msg}")
        process.stdin.flush()
        time.sleep(0.5)
        
        # Did open
        open_notif = {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":test_uri,"languageId":"easycrypt","version":1,"text":open(test_file).read()}}}
        msg = json.dumps(open_notif)
        process.stdin.write(f"Content-Length: {len(msg.encode())}\r\n\r\n{msg}")
        process.stdin.flush()
        time.sleep(0.5)
        
        # Interpret to point
        interp_notif = {"jsonrpc":"2.0","method":"prover/interpretToPoint","params":{"textDocument":{"uri":test_uri,"version":1},"position":{"line":2,"character":10}}}
        msg = json.dumps(interp_notif)
        process.stdin.write(f"Content-Length: {len(msg.encode())}\r\n\r\n{msg}")
        process.stdin.flush()
        
        print("📤 Sent prover/interpretToPoint")
        time.sleep(2)
        
        process.terminate() 
        stdout, stderr = process.communicate(timeout=5)
        
        print("\n🔍 Debug output:")
        if stderr: print(stderr)
        
        if "prover/proofView" in stdout:
            print("✅ SUCCESS: Found prover/proofView!")
        else:
            print("❌ No prover/proofView found")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    test()