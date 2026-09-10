# WinMCP Cleanup / Stopper Script
Write-Output "Stopping WinMCP processes..."

# Stop windows-mcp-server
Get-Process -Name "windows-mcp-server" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Output "Terminating windows-mcp-server (PID: $($_.Id))..."
    Stop-Process -Id $_.Id -Force
}

# Stop cloudflared
Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Output "Terminating cloudflared (PID: $($_.Id))..."
    Stop-Process -Id $_.Id -Force
}

# Stop rathole
Get-Process -Name "rathole" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Output "Terminating rathole (PID: $($_.Id))..."
    Stop-Process -Id $_.Id -Force
}

# Stop python processes running server.py
Get-CimInstance Win32_Process -Filter "Name = 'python.exe' or Name = 'pythonw.exe'" | Where-Object { $_.CommandLine -match "gateway\\server\.py" } | ForEach-Object {
    Write-Output "Terminating WinMCP Gateway Python (PID: $($_.ProcessId))..."
    Stop-Process -Id $_.ProcessId -Force
}

Write-Output "WinMCP stopped."
