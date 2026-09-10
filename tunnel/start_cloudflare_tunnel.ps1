# Starts a Cloudflare Quick Tunnel for WinMCP Gateway
$baseDir = Split-Path -Parent $PSScriptRoot
$cfExe = Join-Path $PSScriptRoot "cloudflare\cloudflared.exe"
$logFile = Join-Path $baseDir "logs\cloudflared.log"

Write-Output "Starting Cloudflare Tunnel to http://127.0.0.1:8765..."
& $cfExe tunnel --url http://127.0.0.1:8765 2>&1 | Tee-Object -FilePath $logFile
