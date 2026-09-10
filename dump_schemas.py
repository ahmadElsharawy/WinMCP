import json
from test_stdio_full import MCPTester

tester = MCPTester()
try:
    tester.call("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "inspect", "version": "1.0"}})
    tester.notify("notifications/initialized")
    res = tester.call("tools/list", {})
    tools = res.get("result", {}).get("tools", [])
    interesting = ["FileSystem", "App", "PowerShell", "Invoke", "Click", "Type", "Snapshot"]
    out = {}
    for t in tools:
        if t["name"] in interesting:
            out[t["name"]] = t.get("inputSchema", {})
    with open("tools_schemas.json", "w") as f:
        json.dump(out, f, indent=2)
    print(f"Dumped {len(out)} tool schemas to tools_schemas.json")
finally:
    tester.close()
