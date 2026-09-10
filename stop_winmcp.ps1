# WinMCP Cleanup / Stopper Script
Write-Output "Stopping WinMCP processes..."

# 1. Stop windows-mcp-server
Get-Process -Name "windows-mcp-server" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Write-Output "Terminating windows-mcp-server (PID: $($_.Id))..."
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    } catch {}
}
cmd.exe /c "taskkill /F /IM windows-mcp-server.exe /T > nul 2>&1"
cmd.exe /c "wmic process where `"name='windows-mcp-server.exe'`" call terminate > nul 2>&1"

# 2. Stop cloudflared
Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Write-Output "Terminating cloudflared (PID: $($_.Id))..."
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    } catch {}
}
cmd.exe /c "wmic process where `"name='cloudflared.exe' and CommandLine like '%WinMCP%'`" call terminate > nul 2>&1"

# 3. Stop rathole
Get-Process -Name "rathole" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Write-Output "Terminating rathole (PID: $($_.Id))..."
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    } catch {}
}

# 4. Stop python processes running gateway/server.py, start_daemon.py, or service_runner.py
try {
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe' or Name = 'pythonw.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "gateway[\\/]server\.py|start_daemon\.py|service_runner\.py" } | ForEach-Object {
        try {
            Write-Output "Terminating WinMCP Gateway Python (PID: $($_.ProcessId))..."
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            cmd.exe /c "wmic process where `"ProcessId=$($_.ProcessId)`" call terminate > nul 2>&1"
        } catch {}
    }
} catch {}

Write-Output "WinMCP stopped."
