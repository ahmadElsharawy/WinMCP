# WinMCP Unified Background Runner
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir

$logDir = "$scriptDir\logs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }

# 1. Stop any existing instances cleanly
& "$scriptDir\stop_winmcp.ps1" | Out-Null
Start-Sleep -Seconds 1

# 2. Launch Gateway and Cloudflare Tunnel detached
Write-Output "Starting Windows MCP Gateway and Tunnel..."
& python "$scriptDir\start_daemon.py"

# 3. Wait for local port 8765 to respond
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

# 4. Wait for Cloudflare Tunnel URL if using Quick Tunnel
$isCustom = $false
$envFile = "$scriptDir\.env"
if (Test-Path $envFile) {
    $modeLine = Get-Content $envFile -ErrorAction SilentlyContinue | Where-Object { $_ -match "^WINMCP_TUNNEL_MODE=Custom" }
    if ($modeLine) { $isCustom = $true }
}

if (-not $isCustom) {
    $tunnelUrl = $null
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $cfErr = "$logDir\cloudflared_error.log"
        if (Test-Path $cfErr) {
            $content = Get-Content $cfErr -ErrorAction SilentlyContinue
            foreach ($line in $content) {
                if ($line -match "(https://[a-zA-Z0-9-]+\.trycloudflare\.com)") {
                    $tunnelUrl = $Matches[1]
                    break
                }
            }
        }
        if ($tunnelUrl) { break }
    }
    if ($tunnelUrl) {
        Write-Output "Cloudflare Tunnel URL: $tunnelUrl"
    }
}

Write-Output "WinMCP started successfully."
