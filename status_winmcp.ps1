# WinMCP Status Checker Script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Output "=================================================="
Write-Output "              WinMCP Status Report                "
Write-Output "=================================================="

# 1. Check Processes
$procs = @("windows-mcp-server", "cloudflared", "rathole")
foreach ($p in $procs) {
    $found = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($found) {
        Write-Output "$p : RUNNING (PIDs: $(($found | ForEach-Object {$_.Id}) -join ', '))"
    } else {
        Write-Output "$p : STOPPED"
    }
}

# 2. Check Gateway Port
$conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
if ($conn) {
    Write-Output "Gateway Port 8765 : LISTENING (PID: $($conn.OwningProcess))"
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:8765/health" -TimeoutSec 3 -ErrorAction Stop
        Write-Output "Health Status     : OK (Backend alive: $($health.backend_alive))"
    } catch {
        Write-Output "Health Status     : ERROR ($($_.Exception.Message))"
    }
} else {
    Write-Output "Gateway Port 8765 : NOT LISTENING"
}

# 3. Check Public Cloudflare URL from log
$cfLog = "$scriptDir\logs\cloudflared_error.log"
if (Test-Path $cfLog) {
    $urlLine = Get-Content $cfLog | Where-Object { $_ -match "https://.*\.trycloudflare\.com" } | Select-Object -Last 1
    if ($urlLine -match "(https://[a-zA-Z0-9-]+\.trycloudflare\.com)") {
        Write-Output "Public Remote URL : $($Matches[1])"
    }
}

# 4. Token info
$envFile = "$scriptDir\.env"
if (Test-Path $envFile) {
    $tokenLine = Get-Content $envFile | Where-Object { $_ -match "^WINMCP_AUTH_TOKEN=" }
    if ($tokenLine) {
        $token = $tokenLine.Split("=", 2)[1]
        Write-Output "Auth Token        : $($token.Substring(0, 8))...$($token.Substring($token.Length - 6))"
    }
}

# 5. Recent Audit Logs
$auditLog = "$scriptDir\logs\gateway-audit.log"
if (Test-Path $auditLog) {
    Write-Output "`nRecent Audit Events (Last 3):"
    Get-Content $auditLog -Tail 3 | ForEach-Object {
        try {
            $evt = $_ | ConvertFrom-Json
            Write-Output "  [$($evt.timestamp)] Method: $($evt.method), Risk: $($evt.risk_level), Status: $($evt.status), IP: $($evt.client_ip)"
        } catch {
            Write-Output "  $_"
        }
    }
}
Write-Output "=================================================="
