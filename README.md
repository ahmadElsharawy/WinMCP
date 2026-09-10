# 🚀 Windows MCP Server & Remote AI Desktop Controller

A complete, turnkey solution that turns any Windows PC or laptop into a secure, remotely accessible AI desktop automation server. Control your entire Windows environment (**Excel, Word, Outlook, Telegram, Web Browsers, Filesystem, PowerShell, Services, and System Administration**) remotely via **Claude** and **ChatGPT** without port forwarding, dynamic DNS headaches, or router configuration.

Powered by the official open-source core engine:
[deploymenttheory/windows-mcp-server](https://github.com/deploymenttheory/windows-mcp-server)

---

## 📦 100% Portable & Self-Contained

This project is engineered to be fully portable and path-independent:
- **Zero Hardcoded Paths**: Automatically detects its current workspace location dynamically on any Windows machine or drive letter.
- **Copy & Run Anywhere**: Clone or move the folder to any machine or USB drive, and run `install.bat` or `winmcp`.
- **Turnkey Setup**: Works out of the box with a single double-click or PowerShell one-liner.

---

## ⚡ 1. Quick Installation (Turnkey One-Liner / Double-Click)

### Method 1 (Easiest - Double-Click):
1. Clone or download the repository:
   ```bash
   git clone https://github.com/ahmadElsharawy/WinMCP.git
   cd WinMCP
   ```
2. Double-click **`install.bat`**.

### Method 2 (PowerShell):
Open a **PowerShell** prompt inside the project folder and run:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; .\install.ps1
```

### What does the automated installer do?
1. **Auto-Detects Paths**: Resolves all relative folders, Python executables, and binaries automatically.
2. **Cloudflare Tunnel Setup**: Prompts you to select between a free instant **Quick Tunnel** (`*.trycloudflare.com`) or a permanent **Custom Domain** (Cloudflare Zero Trust Tunnel).
3. **Environment & Dependencies**: Validates Python and installs required lightweight modules (`flask`, `requests`).
4. **Binary Provisioning**: Downloads or provisions verified releases for `windows-mcp-server.exe`, `cloudflared.exe`, and `nssm.exe`.
5. **Generates Cryptographic Security Token**: Creates a high-entropy 256-bit Bearer token stored in a protected `.env` file.
6. **Configures Dual Background Persistence**:
   - Registers a Windows Scheduled Task (`WindowsMCPServer`).
   - Generates a silent background launcher (`WinMCP_AutoStart.vbs`) in your Windows Startup folder (`shell:startup`).
   - Ensures WinMCP survives system reboots and stays continuously available.
7. **Registers Global CLI (`winmcp`)**: Adds the project folder to the User `PATH` environment variable so you can run `winmcp` from any terminal.
8. **Starts the Server & Displays Endpoints**: Outputs your ready-to-copy endpoints for Claude and ChatGPT along with authentication credentials.

---

## 🖥️ 2. Interactive Control Center Dashboard (CMD & Terminal)

Manage and control every single aspect of your WinMCP server directly from an interactive CMD / PowerShell terminal dashboard — with full control modeled after CTRLMCP:

### Launching the Dashboard:
- **From Any CMD / Terminal**: Simply type `winmcp` (or `WINMCP`) and press Enter from any terminal window.
- **Double-Click**: Double-click **`winmcp.bat`** or **`dashboard.bat`** in the project folder.
- **Optional Web Dashboard**: If you ever prefer a browser view, run `winmcp web` or open [http://127.0.0.1:8765/dashboard](http://127.0.0.1:8765/dashboard).

### CMD Dashboard Menu Features:
```text
============================================================
                 WINMCP SERVER INFORMATION                  
============================================================
Service Status : ACTIVE (RUNNING)
Gateway Port   : 8765 (LISTENING)
Engine Binary  : windows-mcp-server (PID: 364)
Cloudflare PID : CONNECTED
Tunnel Mode    : Custom (or Quick)
Public Endpoint: https://winmcp.yourdomain.com
Current Token  : <256-bit Token>
Logon AutoStart: Enabled
Windows Service: Installed / Running

------------------------------------------------------------
🔗 DIRECT CONNECTION URLS / روابط الاتصال المباشرة:
------------------------------------------------------------
1. Claude Web (claude.ai -> Settings -> Connectors):
   URL       : https://winmcp.yourdomain.com/sse?token=<Token>
   Transport : Server-Sent Events (SSE)

2. ChatGPT (Desktop MCP / Custom GPTs):
   Direct URL: https://winmcp.yourdomain.com/mcp
   Bearer    : Bearer <Token>

3. Claude Desktop Config (claude_desktop_config.json):
{
  "mcpServers": {
    "windows": {
      "command": "C:\\path\\to\\WinMCP\\bin\\windows-mcp-server.exe",
      "args": ["stdio", "--toolsets", "all"]
    }
  }
}
============================================================

MANAGEMENT & CONTROL OPTIONS / خيارات التحكم والإدارة:
------------------------------------------------------------
  [1]  🎲 Change Token to Random (تغيير التوكن عشوائياً وفصل القديم)
  [2]  ✍️  Change Token to Custom (كتابة توكن مخصص من اختيارك)
  [3]  🔄 Restart WinMCP Server & Tunnel (إعادة تشغيل الخادم والنفق)
  [4]  🛑 Stop WinMCP Server (إيقاف تشغيل الخادم)
  [5]  ▶️  Start WinMCP Server (تشغيل الخادم في الخلفية)
  [6]  🌐 Switch / Set Custom Domain (تغيير أو ربط دومين مخصص)
  [7]  📜 View Live Audit Logs (عرض سجلات النشاط المباشرة)
  [8]  🧪 Interactive Tool Runner (تشغيل وتجربة أي أداة مباشرة)
  [9]  ⚙️  Toggle Logon Auto-Start (تفعيل/تعطيل بدء التشغيل التلقائي)
  [10] 🚀 Manage Windows Service (تثبيت/إلغاء خدمة ويندوز 24/7)
  [11] 📋 Refresh Screen (تحديث الشاشة)
  [12] 🗑️  Clean Uninstall WinMCP (حذف الأداة بالكامل من جذورها)
  [0]  🚪 Exit (خروج)
------------------------------------------------------------
```

---

## 🔄 3. Background Execution & Persistence Modes

WinMCP supports two execution modes designed for different deployment scenarios:

### Mode 1: Interactive Desktop Session (Default & Recommended)
- **How it works**: Launches silently upon user login in the active Windows interactive user session.
- **Key Capability**: Full access to the active user desktop (Session 1+). AI models can:
  - Automate native desktop applications: **Excel, Word, Outlook, Telegram, Chrome, Edge**.
  - Capture live UI hierarchy element trees (`Snapshot`).
  - Take desktop screenshots (`Screenshot`).
  - Perform mouse clicks, keyboard input, and window manipulation without Session 0 security isolation.
- **Controls**:
  ```powershell
  winmcp autostart enable   # Enable automatic start on user logon
  winmcp autostart disable  # Disable automatic start on user logon
  ```

### Mode 2: Native Windows Service (Headless VPS / No GUI Only)
> [!WARNING]
> Windows Services run in **Session 0 (Isolated)**. In this mode, **screenshots are blank** and **browsers/apps cannot interact with your physical screen**. Do NOT use this mode if you need desktop automation. Use Mode 1 (`install.bat`) instead.

- **How it works**: Installs WinMCP as a native Windows service named `WinMCP-Service` in `services.msc`.
- **Key Capability**: Boots at system startup before any user logs in. Strictly for headless Cloud VPS environments without display monitors.
- **Controls**:
  - **One-Click**: Double-click **`uninstall_service.bat`** to remove if accidentally installed.
  - **Via CLI**:
    ```powershell
    winmcp service uninstall  # Remove the Windows service from system
    ```

---

## 🌐 4. Cloudflare Tunnel Connectivity (Zero Port Forwarding)

WinMCP provides secure, inbound HTTPS connectivity through Cloudflare Edge without opening firewall ports:

### Option 1: Quick Tunnel (Free & Instant - No Domain Required)
- Generates an ephemeral encrypted tunnel on `*.trycloudflare.com`.
- Zero configuration required.
- Check current tunnel URL anytime with:
  ```powershell
  winmcp status
  ```

### Option 2: Custom Domain Tunnel (Permanent & Fixed)
For a permanent, fixed URL (e.g., `https://winmcp.yourdomain.com`):
1. In the [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com) -> Networks -> Tunnels:
   - Create a tunnel and copy your **Tunnel Token** (starts with `eyJh...`).
   - Add a Public Hostname: Service Type = `HTTP`, URL = `localhost:8765`.
2. Configure your domain anytime via CLI:
   ```powershell
   winmcp domain
   ```
   WinMCP automatically verifies your domain connectivity against Cloudflare DNS and saves the tunnel configuration.

---

## 🛠️ 5. The `winmcp` Management CLI

Manage your entire server lifecycle from any terminal window anywhere on your system:

| Command | Description |
| :--- | :--- |
| `winmcp dashboard` | Open the Interactive Web Control Center Dashboard in your default browser |
| `winmcp status` | Display the comprehensive status dashboard, active tunnel URL, and running processes |
| `winmcp start` | Start the Windows MCP Server, Gateway, and Cloudflare Tunnel |
| `winmcp stop` | Gracefully terminate all WinMCP processes |
| `winmcp restart` | Restart server components and refresh tunnel connections |
| `winmcp domain` | Launch the interactive domain configuration wizard (Quick Tunnel vs. Custom Domain) |
| `winmcp token` | Display your current Bearer authentication token |
| `winmcp token new` | Generate a new high-entropy 256-bit random Bearer token and reload server |
| `winmcp token set <key>` | Set a custom Bearer token of your choice and reload server |
| `winmcp token change` | Interactive token management wizard |
| `winmcp service install` | Install WinMCP as a permanent 24/7 Windows Service |
| `winmcp service uninstall` | Remove the Windows Service registration |
| `winmcp autostart enable` | Enable silent automatic startup on user login |
| `winmcp autostart disable`| Remove silent startup shortcut and task |
| `winmcp logs` | Stream live audit and operation logs in real time |
| `winmcp uninstall` | Launch the root uninstaller wizard (Reset clean or Full purge) |
| `winmcp help` | Show the CLI command reference |

---

## 🔑 6. Token Management

Easily rotate or customize your Bearer authentication token at any time:

1. **Generate a Random 256-bit Token**:
   ```powershell
   winmcp token new
   ```
2. **Assign a Custom Token**:
   ```powershell
   winmcp token set YourCustomSecretKey123
   ```
3. **Interactive Menu / Double-Click**:
   - Run `winmcp token change` or double-click **`change_token.bat`**.

All token updates immediately persist to `.env` and automatically restart the running gateway session.

---

## 🗑️ 7. Complete Root Uninstaller

If you wish to reset your system or completely remove WinMCP:

- **Quick Double-Click**: Run **`uninstall.bat`**.
- **Via CLI**:
  ```powershell
  winmcp uninstall
  ```

### What does the Root Uninstaller do?
1. **Terminates Running Processes**: Kills all associated processes (`windows-mcp-server`, `cloudflared`, `python/gateway`).
2. **Removes Windows Service**: Unregisters `WinMCP-Service` from `services.msc`.
3. **Deletes Scheduled Tasks**: Removes the `WindowsMCPServer` logon task.
4. **Removes Startup Launcher**: Cleans `WinMCP_AutoStart.vbs` from `shell:startup`.
5. **Cleans Environment PATH**: Removes the WinMCP directory from User `PATH`.
6. **Cleans Cache & Configurations**: Resets `.env`, logs, and temporary state.

### Uninstallation Options:
- **[1] Reset & Clean (Recommended for fresh testing)**: Cleans all background registrations, services, and tokens while preserving source code so you can run `install.bat` again cleanly.
- **[2] Full Purge**: Performs all cleaning steps above and deletes the entire WinMCP folder from disk.

---

## 📂 Universal File Engine (Direct Office, PDF, CSV, ZIP & Code Manipulation)

WinMCP includes an integrated **Universal File Engine** that enables remote AI agents (ChatGPT, Claude) to directly read, search, analyze, and edit any file format on your Windows filesystem without opening desktop applications, taking screenshots, or moving the mouse:

| File Format | Supported Capabilities |
| :--- | :--- |
| **Word (`.docx`, `.dotx`)** | Directly reads headings, paragraphs, and tables as structured Markdown. Performs in-place text and table replacements while preserving fonts, formatting, and styles. |
| **Excel (`.xlsx`, `.xlsm`, `.csv`, `.tsv`)** | Parses all sheets into structured Markdown tables with pagination (`max_rows`, `sheet`). In-place cell value and text replacements. |
| **PDF (`.pdf`)** | Extracts text page-by-page with page range pagination (`start_page`, `max_pages`) without context overflow. |
| **PowerPoint (`.pptx`)** | Extracts slide titles, body bullet points, tables, and presenter notes. In-place slide text replacement. |
| **Archives (`.zip`)** | Lists complete archive directory trees and metadata, or reads specific files inside the archive directly (`inner_path`). |
| **Code & Configs (`.py`, `.json`, `.yaml`, `.sql`, etc.)** | Auto-detects text encodings (UTF-8, Arabic CP1256, UTF-16, ANSI) with pagination (`start_line`, `max_lines`) and in-place search-and-replace. |

---

## 🤖 7. Connecting AI Clients

### 1. Claude Web (`claude.ai` Custom Connectors)
1. Go to **claude.ai** -> **Settings** -> **Integrations** (or **Connectors**).
2. Click **Add Custom MCP Connector**.
3. Enter your full SSE endpoint with the embedded token parameter:
   ```
   https://<YOUR_TUNNEL_URL>/sse?token=<YOUR_TOKEN>
   ```
4. Claude establishes a live Server-Sent Events (SSE) stream and retrieves the available Windows tools automatically.

---

### 2. ChatGPT (Custom GPTs / Actions)
1. Go to **ChatGPT** -> **Explore GPTs** -> **Create** -> **Configure** -> **Actions** -> **Create new action**.
2. In the **Servers / URL** field:
   ```
   https://<YOUR_TUNNEL_URL>/mcp
   ```
3. Under **Authentication**:
   - Choose **Bearer**.
   - Paste your token (retrieved via `winmcp token`).
4. ChatGPT will discover all 37 desktop control tools.

---

### 3. Claude Desktop (Local stdio Connection)
Add the following to `%APPDATA%\Claude\claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "windows": {
      "command": "C:\\path\\to\\WinMCP\\bin\\windows-mcp-server.exe",
      "args": ["stdio", "--toolsets", "all"]
    }
  }
}
```
*(Replace `C:\\path\\to\\WinMCP` with the actual path to your WinMCP folder).*

---

## 🔒 8. Security & Audit Logging

- **Strict Bearer Authentication**: Requests missing or supplying an incorrect token are rejected immediately with `401 Unauthorized`.
- **Tool Risk Classification**:
  - **READ ONLY**: System inspection, process list, monitors, screenshots, and accessibility element trees.
  - **LOW RISK**: Application launch, mouse clicks, text typing, navigation, and keypresses.
  - **HIGH RISK**: PowerShell command execution, file modification, registry edits, process termination, and service controls.
- **Audit Logging**: All tool invocations and system actions are logged in real time to `logs/gateway-audit.log`, with passwords and sensitive fields automatically masked (`***MASKED***`).

---

## 📄 License

This repository is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
