#!/usr/bin/env python3

import subprocess
import time
import threading

def read_output_continuously(process):
    """Continuously read and display all output"""
    while process.poll() is None:
        try:
            output = process.stdout.read(1)
            if output:
                print(output.decode('utf-8', errors='ignore'), end='')
            else:
                time.sleep(0.01)
        except:
            break

def test_simple_proof():
    """Test a simple proof to see goal display"""
    print("=== Testing EasyCrypt -emacs mode for goal display ===")
    
    process = subprocess.Popen(
        ["opam", "exec", "--switch=easycrypt", "--", "easycrypt", "cli", "-emacs"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0
    )
    
    # Start output reader
    output_thread = threading.Thread(target=read_output_continuously, args=(process,))
    output_thread.daemon = True
    output_thread.start()
    
    try:
        # Wait for startup
        time.sleep(2)
        
        print("\n=== SENDING: Simple lemma ===")
        process.stdin.write(b"lemma simple : true.\n")
        process.stdin.flush()
        time.sleep(3)
        
        print("\n=== SENDING: proof ===")
        process.stdin.write(b"proof.\n")
        process.stdin.flush()
        time.sleep(3)
        
        print("\n=== SENDING: Check for current goal ===")
        process.stdin.write(b"pragma noop.\n")
        process.stdin.flush()
        time.sleep(3)
        
        print("\n=== SENDING: Complete proof ===")
        process.stdin.write(b"trivial.\n")
        process.stdin.flush()
        time.sleep(3)
        
        print("\n=== SENDING: qed ===")
        process.stdin.write(b"qed.\n")
        process.stdin.flush()
        time.sleep(3)
        
    except Exception as e:
        print(f"Error: {e}")
    finally:
        process.terminate()
        print("\n=== Test completed ===")

if __name__ == "__main__":
    test_simple_proof()