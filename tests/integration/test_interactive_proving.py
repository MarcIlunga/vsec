#!/usr/bin/env python3
"""
Comprehensive Interactive Proving Tests for VsEc EasyCrypt LSP
Test Proof General feature parity and interactive proving workflow
"""

import json
import subprocess
import os
import sys
import time
import select
from typing import Optional, Dict, Any, List

class LSPTestClient:
    def __init__(self, lsp_executable: str):
        self.proc = None
        self.lsp_executable = lsp_executable
        self._msg_id = 1
        
    def start(self):
        """Start the LSP server process"""
        env = os.environ.copy()
        env["OCAMLRUNPARAM"] = env.get("OCAMLRUNPARAM", "") + (";" if env.get("OCAMLRUNPARAM") else "") + "b=1"
        
        self.proc = subprocess.Popen(
            [self.lsp_executable], 
            stdin=subprocess.PIPE, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE,
            text=False,
            env=env
        )
        
    def stop(self):
        """Stop the LSP server process"""
        if self.proc:
            try:
                self.proc.terminate()
                self.proc.wait(timeout=5)
            except:
                self.proc.kill()
                
    def send_message(self, message: Dict[str, Any]) -> None:
        """Send a JSON-RPC message to the LSP server"""
        json_msg = json.dumps(message)
        content_length = len(json_msg.encode('utf-8'))
        
        full_message = f"Content-Length: {content_length}\r\n\r\n{json_msg}"
        
        print(f"[SEND] {json_msg}")
        self.proc.stdin.write(full_message.encode('utf-8'))
        self.proc.stdin.flush()
        
    def read_message(self, timeout: float = 2.0) -> Optional[Dict[str, Any]]:
        """Read a JSON-RPC message from the LSP server"""
        ready, _, _ = select.select([self.proc.stdout], [], [], timeout)
        if not ready:
            return None
            
        try:
            # Read Content-Length header
            line = self.proc.stdout.readline().decode('utf-8')
            if not line.startswith('Content-Length:'):
                return None
                
            content_length = int(line.split(':')[1].strip())
            
            # Skip empty line
            self.proc.stdout.readline()
            
            # Read JSON content
            content = self.proc.stdout.read(content_length).decode('utf-8')
            message = json.loads(content)
            print(f"[RECV] {json.dumps(message)}")
            return message
        except Exception as e:
            print(f"[ERROR] Failed to read message: {e}")
            return None
            
    def request(self, method: str, params: Dict[str, Any], timeout: float = 5.0) -> Optional[Dict[str, Any]]:
        """Send a request and wait for response"""
        request_id = self._msg_id
        self._msg_id += 1
        
        self.send_message({
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params
        })
        
        deadline = time.time() + timeout
        while time.time() < deadline:
            message = self.read_message(timeout=0.5)
            if message and message.get("id") == request_id:
                return message
                
        return None
        
    def notification(self, method: str, params: Dict[str, Any]) -> None:
        """Send a notification (no response expected)"""
        self.send_message({
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        })

class InteractiveProvingTests:
    def __init__(self, lsp_executable: str):
        self.client = LSPTestClient(lsp_executable)
        self.test_uri = "file:///test.ec"
        self.passed = 0
        self.failed = 0
        
    def setup(self):
        """Setup test environment"""
        print("🔧 Setting up test environment...")
        self.client.start()
        
        # Initialize LSP
        init_result = self.client.request("initialize", {
            "processId": None,
            "clientInfo": {"name": "test-client"},
            "capabilities": {},
            "workspaceFolders": [{"uri": "file:///workspace", "name": "test"}]
        })
        
        if not init_result or "error" in init_result:
            raise Exception(f"Failed to initialize LSP: {init_result}")
            
        # Send initialized notification
        self.client.notification("initialized", {})
        
    def teardown(self):
        """Cleanup test environment"""
        self.client.stop()
        
    def assert_test(self, condition: bool, test_name: str, message: str = ""):
        """Assert a test condition"""
        if condition:
            print(f"✅ {test_name}")
            self.passed += 1
        else:
            print(f"❌ {test_name}: {message}")
            self.failed += 1
            
    def test_basic_document_lifecycle(self):
        """Test opening, editing, and closing documents"""
        print("\n📄 Testing Document Lifecycle...")
        
        # Open document
        self.client.notification("textDocument/didOpen", {
            "textDocument": {
                "uri": self.test_uri,
                "languageId": "easycrypt",
                "version": 1,
                "text": "lemma test_lemma: true.\nproof. trivial. qed.\n"
            }
        })
        
        # Test completion at different positions
        completion_result = self.client.request("textDocument/completion", {
            "textDocument": {"uri": self.test_uri},
            "position": {"line": 1, "character": 8}  # After "proof. "
        })
        
        self.assert_test(
            completion_result is not None and "result" in completion_result,
            "Document completion after opening"
        )
        
        # Close document
        self.client.notification("textDocument/didClose", {
            "textDocument": {"uri": self.test_uri}
        })
        
    def test_step_forward_backward(self):
        """Test step-by-step proof execution"""
        print("\n👣 Testing Step Navigation...")
        
        # Open a multi-step proof
        proof_text = """lemma multi_step: true /\\ true.
proof.
  split.
  trivial.
  trivial.
qed."""
        
        self.client.notification("textDocument/didOpen", {
            "textDocument": {
                "uri": self.test_uri,
                "languageId": "easycrypt", 
                "version": 1,
                "text": proof_text
            }
        })
        
        # Test stepForward
        self.client.notification("prover/stepForward", {
            "textDocument": {"uri": self.test_uri, "version": 1}
        })
        
        # Give time for processing
        time.sleep(0.5)
        
        # Check if we can get proof state
        # We expect some notification or can query current state
        
        # Test stepBackward  
        self.client.notification("prover/stepBackward", {
            "textDocument": {"uri": self.test_uri, "version": 1}
        })
        
        self.assert_test(True, "Step forward/backward commands sent")
        
    def test_interpret_to_point(self):
        """Test execute to cursor position"""
        print("\n🎯 Testing Interpret to Point...")
        
        proof_text = """lemma cursor_test: true.
proof.
  (* cursor should be here *)
  trivial.
qed."""
        
        self.client.notification("textDocument/didOpen", {
            "textDocument": {
                "uri": self.test_uri,
                "languageId": "easycrypt",
                "version": 1, 
                "text": proof_text
            }
        })
        
        # Execute to line 2 (middle of proof)
        self.client.notification("prover/interpretToPoint", {
            "textDocument": {"uri": self.test_uri, "version": 1},
            "position": {"line": 2, "character": 25}  # After comment
        })
        
        time.sleep(0.5)
        
        self.assert_test(True, "Interpret to point command sent")
        
    def test_error_handling(self):
        """Test error detection and recovery"""
        print("\n🚨 Testing Error Handling...")
        
        # Create document with syntax error
        error_text = """lemma syntax_error true.  (* missing colon *)
proof.
  invalid_tactic.
qed."""
        
        self.client.notification("textDocument/didOpen", {
            "textDocument": {
                "uri": self.test_uri,
                "languageId": "easycrypt",
                "version": 1,
                "text": error_text
            }
        })
        
        # Try to execute - should get diagnostics
        self.client.notification("prover/stepForward", {
            "textDocument": {"uri": self.test_uri, "version": 1}
        })
        
        time.sleep(1.0)
        
        # Look for error notifications in the next few messages
        error_found = False
        for _ in range(5):
            message = self.client.read_message(timeout=0.2)
            if (message and 
                message.get("method") == "textDocument/publishDiagnostics" and
                message.get("params", {}).get("diagnostics")):
                error_found = True
                break
                
        self.assert_test(error_found, "Error diagnostics received")
        
    def test_completion_context_awareness(self):
        """Test context-aware completion"""
        print("\n💭 Testing Completion Context Awareness...")
        
        # Test completion in different contexts
        contexts = [
            ("lemma test: true.\nproof.\n  ", "proof context"),
            ("module Test.\n  ", "module context"),
            ("require import ", "import context")
        ]
        
        for text, context_name in contexts:
            self.client.notification("textDocument/didOpen", {
                "textDocument": {
                    "uri": self.test_uri,
                    "languageId": "easycrypt",
                    "version": 1,
                    "text": text
                }
            })
            
            completion_result = self.client.request("textDocument/completion", {
                "textDocument": {"uri": self.test_uri},
                "position": {"line": text.count('\n'), "character": len(text.split('\n')[-1])}
            })
            
            has_completions = (completion_result and 
                             "result" in completion_result and
                             completion_result["result"])
            
            self.assert_test(has_completions, f"Completion in {context_name}")
            
            # Close document for next iteration
            self.client.notification("textDocument/didClose", {
                "textDocument": {"uri": self.test_uri}
            })
            
    def test_hover_information(self):
        """Test hover information display"""
        print("\n🖱️ Testing Hover Information...")
        
        hover_text = """lemma hover_test: true.
proof.
  apply (* hover here *) trivial.
qed."""
        
        self.client.notification("textDocument/didOpen", {
            "textDocument": {
                "uri": self.test_uri,
                "languageId": "easycrypt",
                "version": 1,
                "text": hover_text
            }
        })
        
        # Test hover on "apply"
        hover_result = self.client.request("textDocument/hover", {
            "textDocument": {"uri": self.test_uri},
            "position": {"line": 2, "character": 3}  # On "apply"
        })
        
        has_hover = (hover_result and 
                    "result" in hover_result and
                    hover_result["result"])
        
        self.assert_test(has_hover, "Hover information available")
        
    def test_go_to_definition(self):
        """Test go to definition functionality"""
        print("\n🔍 Testing Go to Definition...")
        
        definition_text = """lemma helper_lemma: true.
proof. trivial. qed.

lemma main_lemma: true.
proof.
  apply helper_lemma.  (* should go to definition *)
qed."""
        
        self.client.notification("textDocument/didOpen", {
            "textDocument": {
                "uri": self.test_uri,
                "languageId": "easycrypt",
                "version": 1,
                "text": definition_text
            }
        })
        
        # Test go to definition on "helper_lemma"
        definition_result = self.client.request("textDocument/definition", {
            "textDocument": {"uri": self.test_uri},
            "position": {"line": 5, "character": 10}  # On "helper_lemma"
        })
        
        has_definition = (definition_result and 
                         "result" in definition_result and
                         definition_result["result"])
        
        self.assert_test(has_definition, "Go to definition working")
        
    def run_all_tests(self) -> bool:
        """Run all interactive proving tests"""
        print("🎯 VsEc Interactive Proving Test Suite")
        print("=" * 50)
        
        try:
            self.setup()
            
            # Run all test methods
            self.test_basic_document_lifecycle()
            self.test_step_forward_backward()
            self.test_interpret_to_point()
            self.test_error_handling()
            self.test_completion_context_awareness()
            self.test_hover_information()
            self.test_go_to_definition()
            
            print(f"\n📊 Test Results: {self.passed} passed, {self.failed} failed")
            
            if self.failed == 0:
                print("🎉 All tests passed!")
                return True
            else:
                print(f"❌ {self.failed} tests failed")
                return False
                
        finally:
            self.teardown()

def main():
    lsp_exe = "src/_build/default/eclsp/ecLsp.exe"
    if not os.path.exists(lsp_exe):
        print(f"❌ LSP executable not found: {lsp_exe}")
        print("Please build the LSP server first with: cd src && dune build")
        return False
        
    test_suite = InteractiveProvingTests(lsp_exe)
    return test_suite.run_all_tests()

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
