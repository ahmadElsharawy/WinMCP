# WinMCP Unified Background Runner
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$logDir = "$scriptDir\logs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }

# 1. Start Gateway
$gatewayPy = "$scriptDir\gateway\server.py"
$gatewayLog = "$logDir\gateway.log"
Write-Output "Starting Windows MCP Gateway..."
$gatewayProc = Start-Process -FilePath "python.exe" -ArgumentList "-u `"$gatewayPy`"" -RedirectStandardOutput $gatewayLog -RedirectStandardError "$logDir\gateway_error.log" -PassThru -WindowStyle Hidden

# 2. Wait for local port 8765 to respond
$ready = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    try {
        $res = Invoke-RestMethod -Uri "http://127.0.0.1:8765/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($res.status -eq "ok") {
            $ready = $true
            break
        }
    } catch {}
}

if ($ready) {
    Write-Output "Gateway is ready on http://127.0.0.1:8765"
} else {
    Write-Warning "Gateway took longer than expected to initialize. Check logs/gateway.log"
}

# 3. Start Cloudflare Tunnel
$cfExe = "$scriptDir\tunnel\cloudflare\cloudflared.exe"
if (Test-Path $cfExe) {
    Write-Output "Starting Cloudflare Tunnel..."
    $tunnelLog = "$logDir\cloudflared.log"
    $cfProc = Start-Process -FilePath $cfExe -ArgumentList "tunnel --url http://127.0.0.1:8765" -RedirectStandardOutput $tunnelLog -RedirectStandardError "$logDir\cloudflared_error.log" -PassThru -WindowStyle Hidden
}

Write-Output "WinMCP started successfully."
