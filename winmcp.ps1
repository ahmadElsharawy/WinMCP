<#
.SYNOPSIS
    WinMCP - Windows MCP Server Management CLI
.DESCRIPTION
    Management utility for Windows MCP Server, Gateway, Services and Cloudflare Tunnel.
#>

param(
    [Parameter(Position=0)]
    [string]$Command = "status",

    [Parameter(Position=1)]
    [string]$SubCommand = ""
)

# Portable Path Detection
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir) {
    $cmd = Get-Command "winmcp.cmd" -ErrorAction SilentlyContinue
    if ($cmd) { $scriptDir = Split-Path -Parent $cmd.Path }
}
if (-not $scriptDir -or !(Test-Path $scriptDir)) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir

$envFile = "$scriptDir\.env"
$logDir = "$scriptDir\logs"
$auditLog = "$logDir\gateway-audit.log"
$nssmExe = "$scriptDir\bin\nssm.exe"

function Load-EnvFile {
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#") -and $line -match "=") {
                $parts = $line.Split("=", 2)
                [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), "Process")
            }
        }
    }
}

Load-EnvFile

function Get-TunnelUrl {
    # Check custom domain first
    $customDomain = [Environment]::GetEnvironmentVariable("WINMCP_CUSTOM_DOMAIN", "Process")
    if ($customDomain) {
        return "https://$customDomain"
    }

    # Check error log and standard log
    $logs = @("$logDir\cloudflared_error.log", "$logDir\cloudflared.log")
    foreach ($l in $logs) {
        if (Test-Path $l) {
            $match = Get-Content $l -ErrorAction SilentlyContinue | Where-Object { $_ -match "(https://[a-zA-Z0-9-]+\.trycloudflare\.com)" } | Select-Object -Last 1
            if ($match -match "(https://[a-zA-Z0-9-]+\.trycloudflare\.com)") {
                return $Matches[1]
            }
        }
    }
    return $null
}

function Show-Status {
    $token = [Environment]::GetEnvironmentVariable("WINMCP_AUTH_TOKEN", "Process")
    $tunnelUrl = Get-TunnelUrl

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "         WinMCP Server Status Dashboard                " -ForegroundColor White
    Write-Host "========================================================" -ForegroundColor Cyan

    $mcpProc = Get-Process -Name "windows-mcp-server" -ErrorAction SilentlyContinue
    $cfProc = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    $gwRunning = $false

    $conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
    if ($conn) { $gwRunning = $true }

    if ($mcpProc) {
        Write-Host " [OK] windows-mcp-server : " -NoNewline -ForegroundColor Green
        Write-Host "RUNNING (PID: $($mcpProc.Id -join ', '))" -ForegroundColor White
    } else {
        Write-Host " [X]  windows-mcp-server : " -NoNewline -ForegroundColor Red
        Write-Host "STOPPED" -ForegroundColor DarkGray
    }

    if ($gwRunning) {
        Write-Host " [OK] Gateway Port 8765  : " -NoNewline -ForegroundColor Green
        Write-Host "LISTENING (PID: $($conn.OwningProcess))" -ForegroundColor White
    } else {
        Write-Host " [X]  Gateway Port 8765  : " -NoNewline -ForegroundColor Red
        Write-Host "STOPPED" -ForegroundColor DarkGray
    }

    if ($cfProc) {
        Write-Host " [OK] Cloudflare Tunnel  : " -NoNewline -ForegroundColor Green
        Write-Host "CONNECTED (PID: $($cfProc.Id -join ', '))" -ForegroundColor White
    } else {
        Write-Host " [!]  Cloudflare Tunnel  : " -NoNewline -ForegroundColor Yellow
        Write-Host "NOT RUNNING" -ForegroundColor DarkGray
    }

    Write-Host "`n------------- Background & Service Status --------------" -ForegroundColor DarkCyan
    
    # Check Windows Service
    $svc = Get-Service -Name "WinMCP-Service" -ErrorAction SilentlyContinue
    if ($svc) {
        $svcColor = if ($svc.Status -eq "Running") { "Green" } else { "Yellow" }
        Write-Host " [OK] Windows Service    : " -NoNewline -ForegroundColor $svcColor
        Write-Host "$($svc.Status) (Auto-starts on system boot)" -ForegroundColor White
    } else {
        Write-Host " [-]  Windows Service    : " -NoNewline -ForegroundColor DarkGray
        Write-Host "Not Installed (Use 'winmcp service install' if desired)" -ForegroundColor DarkGray
    }

    # Check Task Scheduler
    $task = Get-ScheduledTask -TaskName "WindowsMCPServer" -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host " [OK] Logon Auto-Start   : " -NoNewline -ForegroundColor Green
        Write-Host "Registered ($($task.State) - Starts on user logon)" -ForegroundColor White
    } else {
        Write-Host " [-]  Logon Auto-Start   : " -NoNewline -ForegroundColor DarkYellow
        Write-Host "Not registered (Use 'winmcp autostart enable')" -ForegroundColor DarkGray
    }

    # Check Startup folder
    $startupFolder = [Environment]::GetFolderPath("Startup")
    $vbsPath = Join-Path $startupFolder "WinMCP_AutoStart.vbs"
    if (Test-Path $vbsPath) {
        Write-Host " [OK] Startup Folder     : " -NoNewline -ForegroundColor Green
        Write-Host "Active (Silent launcher present in shell:startup)" -ForegroundColor White
    }

    Write-Host "`n----------------- Access Endpoints ---------------------" -ForegroundColor DarkCyan
    if ($tunnelUrl) {
        Write-Host " Public URL       : " -NoNewline -ForegroundColor Yellow
        Write-Host $tunnelUrl -ForegroundColor White
        Write-Host " ChatGPT Endpoint : " -NoNewline -ForegroundColor Yellow
        Write-Host "$tunnelUrl/mcp" -ForegroundColor Cyan
        Write-Host " Claude Web SSE   : " -NoNewline -ForegroundColor Yellow
        Write-Host "$tunnelUrl/sse?token=$token" -ForegroundColor Cyan
    } else {
        Write-Host " Public URL       : Tunnel starting or not active." -ForegroundColor Yellow
        Write-Host " Local Endpoint   : http://127.0.0.1:8765/mcp" -ForegroundColor White
    }

    if ($token) {
        Write-Host " Auth Token       : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($token.Substring(0, 8))...$($token.Substring($token.Length - 6)) (Type 'winmcp token' to see full key)" -ForegroundColor DarkGray
    }

    Write-Host "========================================================`n" -ForegroundColor Cyan
}

function Start-WinMCP {
    Write-Host "Starting WinMCP Server and Tunnels..." -ForegroundColor Cyan
    & "$scriptDir\run_winmcp.ps1"
    Start-Sleep -Seconds 3
    Show-Status
}

function Stop-WinMCP {
    Write-Host "Stopping WinMCP Server..." -ForegroundColor Yellow
    & "$scriptDir\stop_winmcp.ps1"
    Write-Host "WinMCP stopped." -ForegroundColor Green
}

function Restart-WinMCP {
    Write-Host "Restarting WinMCP..." -ForegroundColor Yellow
    Stop-WinMCP
    Start-Sleep -Seconds 2
    Start-WinMCP
}

function Manage-Service {
    param([string]$Action)
    switch ($Action.ToLower()) {
        "install" {
            & "$scriptDir\install_service.ps1"
        }
        "uninstall" {
            & "$scriptDir\uninstall_service.ps1"
        }
        "remove" {
            & "$scriptDir\uninstall_service.ps1"
        }
        "start" {
            Start-Service -Name "WinMCP-Service" -ErrorAction SilentlyContinue
            Write-Host "Started WinMCP-Service." -ForegroundColor Green
        }
        "stop" {
            Stop-Service -Name "WinMCP-Service" -ErrorAction SilentlyContinue
            Write-Host "Stopped WinMCP-Service." -ForegroundColor Yellow
        }
        default {
            $svc = Get-Service -Name "WinMCP-Service" -ErrorAction SilentlyContinue
            if ($svc) {
                Write-Host "WinMCP-Service status: $($svc.Status)" -ForegroundColor Cyan
            } else {
                Write-Host "WinMCP-Service is not installed." -ForegroundColor Yellow
                Write-Host "To install: winmcp service install" -ForegroundColor Gray
            }
        }
    }
}

function Manage-AutoStart {
    param([string]$Action)
    switch ($Action.ToLower()) {
        "enable" {
            & "$scriptDir\install_autostart.ps1"
        }
        "disable" {
            & "$scriptDir\uninstall_autostart.ps1"
        }
        default {
            Write-Host "Usage: winmcp autostart [enable | disable]" -ForegroundColor Yellow
        }
    }
}

function Show-Logs {
    param([int]$Lines = 15)
    if (Test-Path $auditLog) {
        Write-Host "`n--- Recent Audit Events (Last $Lines) ---" -ForegroundColor Cyan
        Get-Content $auditLog -Tail $Lines | ForEach-Object {
            try {
                $e = $_ | ConvertFrom-Json
                $color = "Green"
                if ($e.status -eq "unauthorized") { $color = "Red" }
                elseif ($e.risk_level -eq "HIGH_RISK") { $color = "Yellow" }
                Write-Host "[$($e.timestamp)] " -NoNewline -ForegroundColor DarkGray
                Write-Host "[$($e.risk_level)] " -NoNewline -ForegroundColor $color
                Write-Host "$($e.method) ($($e.tool_name)) -> $($e.status) " -ForegroundColor White
            } catch {
                Write-Host $_ -ForegroundColor DarkGray
            }
        }
        Write-Host "----------------------------------------`n" -ForegroundColor Cyan
    } else {
        Write-Host "No audit log found at $auditLog" -ForegroundColor Yellow
    }
}

function Show-Token {
    $token = [Environment]::GetEnvironmentVariable("WINMCP_AUTH_TOKEN", "Process")
    if ($token) {
        Write-Host "`nYour Secret Bearer Token:" -ForegroundColor Cyan
        Write-Host $token -ForegroundColor Yellow
        Write-Host "`nFor ChatGPT: Authorization: Bearer $token" -ForegroundColor White
        Write-Host "For Claude Web: Append '?token=$token' to the URL`n" -ForegroundColor White
    } else {
        Write-Host "No token found in .env" -ForegroundColor Red
    }
}

function Clean-WinMCP {
    Write-Host "Cleaning WinMCP temporary files, logs, and sensitive session data..." -ForegroundColor Yellow
    Stop-WinMCP
    
    # 1. Clear all logs
    if (Test-Path $logDir) {
        Get-ChildItem "$logDir\*.log" -ErrorAction SilentlyContinue | ForEach-Object {
            Clear-Content -Path $_.FullName -Force
        }
        Write-Host " [✔] Cleared all runtime logs." -ForegroundColor Green
    }

    # 2. Remove pycache
    Get-ChildItem -Path $scriptDir -Filter "__pycache__" -Recurse -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 3. Remove test scratch
    $scratch = Join-Path $scriptDir "test_scratch"
    if (Test-Path $scratch) {
        Remove-Item -Path $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host " [✔] Removed temporary caches and scratch folders." -ForegroundColor Green
    Write-Host "`nProject is completely clean and sanitized of any personal or machine-specific data!" -ForegroundColor Cyan
}

function Set-Domain {
    param(
        [string]$DomainName,
        [string]$TokenValue
    )
    
    if (-not $DomainName) {
        Write-Host "`n--- إعداد النطاق المخصص الدائم (Custom Domain Setup) ---" -ForegroundColor Cyan
        Write-Host "خطوات Cloudflare المطلوبة:" -ForegroundColor Yellow
        Write-Host " 1. ادخل على Cloudflare Zero Trust -> Networks -> Tunnels."
        Write-Host " 2. أنشئ نفق جديد وانسخ الـ Tunnel Token (يبدأ بـ eyJh...)."
        Write-Host " 3. اربط الـ Public Hostname: Service Type = HTTP, URL = localhost:8765"
        Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
        
        $DomainName = Read-Host "أدخل النطاق الخاص بك (مثال: mcp.yourdomain.com)"
        $TokenValue = Read-Host "أدخل Cloudflare Tunnel Token"
    }

    if ($DomainName -and $TokenValue) {
        $DomainName = $DomainName.Replace("https://", "").Replace("http://", "").Trim("/")
        
        # Update .env file
        $content = Get-Content $envFile
        $newContent = @()
        foreach ($line in $content) {
            if ($line -match "^WINMCP_TUNNEL_MODE=") { $newContent += "WINMCP_TUNNEL_MODE=Custom" }
            elseif ($line -match "^WINMCP_TUNNEL_TOKEN=") { $newContent += "WINMCP_TUNNEL_TOKEN=$TokenValue" }
            elseif ($line -match "^WINMCP_CUSTOM_DOMAIN=") { $newContent += "WINMCP_CUSTOM_DOMAIN=$DomainName" }
            else { $newContent += $line }
        }
        $newContent | Out-File -FilePath $envFile -Encoding utf8 -Force
        
        Write-Host "`n[✔] تم حفظ إعدادات النطاق الدائم في .env بنجاح!" -ForegroundColor Green
        Write-Host "جاري إعادة تشغيل السيرفر وتفعيل النفق المخصص..." -ForegroundColor Yellow
        Restart-WinMCP
    } else {
        Write-Host "تم الإلغاء. لم يتم إدخال الدومين أو التوكن." -ForegroundColor Yellow
    }
}

function Show-Help {
    Write-Host "`nWinMCP Management CLI Options:" -ForegroundColor Cyan
    Write-Host "  winmcp status              - Show current server status, public URL, and endpoints"
    Write-Host "  winmcp start               - Launch Windows MCP Server, Gateway and Cloudflare Tunnel"
    Write-Host "  winmcp stop                - Safely stop all WinMCP processes"
    Write-Host "  winmcp restart             - Restart all WinMCP services and refresh tunnel"
    Write-Host "  winmcp domain              - Configure permanent Custom Domain on Cloudflare"
    Write-Host "  winmcp clean               - Sanitize and remove all logs, caches, and session data"
    Write-Host "  winmcp service install     - Install as 24/7 native Windows Service (NSSM)"
    Write-Host "  winmcp service uninstall   - Remove native Windows Service"
    Write-Host "  winmcp autostart enable    - Enable automatic start on user logon"
    Write-Host "  winmcp autostart disable   - Disable automatic start on user logon"
    Write-Host "  winmcp logs                - Display recent audit logs of AI interactions"
    Write-Host "  winmcp token               - Display the full authentication token"
    Write-Host "  winmcp help                - Show this help message`n"
}

switch ($Command.ToLower()) {
    "status"    { Show-Status }
    "start"     { Start-WinMCP }
    "stop"      { Stop-WinMCP }
    "restart"   { Restart-WinMCP }
    "domain"    { Set-Domain -DomainName $SubCommand }
    "tunnel"    { Set-Domain -DomainName $SubCommand }
    "clean"     { Clean-WinMCP }
    "service"   { Manage-Service -Action $SubCommand }
    "autostart" { Manage-AutoStart -Action $SubCommand }
    "logs"      { Show-Logs }
    "token"     { Show-Token }
    "help"      { Show-Help }
    default     { Show-Status }
}
