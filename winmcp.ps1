<#
.SYNOPSIS
    WinMCP - Windows MCP Server Interactive Control Center & CLI
.DESCRIPTION
    Interactive terminal dashboard and management CLI for Windows MCP Server,
    Gateway, Tunnels, and Services.
#>

param(
    [Parameter(Position=0)]
    [string]$Command = "menu",

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

function Show-Info {
    Load-EnvFile
    $token = [Environment]::GetEnvironmentVariable("WINMCP_AUTH_TOKEN", "Process")
    $domain = [Environment]::GetEnvironmentVariable("WINMCP_CUSTOM_DOMAIN", "Process")
    $tunnelMode = [Environment]::GetEnvironmentVariable("WINMCP_TUNNEL_MODE", "Process")
    if (-not $tunnelMode) { $tunnelMode = "Quick" }
    $tunnelUrl = Get-TunnelUrl

    $mcpProc = Get-Process -Name "windows-mcp-server" -ErrorAction SilentlyContinue
    $cfProc = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    $conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue

    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                 WINMCP SERVER INFORMATION                  " -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    
    # Status
    Write-Host "Service Status : " -NoNewline -ForegroundColor Gray
    if ($conn -and $mcpProc) {
        Write-Host "ACTIVE (RUNNING)" -ForegroundColor Green
    } elseif ($conn) {
        Write-Host "PARTIAL (Gateway Active, Engine Reviving)" -ForegroundColor Yellow
    } else {
        Write-Host "STOPPED" -ForegroundColor Red
    }

    Write-Host "Gateway Port   : 8765" -NoNewline -ForegroundColor Gray
    if ($conn) {
        Write-Host " (LISTENING - PID: $($conn.OwningProcess))" -ForegroundColor Green
    } else {
        Write-Host " (OFFLINE)" -ForegroundColor Red
    }

    Write-Host "Engine Binary  : " -NoNewline -ForegroundColor Gray
    if ($mcpProc) {
        Write-Host "windows-mcp-server (PID: $($mcpProc.Id -join ', '))" -ForegroundColor Green
    } else {
        Write-Host "STOPPED" -ForegroundColor Red
    }

    Write-Host "Cloudflare PID : " -NoNewline -ForegroundColor Gray
    if ($cfProc) {
        Write-Host "CONNECTED (PID: $($cfProc.Id -join ', '))" -ForegroundColor Green
    } else {
        Write-Host "OFFLINE" -ForegroundColor Red
    }

    Write-Host "Tunnel Mode    : " -NoNewline -ForegroundColor Gray
    Write-Host "$tunnelMode" -ForegroundColor White
    if ($domain) {
        Write-Host "Custom Domain  : " -NoNewline -ForegroundColor Gray
        Write-Host "$domain" -ForegroundColor Magenta
    }

    Write-Host "Public Endpoint: " -NoNewline -ForegroundColor Gray
    if ($tunnelUrl) {
        Write-Host "$tunnelUrl" -ForegroundColor Yellow
    } else {
        Write-Host "Tunnel starting or connecting..." -ForegroundColor DarkYellow
    }

    Write-Host "Current Token  : " -NoNewline -ForegroundColor Gray
    if ($token) {
        Write-Host "$token" -ForegroundColor White
    } else {
        Write-Host "NOT CONFIGURED" -ForegroundColor Red
    }

    # Persistence
    $startupVbs = Join-Path ([Environment]::GetFolderPath("Startup")) "WinMCP_AutoStart.vbs"
    $hasStartup = Test-Path $startupVbs
    $svc = Get-Service -Name "WinMCP-Service" -ErrorAction SilentlyContinue
    Write-Host "Logon AutoStart: " -NoNewline -ForegroundColor Gray
    if ($hasStartup) {
        Write-Host "Enabled" -ForegroundColor Green
    } else {
        Write-Host "Disabled" -ForegroundColor DarkGray
    }
    if ($svc) {
        Write-Host "Windows Service: " -NoNewline -ForegroundColor Gray
        Write-Host "$($svc.Status)" -ForegroundColor Green
    }

    Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " DIRECT CONNECTION URLS / روابط الاتصال المباشرة:" -ForegroundColor Yellow
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan

    if ($tunnelUrl) {
        Write-Host "1. Claude Web (claude.ai -> Settings -> Connectors):" -ForegroundColor White
        Write-Host "   URL       : $tunnelUrl/sse?token=$token" -ForegroundColor Cyan
        Write-Host "   Transport : Server-Sent Events (SSE)`n" -ForegroundColor Gray

        Write-Host "2. ChatGPT (Desktop MCP / Custom GPTs):" -ForegroundColor White
        Write-Host "   Direct URL: $tunnelUrl/mcp" -ForegroundColor Cyan
        Write-Host "   Bearer    : Bearer $token`n" -ForegroundColor Gray

        Write-Host "3. Claude Desktop Config (claude_desktop_config.json):" -ForegroundColor White
        $coreBinEsc = "$scriptDir\bin\windows-mcp-server.exe".Replace('\', '\\')
        $cdSnippet = '{"mcpServers":{"windows":{"command":"' + $coreBinEsc + '","args":["stdio","--toolsets","all"]}}}'
        Write-Host $cdSnippet -ForegroundColor DarkYellow
    } else {
        Write-Host "Local URL    : http://127.0.0.1:8765/mcp" -ForegroundColor Cyan
        Write-Host "Bearer Token : $token" -ForegroundColor White
        Write-Host "(Waiting for public tunnel URL... Press [10] to refresh)" -ForegroundColor DarkYellow
    }
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Show-Status {
    Show-Info
}

function Start-WinMCP {
    Write-Host "`n[*] Starting WinMCP Server and Tunnels in background..." -ForegroundColor Cyan
    & "$scriptDir\run_winmcp.ps1"
}

function Stop-WinMCP {
    Write-Host "`n[*] Stopping WinMCP Server..." -ForegroundColor Yellow
    & "$scriptDir\stop_winmcp.ps1"
    Write-Host "[OK] WinMCP stopped." -ForegroundColor Green
}

function Restart-WinMCP {
    Write-Host "`n[*] Restarting WinMCP Server and refreshing tunnel..." -ForegroundColor Yellow
    Stop-WinMCP
    Start-Sleep -Seconds 1
    Start-WinMCP
}

function Update-EnvToken {
    param([string]$NewToken)
    if (-not $NewToken) { return }

    # Update .env file
    $content = @()
    if (Test-Path $envFile) {
        $content = Get-Content $envFile
    }
    $newContent = @()
    $found = $false
    foreach ($line in $content) {
        if ($line -match "^WINMCP_AUTH_TOKEN=") {
            $newContent += "WINMCP_AUTH_TOKEN=$NewToken"
            $found = $true
        } else {
            $newContent += $line
        }
    }
    if (-not $found) {
        $newContent += "WINMCP_AUTH_TOKEN=$NewToken"
    }
    $newContent | Out-File -FilePath $envFile -Encoding utf8 -Force
    [Environment]::SetEnvironmentVariable("WINMCP_AUTH_TOKEN", $NewToken, "Process")

    # Notify running gateway if alive
    try {
        $body = @{ token = $NewToken } | ConvertTo-Json
        Invoke-RestMethod -Uri "http://127.0.0.1:8765/api/token/custom" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

function Show-Logs {
    param([int]$Lines = 20)
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "                 RECENT AUDIT ACTIVITY LOGS                 " -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    if (Test-Path $auditLog) {
        Get-Content $auditLog -Tail $Lines | ForEach-Object {
            try {
                $e = $_ | ConvertFrom-Json
                $color = "Green"
                if ($e.status -eq "unauthorized") { $color = "Red" }
                elseif ($e.status -eq "error") { $color = "Red" }
                elseif ($e.risk_level -eq "HIGH_RISK") { $color = "Yellow" }
                Write-Host "[$($e.timestamp)] " -NoNewline -ForegroundColor DarkGray
                Write-Host "[$($e.risk_level)] " -NoNewline -ForegroundColor $color
                Write-Host "$($e.method) ($($e.tool_name)) -> $($e.status) " -ForegroundColor White
            } catch {
                Write-Host $_ -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "No audit events logged yet. (Server log at $logDir\gateway.log)" -ForegroundColor Yellow
    }
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Interactive-ToolRunner {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "             INTERACTIVE MCP TOOL RUNNER                   " -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "Select a tool to execute directly on this Windows PC:" -ForegroundColor Yellow
    Write-Host "  [1]  SystemInfo       - Hardware, OS, CPU, and RAM metrics"
    Write-Host "  [2]  Network          - Adapters, DNS, IP config and connectivity"
    Write-Host "  [3]  Process (list)   - Inspect running Windows processes"
    Write-Host "  [4]  Service (list)   - Inspect Windows services status"
    Write-Host "  [5]  PowerShell       - Execute a custom PowerShell command"
    Write-Host "  [6]  FileSystem       - Read, write, or list files"
    Write-Host "  [7]  Clipboard (read) - Read current Windows clipboard"
    Write-Host "  [8]  EventLog         - Query Windows System and Application logs"
    Write-Host "  [9]  Screenshot       - Capture desktop / virtual display"
    Write-Host "  [10] Snapshot         - Labeled UI element tree of open windows"
    Write-Host "  [11] CaptureEvidence  - Combined snapshot + screenshot evidence"
    Write-Host "  [12] Custom Tool Name - Type any tool from the 37 available tools"
    Write-Host "  [0]  Back to Menu"
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan

    $tChoice = Read-Host "Choose tool [0-12]"
    $toolName = ""
    $toolArgs = @{}

    switch ($tChoice.Trim()) {
        "1" { $toolName = "SystemInfo" }
        "2" {
            $toolName = "Network"
            Write-Host "Select Network mode: [1] adapters, [2] dns, [3] config, [4] test (Default: adapters)" -ForegroundColor Cyan
            $nMode = Read-Host "Mode [1-4]"
            if ($nMode -eq "2") { $toolArgs = @{ mode = "dns" } }
            elseif ($nMode -eq "3") { $toolArgs = @{ mode = "config" } }
            elseif ($nMode -eq "4") {
                $targetHost = Read-Host "Target Host (Default: 8.8.8.8)"
                if (-not $targetHost) { $targetHost = "8.8.8.8" }
                $toolArgs = @{ mode = "test"; host = $targetHost }
            } else {
                $toolArgs = @{ mode = "adapters" }
            }
        }
        "3" {
            $toolName = "Process"
            $toolArgs = @{ action = "list" }
        }
        "4" {
            $toolName = "Service"
            $toolArgs = @{ action = "list" }
        }
        "5" {
            $toolName = "PowerShell"
            $cmdText = Read-Host "Enter PowerShell command to execute"
            if (-not $cmdText) { return }
            $toolArgs = @{ command = $cmdText }
        }
        "6" {
            $toolName = "FileSystem"
            Write-Host "Select action: [1] list, [2] read (Default: list)" -ForegroundColor Cyan
            $fsAct = Read-Host "Action [1 or 2]"
            $path = Read-Host "Path (Default: C:\Users\Unknown)"
            if (-not $path) { $path = "C:\Users\Unknown" }
            if ($fsAct -eq "2") {
                $toolArgs = @{ action = "read"; path = $path }
            } else {
                $toolArgs = @{ action = "list"; path = $path }
            }
        }
        "7" {
            $toolName = "Clipboard"
            $toolArgs = @{ action = "read" }
        }
        "8" {
            $toolName = "EventLog"
            $logName = Read-Host "Log Name (Default: System)"
            if (-not $logName) { $logName = "System" }
            $toolArgs = @{ log = $logName; max = 10 }
        }
        "9" {
            $toolName = "Screenshot"
        }
        "10" {
            $toolName = "Snapshot"
        }
        "11" {
            $toolName = "CaptureEvidence"
            $toolArgs = @{ label = "Manual CLI Test" }
        }
        "12" {
            $toolName = Read-Host "Enter tool name"
            $rawArgs = Read-Host "Enter JSON arguments (or press Enter for {})"
            if ($rawArgs) {
                try {
                    $toolArgs = $rawArgs | ConvertFrom-Json
                } catch {
                    $toolArgs = @{}
                }
            }
        }
        default { return }
    }

    if (-not $toolName) { return }

    Write-Host "`n[*] Executing tool '$toolName' against Windows host..." -ForegroundColor Cyan
    try {
        $body = @{
            name = $toolName
            arguments = $toolArgs
        } | ConvertTo-Json -Depth 5
        $res = Invoke-RestMethod -Uri "http://127.0.0.1:8765/api/tools/execute" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 30
        
        Write-Host "`n----------------------- Tool Output ------------------------" -ForegroundColor Green
        if ($res.result.content) {
            foreach ($c in $res.result.content) {
                if ($c.type -eq "text") {
                    Write-Host $c.text -ForegroundColor White
                } elseif ($c.type -eq "image") {
                    $imgLen = 0
                    if ($c.data) { $imgLen = $c.data.Length }
                    Write-Host "[Captured Image: $($c.mimeType) ($imgLen Base64 bytes)]" -ForegroundColor Magenta
                }
            }
        } else {
            $res | ConvertTo-Json -Depth 4 | Write-Host -ForegroundColor White
        }
        Write-Host "------------------------------------------------------------" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Tool execution failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Toggle-LogonAutoStart {
    $startupFolder = [Environment]::GetFolderPath("Startup")
    $vbsPath = Join-Path $startupFolder "WinMCP_AutoStart.vbs"
    if (Test-Path $vbsPath) {
        & "$scriptDir\uninstall_autostart.ps1"
        Write-Host "[OK] Logon Auto-Start Disabled." -ForegroundColor Yellow
    } else {
        & "$scriptDir\install_autostart.ps1"
        Write-Host "[OK] Logon Auto-Start Enabled!" -ForegroundColor Green
    }
}

function Manage-ServiceMenu {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "              WINDOWS 24/7 BACKGROUND SERVICE               " -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    $svc = Get-Service -Name "WinMCP-Service" -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "Current Service State: $($svc.Status)" -ForegroundColor Green
    } else {
        Write-Host "Current Service State: Not Installed" -ForegroundColor DarkGray
    }
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "  [1] Install and Start Windows Service (24/7 background mode)" -ForegroundColor White
    Write-Host "  [2] Start Service" -ForegroundColor White
    Write-Host "  [3] Stop Service" -ForegroundColor White
    Write-Host "  [4] Uninstall Service" -ForegroundColor White
    Write-Host "  [0] Back" -ForegroundColor Red
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
    $sChoice = Read-Host "Choose option [0-4]"
    switch ($sChoice.Trim()) {
        "1" { & "$scriptDir\install_service.ps1" }
        "2" { Start-Service -Name "WinMCP-Service" -ErrorAction SilentlyContinue; Write-Host "Service started." -ForegroundColor Green }
        "3" { Stop-Service -Name "WinMCP-Service" -ErrorAction SilentlyContinue; Write-Host "Service stopped." -ForegroundColor Yellow }
        "4" { & "$scriptDir\uninstall_service.ps1" }
        default {}
    }
}

function Set-Domain {
    param([string]$DomainName)
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "                 CLOUDFLARE TUNNEL & DOMAIN                 " -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " [1] Free Cloudflare Quick Tunnel (Automatic *.trycloudflare.com)" -ForegroundColor Green
    Write-Host " [2] Custom Domain (Fixed permanent URL e.g. winmcp.yourdomain.com)" -ForegroundColor Magenta
    Write-Host " [0] Cancel" -ForegroundColor DarkGray
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan

    $modeChoice = Read-Host "Choose option [0-2]"
    if ($modeChoice.Trim() -eq "1") {
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
    } elseif ($modeChoice.Trim() -ne "2") {
        return
    }

    if (-not $DomainName) {
        $DomainName = Read-Host "Enter your custom domain (e.g., winmcp.ctrlvps.dpdns.org)"
    }
    if (-not $DomainName) { return }
    $DomainName = $DomainName.Replace("https://", "").Replace("http://", "").Trim("/")

    $tokenVal = Read-Host "Enter Cloudflare Tunnel Token (starts with eyJh...)"
    if ($DomainName -and $tokenVal) {
        $content = Get-Content $envFile
        $newContent = @()
        foreach ($line in $content) {
            if ($line -match "^WINMCP_TUNNEL_MODE=") { $newContent += "WINMCP_TUNNEL_MODE=Custom" }
            elseif ($line -match "^WINMCP_TUNNEL_TOKEN=") { $newContent += "WINMCP_TUNNEL_TOKEN=$tokenVal" }
            elseif ($line -match "^WINMCP_CUSTOM_DOMAIN=") { $newContent += "WINMCP_CUSTOM_DOMAIN=$DomainName" }
            else { $newContent += $line }
        }
        $newContent | Out-File -FilePath $envFile -Encoding utf8 -Force
        Write-Host "`n[OK] Custom domain configuration saved to .env successfully!" -ForegroundColor Green
        Restart-WinMCP
    }
}

function Clean-WinMCP {
    Write-Host "Cleaning WinMCP temporary files, logs, and sensitive session data..." -ForegroundColor Yellow
    Stop-WinMCP
    if (Test-Path $logDir) {
        Get-ChildItem "$logDir\*.log" -ErrorAction SilentlyContinue | ForEach-Object {
            Clear-Content -Path $_.FullName -Force
        }
    }
    Get-ChildItem -Path $scriptDir -Filter "__pycache__" -Recurse -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[OK] Cleaned logs and temporary files." -ForegroundColor Green
}

function Uninstall-WinMCP {
    & "$scriptDir\uninstall.ps1"
}

function Open-WebDashboard {
    $url = "http://127.0.0.1:8765/dashboard"
    Write-Host "Opening WinMCP Web Dashboard in browser: $url" -ForegroundColor Green
    Start-Process $url
}

function Interactive-Menu {
    while ($true) {
        Clear-Host
        Show-Info
        Write-Host ""
        Write-Host "MANAGEMENT & CONTROL OPTIONS / خيارات التحكم والإدارة:" -ForegroundColor Yellow
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host "  [1]  🎲 Change Token to Random (تغيير التوكن عشوائياً وفصل القديم)" -ForegroundColor White
        Write-Host "  [2]  ✍️  Change Token to Custom (كتابة توكن مخصص من اختيارك)" -ForegroundColor White
        Write-Host "  [3]  🔄 Restart WinMCP Server & Tunnel (إعادة تشغيل الخادم والنفق)" -ForegroundColor White
        Write-Host "  [4]  🛑 Stop WinMCP Server (إيقاف تشغيل الخادم)" -ForegroundColor White
        Write-Host "  [5]  ▶️  Start WinMCP Server (تشغيل الخادم في الخلفية)" -ForegroundColor White
        Write-Host "  [6]  🌐 Switch / Set Custom Domain (تغيير أو ربط دومين مخصص)" -ForegroundColor White
        Write-Host "  [7]  📜 View Live Audit Logs (عرض سجلات النشاط المباشرة)" -ForegroundColor White
        Write-Host "  [8]  🧪 Interactive Tool Runner (تشغيل وتجربة أي أداة مباشرة)" -ForegroundColor White
        Write-Host "  [9]  ⚙️  Toggle Logon Auto-Start (تفعيل/تعطيل بدء التشغيل التلقائي)" -ForegroundColor White
        Write-Host "  [10] 🚀 Manage Windows Service (تثبيت/إلغاء خدمة ويندوز 24/7)" -ForegroundColor White
        Write-Host "  [11] 📋 Refresh Screen (تحديث الشاشة)" -ForegroundColor White
        Write-Host "  [12] 🗑️  Clean Uninstall WinMCP (حذف الأداة بالكامل من جذورها)" -ForegroundColor White
        Write-Host "  [0]  🚪 Exit (خروج)" -ForegroundColor Red
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan

        $choice = Read-Host "Choose an option [0-12]"
        $choice = $choice.Trim()

        switch ($choice) {
            "1" {
                Write-Host "`nGenerating cryptographically secure 256-bit token..." -ForegroundColor Cyan
                $bytes = New-Object byte[] 32
                [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
                $newToken = -join ($bytes | ForEach-Object { "{0:x2}" -f $_ })
                Update-EnvToken -NewToken $newToken
                Write-Host "[OK] New Token: $newToken" -ForegroundColor Green
                Read-Host "Press [Enter] to refresh dashboard with new URLs..."
            }
            "2" {
                Write-Host "`nEnter your new custom Bearer token:" -ForegroundColor Cyan
                $customTok = Read-Host "New Token"
                $customTok = $customTok.Trim()
                if ($customTok.Length -ge 8) {
                    Update-EnvToken -NewToken $customTok
                    Write-Host "[OK] Custom Token set successfully!" -ForegroundColor Green
                } else {
                    Write-Host "[ERROR] Token must be at least 8 characters long." -ForegroundColor Red
                }
                Read-Host "Press [Enter] to refresh dashboard..."
            }
            "3" {
                Restart-WinMCP
                Start-Sleep -Seconds 2
                Read-Host "Press [Enter] to return to dashboard..."
            }
            "4" {
                Stop-WinMCP
                Start-Sleep -Seconds 1
                Read-Host "Press [Enter] to return to dashboard..."
            }
            "5" {
                Start-WinMCP
                Start-Sleep -Seconds 2
                Read-Host "Press [Enter] to return to dashboard..."
            }
            "6" {
                Set-Domain
                Read-Host "Press [Enter] to return to dashboard..."
            }
            "7" {
                Show-Logs
                Read-Host "Press [Enter] to return to dashboard..."
            }
            "8" {
                Interactive-ToolRunner
                Read-Host "Press [Enter] to return to dashboard..."
            }
            "9" {
                Toggle-LogonAutoStart
                Start-Sleep -Seconds 1
                Read-Host "Press [Enter] to return to dashboard..."
            }
            "10" {
                Manage-ServiceMenu
                Read-Host "Press [Enter] to return to dashboard..."
            }
            "11" {
                # Loops and refreshes
            }
            "12" {
                Uninstall-WinMCP
                break
            }
            "0" {
                Write-Host "`nGoodbye! WinMCP continues running safely in the background." -ForegroundColor Green
                return
            }
            default {}
        }
    }
}

switch ($Command.ToLower()) {
    "menu"      { Interactive-Menu }
    "dashboard" { Interactive-Menu }
    ""          { Interactive-Menu }
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
    "run"       { Interactive-ToolRunner }
    "tool"      { Interactive-ToolRunner }
    "token"     { Manage-Token -SubAction $SubCommand -CustomValue $Value }
    "web"       { Open-WebDashboard }
    "gui"       { Open-WebDashboard }
    "uninstall" { Uninstall-WinMCP }
    default     { Interactive-Menu }
}
