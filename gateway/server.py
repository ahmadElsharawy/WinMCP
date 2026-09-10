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
    raise RuntimeError("WINMCP_AUTH_TOKEN is not configured! Please check your .env file.")

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
        self.start_process()

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
                bufsize=0
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

            notif = {"jsonrpc": "2.0", "method": "notifications/initialized"}
            self.proc.stdin.write(json.dumps(notif) + "\n")
            self.proc.stdin.flush()
        except Exception as e:
            sys.stderr.write(f"Handshake failed: {e}\n")

    def dispatch(self, req: Dict[str, Any]) -> Dict[str, Any]:
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

@app.route("/", methods=["GET"])
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
    is_alive = BACKEND.proc and BACKEND.proc.poll() is None
    return jsonify({
        "status": "ok" if is_alive else "degraded",
        "backend_alive": is_alive,
        "active_sessions": len(SESSIONS.sessions),
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()
    }), (200 if is_alive else 503)

@app.route("/mcp", methods=["POST"])
@app.route("/rpc", methods=["POST"])
def mcp_streamable_http():
    """Streamable HTTP / Direct JSON-RPC endpoint (used by ChatGPT and Claude Desktop)."""
    start_time = time.time()
    client_ip = request.remote_addr

    if not check_auth():
        log_audit({
            "client_ip": client_ip,
            "method": "POST /mcp",
            "status": "unauthorized",
            "reason": "Invalid or missing token"
        })
        return jsonify({"error": "Unauthorized: Invalid or missing token"}), 401

    try:
        req_json = request.get_json(force=True)
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
        "method": "POST /mcp",
        "rpc_method": rpc_method,
        "tool_name": tool_name,
        "risk_level": risk_level,
        "safe_args": safe_args,
        "duration_ms": duration_ms,
        "status": "error" if is_error else "success"
    })

    return jsonify(resp)

@app.route("/sse", methods=["GET"])
def sse_handshake():
    """Server-Sent Events endpoint for MCP SSE clients (Claude Web / claude.ai)."""
    client_ip = request.remote_addr
    if not check_auth():
        log_audit({
            "client_ip": client_ip,
            "method": "GET /sse",
            "status": "unauthorized",
            "reason": "Invalid or missing token"
        })
        return jsonify({"error": "Unauthorized: Invalid or missing token"}), 401

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

    # Route response into the SSE stream queue
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
