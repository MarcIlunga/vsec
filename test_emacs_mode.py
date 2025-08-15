#!/usr/bin/env python3

import subprocess
import time
import threading

def read_output(process):
    """Read and print output from the EasyCrypt process"""
    while True:
        try:
            line = process.stdout.readline()
            if not line:
                break
            print(f"OUT: {line.decode('utf-8').rstrip()}")
        except Exception as e:
            print(f"Error reading output: {e}")
            break

def test_easycrypt_emacs_mode():
    """Test EasyCrypt in -emacs mode"""
    print("Starting EasyCrypt in -emacs mode...")
    
    # Start EasyCrypt cli with -emacs flag
    process = subprocess.Popen(
        ["opam", "exec", "--switch=easycrypt", "--", "easycrypt", "cli", "-emacs"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False,  # Binary mode
        bufsize=1  # Line buffered
    )
    
    # Start reading output in background thread
    output_thread = threading.Thread(target=read_output, args=(process,))
    output_thread.daemon = True
    output_thread.start()
    
    try:
        print("Sending commands to test -emacs mode...")
        
        # Test basic lemma and proof commands from Proof General patterns
        commands = [
            "lemma test_lemma : forall (x : int), x + 0 = x.",
            "proof.",
            "pragma noop.",  # Query current state (from Proof General)
            "move => x.",
            "pragma noop.",  # Query state after tactic
            "ring.", 
            "pragma noop.",  # Query state after completing goal
            "qed."
        ]
        
        for cmd in commands:
            print(f"SEND: {cmd}")
            process.stdin.write((cmd + "\n").encode('utf-8'))
            process.stdin.flush()
            time.sleep(2)  # Wait for output
        
        # Give some time for final output
        time.sleep(3)
        
    except KeyboardInterrupt:
        print("Test interrupted")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        process.terminate()
        process.wait()
        print("EasyCrypt process ended")

if __name__ == "__main__":
    test_easycrypt_emacs_mode()