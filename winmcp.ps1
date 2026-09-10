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
    [string]$SubCommand = "",

    [Parameter(Position=2)]
    [string]$Value = ""
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
    Write-Host " Local Dashboard  : " -NoNewline -ForegroundColor Yellow
    Write-Host "http://127.0.0.1:8765/dashboard" -ForegroundColor Green
    if ($tunnelUrl) {
        Write-Host " Public URL       : " -NoNewline -ForegroundColor Yellow
        Write-Host $tunnelUrl -ForegroundColor White
        Write-Host " Remote Dashboard : " -NoNewline -ForegroundColor Yellow
        Write-Host "$tunnelUrl/dashboard?token=$token" -ForegroundColor Cyan
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

function Generate-RandomToken {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return -join ($bytes | ForEach-Object { "{0:x2}" -f $_ })
}

function Manage-Token {
    param(
        [string]$SubAction,
        [string]$CustomValue
    )
    
    $token = [Environment]::GetEnvironmentVariable("WINMCP_AUTH_TOKEN", "Process")
    
    # If called with 'winmcp token' (no subaction) -> Show current token
    if (-not $SubAction) {
        if ($token) {
            Write-Host "`n========================================================" -ForegroundColor Cyan
            Write-Host "           Current Bearer Authentication Token          " -ForegroundColor White
            Write-Host "========================================================" -ForegroundColor Cyan
            Write-Host $token -ForegroundColor Yellow
            Write-Host "`nAuthentication Usage:" -ForegroundColor DarkCyan
            Write-Host "  * For ChatGPT    : Authorization: Bearer $token" -ForegroundColor White
            Write-Host "  * For Claude Web : Append '?token=$token' to the SSE URL" -ForegroundColor White
            Write-Host "`nToken Management Commands:" -ForegroundColor DarkGray
            Write-Host "  winmcp token new             - Generate a new random 256-bit token" -ForegroundColor DarkGray
            Write-Host "  winmcp token set <your_key>  - Set a custom token of your choice" -ForegroundColor DarkGray
            Write-Host "  winmcp token change          - Interactive wizard to rotate or customize`n" -ForegroundColor DarkGray
        } else {
            Write-Host "No token found in .env" -ForegroundColor Red
        }
        return
    }

    $newToken = ""
    switch ($SubAction.ToLower()) {
        "new" {
            $newToken = Generate-RandomToken
            Write-Host "Generated new secure random 256-bit token." -ForegroundColor Green
        }
        "random" {
            $newToken = Generate-RandomToken
            Write-Host "Generated new secure random 256-bit token." -ForegroundColor Green
        }
        "rotate" {
            $newToken = Generate-RandomToken
            Write-Host "Rotated token: Generated new secure random 256-bit token." -ForegroundColor Green
        }
        "generate" {
            $newToken = Generate-RandomToken
            Write-Host "Generated new secure random 256-bit token." -ForegroundColor Green
        }
        "set" {
            if ($CustomValue) {
                $newToken = $CustomValue.Trim()
            } else {
                $newToken = Read-Host "Enter your new custom secret token"
                $newToken = $newToken.Trim()
            }
        }
        "custom" {
            if ($CustomValue) {
                $newToken = $CustomValue.Trim()
            } else {
                $newToken = Read-Host "Enter your new custom secret token"
                $newToken = $newToken.Trim()
            }
        }
        "change" {
            Write-Host "`n========================================================" -ForegroundColor Cyan
            Write-Host "             Security Token Management                  " -ForegroundColor White
            Write-Host "========================================================" -ForegroundColor Cyan
            if ($token) {
                Write-Host "Current Token: $token`n" -ForegroundColor DarkGray
            }
            Write-Host "Choose how to update your authentication token:" -ForegroundColor White
            Write-Host "--------------------------------------------------------" -ForegroundColor DarkCyan
            Write-Host " [1] Generate cryptographically secure random token (256-bit)" -ForegroundColor Green
            Write-Host "     * Automatically generates a high-entropy 64-character hex key."
            Write-Host " [2] Enter a custom secret token of my choice" -ForegroundColor Magenta
            Write-Host "     * Type your own custom passphrase or secret key."
            Write-Host " [3] Cancel and keep current token" -ForegroundColor DarkGray
            Write-Host "--------------------------------------------------------" -ForegroundColor DarkCyan
            $c = Read-Host "Enter choice [1, 2, or 3] (Default: 1)"
            if ($c -eq "2") {
                while (-not $newToken) {
                    $newToken = Read-Host "Enter your new custom secret token"
                    $newToken = $newToken.Trim()
                    if (-not $newToken) {
                        Write-Host "Token cannot be empty!" -ForegroundColor Yellow
                    }
                }
            } elseif ($c -eq "3") {
                Write-Host "Token change canceled. Keeping current token." -ForegroundColor Yellow
                return
            } else {
                $newToken = Generate-RandomToken
                Write-Host "Generated new secure random 256-bit token." -ForegroundColor Green
            }
        }
        default {
            # In case the user ran: winmcp token my_custom_token_directly
            $newToken = $SubAction.Trim()
        }
    }

    if ($newToken) {
        # Update .env file
        $content = Get-Content $envFile
        $newContent = @()
        $found = $false
        foreach ($line in $content) {
            if ($line -match "^WINMCP_AUTH_TOKEN=") {
                $newContent += "WINMCP_AUTH_TOKEN=$newToken"
                $found = $true
            } else {
                $newContent += $line
            }
        }
        if (-not $found) {
            $newContent += "WINMCP_AUTH_TOKEN=$newToken"
        }
        $newContent | Out-File -FilePath $envFile -Encoding utf8 -Force
        [Environment]::SetEnvironmentVariable("WINMCP_AUTH_TOKEN", $newToken, "Process")

        $tunnelUrl = Get-TunnelUrl

        Write-Host "`n========================================================" -ForegroundColor Green
        Write-Host "       [OK] Bearer Token Successfully Updated!           " -ForegroundColor White
        Write-Host "========================================================" -ForegroundColor Green
        Write-Host "New Token:" -ForegroundColor White
        Write-Host $newToken -ForegroundColor Yellow
        Write-Host ""
        Write-Host "How to use with AI Models:" -ForegroundColor Cyan
        Write-Host " * With ChatGPT   : Select Bearer Token and paste the new token." -ForegroundColor White
        if ($tunnelUrl) {
            Write-Host " * With Claude Web: Updated connection URL:" -ForegroundColor White
            Write-Host "   $tunnelUrl/sse?token=$newToken" -ForegroundColor Cyan
        }
        Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "Restarting server to apply new authentication token..." -ForegroundColor Yellow
        Restart-WinMCP
    } else {
        Write-Host "Token update canceled." -ForegroundColor Yellow
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
        Write-Host " [OK] Cleared all runtime logs." -ForegroundColor Green
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

    Write-Host " [OK] Removed temporary caches and scratch folders." -ForegroundColor Green
    Write-Host "`nProject is completely clean and sanitized of any personal or machine-specific data!" -ForegroundColor Cyan
}

function Test-CloudflareDomain {
    param([string]$Domain)
    $clean = $Domain.Replace("https://", "").Replace("http://", "").Trim("/").ToLower()
    $parts = $clean.Split(".")
    for ($i = 0; $i -lt ($parts.Length - 1); $i++) {
        $candidate = ($parts[$i..($parts.Length - 1)]) -join "."
        try {
            $res = Invoke-RestMethod -Uri "https://cloudflare-dns.com/dns-query?name=$candidate&type=NS" -Headers @{Accept="application/dns-json"} -TimeoutSec 3 -ErrorAction SilentlyContinue
            if ($res -and $res.Answer) {
                foreach ($ans in $res.Answer) {
                    if ($ans.data -match "cloudflare\.com") {
                        return @{ IsCloudflare = $true; BaseDomain = $candidate }
                    }
                }
            }
            $nsRecords = Resolve-DnsName -Name $candidate -Type NS -ErrorAction SilentlyContinue
            if ($nsRecords) {
                foreach ($r in $nsRecords) {
                    if ($r.NameHost -match "cloudflare\.com") {
                        return @{ IsCloudflare = $true; BaseDomain = $candidate }
                    }
                }
            }
        } catch {}
    }
    return @{ IsCloudflare = $false; BaseDomain = $clean }
}

function Set-Domain {
    param(
        [string]$DomainName,
        [string]$TokenValue
    )
    
    if (-not $DomainName) {
        Write-Host "`nChoose tunnel connection mode:" -ForegroundColor Cyan
        Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host " [1] Custom Domain (Permanent, stable, and fixed URL)" -ForegroundColor Magenta
        Write-Host " [2] Quick Tunnel (Temporary free tunnel on *.trycloudflare.com)" -ForegroundColor Green
        Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkCyan
        
        $choice = Read-Host "Enter your choice [1 or 2] (Default: 1)"
        if ($choice -eq "2") {
            # Switch to Quick Tunnel
            $content = Get-Content $envFile
            $newContent = @()
            foreach ($line in $content) {
                if ($line -match "^WINMCP_TUNNEL_MODE=") { $newContent += "WINMCP_TUNNEL_MODE=Quick" }
                elseif ($line -match "^WINMCP_TUNNEL_TOKEN=") { $newContent += "WINMCP_TUNNEL_TOKEN=" }
                elseif ($line -match "^WINMCP_CUSTOM_DOMAIN=") { $newContent += "WINMCP_CUSTOM_DOMAIN=" }
                else { $newContent += $line }
            }
            $newContent | Out-File -FilePath $envFile -Encoding utf8 -Force
            Write-Host "`n[OK] Switched to Cloudflare Quick Tunnel!" -ForegroundColor Green
            Restart-WinMCP
            return
        }

        Write-Host "`n--- Custom Domain Setup ---" -ForegroundColor Cyan
        Write-Host "Cloudflare Zero Trust setup steps:" -ForegroundColor Yellow
        Write-Host " 1. Open: https://one.dash.cloudflare.com -> Networks -> Tunnels"
        Write-Host " 2. Create a new tunnel and copy the Tunnel Token (starts with eyJh...)."
        Write-Host " 3. Route Public Hostname: Service Type = HTTP, URL = localhost:8765"
        Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
        
        $DomainName = Read-Host "Enter your domain (e.g., mcp.yourdomain.com)"
    }

    if (-not $DomainName) {
        Write-Host "Canceled. No domain entered." -ForegroundColor Yellow
        return
    }

    $DomainName = $DomainName.Replace("https://", "").Replace("http://", "").Trim("/")

    # Verify domain on Cloudflare
    Write-Host "`n[>] Verifying domain ($DomainName) with Cloudflare nameservers..." -ForegroundColor Cyan
    $cfCheck = Test-CloudflareDomain -Domain $DomainName

    if ($cfCheck.IsCloudflare) {
        Write-Host " [OK] Domain verified: ($($cfCheck.BaseDomain)) is connected to Cloudflare!" -ForegroundColor Green
    } else {
        Write-Host "`n[!] Warning: Domain '$DomainName' does not appear to be routed through Cloudflare NS." -ForegroundColor Yellow
        Write-Host "    (No Cloudflare Nameservers like *.ns.cloudflare.com were detected)" -ForegroundColor Gray
        Write-Host "    Make sure the domain is added to your Cloudflare account." -ForegroundColor Gray
        Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host " [1] Cancel and re-enter domain."
        Write-Host " [2] Continue anyway (if recently configured and DNS is still propagating)."
        
        $unv = Read-Host "Enter choice [1 or 2] (Default: 1)"
        if ($unv -ne "2") {
            Write-Host "Domain setup canceled." -ForegroundColor Yellow
            return
        }
    }

    if (-not $TokenValue) {
        $TokenValue = Read-Host "Enter Cloudflare Tunnel Token (starts with eyJh...)"
    }

    if ($DomainName -and $TokenValue) {
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
        
        Write-Host "`n[OK] Custom domain configuration saved to .env successfully!" -ForegroundColor Green
        Write-Host "Restarting server to activate custom domain tunnel..." -ForegroundColor Yellow
        Restart-WinMCP
    } else {
        Write-Host "Canceled. Token was not provided." -ForegroundColor Yellow
    }
}

function Uninstall-WinMCP {
    & "$scriptDir\uninstall.ps1"
}

function Open-Dashboard {
    $conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
    if (-not $conn) {
        Write-Host "WinMCP server is not running. Starting it now..." -ForegroundColor Yellow
        Start-WinMCP
        Start-Sleep -Seconds 2
    }
    $url = "http://127.0.0.1:8765/dashboard"
    Write-Host "Opening WinMCP Interactive Dashboard: $url" -ForegroundColor Green
    Start-Process $url
}

function Show-Help {
    Write-Host "`nWinMCP Management CLI Options:" -ForegroundColor Cyan
    Write-Host "  winmcp dashboard           - Open the Interactive Web Control Center Dashboard"
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
    Write-Host "  winmcp token               - Display current token"
    Write-Host "  winmcp token new           - Generate a new random 256-bit token"
    Write-Host "  winmcp token set <key>     - Set a custom token"
    Write-Host "  winmcp token change        - Interactive token change wizard"
    Write-Host "  winmcp uninstall           - Completely remove WinMCP from roots (services, tasks, PATH, configs)"
    Write-Host "  winmcp help                - Show this help message`n"
}

switch ($Command.ToLower()) {
    "dashboard" { Open-Dashboard }
    "gui"       { Open-Dashboard }
    "web"       { Open-Dashboard }
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
    "token"     { Manage-Token -SubAction $SubCommand -CustomValue $Value }
    "uninstall" { Uninstall-WinMCP }
    "wipe"      { Uninstall-WinMCP }
    "purge"     { Uninstall-WinMCP }
    "help"      { Show-Help }
    default     { Show-Status }
}

