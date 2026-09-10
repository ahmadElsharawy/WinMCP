"""
WinMCP 24/7 Windows Service Master Runner
Coordinates the Gateway server and Cloudflare Tunnel under Windows Service (NSSM).
Runs 100% silently in background with zero console windows.
"""

import os
import sys
import time
import signal
import subprocess
import glob

# Ensure user site-packages are loaded even when running as LocalSystem service
user_packages = glob.glob(r"C:\Users\*\AppData\Local\Python\*\Lib\site-packages") + glob.glob(r"C:\Users\*\AppData\Roaming\Python\*\site-packages")
for p in user_packages:
    if os.path.isdir(p) and p not in sys.path:
        sys.path.insert(0, p)

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
GATEWAY_SERVER = os.path.join(PROJECT_DIR, "gateway", "server.py")
CLOUDFLARED_EXE = os.path.join(PROJECT_DIR, "tunnel", "cloudflare", "cloudflared.exe")
LOG_DIR = os.path.join(PROJECT_DIR, "logs")
ENV_PATH = os.path.join(PROJECT_DIR, ".env")

os.makedirs(LOG_DIR, exist_ok=True)

# Read environment config
tunnel_mode = "Quick"
tunnel_token = ""
if os.path.exists(ENV_PATH):
    with open(ENV_PATH, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip()
                if k == "WINMCP_TUNNEL_MODE":
                    tunnel_mode = v
                elif k == "WINMCP_TUNNEL_TOKEN":
                    tunnel_token = v

cf_proc = None

def cleanup(*args):
    global cf_proc
    if cf_proc and cf_proc.poll() is None:
        try:
            cf_proc.terminate()
            cf_proc.wait(timeout=3)
        except Exception:
            try:
                cf_proc.kill()
            except Exception:
                pass
    sys.exit(0)

signal.signal(signal.SIGINT, cleanup)
signal.signal(signal.SIGTERM, cleanup)

# 1. Start Cloudflared
creationflags = 0x08000000 if sys.platform == "win32" else 0
startupinfo = None
if sys.platform == "win32":
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = subprocess.SW_HIDE

if os.path.exists(CLOUDFLARED_EXE):
    cf_out = open(os.path.join(LOG_DIR, "cloudflared.log"), "w", encoding="utf-8")
    cf_err = open(os.path.join(LOG_DIR, "cloudflared_error.log"), "w", encoding="utf-8")
    if tunnel_mode == "Custom" and tunnel_token:
        args = [CLOUDFLARED_EXE, "tunnel", "run", "--token", tunnel_token]
    else:
        args = [CLOUDFLARED_EXE, "tunnel", "--url", "http://127.0.0.1:8765", "--protocol", "http2"]
    
    cf_proc = subprocess.Popen(
        args,
        stdout=cf_out,
        stderr=cf_err,
        creationflags=creationflags,
        startupinfo=startupinfo
    )

# 2. Run Gateway in main thread
# Import and run gateway
sys.path.insert(0, PROJECT_DIR)
import gateway.server

# Start Flask server
gateway.server.app.run(
    host=gateway.server.HOST,
    port=gateway.server.PORT,
    threaded=True,
    use_reloader=False
)
