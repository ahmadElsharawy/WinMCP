import json
import subprocess
import sys
import threading
import time
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BINARY_PATH = os.path.join(BASE_DIR, "bin", "windows-mcp-server.exe")

def run():
    print("[TEST] Launching binary...", flush=True)
    proc = subprocess.Popen(
        [BINARY_PATH, "stdio", "--toolsets", "all"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=0
    )

    def read_stderr():
        for line in proc.stderr:
            print(f"[STDERR] {line.strip()}", flush=True)

    t = threading.Thread(target=read_stderr, daemon=True)
    t.start()

    time.sleep(1)

    init_payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test", "version": "1.0"}
        }
    }
    raw = json.dumps(init_payload) + "\n"
    print(f"[TEST] Sending initialize: {raw.strip()}", flush=True)
    proc.stdin.write(raw)
    proc.stdin.flush()

    print("[TEST] Reading response...", flush=True)
    line = proc.stdout.readline()
    print(f"[TEST] Received response: {line.strip()}", flush=True)

    proc.terminate()

if __name__ == "__main__":
    run()
