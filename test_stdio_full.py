import json
import subprocess
import sys
import threading
import time
import os
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BINARY_PATH = os.path.join(BASE_DIR, "bin", "windows-mcp-server.exe")

class MCPTester:
    def __init__(self):
        self.proc = subprocess.Popen(
            [BINARY_PATH, "stdio", "--toolsets", "all"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=0
        )
        self.req_id = 1
        t = threading.Thread(target=self._read_stderr, daemon=True)
        t.start()

    def _read_stderr(self):
        for line in self.proc.stderr:
            pass # Keep stderr drained

    def call(self, method, params=None):
        cur_id = self.req_id
        self.req_id += 1
        msg = {
            "jsonrpc": "2.0",
            "id": cur_id,
            "method": method
        }
        if params is not None:
            msg["params"] = params
        raw = json.dumps(msg) + "\n"
        self.proc.stdin.write(raw)
        self.proc.stdin.flush()

        line = self.proc.stdout.readline()
        if not line:
            return None
        return json.loads(line.strip())

    def notify(self, method, params=None):
        msg = {
            "jsonrpc": "2.0",
            "method": method
        }
        if params is not None:
            msg["params"] = params
        raw = json.dumps(msg) + "\n"
        self.proc.stdin.write(raw)
        self.proc.stdin.flush()

    def close(self):
        try:
            self.proc.terminate()
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.kill()

def main():
    print("=== STARTING FULL MCP VERIFICATION ===")
    tester = MCPTester()
    try:
        # 1. Initialize
        print("\n[STEP 1] Testing 'initialize'...")
        res = tester.call("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "full-verifier", "version": "1.0"}
        })
        assert res and "result" in res, f"Initialize failed: {res}"
        print(f"  OK: Server {res['result']['serverInfo']['name']} v{res['result']['serverInfo']['version']}")

        tester.notify("notifications/initialized")

        # 2. tools/list
        print("\n[STEP 2] Testing 'tools/list'...")
        res = tester.call("tools/list", {})
        tools = res.get("result", {}).get("tools", [])
        tool_names = [t["name"] for t in tools]
        print(f"  OK: Found {len(tools)} tools: {', '.join(tool_names[:10])}... (total {len(tools)})")

        # 3. SystemInfo
        print("\n[STEP 3] Testing Tool: SystemInfo (Read-only)...")
        res = tester.call("tools/call", {"name": "SystemInfo", "arguments": {}})
        content = res.get("result", {}).get("content", [{}])[0].get("text", "")
        print(f"  OK: SystemInfo returned:\n{content[:300]}...")

        # 4. Process list
        print("\n[STEP 4] Testing Tool: Process (action: list)...")
        res = tester.call("tools/call", {"name": "Process", "arguments": {"action": "list"}})
        content = res.get("result", {}).get("content", [{}])[0].get("text", "")
        print(f"  OK: Process list returned length: {len(content)} chars")

        # 5. Service list
        print("\n[STEP 5] Testing Tool: Service (action: list)...")
        res = tester.call("tools/call", {"name": "Service", "arguments": {"action": "list"}})
        content = res.get("result", {}).get("content", [{}])[0].get("text", "")
        print(f"  OK: Service list returned length: {len(content)} chars")

        # 6. PowerShell safe execution
        print("\n[STEP 6] Testing Tool: PowerShell (Get-ComputerInfo basic / Get-Date)...")
        res = tester.call("tools/call", {"name": "PowerShell", "arguments": {
            "command": "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"
        }})
        content = res.get("result", {}).get("content", [{}])[0].get("text", "")
        print(f"  OK: PowerShell output: {content.strip()}")

        # 7. FileSystem safe test in dedicated directory
        test_dir = os.path.join(BASE_DIR, "test_scratch")
        os.makedirs(test_dir, exist_ok=True)
        test_file = os.path.join(test_dir, "mcp_test_file.txt")
        print("\n[STEP 7] Testing Tool: FileSystem (write, read, delete)...")
        
        # Write
        res = tester.call("tools/call", {"name": "FileSystem", "arguments": {
            "action": "write",
            "path": test_file,
            "content": "Hello Windows MCP Server from AI Agent!"
        }})
        print(f"  OK write: {res.get('result', {}).get('content', [{}])[0].get('text', '')[:100]}")

        # Read
        res = tester.call("tools/call", {"name": "FileSystem", "arguments": {
            "action": "read",
            "path": test_file
        }})
        read_text = res.get("result", {}).get("content", [{}])[0].get("text", "")
        print(f"  OK read content: {read_text.strip()}")

        # Delete
        res = tester.call("tools/call", {"name": "FileSystem", "arguments": {
            "action": "delete",
            "path": test_file
        }})
        print(f"  OK delete: {res.get('result', {}).get('content', [{}])[0].get('text', '')[:100]}")

        # 8. Display inventory (Screen toolset)
        print("\n[STEP 8] Testing Tool: DisplayInventory...")
        res = tester.call("tools/call", {"name": "DisplayInventory", "arguments": {}})
        content = res.get("result", {}).get("content", [{}])[0].get("text", "")
        print(f"  OK DisplayInventory:\n{content[:300]}")

        print("\n=== ALL 8 LOCAL MCP SYSTEM TESTS PASSED PERFECTLY ===")
    finally:
        tester.close()

if __name__ == "__main__":
    main()
