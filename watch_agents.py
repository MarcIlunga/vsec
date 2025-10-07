#!/usr/bin/env python3
"""Simple agent watcher - waits until ALL agents show STATUS: COMPLETE
Supervisor review loop: For each agent, wait for supervisor ACCEPT or FEEDBACK via files
  /home/marcilunga/dev/vsec/review_agent{n}.txt containing either:
    ACCEPT
    FEEDBACK: <one-line message>
Up to 3 feedback rounds; then auto-accept or run supervisor fix.
Optionally runs a command after all agents are accepted (args after agent numbers)."""
import time
import sys
import os
from pathlib import Path

ROOT = "/home/marcilunga/dev/vsec"


def is_complete(agent_num: int) -> bool:
    try:
        with open(f"{ROOT}/agent{agent_num}.txt") as f:
            return any(line.strip().startswith("STATUS: COMPLETE") for line in f)
    except Exception:
        return False


def read_review(agent_num: int):
    p = Path(f"{ROOT}/review_agent{agent_num}.txt")
    if not p.exists():
        return None
    try:
        content = p.read_text().strip()
        if content.upper().startswith("ACCEPT"):
            return ("ACCEPT", None)
        if content.upper().startswith("FEEDBACK:"):
            return ("FEEDBACK", content.split(":", 1)[1].strip())
    except Exception:
        return None
    return None


def clear_review(agent_num: int):
    p = Path(f"{ROOT}/review_agent{agent_num}.txt")
    if p.exists():
        p.unlink(missing_ok=True)


def append_feedback_to_agent(agent_num: int, feedback: str):
    with open(f"{ROOT}/agent{agent_num}.txt", "a") as f:
        f.write("\n\nSUPERVISOR FEEDBACK:\n" + feedback + "\n")


def dispatch_agent(agent_num: int, title: str):
    os.system(f"python3 {ROOT}/agent_manager.py dispatch{agent_num} '{title}'")


def watch_agents(agent_nums, then_cmd=None):
    print(f"[Watcher] Monitoring agents {agent_nums}...", flush=True)

    completed = set()
    for num in agent_nums:
        if is_complete(num):
            print(f"✅ Agent {num} already complete", flush=True)
            completed.add(num)

    # Wait for all to complete
    while len(completed) < len(agent_nums):
        for num in agent_nums:
            if num not in completed and is_complete(num):
                print(f"✅ Agent {num} completed", flush=True)
                completed.add(num)
        time.sleep(0.3)

    # Supervisor review loop per agent
    print("🔎 Entering supervisor review loop (up to 3 rounds per agent)", flush=True)
    fix_cmd = os.environ.get("SUPERVISOR_FIX_CMD")
    for num in agent_nums:
        rounds = 0
        accepted = False
        while rounds < 3:
            print(f"[Review] Agent {num}: Please create {ROOT}/review_agent{num}.txt with 'ACCEPT' or 'FEEDBACK: <msg>'", flush=True)
            # Poll for supervisor input
            waited = 0
            while True:
                decision = read_review(num)
                if decision:
                    kind, payload = decision
                    clear_review(num)
                    if kind == "ACCEPT":
                        print(f"👍 Agent {num} accepted", flush=True)
                        accepted = True
                        rounds = 3
                        break
                    else:
                        rounds += 1
                        print(f"↩️ Feedback for Agent {num} (round {rounds}/3): {payload}", flush=True)
                        append_feedback_to_agent(num, payload)
                        dispatch_agent(num, "Supervisor feedback")
                        # Wait for completion again
                        while not is_complete(num):
                            time.sleep(0.5)
                        print(f"✅ Agent {num} completed after feedback", flush=True)
                        # Loop again for next review round
                        break
                time.sleep(0.5)
                waited += 0.5
                if waited % 10 == 0:
                    print(f"[Review] Agent {num}: waiting for supervisor decision...", flush=True)
        if not accepted:
            if fix_cmd:
                print(f"🛠️ Supervisor applying fix for Agent {num}: {fix_cmd}", flush=True)
                os.system(fix_cmd)
            else:
                print(f"✅ Agent {num} auto-accepted after 3 rounds (no fix_cmd provided)", flush=True)

    print("🎯 All agents accepted.", flush=True)
    if then_cmd:
        print(f"[Next] Running: {then_cmd}", flush=True)
        os.system(then_cmd)
    return 0


if __name__ == "__main__":
    agents = []
    rest = []
    for arg in sys.argv[1:]:
        if arg.isdigit():
            agents.append(int(arg))
        else:
            rest.append(arg)
    if not agents:
        agents = [1, 2]
    then_cmd = " ".join(rest).strip() if rest else None
    sys.exit(watch_agents(agents, then_cmd))
