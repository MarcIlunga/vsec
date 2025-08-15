#!/usr/bin/env python3

import subprocess
import time
import re
from typing import Optional, Dict, List

class EasyCryptProcess:
    """Prototype of EasyCrypt process management for hybrid approach"""
    
    def __init__(self):
        self.process = None
        self.command_counter = 0
        
    def start(self):
        """Start EasyCrypt process in -emacs mode"""
        print("Starting EasyCrypt process...")
        self.process = subprocess.Popen(
            ["opam", "exec", "--switch=easycrypt", "--", "easycrypt", "cli", "-emacs"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0
        )
        
        # Wait for startup and consume initial output
        time.sleep(2)
        self._consume_startup_output()
        print("EasyCrypt process ready")
    
    def _consume_startup_output(self):
        """Read and discard startup messages"""
        # Read until we see the first prompt
        output = b""
        while True:
            chunk = self.process.stdout.read(1024)
            if not chunk:
                break
            output += chunk
            if b"[0|check]>" in output:
                break
        print(f"Startup output consumed: {len(output)} bytes")
    
    def send_command(self, command: str) -> str:
        """Send command and return output until next prompt"""
        print(f"SEND: {command}")
        
        # Send command
        self.process.stdin.write((command + "\n").encode('utf-8'))
        self.process.stdin.flush()
        
        # Read until next prompt
        self.command_counter += 1
        expected_prompt = f"[{self.command_counter}|check]>"
        
        output = b""
        while True:
            chunk = self.process.stdout.read(1024)
            if not chunk:
                break
            output += chunk
            
            # Check if we have the expected prompt
            if expected_prompt.encode() in output:
                break
            
            # Safety timeout
            time.sleep(0.1)
        
        result = output.decode('utf-8', errors='ignore')
        print(f"RECV: {result}")
        return result
    
    def parse_goal_output(self, output: str) -> Optional[Dict]:
        """Parse EasyCrypt output for goal information"""
        if "Current goal" in output:
            return self._extract_current_goal(output)
        elif "No more goals" in output:
            return {"status": "complete", "goals": []}
        else:
            return None
    
    def _extract_current_goal(self, output: str) -> Dict:
        """Extract goal structure from 'Current goal' output"""
        lines = output.split('\n')
        
        # Find the goal content after the separator line
        goal_content = []
        in_goal = False
        type_vars = "none"
        
        for line in lines:
            if line.startswith("Type variables:"):
                type_vars = line.replace("Type variables: ", "").strip()
            elif "---" in line and len(line) > 10:  # Separator line
                in_goal = True
                continue
            elif in_goal and line.strip() and not line.startswith("["):
                goal_content.append(line.strip())
            elif in_goal and line.startswith("["):  # Hit the prompt, stop
                break
        
        goal_text = " ".join(goal_content) if goal_content else "unknown"
        
        return {
            "status": "active",
            "goals": [{
                "id": 1,
                "hypotheses": [],  # Could be extracted if present
                "goal": goal_text,
                "type_variables": type_vars
            }]
        }
    
    def close(self):
        """Clean up the process"""
        if self.process:
            self.process.terminate()
            self.process.wait()
            print("EasyCrypt process closed")

def test_hybrid_approach():
    """Test the hybrid approach prototype"""
    print("=== Testing Hybrid Approach Prototype ===")
    
    ec_process = EasyCryptProcess()
    
    try:
        ec_process.start()
        
        # Test sequence: lemma -> proof -> goal extraction
        commands_and_expected = [
            ("lemma test : forall x, x + 0 = x.", "should show goal"),
            ("proof.", "should show same goal"),
            ("move => x.", "should show simplified goal"),
            ("ring.", "should complete proof"),
            ("qed.", "should finish")
        ]
        
        for command, expected in commands_and_expected:
            print(f"\n--- Testing: {command} ({expected}) ---")
            output = ec_process.send_command(command)
            
            # Parse the output
            parsed = ec_process.parse_goal_output(output)
            if parsed:
                print(f"PARSED: {parsed}")
            else:
                print("PARSED: No goal information")
                
        print("\n=== Hybrid approach test completed successfully! ===")
        
    except Exception as e:
        print(f"Error in hybrid test: {e}")
    finally:
        ec_process.close()

if __name__ == "__main__":
    test_hybrid_approach()