# WinMCP Cleanup / Stopper Script
Write-Output "Stopping WinMCP processes..."

# Stop windows-mcp-server
Get-Process -Name "windows-mcp-server" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Write-Output "Terminating windows-mcp-server (PID: $($_.Id))..."
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    } catch {}
}

# Stop cloudflared
Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Write-Output "Terminating cloudflared (PID: $($_.Id))..."
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    } catch {}
}

# Stop rathole
Get-Process -Name "rathole" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Write-Output "Terminating rathole (PID: $($_.Id))..."
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    } catch {}
}

# Stop python processes running server.py
try {
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe' or Name = 'pythonw.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "gateway[\\/]server\.py|start_daemon\.py" } | ForEach-Object {
        try {
            Write-Output "Terminating WinMCP Gateway Python (PID: $($_.ProcessId))..."
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        } catch {}
    }
} catch {}

Write-Output "WinMCP stopped."
