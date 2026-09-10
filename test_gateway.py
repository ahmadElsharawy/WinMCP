import time
import requests
import json
import os
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_URL = "http://127.0.0.1:8765"
ENV_PATH = os.path.join(BASE_DIR, ".env")

def load_token():
    with open(ENV_PATH, "r") as f:
        for line in f:
            if line.startswith("WINMCP_AUTH_TOKEN="):
                return line.strip().split("=", 1)[1]
    raise ValueError("Token not found in .env")

def test_gateway():
    token = load_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    print("=== STARTING GATEWAY INTEGRATION TESTS ===")

    # 1. Health check
    print("\n[TEST 1] GET /health...")
    r = requests.get(f"{BASE_URL}/health")
    assert r.status_code == 200, f"Health check failed: {r.status_code} {r.text}"
    print(f"  OK: {r.json()}")

    # 2. Unauthorized request (No Token)
    print("\n[TEST 2] POST /mcp (Unauthorized - No Token)...")
    r = requests.post(f"{BASE_URL}/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    assert r.status_code == 401, f"Expected 401, got {r.status_code}"
    print("  OK: Correctly rejected with 401 Unauthorized.")

    # 3. Unauthorized request (Bad Token)
    print("\n[TEST 3] POST /mcp (Unauthorized - Bad Token)...")
    r = requests.post(
        f"{BASE_URL}/mcp",
        headers={"Authorization": "Bearer BAD_TOKEN_123"},
        json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
    )
    assert r.status_code == 401, f"Expected 401, got {r.status_code}"
    print("  OK: Correctly rejected with 401 Unauthorized.")

    # 4. Authorized tools/list
    print("\n[TEST 4] POST /mcp (Authorized tools/list)...")
    r = requests.post(
        f"{BASE_URL}/mcp",
        headers=headers,
        json={"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}
    )
    assert r.status_code == 200, f"Expected 200, got {r.status_code} {r.text}"
    tools = r.json().get("result", {}).get("tools", [])
    print(f"  OK: Successfully listed {len(tools)} tools via Gateway!")

    # 5. Authorized tools/call: SystemInfo
    print("\n[TEST 5] POST /mcp (Authorized Tool: SystemInfo)...")
    r = requests.post(
        f"{BASE_URL}/mcp",
        headers=headers,
        json={
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {"name": "SystemInfo", "arguments": {}}
        }
    )
    assert r.status_code == 200, f"Expected 200, got {r.status_code} {r.text}"
    text = r.json().get("result", {}).get("content", [{}])[0].get("text", "")
    print(f"  OK: SystemInfo result preview:\n{text[:200]}...")

    # 6. Authorized tools/call: PowerShell
    print("\n[TEST 6] POST /mcp (Authorized Tool: PowerShell)...")
    r = requests.post(
        f"{BASE_URL}/mcp",
        headers=headers,
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "PowerShell",
                "arguments": {"command": "Write-Output 'Gateway PowerShell Test Passed'"}
            }
        }
    )
    assert r.status_code == 200, f"Expected 200, got {r.status_code} {r.text}"
    text = r.json().get("result", {}).get("content", [{}])[0].get("text", "")
    print(f"  OK: PowerShell output: {text.strip()}")

    # 7. URL Token parameter (Claude Web style)
    print("\n[TEST 7] POST /mcp?token=... (Query param auth)...")
    r = requests.post(
        f"{BASE_URL}/mcp?token={token}",
        headers={"Content-Type": "application/json"},
        json={"jsonrpc": "2.0", "id": 4, "method": "tools/list", "params": {}}
    )
    assert r.status_code == 200, f"Expected 200, got {r.status_code}"
    print(f"  OK: Query param authentication succeeded!")

    # 8. Check Audit Log
    print("\n[TEST 8] Checking Audit Log...")
    audit_file = os.path.join(BASE_DIR, "logs", "gateway-audit.log")
    assert os.path.exists(audit_file), "Audit log file does not exist"
    with open(audit_file, "r", encoding="utf-8") as f:
        lines = f.readlines()
    print(f"  OK: Audit log exists and has {len(lines)} records.")
    print(f"  Last audit record: {lines[-1].strip()}")

    print("\n=== ALL GATEWAY TESTS PASSED SUCCESSFULLY! ===")

if __name__ == "__main__":
    test_gateway()
