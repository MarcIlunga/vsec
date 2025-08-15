#!/usr/bin/env python3

import subprocess
import time
import select
import sys

def test_easycrypt_interactive():
    """Test EasyCrypt interactively to understand -emacs mode output"""
    print("Starting EasyCrypt in -emacs mode for interactive testing...")
    print("Commands to try:")
    print("1. lemma test : forall x, x + 0 = x.")
    print("2. proof.")
    print("3. Check what happens...")
    
    # Start EasyCrypt process
    process = subprocess.Popen(
        ["opam", "exec", "--switch=easycrypt", "--", "easycrypt", "cli", "-emacs"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=False,
        bufsize=0
    )
    
    try:
        while True:
            # Check for output from EasyCrypt
            ready, _, _ = select.select([process.stdout, sys.stdin], [], [], 0.1)
            
            if process.stdout in ready:
                try:
                    output = process.stdout.read(1024)
                    if output:
                        print(f"EC: {output.decode('utf-8', errors='ignore')}", end='')
                    else:
                        break
                except:
                    break
            
            if sys.stdin in ready:
                line = sys.stdin.readline()
                if line.strip() == 'quit':
                    break
                process.stdin.write(line.encode('utf-8'))
                process.stdin.flush()
    
    except KeyboardInterrupt:
        print("\nExiting...")
    finally:
        process.terminate()
        process.wait()

if __name__ == "__main__":
    test_easycrypt_interactive()