import requests
import json
import time
import re
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(BASE_DIR, ".env")

def load_token():
    with open(ENV_PATH, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("WINMCP_AUTH_TOKEN="):
                return line.strip().split("=", 1)[1]
    raise ValueError("Token not found in .env")

def get_public_url():
    # Check .env for custom domain
    if os.path.exists(ENV_PATH):
        with open(ENV_PATH, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("WINMCP_CUSTOM_DOMAIN="):
                    d = line.strip().split("=", 1)[1].strip()
                    if d:
                        return f"https://{d}"
    # Check logs for Cloudflare quick tunnel URL
    for fname in ["cloudflared_error.log", "cloudflared.log"]:
        fpath = os.path.join(BASE_DIR, "logs", fname)
        if os.path.exists(fpath):
            with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                for line in reversed(f.readlines()):
                    m = re.search(r"(https://[a-zA-Z0-9-]+\.trycloudflare\.com)", line)
                    if m:
                        return m.group(1)
    return "http://127.0.0.1:8765"

def main():
    token = load_token()
    public_url = get_public_url()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    print("========================================================")
    print("      Testing Remote WinMCP Endpoint Over HTTPS         ")
    print("========================================================")
    print(f"Target URL: {public_url}\n")

    # 1. Health check over public internet
    print("[REMOTE 1] Checking /health over public HTTPS...")
    r = requests.get(f"{public_url}/health", timeout=15)
    print(f"  Status: {r.status_code}, Response: {r.json()}")
    assert r.status_code == 200

    # 2. Unauthorized over public internet
    print("\n[REMOTE 2] Checking 401 Unauthorized over public HTTPS...")
    r = requests.post(f"{public_url}/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"}, timeout=15)
    print(f"  Status: {r.status_code}")
    assert r.status_code == 401

    # 3. Authorized tools/list over public internet
    print("\n[REMOTE 3] Checking tools/list with Bearer token over public HTTPS...")
    r = requests.post(
        f"{public_url}/mcp",
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
        f"{public_url}/mcp",
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
    print(f"  SystemInfo Output preview:\n{res_text[:250]}...")

    print("\n========================================================")
    print("      Remote MCP Endpoint Fully Verified Over HTTPS!    ")
    print("========================================================")

if __name__ == "__main__":
    main()
