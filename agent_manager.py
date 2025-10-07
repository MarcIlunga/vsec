#!/usr/bin/env python3
"""Simple agent manager - dispatch tasks and wait for completion"""
import subprocess
import time
import sys

def tmux_send(agent_num, text):
    """Send text + Enter to agent pane"""
    pane = f"vsec-dev:1.{agent_num}"
    subprocess.run(["tmux", "send-keys", "-t", pane, text])
    subprocess.run(["tmux", "send-keys", "-t", pane, "", "C-m"])

def is_complete(agent_num):
    """Check if agent finished (first line = STATUS: COMPLETE)"""
    try:
        with open(f"/home/marcilunga/dev/vsec/agent{agent_num}.txt") as f:
            return f.readline().strip().startswith("STATUS: COMPLETE")
    except:
        return False

def dispatch(agent_num, congrats=""):
    """Tell agent to read their task file"""
    msg = f"{congrats} Read /home/marcilunga/dev/vsec/agent{agent_num}.txt and execute"
    tmux_send(agent_num, msg)
    print(f"[Agent {agent_num}] Dispatched")

def wait_all():
    """Wait for both agents to complete"""
    print("[Wait] Monitoring agents...")
    done = set()
    while len(done) < 2:
        for i in [1, 2]:
            if i not in done and is_complete(i):
                print(f"✅ Agent {i} done")
                done.add(i)
        time.sleep(0.5)
    print("🎉 All done")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: agent_manager.py [dispatch1 'msg' | dispatch2 'msg' | wait]")
        sys.exit(1)
    
    cmd = sys.argv[1]
    if cmd == "dispatch1":
        dispatch(1, sys.argv[2] if len(sys.argv) > 2 else "")
    elif cmd == "dispatch2":
        dispatch(2, sys.argv[2] if len(sys.argv) > 2 else "")
    elif cmd == "wait":
        wait_all()
