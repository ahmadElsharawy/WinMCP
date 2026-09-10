"""
WinMCP Context Engine
Provides full situational awareness for remote AI agents (ChatGPT, Claude):
- Real-time detection of open File Explorer folders with exact disk paths.
- Active & background application windows with open document names.
- Active foreground window detection.
- Windows Recent files and folders resolution.
- Smart auto-resolution from partial or contextual names ("the open file", "محضر اجتماع", "active folder").
"""

import os
import sys
import glob
import json
import subprocess
import ctypes
from ctypes import wintypes
from typing import Dict, Any, List, Optional

# Ensure user site-packages are loaded
user_packages = glob.glob(r"C:\Users\*\AppData\Local\Python\*\Lib\site-packages") + glob.glob(r"C:\Users\*\AppData\Roaming\Python\*\site-packages")
for p in user_packages:
    if os.path.isdir(p) and p not in sys.path:
        sys.path.insert(0, p)


def get_foreground_window_info() -> Dict[str, Any]:
    """Returns the title, process name, and handle of the window currently in focus."""
    if sys.platform != "win32":
        return {"title": "", "process": "", "hwnd": 0}
    try:
        user32 = ctypes.windll.user32
        hwnd = user32.GetForegroundWindow()
        if not hwnd:
            return {"title": "", "process": "", "hwnd": 0}

        length = user32.GetWindowTextLengthW(hwnd)
        buff = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buff, length + 1)
        title = buff.value

        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        
        proc_name = ""
        try:
            import psutil
            proc_name = psutil.Process(pid.value).name()
        except Exception:
            pass

        return {"title": title, "process": proc_name, "hwnd": hwnd, "pid": pid.value}
    except Exception:
        return {"title": "", "process": "", "hwnd": 0}


def get_open_explorer_folders() -> List[Dict[str, str]]:
    """Inspects all open File Explorer windows and returns their exact directory paths."""
    ps = """
$ProgressPreference = 'SilentlyContinue'
$folders = @()
try {
    $shell = New-Object -ComObject Shell.Application
    foreach ($w in $shell.Windows()) {
        try {
            $p = $w.Document.Folder.Self.Path
            if ($p -and (Test-Path $p)) {
                $folders += [PSCustomObject]@{
                    title = $w.LocationName
                    path = $p
                }
            }
        } catch {}
    }
} catch {}
$folders | ConvertTo-Json -Depth 2
"""
    try:
        creationflags = 0x08000000 if sys.platform == "win32" else 0
        res = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            creationflags=creationflags, timeout=8
        )
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout.strip())
            if isinstance(data, dict):
                return [data]
            elif isinstance(data, list):
                return data
    except Exception:
        pass
    return []


def get_open_windows() -> List[Dict[str, Any]]:
    """Returns all open visible application windows, filtering out internal background helper windows."""
    ps = """
$ProgressPreference = 'SilentlyContinue'
@(Get-Process | Where-Object { $_.MainWindowTitle -ne '' } | ForEach-Object {
    [PSCustomObject]@{
        process = $_.ProcessName
        title = $_.MainWindowTitle
        pid = $_.Id
    }
}) | ConvertTo-Json -Depth 2
"""
    try:
        creationflags = 0x08000000 if sys.platform == "win32" else 0
        res = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            creationflags=creationflags, timeout=8
        )
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout.strip())
            if isinstance(data, dict):
                return [data]
            elif isinstance(data, list):
                return data
    except Exception:
        pass
    return []


def get_recent_files(limit: int = 15) -> List[Dict[str, Any]]:
    """Resolves Windows Recent files from shell:recent to actual disk paths."""
    ps = f"""
$ProgressPreference = 'SilentlyContinue'
$wsh = New-Object -ComObject WScript.Shell
$items = @()
$recentDir = [System.Environment]::GetFolderPath('Recent')
if (Test-Path $recentDir) {{
    @(Get-ChildItem -Path $recentDir -Filter '*.lnk' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First {limit} | ForEach-Object {{
            try {{
                $sc = $wsh.CreateShortcut($_.FullName)
                if ($sc.TargetPath -and (Test-Path $sc.TargetPath)) {{
                    $isDir = Test-Path -Path $sc.TargetPath -PathType Container
                    $items += [PSCustomObject]@{{
                        name = $_.Name.Replace('.lnk', '')
                        path = $sc.TargetPath
                        is_dir = $isDir
                        last_modified = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                    }}
                }}
            }} catch {{}}
        }})
}}
$items | ConvertTo-Json -Depth 2
"""
    try:
        creationflags = 0x08000000 if sys.platform == "win32" else 0
        res = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            creationflags=creationflags, timeout=8
        )
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout.strip())
            if isinstance(data, dict):
                return [data]
            elif isinstance(data, list):
                return data
    except Exception:
        pass
    return []


def extract_doc_name_from_title(title: str) -> Optional[str]:
    """Extracts the underlying filename from window titles like 'file.docx - Word'."""
    if not title:
        return None
    # Word: "document.docx - Word" or "document.docx [Compatibility Mode] - Word"
    # Excel: "sheet.xlsx - Excel"
    # Notepad: "notes.txt - Notepad" or "*notes.txt - Notepad"
    # VS Code: "file.py - project - Visual Studio Code"
    clean = title.strip().lstrip("*")
    separators = [" - Word", " - Excel", " - PowerPoint", " - Notepad", " - Acrobat", " - Visual Studio Code", " — "]
    for sep in separators:
        if sep.lower() in clean.lower():
            part = clean.split(sep, 1)[0].strip()
            # Clean compatibility mode
            part = part.replace("[Compatibility Mode]", "").strip()
            return part
    return clean


def smart_resolve_resource(query: str) -> Optional[str]:
    """
    Intelligently maps vague or partial user queries to real, existing filesystem paths:
    - 'active' / 'current' / 'open' -> current open document or active folder
    - 'active_folder' / 'open_folder' -> open File Explorer folder
    - '09-09-2026 محضر اجتماع' -> searches open folders, recent files, Downloads, Desktop
    """
    if not query:
        return None

    q_lower = query.lower().strip()

    # 1. Active Explorer Folder
    open_folders = get_open_explorer_folders()
    if q_lower in ("active_folder", "current_folder", "open_folder", "folder"):
        if open_folders:
            return open_folders[0]["path"]
        return os.path.join(os.path.expanduser("~"), "Desktop")

    # 2. Active Window / Document
    fg = get_foreground_window_info()
    doc_name = extract_doc_name_from_title(fg.get("title", ""))

    if q_lower in ("active", "current", "open", "active_file", "current_file", "open_file"):
        if doc_name:
            query = doc_name
        elif open_folders:
            return open_folders[0]["path"]

    # 3. Direct path check
    if os.path.exists(query):
        return os.path.abspath(query)

    # 4. Check if query matches any open Explorer folder title or path
    for f in open_folders:
        if f.get("title", "").lower() == q_lower or query.lower() in f.get("path", "").lower():
            return f["path"]

    # 5. Search in open Explorer folders for a file matching query
    search_dirs = [f["path"] for f in open_folders if os.path.isdir(f["path"])]
    search_dirs.extend([
        os.path.join(os.path.expanduser("~"), "Downloads", "Documents"),
        os.path.join(os.path.expanduser("~"), "Downloads"),
        os.path.join(os.path.expanduser("~"), "Documents"),
        os.path.join(os.path.expanduser("~"), "Desktop"),
    ])

    # Clean query for file extension guessing
    base_q = query.strip()
    candidate_names = [base_q]
    if not os.path.splitext(base_q)[1]:
        for ext in (".docx", ".xlsx", ".pdf", ".pptx", ".txt", ".csv"):
            candidate_names.append(base_q + ext)

    for d in search_dirs:
        if not os.path.isdir(d):
            continue
        # Direct check
        for c in candidate_names:
            p = os.path.join(d, c)
            if os.path.exists(p):
                return os.path.normpath(p)

        # Substring / partial match inside directory
        try:
            for item in os.listdir(d):
                for c in candidate_names:
                    if c.lower() in item.lower():
                        return os.path.normpath(os.path.join(d, item))
        except Exception:
            pass

    # 6. Check Recent Files
    recent_items = get_recent_files(20)
    for r in recent_items:
        r_path = r.get("path", "")
        r_name = r.get("name", "")
        for c in candidate_names:
            if c.lower() in r_name.lower() or c.lower() in os.path.basename(r_path).lower():
                if os.path.exists(r_path):
                    return os.path.normpath(r_path)

    return None


def get_active_context_report() -> Dict[str, Any]:
    """Generates a complete situational awareness report formatted in clean Markdown."""
    fg = get_foreground_window_info()
    open_folders = get_open_explorer_folders()
    open_windows = get_open_windows()
    recent = get_recent_files(10)

    lines = ["# 🖥️ Windows Active Desktop & Resource Context\n"]

    # Foreground Window
    lines.append("## 🎯 Active Foreground Window:")
    if fg.get("title"):
        doc_extracted = extract_doc_name_from_title(fg['title'])
        resolved_path = smart_resolve_resource(doc_extracted) if doc_extracted else None
        lines.append(f"- **Title:** {fg['title']}")
        lines.append(f"- **Process:** {fg.get('process', 'Unknown')} (PID: {fg.get('pid', 0)})")
        if resolved_path:
            lines.append(f"- **Active File Path:** `{resolved_path}`")
    else:
        lines.append("- *No foreground window detected.*")
    lines.append("")

    # Open Explorer Folders
    lines.append(f"## 📂 Open File Explorer Folders ({len(open_folders)} open):")
    if open_folders:
        for f in open_folders:
            lines.append(f"- **{f.get('title', 'Folder')}**: `{f.get('path', '')}`")
    else:
        lines.append("- *No File Explorer windows currently open.*")
    lines.append("")

    # Open Application Windows
    lines.append(f"## 🪟 Open Application Windows ({len(open_windows)} visible):")
    if open_windows:
        for w in open_windows:
            doc_hint = extract_doc_name_from_title(w.get("title", ""))
            resolved = smart_resolve_resource(doc_hint) if doc_hint else None
            path_info = f" -> File: `{resolved}`" if resolved else ""
            lines.append(f"- **[{w.get('process')}]** {w.get('title')}{path_info}")
    else:
        lines.append("- *No visible application windows.*")
    lines.append("")

    # Recent Files
    lines.append("## 🕒 Recent Documents & Files:")
    if recent:
        for r in recent:
            type_tag = "[Folder]" if r.get("is_dir") else "[File]"
            lines.append(f"- {type_tag} **{r.get('name')}**: `{r.get('path')}` *(Modified: {r.get('last_modified')})*")
    else:
        lines.append("- *No recent items found.*")

    full_text = "\n".join(lines).strip()
    return {
        "content": [{"type": "text", "text": full_text}],
        "isError": False,
        "raw_context": {
            "foreground": fg,
            "open_folders": open_folders,
            "open_windows": open_windows,
            "recent_items": recent
        }
    }
