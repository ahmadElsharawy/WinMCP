#!/usr/bin/env python3
"""
Windows MCP Gateway & Remote Adapter
Bridges remote AI clients (ChatGPT, Claude Web, Claude Desktop) to the official
windows-mcp-server Go binary over HTTP/SSE with Bearer authentication and audit logging.
"""

import os
import sys
import json
import time
import uuid
import queue
import logging
import datetime
import threading
import subprocess
import re
import secrets
from typing import Dict, Any, Optional
from urllib.parse import parse_qs, urlparse

from flask import Flask, request, Response, jsonify, stream_with_context

# --- Load Configuration ---
GATEWAY_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(GATEWAY_DIR)
ENV_PATH = os.path.join(PROJECT_DIR, ".env")

def load_env(path: str) -> Dict[str, str]:
    config = {}
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    config[k.strip()] = v.strip()
    return config

def save_env_value(key: str, val: str):
    lines = []
    found = False
    if os.path.exists(ENV_PATH):
        with open(ENV_PATH, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip().startswith(f"{key}="):
                    lines.append(f"{key}={val}\n")
                    found = True
                else:
                    lines.append(line)
    if not found:
        lines.append(f"{key}={val}\n")
    with open(ENV_PATH, "w", encoding="utf-8") as f:
        f.writelines(lines)

ENV_CONFIG = load_env(ENV_PATH)

HOST = os.environ.get("WINMCP_HOST", ENV_CONFIG.get("WINMCP_HOST", "127.0.0.1"))
PORT = int(os.environ.get("WINMCP_PORT", ENV_CONFIG.get("WINMCP_PORT", "8765")))
AUTH_TOKEN = os.environ.get("WINMCP_AUTH_TOKEN", ENV_CONFIG.get("WINMCP_AUTH_TOKEN", ""))
BINARY_PATH = os.environ.get("WINMCP_BINARY_PATH", ENV_CONFIG.get("WINMCP_BINARY_PATH", os.path.join(PROJECT_DIR, "bin", "windows-mcp-server.exe")))
TOOLSETS = os.environ.get("WINMCP_TOOLSETS", ENV_CONFIG.get("WINMCP_TOOLSETS", "all"))
LOG_DIR = os.environ.get("WINMCP_LOG_DIR", ENV_CONFIG.get("WINMCP_LOG_DIR", os.path.join(PROJECT_DIR, "logs")))

if not os.path.isabs(BINARY_PATH):
    BINARY_PATH = os.path.normpath(os.path.join(PROJECT_DIR, BINARY_PATH))
if not os.path.isabs(LOG_DIR):
    LOG_DIR = os.path.normpath(os.path.join(PROJECT_DIR, LOG_DIR))

os.makedirs(LOG_DIR, exist_ok=True)
AUDIT_LOG_FILE = os.path.join(LOG_DIR, "gateway-audit.log")
if not AUTH_TOKEN:
    AUTH_TOKEN = secrets.token_hex(32)
    save_env_value("WINMCP_AUTH_TOKEN", AUTH_TOKEN)

# --- Security Classification Matrix ---
READ_ONLY_TOOLS = {
    "SystemInfo", "DisplayInventory", "Snapshot", "Screenshot",
    "GetText", "Assert", "CaptureEvidence", "GuardrailStatus"
}

LOW_RISK_TOOLS = {
    "App", "Click", "Type", "Move", "Scroll", "Shortcut",
    "Wait", "WaitFor", "MultiSelect", "MultiEdit", "Invoke",
    "Clipboard", "Notification"
}

HIGH_RISK_TOOLS = {
    "PowerShell", "FileSystem", "Registry", "ScheduledTask",
    "Process", "Service", "Package", "Kill", "Plan", "Apply"
}

def classify_tool(tool_name: str, args: Dict[str, Any]) -> str:
    # Process / Service read-only actions
    if tool_name == "Process" and args.get("action") == "list":
        return "READ_ONLY"
    if tool_name == "Service" and args.get("action") == "list":
        return "READ_ONLY"
    if tool_name in READ_ONLY_TOOLS:
        return "READ_ONLY"
    if tool_name in LOW_RISK_TOOLS:
        return "LOW_RISK"
    return "HIGH_RISK"

def sanitize_args(args: Any) -> Any:
    """Mask potential secrets in arguments for safe audit logging."""
    if not isinstance(args, dict):
        return args
    sensitive_keys = {"password", "token", "secret", "auth", "key", "credential", "private"}
    sanitized = {}
    for k, v in args.items():
        if any(s in k.lower() for s in sensitive_keys):
            sanitized[k] = "***MASKED***"
        elif isinstance(v, dict):
            sanitized[k] = sanitize_args(v)
        else:
            sanitized[k] = v
    return sanitized

def log_audit(event: Dict[str, Any]):
    """Append a structured JSON record to the tamper-evident audit log."""
    event["timestamp"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        line = json.dumps(event, ensure_ascii=False) + "\n"
        with open(AUDIT_LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception as e:
        sys.stderr.write(f"Audit log write failed: {e}\n")

# --- Persistent MCP Backend Manager ---
class WindowsMCPBackend:
    def __init__(self, binary_path: str, toolsets: str):
        self.binary_path = binary_path
        self.toolsets = toolsets
        self.proc: Optional[subprocess.Popen] = None
        self.lock = threading.Lock()
        self.req_id = 1000
        self.keep_alive_started = False
        self.start_process()
        self._ensure_keep_alive()

    def _ensure_keep_alive(self):
        if not self.keep_alive_started:
            self.keep_alive_started = True
            t = threading.Thread(target=self._keep_alive_loop, daemon=True)
            t.start()

    def _keep_alive_loop(self):
        while True:
            time.sleep(30)
            try:
                with self.lock:
                    if not self.proc or self.proc.poll() is not None:
                        sys.stderr.write("Keepalive: backend is down, reviving...\n")
                        self.start_process()
                    else:
                        ping = {"jsonrpc": "2.0", "id": 99999, "method": "ping"}
                        self.proc.stdin.write(json.dumps(ping) + "\n")
                        self.proc.stdin.flush()
                        _ = self.proc.stdout.readline()
            except Exception as e:
                sys.stderr.write(f"Keepalive ping error: {e}\n")

    def is_alive(self) -> bool:
        with self.lock:
            if not self.proc or self.proc.poll() is not None:
                self.start_process()
            return self.proc is not None and self.proc.poll() is None

    def start_process(self):
        with self.lock:
            if self.proc and self.proc.poll() is None:
                return
            sys.stderr.write(f"Starting windows-mcp-server: {os.path.basename(self.binary_path)} --toolsets {self.toolsets}\n")
            cmd = [self.binary_path, "stdio", "--toolsets", self.toolsets]
            self.proc = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1
            )
            # Drain stderr asynchronously to avoid buffer blocking
            t = threading.Thread(target=self._drain_stderr, daemon=True)
            t.start()

            # Perform initial MCP handshake
            self._do_handshake()

    def _drain_stderr(self):
        p = self.proc
        if not p or not p.stderr:
            return
        for line in p.stderr:
            line = line.strip()
            if line:
                sys.stderr.write(f"[WIN-MCP-CORE] {line}\n")

    def _do_handshake(self):
        try:
            init_msg = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "winmcp-remote-gateway", "version": "1.4.0"}
                }
            }
            raw = json.dumps(init_msg) + "\n"
            self.proc.stdin.write(raw)
            self.proc.stdin.flush()
            resp = self.proc.stdout.readline()
            sys.stderr.write(f"Handshake response: {resp.strip()[:150]}\n")
            try:
                parsed = json.loads(resp)
                if "result" in parsed:
                    self.init_result = parsed["result"]
            except Exception:
                pass
            if not self.init_result:
                self.init_result = {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}, "prompts": {}, "resources": {}},
                    "serverInfo": {"name": "windows-mcp-server", "version": "1.4.0"}
                }

            notif = {"jsonrpc": "2.0", "method": "notifications/initialized"}
            self.proc.stdin.write(json.dumps(notif) + "\n")
            self.proc.stdin.flush()
        except Exception as e:
            sys.stderr.write(f"Handshake failed: {e}\n")

    def dispatch(self, req: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = req.get("method", "")
        req_id = req.get("id")

        # Handle client MCP handshake cleanly without causing duplicate initialize error on Go server
        if method == "initialize":
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": self.init_result or {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}, "prompts": {}, "resources": {}},
                    "serverInfo": {"name": "windows-mcp-server", "version": "1.4.0"}
                }
            }

        if method == "notifications/initialized":
            return None

        with self.lock:
            # Check if process is alive
            if not self.proc or self.proc.poll() is not None:
                sys.stderr.write("Backend process down, restarting...\n")
                self.start_process()

            try:
                raw_in = json.dumps(req) + "\n"
                self.proc.stdin.write(raw_in)
                self.proc.stdin.flush()

                line = self.proc.stdout.readline()
                if not line:
                    raise IOError("Empty response from windows-mcp-server")
                return json.loads(line.strip())
            except Exception as e:
                sys.stderr.write(f"Dispatch error: {e}\n")
                # Attempt recovery
                return {
                    "jsonrpc": "2.0",
                    "id": req.get("id"),
                    "error": {
                        "code": -32603,
                        "message": f"Internal Windows MCP Server error: {str(e)}"
                    }
                }

BACKEND = WindowsMCPBackend(BINARY_PATH, TOOLSETS)

# --- Active SSE Sessions Manager ---
class SessionManager:
    def __init__(self):
        self.sessions: Dict[str, queue.Queue] = {}
        self.lock = threading.Lock()

    def create_session(self) -> str:
        with self.lock:
            s_id = str(uuid.uuid4())
            self.sessions[s_id] = queue.Queue()
            return s_id

    def get_queue(self, s_id: str) -> Optional[queue.Queue]:
        with self.lock:
            return self.sessions.get(s_id)

    def remove_session(self, s_id: str):
        with self.lock:
            self.sessions.pop(s_id, None)

SESSIONS = SessionManager()

# --- Flask Application ---
app = Flask(__name__)

def check_auth() -> bool:
    """Validate Bearer header or ?token= query parameter."""
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[7:].strip()
        if token == AUTH_TOKEN:
            return True
    
    # Query param fallback (essential for Claude Web Connectors)
    q_token = request.args.get("token", "")
    if q_token and q_token == AUTH_TOKEN:
        return True

    return False

@app.before_request
def handle_cors_preflight():
    if request.method == "OPTIONS":
        resp = Response(status=204)
        resp.headers["Access-Control-Allow-Origin"] = "*"
        resp.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        resp.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept"
        return resp

@app.after_request
def add_cors_headers(resp):
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept"
    resp.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    return resp

# --- Endpoints ---

@app.route("/api/info", methods=["GET"])
def index():
    return jsonify({
        "status": "online",
        "service": "Windows MCP Remote Gateway",
        "version": "1.4.0",
        "endpoints": {
            "mcp": "/mcp",
            "sse": "/sse",
            "health": "/health"
        },
        "auth_required": True,
        "instructions": "Send requests with Authorization: Bearer <TOKEN> header or ?token=<TOKEN> query parameter."
    })

@app.route("/health", methods=["GET"])
def health():
    alive = BACKEND.is_alive()
    return jsonify({
        "status": "ok" if alive else "degraded",
        "backend_alive": alive,
        "active_sessions": len(SESSIONS.sessions),
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()
    }), (200 if alive else 503)

@app.route("/mcp", methods=["GET", "POST"])
@app.route("/rpc", methods=["GET", "POST"])
def mcp_streamable_http():
    """Streamable HTTP / Direct JSON-RPC endpoint (used by Claude and ChatGPT)."""
    start_time = time.time()
    client_ip = request.remote_addr

    # If client requests via GET:
    if request.method == "GET":
        if "text/event-stream" in request.headers.get("Accept", ""):
            return sse_handshake()
        return jsonify({
            "status": "online",
            "service": "Windows MCP Remote Gateway",
            "transport": "streamable-http",
            "protocolVersion": "2024-11-05",
            "endpoints": {"mcp": "/mcp", "sse": "/sse"}
        }), 200

    if not check_auth():
        log_audit({
            "client_ip": client_ip,
            "method": f"{request.method} {request.path}",
            "status": "unauthorized",
            "reason": "Invalid or missing token"
        })
        resp = jsonify({"error": "Unauthorized: Invalid or missing token"})
        resp.headers["WWW-Authenticate"] = 'Bearer realm="WinMCP"'
        return resp, 401

    # If client sends an empty POST probe
    if not request.data or request.content_length == 0:
        return jsonify({
            "status": "ok",
            "service": "Windows MCP Remote Gateway",
            "transport": "streamable-http",
            "protocolVersion": "2024-11-05"
        }), 200

    try:
        req_json = request.get_json(force=True, silent=True)
        if not req_json:
            return jsonify({
                "status": "ok",
                "service": "Windows MCP Remote Gateway",
                "transport": "streamable-http"
            }), 200
    except Exception as e:
        return jsonify({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": f"Parse error: {e}"}}), 400

    rpc_method = req_json.get("method", "")
    req_id = req_json.get("id")
    tool_name = ""
    risk_level = "READ_ONLY"

    if rpc_method == "tools/call":
        params = req_json.get("params", {})
        tool_name = params.get("name", "")
        args = params.get("arguments", {})
        risk_level = classify_tool(tool_name, args)
        safe_args = sanitize_args(args)
    else:
        safe_args = sanitize_args(req_json.get("params", {}))

    # Intercept 'initialize' from client to return consistent capabilities
    if rpc_method == "initialize":
        # Pass to backend to let it know the client
        resp = BACKEND.dispatch(req_json)
    elif rpc_method == "notifications/initialized":
        return "", 204
    else:
        resp = BACKEND.dispatch(req_json)

    duration_ms = round((time.time() - start_time) * 1000, 2)
    is_error = "error" in resp or resp.get("result", {}).get("isError", False)

    log_audit({
        "client_ip": client_ip,
        "method": f"{request.method} {request.path}",
        "rpc_method": rpc_method,
        "tool_name": tool_name,
        "risk_level": risk_level,
        "safe_args": safe_args,
        "duration_ms": duration_ms,
        "status": "error" if is_error else "success"
    })

    return jsonify(resp)

@app.route("/sse", methods=["GET", "POST"])
def sse_handshake():
    """Server-Sent Events endpoint for MCP SSE clients (Claude Web / claude.ai)."""
    if request.method == "POST":
        return mcp_streamable_http()

    client_ip = request.remote_addr
    if not check_auth():
        log_audit({
            "client_ip": client_ip,
            "method": "GET /sse",
            "status": "unauthorized",
            "reason": "Invalid or missing token"
        })
        resp = jsonify({"error": "Unauthorized: Invalid or missing token"})
        resp.headers["WWW-Authenticate"] = 'Bearer realm="WinMCP"'
        return resp, 401

    session_id = SESSIONS.create_session()
    session_queue = SESSIONS.get_queue(session_id)

    log_audit({
        "client_ip": client_ip,
        "method": "GET /sse",
        "session_id": session_id,
        "status": "session_opened"
    })

    def event_stream():
        # Step 1: Emit endpoint announcement
        token_param = f"?session_id={session_id}&token={AUTH_TOKEN}"
        endpoint_url = f"/messages{token_param}"
        yield f"event: endpoint\ndata: {endpoint_url}\n\n"

        # Step 2: Stream messages pushed into this session's queue
        try:
            while True:
                try:
                    msg = session_queue.get(timeout=20.0)
                    yield f"event: message\ndata: {json.dumps(msg)}\n\n"
                except queue.Empty:
                    # Keep-alive comment
                    yield ": ping\n\n"
        except GeneratorExit:
            SESSIONS.remove_session(session_id)
            log_audit({
                "client_ip": client_ip,
                "session_id": session_id,
                "status": "session_closed"
            })

    return Response(
        stream_with_context(event_stream()),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )

@app.route("/messages", methods=["POST"])
def post_messages():
    """Receives JSON-RPC messages for an active SSE session."""
    client_ip = request.remote_addr
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401

    session_id = request.args.get("session_id", "")
    session_queue = SESSIONS.get_queue(session_id)
    if not session_queue:
        return jsonify({"error": "Invalid or expired session_id"}), 400

    try:
        req_json = request.get_json(force=True)
    except Exception as e:
        return jsonify({"error": f"Invalid JSON: {e}"}), 400

    rpc_method = req_json.get("method", "")
    tool_name = ""
    risk_level = "READ_ONLY"

    if rpc_method == "tools/call":
        params = req_json.get("params", {})
        tool_name = params.get("name", "")
        args = params.get("arguments", {})
        risk_level = classify_tool(tool_name, args)
        safe_args = sanitize_args(args)
    else:
        safe_args = sanitize_args(req_json.get("params", {}))

    start_time = time.time()
    resp = BACKEND.dispatch(req_json)
    duration_ms = round((time.time() - start_time) * 1000, 2)

    # Route response into the SSE stream queue if not a notification
    if resp is not None:
        session_queue.put(resp)

    log_audit({
        "client_ip": client_ip,
        "method": "POST /messages",
        "session_id": session_id,
        "rpc_method": rpc_method,
        "tool_name": tool_name,
        "risk_level": risk_level,
        "safe_args": safe_args,
        "duration_ms": duration_ms,
        "status": "queued"
    })

    return Response(status=202)

# --- Interactive Web Dashboard & Control API ---

@app.route("/", methods=["GET"])
@app.route("/dashboard", methods=["GET"])
def dashboard():
    """Serves the interactive web dashboard."""
    template_path = os.path.join(GATEWAY_DIR, "templates", "dashboard.html")
    if os.path.exists(template_path):
        with open(template_path, "r", encoding="utf-8") as f:
            return f.read(), 200, {"Content-Type": "text/html; charset=utf-8"}
    return "Dashboard template not found", 404

@app.route("/api/status", methods=["GET"])
def api_status():
    global AUTH_TOKEN
    env_data = load_env(ENV_PATH)
    tunnel_mode = env_data.get("WINMCP_TUNNEL_MODE", "Quick")
    custom_domain = env_data.get("WINMCP_CUSTOM_DOMAIN", "")
    public_url = f"https://{custom_domain}" if (tunnel_mode == "Custom" and custom_domain) else ""
    
    if not public_url and os.path.exists(os.path.join(LOG_DIR, "cloudflared_error.log")):
        try:
            with open(os.path.join(LOG_DIR, "cloudflared_error.log"), "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    m = re.search(r"(https://[a-zA-Z0-9-]+\.trycloudflare\.com)", line)
                    if m:
                        public_url = m.group(1)
        except Exception:
            pass
    if not public_url:
        public_url = f"http://{HOST}:{PORT}"

    core_alive = BACKEND.is_alive()
    core_pid = BACKEND.proc.pid if BACKEND.proc else None

    # Autostart check
    startup_vbs = os.path.join(os.environ.get("APPDATA", ""), "Microsoft", "Windows", "Start Menu", "Programs", "Startup", "WinMCP_AutoStart.vbs")
    autostart_active = os.path.exists(startup_vbs)

    token_masked = AUTH_TOKEN[:6] + "..." + AUTH_TOKEN[-6:] if len(AUTH_TOKEN) > 12 else "****"

    return jsonify({
        "status": "ok",
        "core_alive": core_alive,
        "core_pid": core_pid,
        "gateway_pid": os.getpid(),
        "port": PORT,
        "host": HOST,
        "binary_path": BINARY_PATH,
        "tunnel_mode": tunnel_mode,
        "custom_domain": custom_domain,
        "tunnel_connected": True,
        "public_url": public_url,
        "token": AUTH_TOKEN,
        "token_masked": token_masked,
        "autostart_active": autostart_active,
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()
    })

@app.route("/api/token/rotate", methods=["POST"])
def api_token_rotate():
    global AUTH_TOKEN
    new_token = secrets.token_hex(32)
    save_env_value("WINMCP_AUTH_TOKEN", new_token)
    AUTH_TOKEN = new_token
    return jsonify({"status": "ok", "token": new_token})

@app.route("/api/token/custom", methods=["POST"])
def api_token_custom():
    global AUTH_TOKEN
    data = request.get_json(silent=True) or {}
    new_token = data.get("token", "").strip()
    if len(new_token) < 8:
        return jsonify({"error": "Token must be at least 8 characters"}), 400
    save_env_value("WINMCP_AUTH_TOKEN", new_token)
    AUTH_TOKEN = new_token
    return jsonify({"status": "ok", "token": new_token})

@app.route("/api/domain/update", methods=["POST"])
def api_domain_update():
    data = request.get_json(silent=True) or {}
    mode = data.get("mode", "Quick")
    domain = data.get("domain", "").strip()
    token = data.get("token", "").strip()

    save_env_value("WINMCP_TUNNEL_MODE", mode)
    if mode == "Custom":
        if domain:
            save_env_value("WINMCP_CUSTOM_DOMAIN", domain)
        if token:
            save_env_value("WINMCP_TUNNEL_TOKEN", token)
    else:
        save_env_value("WINMCP_CUSTOM_DOMAIN", "")
        save_env_value("WINMCP_TUNNEL_TOKEN", "")

    # Restart cloudflared in background thread
    def restart_cf():
        subprocess.run(["powershell", "-NoProfile", "-Command", "Stop-Process -Name cloudflared -Force -ErrorAction SilentlyContinue"], capture_output=True)
        time.sleep(1)
        start_daemon_py = os.path.join(PROJECT_DIR, "start_daemon.py")
        subprocess.run([sys.executable, start_daemon_py], capture_output=True)
    
    threading.Thread(target=restart_cf, daemon=True).start()
    return jsonify({"status": "ok", "mode": mode, "domain": domain})

@app.route("/api/server/restart", methods=["POST"])
def api_server_restart():
    def restart_worker():
        time.sleep(1)
        run_winmcp = os.path.join(PROJECT_DIR, "run_winmcp.ps1")
        subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", run_winmcp], capture_output=True)
    
    threading.Thread(target=restart_worker, daemon=True).start()
    return jsonify({"status": "restarting"})

@app.route("/api/server/stop", methods=["POST"])
def api_server_stop():
    def stop_worker():
        time.sleep(1)
        stop_winmcp = os.path.join(PROJECT_DIR, "stop_winmcp.ps1")
        subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", stop_winmcp], capture_output=True)
    
    threading.Thread(target=stop_worker, daemon=True).start()
    return jsonify({"status": "stopping"})

@app.route("/api/autostart/toggle", methods=["POST"])
def api_autostart_toggle():
    startup_vbs = os.path.join(os.environ.get("APPDATA", ""), "Microsoft", "Windows", "Start Menu", "Programs", "Startup", "WinMCP_AutoStart.vbs")
    is_active = os.path.exists(startup_vbs)
    
    script = "uninstall_autostart.ps1" if is_active else "install_autostart.ps1"
    target = os.path.join(PROJECT_DIR, script)
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", target], capture_output=True)
    return jsonify({"status": "ok", "autostart_active": not is_active})

@app.route("/api/service/action", methods=["POST"])
def api_service_action():
    target = os.path.join(PROJECT_DIR, "install_service.ps1")
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", target], capture_output=True)
    return jsonify({"status": "ok"})

@app.route("/api/logs/audit", methods=["GET"])
def api_logs_audit():
    audit_file = os.path.join(LOG_DIR, "gateway-audit.log")
    logs = []
    if os.path.exists(audit_file):
        try:
            with open(audit_file, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()
                for line in reversed(lines[-40:]):
                    line = line.strip()
                    if line:
                        try:
                            logs.append(json.loads(line))
                        except Exception:
                            pass
        except Exception:
            pass
    return jsonify({"logs": logs})

@app.route("/api/tools", methods=["GET"])
def api_tools():
    resp = BACKEND.dispatch({"jsonrpc": "2.0", "id": 9999, "method": "tools/list"})
    tools_raw = (resp.get("result", {}) if resp else {}).get("tools", [])
    
    annotated = []
    for t in tools_raw:
        t_name = t.get("name", "")
        t_risk = classify_tool(t_name, {})
        annotated.append({
            "name": t_name,
            "description": t.get("description", ""),
            "inputSchema": t.get("inputSchema", {}),
            "risk": t_risk
        })
    return jsonify({"tools": annotated})

@app.route("/api/tools/execute", methods=["POST"])
def api_tools_execute():
    data = request.get_json(silent=True) or {}
    tool_name = data.get("name", "")
    args = data.get("arguments", {})

    if not tool_name:
        return jsonify({"error": "Missing tool name"}), 400

    resp = BACKEND.dispatch({
        "jsonrpc": "2.0",
        "id": int(time.time()),
        "method": "tools/call",
        "params": {
            "name": tool_name,
            "arguments": args
        }
    })
    return jsonify(resp)

if __name__ == "__main__":
    print(f"==================================================")
    print(f"   Windows MCP Remote Gateway Server Starting")
    print(f"==================================================")
    print(f" Host: {HOST}")
    print(f" Port: {PORT}")
    print(f" Binary: {os.path.basename(BINARY_PATH)}")
    print(f" Toolsets: {TOOLSETS}")
    print(f" Auth Token: {AUTH_TOKEN[:8]}...{AUTH_TOKEN[-6:]}")
    print(f" Local Endpoint: http://{HOST}:{PORT}/mcp")
    print(f" SSE Endpoint:   http://{HOST}:{PORT}/sse")
    print(f"==================================================")
    app.run(host=HOST, port=PORT, threaded=True)
