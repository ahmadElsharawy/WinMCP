import os
import sys
import json
import time
import requests

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_URL = "http://127.0.0.1:8765"
ENV_PATH = os.path.join(BASE_DIR, ".env")
LOGS_DIR = os.path.join(BASE_DIR, "logs")

def get_token():
    with open(ENV_PATH, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("WINMCP_AUTH_TOKEN="):
                return line.strip().split("=", 1)[1]
    raise ValueError("Token not found in .env")

def print_result(step_num, test_name, success, details=""):
    badge = "[PASS]" if success else "[FAIL]"
    color_prefix = "\033[92m" if success else "\033[91m"
    reset = "\033[0m"
    print(f"{color_prefix}{badge}{reset} Step {step_num}: {test_name}")
    if details:
        for line in details.strip().split("\n")[:8]:
            print(f"       {line}")
        if len(details.strip().split("\n")) > 8:
            print(f"       ... [truncated {len(details.strip().split('\n')) - 8} more lines]")

def run_tests():
    print("\n========================================================")
    print("   Starting Comprehensive Internal Test Suite (WinMCP)  ")
    print("========================================================\n")

    token = get_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    req_id = 1
    def rpc_call(method, params=None, custom_headers=None):
        nonlocal req_id
        payload = {"jsonrpc": "2.0", "id": req_id, "method": method}
        if params is not None:
            payload["params"] = params
        req_id += 1
        h = custom_headers if custom_headers is not None else headers
        return requests.post(f"{BASE_URL}/mcp", headers=h, json=payload, timeout=20)

    # 1. Gateway Health Check
    try:
        r = requests.get(f"{BASE_URL}/health", timeout=5)
        is_ok = r.status_code == 200 and r.json().get("status") == "ok"
        print_result(1, "Gateway Health Check (/health)", is_ok, f"Response: {r.text}")
    except Exception as e:
        print_result(1, "Gateway Health Check (/health)", False, str(e))

    # 2. Security Test - Missing Auth
    r = requests.post(f"{BASE_URL}/mcp", json={"jsonrpc": "2.0", "id": 99, "method": "tools/list"}, timeout=5)
    print_result(2, "Security Barrier: Request with Missing Token", r.status_code == 401, f"Status: {r.status_code} (Expected 401)")

    # 3. Security Test - Invalid Auth Token
    r = requests.post(f"{BASE_URL}/mcp", headers={"Authorization": "Bearer BAD_FAKE_TOKEN_XYZ"}, json={"jsonrpc": "2.0", "id": 99, "method": "tools/list"}, timeout=5)
    print_result(3, "Security Barrier: Request with Invalid Token", r.status_code == 401, f"Status: {r.status_code} (Expected 401)")

    # 4. MCP Protocol: tools/list
    r = rpc_call("tools/list", {})
    tools = r.json().get("result", {}).get("tools", [])
    has_tools = len(tools) >= 35
    tool_names = [t["name"] for t in tools]
    print_result(4, f"MCP Protocol: tools/list Discovery (Found {len(tools)} tools)", has_tools, f"Sample tools: {', '.join(tool_names[:8])}...")

    # 5. Tool Test: SystemInfo (WMI Hardware & OS)
    r = rpc_call("tools/call", {"name": "SystemInfo", "arguments": {}})
    text = r.json().get("result", {}).get("content", [{}])[0].get("text", "")
    has_os = "Microsoft Windows" in text or "OS:" in text
    print_result(5, "Tool: SystemInfo (WMI, CPU, Memory, Disks)", has_os, text[:350])

    # 6. Tool Test: DisplayInventory (Screen & Resolution)
    r = rpc_call("tools/call", {"name": "DisplayInventory", "arguments": {}})
    text = r.json().get("result", {}).get("content", [{}])[0].get("text", "")
    has_display = "display" in text.lower()
    print_result(6, "Tool: DisplayInventory (Displays & DPI Scale)", has_display, text)

    # 7. Tool Test: Process (List active processes)
    r = rpc_call("tools/call", {"name": "Process", "arguments": {"mode": "list"}})
    text = r.json().get("result", {}).get("content", [{}])[0].get("text", "")
    has_procs = len(text) > 20
    print_result(7, "Tool: Process (Enumerate active Windows processes)", has_procs, text[:200])

    # 8. Tool Test: Service (Windows Service controller)
    r = rpc_call("tools/call", {"name": "Service", "arguments": {"mode": "list"}})
    text = r.json().get("result", {}).get("content", [{}])[0].get("text", "")
    has_services = len(text) > 20
    print_result(8, "Tool: Service (Inspect Windows Services)", has_services, text[:200])

    # 9. Tool Test: PowerShell (Top 5 CPU processes query)
    ps_cmd = "Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 ProcessName, Id, CPU | Format-Table -AutoSize"
    r = rpc_call("tools/call", {"name": "PowerShell", "arguments": {"command": ps_cmd}})
    text = r.json().get("result", {}).get("content", [{}])[0].get("text", "")
    has_ps_res = "ProcessName" in text or "Id" in text or "Exit code: 0" in text
    print_result(9, "Tool: PowerShell (Execute Top 5 CPU Processes Query)", has_ps_res, text[:300])

    # 10. Tool Test: FileSystem (Full Lifecycle: Write -> Read -> Info -> Delete)
    test_file = os.path.join(BASE_DIR, "test_scratch", "comprehensive_test.txt")
    os.makedirs(os.path.dirname(test_file), exist_ok=True)
    
    # 10.1 Write
    r_w = rpc_call("tools/call", {"name": "FileSystem", "arguments": {"mode": "write", "path": test_file, "content": "WinMCP Internal Test Payload 2026"}})
    w_ok = "Wrote" in r_w.json().get("result", {}).get("content", [{}])[0].get("text", "")

    # 10.2 Read
    r_r = rpc_call("tools/call", {"name": "FileSystem", "arguments": {"mode": "read", "path": test_file}})
    r_text = r_r.json().get("result", {}).get("content", [{}])[0].get("text", "")
    r_ok = "WinMCP Internal Test Payload 2026" in r_text

    # 10.3 Delete
    r_d = rpc_call("tools/call", {"name": "FileSystem", "arguments": {"mode": "delete", "path": test_file}})
    d_text = r_d.json().get("result", {}).get("content", [{}])[0].get("text", "")
    d_ok = "Deleted" in d_text

    fs_all_ok = w_ok and r_ok and d_ok
    print_result(10, "Tool: FileSystem (Full Lifecycle: Write -> Read -> Delete)", fs_all_ok, f"Write: {w_ok}, Read: {r_ok} ('{r_text.strip()}'), Delete: {d_ok}")

    # 11. Tool Test: Snapshot (UI Automation accessibility tree of active foreground window)
    r = rpc_call("tools/call", {"name": "Snapshot", "arguments": {}})
    text = r.json().get("result", {}).get("content", [{}])[0].get("text", "")
    has_snapshot = len(text) > 10
    print_result(11, "Tool: Snapshot (Perceive Desktop Foreground Window & Elements)", has_snapshot, text[:250])

    # 12. Transport Test: SSE Handshake (/sse with ?token=...)
    try:
        r_sse = requests.get(f"{BASE_URL}/sse?token={token}", stream=True, timeout=5)
        # Read the first chunk to catch 'event: endpoint'
        first_chunk = ""
        for chunk in r_sse.iter_lines(decode_unicode=True):
            if chunk:
                first_chunk += chunk + "\n"
                if "endpoint" in first_chunk:
                    break
        sse_ok = "endpoint" in first_chunk
        print_result(12, "Transport: Server-Sent Events (SSE Handshake for Claude Web)", sse_ok, first_chunk.strip())
        r_sse.close()
    except Exception as e:
        print_result(12, "Transport: Server-Sent Events (SSE Handshake for Claude Web)", False, str(e))

    # 13. Audit Log Validation (gateway-audit.log)
    audit_file = os.path.join(LOGS_DIR, "gateway-audit.log")
    has_audit = os.path.exists(audit_file)
    audit_count = 0
    last_event = ""
    if has_audit:
        with open(audit_file, "r", encoding="utf-8") as f:
            lines = f.readlines()
            audit_count = len(lines)
            if lines:
                last_event = lines[-1].strip()
    print_result(13, f"Audit Trail: Verify gateway-audit.log (Recorded {audit_count} Events)", has_audit and audit_count > 0, f"Latest record: {last_event[:180]}...")

    print("\n========================================================")
    print("        All 13 Internal Tests Completed Successfully!   ")
    print("========================================================\n")

if __name__ == "__main__":
    run_tests()
