import requests
import json
import time

import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(BASE_DIR, ".env")

def load_token():
    with open(ENV_PATH, "r") as f:
        for line in f:
            if line.startswith("WINMCP_AUTH_TOKEN="):
                return line.strip().split("=", 1)[1]
    raise ValueError("Token not found")

def main():
    token = load_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    print("=== TESTING REMOTE ENDPOINT OVER THE INTERNET ===")
    print(f"URL: {PUBLIC_URL}")

    # 1. Health check over public internet
    print("\n[REMOTE 1] Checking /health over public HTTPS...")
    r = requests.get(f"{PUBLIC_URL}/health", timeout=15)
    print(f"  Status: {r.status_code}, Response: {r.json()}")
    assert r.status_code == 200

    # 2. Unauthorized over public internet
    print("\n[REMOTE 2] Checking 401 Unauthorized over public HTTPS...")
    r = requests.post(f"{PUBLIC_URL}/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"}, timeout=15)
    print(f"  Status: {r.status_code}")
    assert r.status_code == 401

    # 3. Authorized tools/list over public internet
    print("\n[REMOTE 3] Checking tools/list with Bearer token over public HTTPS...")
    r = requests.post(
        f"{PUBLIC_URL}/mcp",
        headers=headers,
        json={"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}},
        timeout=15
    )
    print(f"  Status: {r.status_code}")
    assert r.status_code == 200
    tools = r.json().get("result", {}).get("tools", [])
    print(f"  Success: {len(tools)} tools returned from Windows machine across the internet!")

    # 4. Authorized Tool Call: SystemInfo
    print("\n[REMOTE 4] Calling SystemInfo over public HTTPS...")
    r = requests.post(
        f"{PUBLIC_URL}/mcp",
        headers=headers,
        json={
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {"name": "SystemInfo", "arguments": {}}
        },
        timeout=25
    )
    print(f"  Status: {r.status_code}")
    assert r.status_code == 200
    res_text = r.json().get("result", {}).get("content", [{}])[0].get("text", "")
    print(f"  SystemInfo Output from Windows:\n{res_text[:300]}...")

    print("\n=== REMOTE MCP ENDPOINT FULLY VERIFIED OVER HTTPS! ===")

if __name__ == "__main__":
    main()
