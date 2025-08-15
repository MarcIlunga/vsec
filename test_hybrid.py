#!/usr/bin/env python3

"""
Quick test to verify hybrid architecture logs
"""

import subprocess
import time
import os

def test_hybrid_logs():
    print("🔍 Testing Hybrid Architecture Implementation")
    print("=" * 50)
    
    # Create test proof file
    test_content = """
lemma test_hybrid: true.
proof.
  trivial.
qed.
"""
    
    with open("test_hybrid.ec", "w") as f:
        f.write(test_content)
    
    # Start LSP server and capture stderr
    lsp_process = subprocess.Popen(
        ["/home/marcilunga/dev/vsec/vscode-extension/vsec-lsp"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, 
        stderr=subprocess.PIPE,
        text=True
    )
    
    try:
        # Send basic initialization
        init_msg = '''{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootPath":"/home/marcilunga/dev/vsec","capabilities":{}}}'''
        lsp_process.stdin.write(f"Content-Length: {len(init_msg)}\r\n\r\n{init_msg}")
        lsp_process.stdin.flush()
        
        # Wait a bit
        time.sleep(2)
        
        # Try to read stderr for our hybrid architecture logs
        try:
            lsp_process.terminate()
            stdout, stderr = lsp_process.communicate(timeout=3)
            
            print("🔍 Looking for hybrid architecture log messages:")
            print("-" * 30)
            
            hybrid_logs = [
                "🚀 Spawning EasyCrypt process",
                "Attempting hybrid goal extraction", 
                "EasyCrypt process spawned",
                "-emacs mode"
            ]
            
            found_logs = []
            for log in hybrid_logs:
                if log in stderr:
                    found_logs.append(log)
                    print(f"✅ Found: {log}")
                else:
                    print(f"❌ Missing: {log}")
            
            if found_logs:
                print(f"\n✅ Hybrid architecture is active! Found {len(found_logs)} log indicators")
            else:
                print("\n⚠️ No hybrid architecture logs found")
                print("Raw stderr sample:")
                print(stderr[:500])
                
        except:
            print("⚠️ Could not capture logs properly")
            
    finally:
        try:
            lsp_process.terminate()
            lsp_process.wait(timeout=2)
        except:
            lsp_process.kill()
        
        # Cleanup
        try:
            os.remove("test_hybrid.ec")
        except:
            pass

if __name__ == "__main__":
    test_hybrid_logs()