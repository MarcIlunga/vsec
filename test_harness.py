#!/usr/bin/env python3

import argparse
import json
import os
import select
import subprocess
import sys
import time
import threading
from collections import deque

def send(process, msg):
    data = json.dumps(msg)
    header = f"Content-Length: {len(data.encode('utf-8'))}\r\n\r\n"
    process.stdin.write(header.encode('utf-8'))
    process.stdin.write(data.encode('utf-8'))
    process.stdin.flush()

class LspClient:
    def __init__(self, cmd):
        # cmd can be a string path or a list argv
        env = os.environ.copy()
        env["OCAMLRUNPARAM"] = env.get("OCAMLRUNPARAM", "") + (";" if env.get("OCAMLRUNPARAM") else "") + "b=1"
        if isinstance(cmd, list):
            self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=False, env=env)
        else:
            self.proc = subprocess.Popen([cmd], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=False, env=env)
        self._next_id = 1
        # Non-blocking stderr drain loop configuration
        self._stderr_last_print = 0.0
        # Background reader state
        self._resp_by_id = {}
        self._notifs = deque()
        self._lock = threading.Lock()
        self._reader_alive = True
        self._reader = threading.Thread(target=self._reader_loop, daemon=True)
        self._reader.start()

    def _reader_loop(self):
        while self._reader_alive:
            msg = read_one(self.proc, timeout=0.2)
            if not msg:
                continue
            if isinstance(msg, dict):
                if "id" in msg:
                    key = str(msg.get("id"))
                    with self._lock:
                        self._resp_by_id[key] = msg
                elif "method" in msg and "id" not in msg:
                    with self._lock:
                        self._notifs.append(msg)
            # Drain stderr opportunistically
            try:
                drain_stderr_nonblocking(self.proc, max_time=0.02)
            except Exception:
                pass

    def close(self):
        try:
            self.proc.terminate()
        except Exception:
            pass
        self._reader_alive = False
        # Drain any remaining stderr
        try:
            while True:
                ready, _, _ = select.select([self.proc.stderr], [], [], 0.05)
                if not ready:
                    break
                chunk = self.proc.stderr.read(4096)
                if not chunk:
                    break
                try:
                    sys.stderr.write(chunk.decode('utf-8', errors='replace'))
                except Exception:
                    pass
        except Exception:
            pass

    def send(self, msg):
        send(self.proc, msg)

    def new_id(self):
        i = self._next_id
        self._next_id += 1
        return i

    def request(self, method, params, timeout=1.0):
        req_id = self.new_id()
        print(f"client-req: method={method} id={req_id}")
        self.send({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params})
        deadline = time.time() + timeout
        key = str(req_id)
        while time.time() < deadline:
            with self._lock:
                msg = self._resp_by_id.pop(key, None)
            if msg is not None:
                try:
                    print("resp:", msg)
                except Exception:
                    pass
                return msg
            drain_stderr_nonblocking(self.proc, max_time=0.05)
            time.sleep(0.05)
        # After timeout, if buffered response arrived late, print and return it
        with self._lock:
            late = self._resp_by_id.pop(key, None)
        if late is not None:
            try:
                print("resp-buffered:", late)
            except Exception:
                pass
            return late
        return None

def _read_line_with_timeout(proc, timeout):
    fd = proc.stdout
    ready, _, _ = select.select([fd], [], [], timeout)
    if not ready:
        return None
    data = fd.readline()
    if not data:
        return None
    return data.decode('utf-8')

def _read_exact_with_timeout(proc, nbytes, timeout):
    fd = proc.stdout
    chunks = []
    total = 0
    end_time = time.time() + timeout
    while total < nbytes and time.time() < end_time:
        remaining = nbytes - total
        ready, _, _ = select.select([fd], [], [], max(0.0, end_time - time.time()))
        if not ready:
            break
        chunk = fd.read(remaining)
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
    if total < nbytes:
        return None
    return b"".join(chunks).decode('utf-8')

def read_one(process, timeout=0.5):
    """Read a single JSON-RPC message with overall timeout."""
    end_time = time.time() + timeout
    length = None
    # Read headers until blank line
    while time.time() < end_time:
        line = _read_line_with_timeout(process, max(0.0, end_time - time.time()))
        if line is None:
            return None
        # Blank line terminates headers
        if line.strip() == "":
            break
        lower = line.lower()
        if lower.startswith('content-length:'):
            try:
                length = int(line.split(':', 1)[1].strip())
            except Exception:
                return None
        # ignore other headers (e.g., content-type)
    if length is None:
        return None
    body = _read_exact_with_timeout(process, length, max(0.0, end_time - time.time()))
    if body is None:
        return None
    try:
        return json.loads(body)
    except Exception:
        return None

def drain_notifications_client(client: LspClient, duration_sec=1.0, max_count=200):
    end_t = time.time() + duration_sec
    printed = 0
    while time.time() < end_t and printed < max_count:
        msg = None
        with client._lock:
            if client._notifs:
                msg = client._notifs.popleft()
        if not msg:
            time.sleep(0.05)
            continue
        try:
            print("notif:", msg)
        except Exception:
            pass
        printed += 1

def dump_raw_stdout(process, duration_sec=1.0):
    end_t = time.time() + duration_sec
    fd = process.stdout
    while time.time() < end_t:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if not ready:
            continue
        chunk = fd.read(4096)
        if not chunk:
            break
        sys.stdout.write("raw-chunk:" + repr(chunk) + "\n")

def drain_all_messages(process, duration_sec=1.0):
    end_t = time.time() + duration_sec
    while time.time() < end_t:
        msg = read_one(process, timeout=0.1)
        if not msg:
            continue
        try:
            print("any:", msg)
        except Exception:
            pass

def drain_stderr_nonblocking(proc, max_lines=50, max_time=0.1):
    end_time = time.time() + max_time
    lines = 0
    try:
        while lines < max_lines and time.time() < end_time:
            ready, _, _ = select.select([proc.stderr], [], [], 0.0)
            if not ready:
                break
            data = proc.stderr.readline()
            if not data:
                break
            try:
                sys.stderr.write(data.decode('utf-8', errors='replace'))
            except Exception:
                pass
            lines += 1
    except Exception:
        pass

def run_test(lsp_path, uri, max_seconds=3.0, max_messages=20):
    client = LspClient(lsp_path)
    try:
        # Give server a brief moment to start its loop
        time.sleep(0.5)
        drain_stderr_nonblocking(client.proc, max_time=0.3)

        # Initialize via request and wait for response
        init_params = {
            "processId": None,
            "clientInfo": {"name": "harness"},
            "capabilities": {},
            "workspaceFolders": [{"uri": uri, "name": "workspace"}]
        }
        init_resp = client.request("initialize", init_params, timeout=12.0)
        print("initialize:", init_resp)
        if init_resp is None:
            # Try to show what we buffered for id 1
            with client._lock:
                late = client._resp_by_id.pop("1", None)
            if late is not None:
                print("initialize-buffered:", late)
        drain_stderr_nonblocking(client.proc, max_time=0.2)
        drain_notifications_client(client, duration_sec=0.5)

        client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})

        # Open a document
        did_open = {
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": f"{uri}/test.ec",
                    "languageId": "easycrypt",
                    "version": 1,
                    "text": "lemma t: true. proof. qed.\n"
                }
            }
        }
        client.send(did_open)
        drain_stderr_nonblocking(client.proc, max_time=0.2)

        # vsec/ping sanity request
        ping_resp = client.request("vsec/ping", {}, timeout=8.0)
        print("ping:", ping_resp)
        drain_notifications_client(client, duration_sec=0.5)
        drain_stderr_nonblocking(client.proc, max_time=0.2)

        # Issue requests early (before draining many notifications)
        comp_resp = client.request("textDocument/completion", {
            "textDocument": {"uri": f"{uri}/test.ec"},
            "position": {"line": 0, "character": 6}
        }, timeout=12.0)
        print("completion:", comp_resp)
        # See if fallback emitted a window/logMessage
        drain_notifications_client(client, duration_sec=1.0)
        drain_all_messages(client.proc, duration_sec=0.5)
        drain_stderr_nonblocking(client.proc, max_time=0.2)

        def_resp = client.request("textDocument/definition", {
            "textDocument": {"uri": f"{uri}/test.ec"},
            "position": {"line": 0, "character": 7}
        }, timeout=12.0)
        print("definition:", def_resp)
        drain_notifications_client(client, duration_sec=1.0)
        drain_all_messages(client.proc, duration_sec=0.5)
        drain_stderr_nonblocking(client.proc, max_time=0.2)

        # Custom stepForward (if supported)
        client.send({
            "jsonrpc": "2.0",
            "method": "prover/stepForward",
            "params": {"textDocument": {"uri": f"{uri}/test.ec", "version": 1}}
        })
        drain_stderr_nonblocking(client.proc, max_time=0.2)

        # Brief settling period; ignore notifications
        _settle_deadline = time.time() + 0.5
        while time.time() < _settle_deadline:
            _ = read_one(client.proc, timeout=0.1)

        # Negative: unopened file
        def_neg = client.request("textDocument/definition", {
            "textDocument": {"uri": f"{uri}/unopened.ec"},
            "position": {"line": 0, "character": 0}
        }, timeout=5.0)
        print("definition-unopened:", def_neg)
        drain_stderr_nonblocking(client.proc, max_time=0.2)

        # Edge: out-of-bounds
        def_oob = client.request("textDocument/definition", {
            "textDocument": {"uri": f"{uri}/test.ec"},
            "position": {"line": 999, "character": 999}
        }, timeout=5.0)
        print("definition-oob:", def_oob)
        drain_stderr_nonblocking(client.proc, max_time=0.2)

        # Final response collection window; print only responses
        end_deadline = time.time() + 3.0
        while time.time() < end_deadline:
            msg = read_one(client.proc, timeout=0.2)
            if not msg:
                continue
            if isinstance(msg, dict) and "id" in msg:
                try:
                    print("final:", msg)
                except Exception:
                    pass
            drain_stderr_nonblocking(client.proc, max_time=0.05)
        # Final drain of notifications for visibility
        drain_notifications_client(client, duration_sec=2.0)
        # Dump any remaining raw stdout bytes for diagnostics
        dump_raw_stdout(client.proc, duration_sec=0.5)

    finally:
        client.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lsp", default=os.path.join(os.getcwd(), "vscode-extension", "vsec-lsp"))
    parser.add_argument("--workspace", default="file:///home/marcilunga/dev/vsec")
    parser.add_argument("--max-seconds", type=float, default=3.0)
    parser.add_argument("--max-messages", type=int, default=20)
    args = parser.parse_args()
    run_test(args.lsp, args.workspace, max_seconds=args.max_seconds, max_messages=args.max_messages)

if __name__ == "__main__":
    main()


