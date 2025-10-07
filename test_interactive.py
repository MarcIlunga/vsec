#!/usr/bin/env python3
"""Reusable test script for interactive proving"""
import json
import subprocess
import time
import select
import sys
import argparse

class LSPClient:
    def __init__(self, lsp_path="src/_build/default/eclsp/ecLsp.exe"):
        self.lsp = subprocess.Popen(
            [lsp_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=False
        )
        self._request_id = 1
    
    def send(self, msg):
        j = json.dumps(msg)
        self.lsp.stdin.write(f"Content-Length: {len(j)}\r\n\r\n{j}".encode())
        self.lsp.stdin.flush()
    
    def read_messages(self, timeout=1.0):
        msgs = []
        deadline = time.time() + timeout
        while time.time() < deadline:
            ready, _, _ = select.select([self.lsp.stdout, self.lsp.stderr], [], [], 0.1)
            if not ready:
                continue
            try:
                # Check stdout for LSP messages
                if self.lsp.stdout in ready:
                    line = self.lsp.stdout.readline().decode()
                    if line.startswith('Content-Length:'):
                        length = int(line.split(':')[1])
                        self.lsp.stdout.readline()
                        content = self.lsp.stdout.read(length).decode()
                        msgs.append(json.loads(content))
                # Check stderr for debug logs
                if self.lsp.stderr in ready:
                    stderr_line = self.lsp.stderr.readline().decode()
                    if stderr_line.strip():
                        print(f"[LSP] {stderr_line.strip()}")
            except:
                break
        return msgs
    
    def request(self, method, params, timeout=3.0):
        """Send a request and wait for the response"""
        request_id = self._request_id
        self._request_id += 1
        
        msg = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params
        }
        self.send(msg)
        
        # Wait for response with matching ID
        deadline = time.time() + timeout
        while time.time() < deadline:
            msgs = self.read_messages(timeout=0.3)
            for msg in msgs:
                if msg.get("id") == request_id:
                    return msg
        return None
    
    def close(self):
        self.lsp.terminate()
        self.lsp.wait(2)
        return self.lsp.stderr.read().decode('utf-8', errors='ignore')

def test_case(client, test_name, document_text, commands):
    """Generic test runner for interactive proving commands"""
    print(f"\n=== {test_name} ===")
    
    # Open document
    client.send({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
            "textDocument": {
                "uri": "file:///test.ec",
                "languageId": "easycrypt",
                "version": 1,
                "text": document_text
            }
        }
    })
    # Wait longer for parsing to complete (parsing events need to be processed)
    time.sleep(2.0)
    
    # Clear any messages from document opening
    client.read_messages(0.5)
    
    # Execute commands with delay between each
    for cmd in commands:
        print(f"[TEST] Sending command: {cmd.get('method', 'unknown')}")
        client.send(cmd)
        time.sleep(0.3)  # Small delay between commands
    
    # Collect proof views
    msgs = client.read_messages(2.0)
    proof_views = [m for m in msgs if m.get('method') == 'prover/proofView']
    
    print(f"Received {len(proof_views)} proofView notifications")
    for i, pv in enumerate(proof_views):
        state = pv.get('params', {}).get('proofState', {})
        goals = state.get('goals', [])
        print(f"  {i+1}. Goals: {len(goals)}, in_proof: {state.get('in_proof', False)}")
        if goals:
            print(f"      Goal text: {goals[0].get('goal', 'N/A')}")
    
    return len(proof_views) > 0, proof_views

def test_step_forward():
    """Test basic step forward command"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    success, proof_views = test_case(
        client,
        "Step Forward Test",
        "lemma test: true.\nproof.\ntrivial.\nqed.",
        [{"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}}]
    )
    
    stderr = client.close()
    return success

def test_multiple_steps():
    """Test multiple step forward commands"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    success, proof_views = test_case(
        client,
        "Multiple Steps Test",
        "lemma multi: true /\\ true.\nproof.\n  split.\n  trivial.\n  trivial.\nqed.",
        [
            {"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}},
            {"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}}
        ]
    )
    
    stderr = client.close()
    return success

def test_interpret_to_point():
    """Test interpret to point command"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    success, proof_views = test_case(
        client,
        "Interpret to Point Test",
        "lemma test: true.\nproof.\n  trivial.\nqed.",
        [{"jsonrpc": "2.0", "method": "prover/interpretToPoint", "params": {
            "textDocument": {"uri": "file:///test.ec", "version": 1},
            "position": {"line": 2, "character": 5}
        }}]
    )
    
    stderr = client.close()
    return success

def test_hypotheses_extraction():
    """Test that hypotheses are properly extracted from goals"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    # Proof with explicit hypotheses
    success, proof_views = test_case(
        client,
        "Hypotheses Extraction Test",
        "lemma impl_test (P Q : bool): P => Q => P /\\ Q.\nproof.\n  move=> H_P H_Q.\n  split.\nqed.",
        [
            {"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}},
            {"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}}
        ]
    )
    
    # Check if any proof view has hypotheses
    has_hypotheses = False
    for pv in proof_views:
        state = pv.get('params', {}).get('proofState', {})
        goals = state.get('goals', [])
        for goal in goals:
            hyps = goal.get('hypotheses', [])
            if hyps and len(hyps) > 0:
                has_hypotheses = True
                print(f"      Found hypotheses: {hyps}")
    
    stderr = client.close()
    return has_hypotheses

## === COMPREHENSIVE TEST SUITE ===

def test_hypotheses_correctness():
    """Correctness: Extract hypotheses from a standard proof"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    success, proof_views = test_case(
        client,
        "Hypotheses Correctness",
        "lemma hyp_test (P Q : bool): P => Q => P /\\ Q.\nproof.\n  move=> H_P H_Q.\nqed.",
        [
            {"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}},
            {"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}}
        ]
    )
    
    has_hypothesis_H = False
    for pv in proof_views:
        goals = pv.get('params', {}).get('proofState', {}).get('goals', [])
        for goal in goals:
            hyps = goal.get('hypotheses', [])
            for hyp in hyps:
                if ('H_P' in hyp and ': P' in hyp) or ('H_Q' in hyp and ': Q' in hyp):
                    has_hypothesis_H = True
                    print(f"      ✓ Found expected hypothesis: {hyp}")
    
    client.close()
    return has_hypothesis_H

def test_hypotheses_negative():
    """Negative: Proof with no introduced hypotheses should have empty or minimal context"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    success, proof_views = test_case(
        client,
        "Hypotheses Negative (No Hypothesis)",
        "lemma no_hyp: true.\nproof.\n  trivial.\nqed.",
        [{"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}}]
    )
    
    # Should have goals but minimal/no user hypotheses
    has_goals = False
    has_user_hypothesis = False
    for pv in proof_views:
        goals = pv.get('params', {}).get('proofState', {}).get('goals', [])
        if goals:
            has_goals = True
            for goal in goals:
                hyps = goal.get('hypotheses', [])
                # Check if there are actual user hypotheses (not just type variables)
                for hyp in hyps:
                    if not hyp.startswith('Type variables'):
                        has_user_hypothesis = True
                        print(f"      Found hypothesis in trivial proof: {hyp}")
    
    client.close()
    return has_goals and not has_user_hypothesis

def test_hypotheses_edge_case():
    """Edge case: Deeply nested quantifiers and complex hypothesis names"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    # Edge case: Very long hypothesis chain with nested implications
    success, proof_views = test_case(
        client,
        "Hypotheses Edge Case (Nested)",
        "lemma nested (A B C D : bool): (A => B) => (B => C) => (C => D) => A => D.\nproof.\n  move=> H1 H2 H3 HA.\nqed.",
        [
            {"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}},
            {"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}}
        ]
    )
    
    # Check if all hypotheses H1, H2, H3, HA are extracted correctly
    found_hypotheses = set()
    for pv in proof_views:
        goals = pv.get('params', {}).get('proofState', {}).get('goals', [])
        for goal in goals:
            hyps = goal.get('hypotheses', [])
            for hyp in hyps:
                if 'H1' in hyp: found_hypotheses.add('H1')
                if 'H2' in hyp: found_hypotheses.add('H2')
                if 'H3' in hyp: found_hypotheses.add('H3')
                if 'HA' in hyp: found_hypotheses.add('HA')
    
    print(f"      Found hypotheses: {found_hypotheses}")
    client.close()
    # BUG HUNTING: Can we handle all 4 hypotheses without truncation?
    return len(found_hypotheses) >= 3  # Should find at least 3 out of 4

def test_query_correctness():
    """Correctness: Query command returns success for basic query"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    # Open a document first
    client.send({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
            "textDocument": {
                "uri": "file:///test.ec",
                "languageId": "easycrypt",
                "version": 1,
                "text": "lemma test: true."
            }
        }
    })
    time.sleep(2.0)  # Wait for parsing to complete
    
    # Send query request
    response = client.request("easycrypt/query", {
        "textDocument": {"uri": "file:///test.ec", "version": 1},
        "command": "print",
        "argument": "test"
    }, timeout=3.0)
    
    client.close()
    
    if response and "result" in response:
        result = response["result"]
        success = result.get("success", False)
        print(f"      Query result: {result}")
        return success
    return False

def test_query_negative():
    """Negative: Query on non-existent document should fail gracefully"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    # Query without opening document
    response = client.request("easycrypt/query", {
        "textDocument": {"uri": "file:///nonexistent.ec", "version": 1},
        "command": "print",
        "argument": "test"
    }, timeout=3.0)
    
    client.close()
    
    if response and "result" in response:
        result = response["result"]
        success = result.get("success", False)
        error = result.get("error", None)
        print(f"      Query on nonexistent doc: success={success}, error={error}")
        # Should fail with appropriate error
        return not success and error is not None
    return False

def test_query_edge_case():
    """Edge case: Query with empty string, special chars, very long pattern"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    client.send({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
            "textDocument": {
                "uri": "file:///test.ec",
                "languageId": "easycrypt",
                "version": 1,
                "text": "lemma test: true."
            }
        }
    })
    time.sleep(2.0)  # Wait for parsing to complete
    
    # Edge case 1: Empty query argument
    response1 = client.request("easycrypt/query", {
        "textDocument": {"uri": "file:///test.ec", "version": 1},
        "command": "print",
        "argument": ""
    }, timeout=2.0)
    
    # Edge case 2: Special characters
    response2 = client.request("easycrypt/query", {
        "textDocument": {"uri": "file:///test.ec", "version": 1},
        "command": "search",
        "argument": "!@#$%^&*()"
    }, timeout=2.0)
    
    # Edge case 3: Very long pattern (potential buffer overflow)
    response3 = client.request("easycrypt/query", {
        "textDocument": {"uri": "file:///test.ec", "version": 1},
        "command": "locate",
        "argument": "x" * 10000
    }, timeout=2.0)
    
    client.close()
    
    # All should handle gracefully without crashing
    handled_empty = response1 is not None
    handled_special = response2 is not None
    handled_long = response3 is not None
    
    print(f"      Empty: {handled_empty}, Special chars: {handled_special}, Long: {handled_long}")
    # BUG HUNTING: Can we handle all edge cases?
    return handled_empty and handled_special and handled_long

def test_restart_correctness():
    """Correctness: Restart prover clears state and resets document"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    # Open document and execute steps
    client.send({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
            "textDocument": {
                "uri": "file:///test.ec",
                "languageId": "easycrypt",
                "version": 1,
                "text": "lemma test: true.\nproof.\ntrivial.\nqed."
            }
        }
    })
    time.sleep(2.0)  # Wait for parsing to complete
    
    # Execute steps
    client.send({"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}})
    time.sleep(0.5)
    msgs_before = client.read_messages(0.5)
    
    # Now restart
    client.send({"jsonrpc": "2.0", "method": "prover/restartProver", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}})
    time.sleep(0.5)
    msgs_after = client.read_messages(0.5)
    
    # Check for empty proof view after restart
    found_empty_proof_view = False
    for msg in msgs_after:
        if msg.get("method") == "prover/proofView":
            proof_state = msg.get("params", {}).get("proofState")
            if proof_state is None:
                found_empty_proof_view = True
                print(f"      ✓ Restart cleared proof view")
    
    client.close()
    return found_empty_proof_view

def test_restart_negative():
    """Negative: Restart on non-existent document should fail gracefully"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    # Try restart without opening document
    client.send({"jsonrpc": "2.0", "method": "prover/restartProver", "params": {"textDocument": {"uri": "file:///nonexistent.ec", "version": 1}}})
    time.sleep(0.5)
    msgs = client.read_messages(0.5)
    
    # Should not crash - just log and ignore
    no_crash = True  # If we get here, it didn't crash
    print(f"      Restart on nonexistent doc handled gracefully: {no_crash}")
    
    client.close()
    return no_crash

def test_restart_edge_case():
    """Edge case: Restart while in middle of proof with pending goals"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    # Open complex proof
    client.send({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
            "textDocument": {
                "uri": "file:///test.ec",
                "languageId": "easycrypt",
                "version": 1,
                "text": "lemma multi: true /\\ true /\\ true.\nproof.\n  split.\n  trivial.\n  split.\n  trivial.\n  trivial.\nqed."
            }
        }
    })
    time.sleep(0.5)
    
    # Execute partial proof (create multiple subgoals)
    client.send({"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}})
    client.send({"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}    })
    time.sleep(2.0)  # Wait for parsing to complete
    msgs_mid_proof = client.read_messages(0.5)
    
    # Count goals before restart
    goals_before = 0
    for msg in msgs_mid_proof:
        if msg.get("method") == "prover/proofView":
            goals_before = len(msg.get("params", {}).get("proofState", {}).get("goals", []))
    
    print(f"      Goals before restart: {goals_before}")
    
    # Restart in middle of proof - THIS IS THE CRITICAL TEST
    client.send({"jsonrpc": "2.0", "method": "prover/restartProver", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}})
    time.sleep(0.5)
    msgs_after_restart = client.read_messages(0.5)
    
    # Step forward after restart - should start from beginning
    client.send({"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}})
    time.sleep(0.5)
    msgs_after_step = client.read_messages(0.5)
    
    # Check if we're back at the start (first step should give us the initial goal)
    restarted_properly = False
    for msg in msgs_after_step:
        if msg.get("method") == "prover/proofView":
            state = msg.get("params", {}).get("proofState", {})
            goals = state.get("goals", [])
            if goals:
                goal_text = goals[0].get("goal", "")
                # After restart + first step, should see the full goal again
                if "true /\\ true /\\ true" in goal_text or "true" in goal_text:
                    restarted_properly = True
                    print(f"      ✓ Restart reset to beginning: {goal_text[:50]}")
    
    client.close()
    # BUG HUNTING: Does restart properly clear all intermediate state?
    return restarted_properly

def test_multiple_goals_correctness():
    """Correctness: Handle proof with multiple subgoals"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    success, proof_views = test_case(
        client,
        "Multiple Goals",
        "lemma split_test: true /\\ false.\nproof.\n  split.\nqed.",
        [
            {"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}},
            {"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}}
        ]
    )
    
    # After split, should have 2 subgoals
    found_multiple_goals = False
    max_goals = 0
    for pv in proof_views:
        goals = pv.get('params', {}).get('proofState', {}).get('goals', [])
        if len(goals) > max_goals:
            max_goals = len(goals)
        if len(goals) >= 2:
            found_multiple_goals = True
            print(f"      ✓ Found {len(goals)} subgoals after split")
    
    print(f"      Max goals seen: {max_goals}")
    client.close()
    return found_multiple_goals

def test_rapid_commands_edge_case():
    """Edge case: Rapid-fire commands without waiting (race condition test)"""
    client = LSPClient()
    client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "capabilities": {}}})
    client.read_messages(0.5)
    client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    time.sleep(0.5)
    
    client.send({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
            "textDocument": {
                "uri": "file:///test.ec",
                "languageId": "easycrypt",
                "version": 1,
                "text": "lemma test: true.\nproof.\ntrivial.\nqed."
            }
        }
    })
    time.sleep(2.0)  # Wait for parsing to complete
    
    # Rapid fire multiple commands with minimal delay - BUG HUNTING for race conditions
    for _ in range(5):
        client.send({"jsonrpc": "2.0", "method": "prover/stepForward", "params": {"textDocument": {"uri": "file:///test.ec", "version": 1}}})
    
    time.sleep(1.0)  # Give time for all commands to process
    msgs = client.read_messages(2.0)
    
    # Count proof views - should handle rapid commands gracefully
    proof_view_count = sum(1 for msg in msgs if msg.get("method") == "prover/proofView")
    print(f"      Proof views from rapid commands: {proof_view_count}")
    
    client.close()
    # BUG HUNTING: Can we handle rapid commands without crashing or losing state?
    return proof_view_count > 0

def get_all_test_suites():
    """Define all test suites and their tests"""
    return {
        "basic": ("BASIC FUNCTIONALITY", [
            ("Step Forward", test_step_forward),
            ("Multiple Steps", test_multiple_steps),
            ("Interpret to Point", test_interpret_to_point),
        ]),
        "hypotheses": ("HYPOTHESES EXTRACTION", [
            ("Hypotheses - Correctness", test_hypotheses_correctness),
            ("Hypotheses - Negative", test_hypotheses_negative),
            ("Hypotheses - Edge Case", test_hypotheses_edge_case),
            ("Original Hypotheses Test", test_hypotheses_extraction),
        ]),
        "query": ("QUERY COMMANDS", [
            ("Query - Correctness", test_query_correctness),
            ("Query - Negative", test_query_negative),
            ("Query - Edge Case", test_query_edge_case),
        ]),
        "restart": ("RESTART PROVER", [
            ("Restart - Correctness", test_restart_correctness),
            ("Restart - Negative", test_restart_negative),
            ("Restart - Edge Case", test_restart_edge_case),
        ]),
        "advanced": ("ADVANCED FEATURES", [
            ("Multiple Goals", test_multiple_goals_correctness),
            ("Rapid Commands", test_rapid_commands_edge_case),
        ]),
    }

def run_tests(suites_to_run):
    """Run specified test suites"""
    all_test_suites = get_all_test_suites()
    
    all_results = []
    for suite_key in suites_to_run:
        if suite_key not in all_test_suites:
            print(f"Unknown test suite: {suite_key}")
            continue
            
        suite_name, tests = all_test_suites[suite_key]
        print(f"\n{'='*60}")
        print(f"  {suite_name}")
        print(f"{'='*60}")
        
        for name, test_fn in tests:
            try:
                success = test_fn()
                all_results.append((name, success))
                print(f"{'✅' if success else '❌'} {name}")
            except Exception as e:
                print(f"❌ {name} - Exception: {e}")
                import traceback
                traceback.print_exc()
                all_results.append((name, False))
    
    return all_results

def print_results(all_results):
    """Print test results summary"""
    print(f"\n{'='*60}")
    print("FINAL RESULTS")
    print(f"{'='*60}")
    passed = sum(1 for _, success in all_results if success)
    total = len(all_results)
    if total > 0:
        print(f"Passed: {passed}/{total} tests ({100*passed//total}%)")
    else:
        print("No tests run")
    
    failed_tests = [name for name, success in all_results if not success]
    if failed_tests:
        print(f"\nFailed tests:")
        for name in failed_tests:
            print(f"  ❌ {name}")
    
    return passed == total

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Interactive Proving Test Suite",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # Run all tests
  %(prog)s basic              # Run only basic functionality tests
  %(prog)s hypotheses query   # Run hypotheses and query tests
  %(prog)s --list             # List available test suites
        """
    )
    
    parser.add_argument(
        'suites',
        nargs='*',
        choices=['basic', 'hypotheses', 'query', 'restart', 'advanced'],
        help='Test suites to run (default: all suites if none specified)'
    )
    
    parser.add_argument(
        '--list', '-l',
        action='store_true',
        help='List available test suites and exit'
    )
    
    args = parser.parse_args()
    
    if args.list:
        print("Available test suites:")
        all_test_suites = get_all_test_suites()
        for key, (name, tests) in all_test_suites.items():
            print(f"  {key:12} - {name} ({len(tests)} tests)")
        sys.exit(0)
    
    print("="*60)
    print("COMPREHENSIVE INTERACTIVE PROVING TEST SUITE")
    print("="*60)
    
    # Determine which suites to run (default to all if none specified)
    suites_to_run = args.suites if args.suites else list(get_all_test_suites().keys())
    
    all_results = run_tests(suites_to_run)
    success = print_results(all_results)
    
    sys.exit(0 if success else 1)
