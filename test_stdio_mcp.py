import json
import subprocess
import sys
import time
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BINARY_PATH = os.path.join(BASE_DIR, "bin", "windows-mcp-server.exe")

def run_test():
    print("Starting windows-mcp-server process...")
    proc = subprocess.Popen(
        [BINARY_PATH, "stdio", "--toolsets", "all"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1
    )

    def send_msg(msg):
        line = json.dumps(msg) + "\n"
        proc.stdin.write(line)
        proc.stdin.flush()

    def recv_msg():
        while True:
            line = proc.stdout.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            try:
                return json.loads(line)
            except Exception as e:
                print(f"Non-JSON line from stdout: {line}")
        return None

    # 1. Initialize
    print("\n--- 1. Testing Initialize ---")
    send_msg({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "local-tester", "version": "1.0.0"}
        }
    })
    init_res = recv_msg()
    print("Initialize response received:")
    print(json.dumps(init_res, indent=2))

    send_msg({
        "jsonrpc": "2.0",
        "method": "notifications/initialized"
    })

    # 2. List tools
    print("\n--- 2. Testing tools/list ---")
    send_msg({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list",
        "params": {}
    })
    tools_res = recv_msg()
    tools = tools_res.get("result", {}).get("tools", [])
    print(f"Total tools returned: {len(tools)}")
    tool_names = [t.get("name") for t in tools]
    print(f"Tools: {tool_names}")

    # 3. Call SystemInfo (Read-Only)
    print("\n--- 3. Testing Call Tool: SystemInfo ---")
    send_msg({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "SystemInfo",
            "arguments": {}
        }
    })
    sys_res = recv_msg()
    print("SystemInfo Result:")
    print(json.dumps(sys_res, indent=2)[:1000] + "\n... [truncated]")

    # 4. Call PowerShell (Safe command)
    print("\n--- 4. Testing Call Tool: PowerShell (Safe command) ---")
    send_msg({
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {
            "name": "PowerShell",
            "arguments": {
                "command": "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"
            }
        }
    })
    ps_res = recv_msg()
    print("PowerShell Result:")
    print(json.dumps(ps_res, indent=2))

    # Clean shutdown
    proc.terminate()
    print("\nAll local stdio tests completed successfully!")

if __name__ == "__main__":
    run_test()
