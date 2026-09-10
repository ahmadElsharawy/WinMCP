import subprocess
import os
import sys
import time

script_dir = os.path.dirname(os.path.abspath(__file__))
gateway_py = os.path.join(script_dir, "gateway", "server.py")
pythonw_exe = sys.executable.replace("python.exe", "pythonw.exe")
if not os.path.exists(pythonw_exe):
    pythonw_exe = sys.executable

cf_exe = os.path.join(script_dir, "tunnel", "cloudflare", "cloudflared.exe")
log_dir = os.path.join(script_dir, "logs")
os.makedirs(log_dir, exist_ok=True)

flags = 0x08000000 | 0x00000008 # CREATE_NO_WINDOW | DETACHED_PROCESS

# 1. Start gateway
gw_out = open(os.path.join(log_dir, "gateway.log"), "a", encoding="utf-8")
gw_err = open(os.path.join(log_dir, "gateway_error.log"), "a", encoding="utf-8")
p_gw = subprocess.Popen([pythonw_exe, gateway_py], stdout=gw_out, stderr=gw_err, creationflags=flags)

# 2. Start cloudflared
cf_out = open(os.path.join(log_dir, "cloudflared.log"), "a", encoding="utf-8")
cf_err = open(os.path.join(log_dir, "cloudflared_error.log"), "a", encoding="utf-8")
p_cf = subprocess.Popen([cf_exe, "tunnel", "--url", "http://127.0.0.1:8765"], stdout=cf_out, stderr=cf_err, creationflags=flags)

print(f"Detached Gateway PID: {p_gw.pid}, Cloudflared PID: {p_cf.pid}")
