<#
.SYNOPSIS
    Windows MCP Server - Turnkey One-Liner Installer & Configurator
.DESCRIPTION
    Automated installation, configuration, testing and deployment of Windows MCP Server
    with Cloudflare Tunnel, Bearer Token Authentication, and Task Scheduler auto-start.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Quick", "Custom")]
    [string]$TunnelMode = "",

    [Parameter(Mandatory=$false)]
    [string]$TunnelToken = "",

    [Parameter(Mandatory=$false)]
    [string]$CustomDomain = "",

    [Parameter(Mandatory=$false)]
    [switch]$NonInteractive
)

$ErrorActionPreference = "Continue"

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir -or !(Test-Path $scriptDir)) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir

# --- Styling Helpers ---
function Print-Banner {
    Clear-Host
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "       Windows MCP Server - Turnkey Automated Installer               " -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "Transforms this Windows PC into a remote AI desktop controller" -ForegroundColor Gray
    Write-Host "(Word, Excel, Outlook, Telegram, Browsers, PowerShell, Full System)" -ForegroundColor Gray
    Write-Host "Accessible via Claude & ChatGPT with zero router port forwarding!" -ForegroundColor Yellow
    Write-Host "======================================================================`n" -ForegroundColor Cyan
}

function Print-Step {
    param([string]$Title)
    Write-Host "`n[>] $Title..." -ForegroundColor Cyan
}

function Print-Success {
    param([string]$Msg)
    Write-Host " [OK] $Msg" -ForegroundColor Green
}

function Print-Warning {
    param([string]$Msg)
    Write-Host " [!] $Msg" -ForegroundColor Yellow
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

Print-Banner

# --- Step 1: Tunnel Mode Selection ---
if (-not $TunnelMode) {
    if ($NonInteractive) {
        $TunnelMode = "Quick"
    } else {
        Write-Host "Choose your Cloudflare tunnel mode:" -ForegroundColor White
        Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host " [1] Cloudflare Quick Tunnel (Free, automatic *.trycloudflare.com URL) [Default]" -ForegroundColor Green
        Write-Host "     * Instant setup without requiring a Cloudflare account or domain."
        Write-Host "     * Generates a temporary encrypted HTTPS tunnel URL."
        Write-Host ""
        Write-Host " [2] Custom Domain (Permanent, stable 24/7 URL)" -ForegroundColor Magenta
        Write-Host "     * If you have a domain managed on Cloudflare."
        Write-Host "     * Requires your domain name and Cloudflare Tunnel Token."
        Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkCyan
        
        $choice = Read-Host "Enter your choice [1 or 2] (Default: 1 - Quick Tunnel)"
        if ($choice -eq "2") {
            $TunnelMode = "Custom"
        } else {
            $TunnelMode = "Quick"
        }
    }
}

if ($TunnelMode -eq "Custom") {
    Write-Host "`n--- Custom Domain Setup ---" -ForegroundColor Magenta
    Write-Host "Quick steps from Cloudflare Zero Trust dashboard:" -ForegroundColor Yellow
    Write-Host " 1. Go to: https://one.dash.cloudflare.com -> Networks -> Tunnels"
    Write-Host " 2. Create Tunnel and copy Tunnel Token (starts with eyJh...)."
    Write-Host " 3. Route Public Hostname: Service Type = HTTP, URL = localhost:8765"
    Write-Host "----------------------------------------------------------------------`n" -ForegroundColor DarkGray

    $domainVerified = $false
    while (-not $domainVerified) {
        if (-not $CustomDomain) {
            $CustomDomain = Read-Host "Enter your custom domain (e.g., mcp.yourdomain.com) [or press Enter for Quick Tunnel]"
        }
        
        if (-not $CustomDomain) {
            Write-Host "`n[!] Proceeding with free Cloudflare Quick Tunnel." -ForegroundColor Yellow
            $TunnelMode = "Quick"
            $CustomDomain = ""
            $TunnelToken = ""
            break
        }

        $CustomDomain = $CustomDomain.Replace("https://", "").Replace("http://", "").Trim("/")

        # Check if domain is connected to Cloudflare
        Print-Step "Verifying domain connection ($CustomDomain) with Cloudflare nameservers"
        $cfCheck = Test-CloudflareDomain -Domain $CustomDomain
        
        if ($cfCheck.IsCloudflare) {
            Print-Success "Domain verified: ($($cfCheck.BaseDomain)) is connected to Cloudflare!"
            $domainVerified = $true
        } else {
            Write-Host "`n[!] Warning: Domain '$CustomDomain' does not appear to be routed through Cloudflare NS." -ForegroundColor Yellow
            Write-Host "    (No Cloudflare Nameservers like *.ns.cloudflare.com were detected)" -ForegroundColor Gray
            Write-Host "    To route traffic, the domain must be managed by your Cloudflare account." -ForegroundColor Gray
            Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkCyan
            Write-Host " [1] Re-enter domain name."
            Write-Host " [2] Switch to free Cloudflare Quick Tunnel temporarily."
            Write-Host " [3] Continue with this domain anyway (if DNS propagation is in progress)."
            
            $unverifiedChoice = Read-Host "Enter choice [1, 2, or 3] (Default: 1)"
            if ($unverifiedChoice -eq "2") {
                $TunnelMode = "Quick"
                $CustomDomain = ""
                $TunnelToken = ""
                Write-Host "`nSwitched to free Cloudflare Quick Tunnel." -ForegroundColor Green
                break
            } elseif ($unverifiedChoice -eq "3") {
                Write-Host "`nProceeding with domain regardless of DNS propagation check." -ForegroundColor Yellow
                $domainVerified = $true
            } else {
                $CustomDomain = "" # Reset to prompt again in loop
            }
        }
    }

    if ($TunnelMode -eq "Custom" -and -not $TunnelToken) {
        $TunnelToken = Read-Host "Enter Cloudflare Tunnel Token (starts with eyJh...)"
        if (-not $TunnelToken) {
            Write-Host "`n[!] No token entered. Falling back to Quick Tunnel temporarily." -ForegroundColor Yellow
            Write-Host "You can link your custom domain at any time by running: winmcp domain`n" -ForegroundColor Cyan
            $TunnelMode = "Quick"
            $CustomDomain = ""
        }
    }
}

# --- Step 2: Directories Initialization ---
Print-Step "Setting up workspace directories and environment"
$dirs = @("$scriptDir\bin", "$scriptDir\gateway", "$scriptDir\tunnel\cloudflare", "$scriptDir\logs")
foreach ($d in $dirs) {
    if (!(Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
Print-Success "Directories ready at: $scriptDir"

# --- Step 3: Python Environment Check ---
Print-Step "Checking Python environment and dependencies"
$pythonCmd = Get-Command "python" -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    Write-Error "Python was not found on this machine! Please install Python 3.10+ first."
    exit 1
}
Print-Success "Python detected: $($pythonCmd.Source)"

# Ensure Flask and Requests are installed
$pkgsInstalled = $false
try {
    $out = & python -c "import flask, requests, docx, openpyxl, pypdf, pptx, charset_normalizer; print('OK')" 2>$null
    if ($out -match "OK") { $pkgsInstalled = $true }
} catch {}
if (-not $pkgsInstalled) {
    Write-Host "Installing required packages (Flask, Requests, python-docx, openpyxl, pypdf, python-pptx, charset-normalizer)..." -ForegroundColor Yellow
    & python -m pip install flask requests python-docx openpyxl pypdf python-pptx charset-normalizer --quiet
}
Print-Success "Required packages (Flask, Requests, Universal Document Parsers) are installed."

# --- Step 4: Download windows-mcp-server binary ---
Print-Step "Verifying official engine binary (windows-mcp-server)"
$mcpExe = "$scriptDir\bin\windows-mcp-server.exe"
if (-not (Test-Path $mcpExe)) {
    Write-Host "Downloading windows-mcp-server v1.4.0 official binary..." -ForegroundColor Yellow
    $zipPath = "$scriptDir\bin\windows-mcp-server.zip"
    $dlUrl = "https://github.com/deploymenttheory/windows-mcp-server/releases/download/v1.4.0/windows-mcp-server_1.4.0_windows_amd64.zip"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $dlUrl -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath "$scriptDir\bin" -Force
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
}
Print-Success "Engine binary ready: $mcpExe"

# --- Step 5: Download cloudflared binary ---
Print-Step "Verifying Cloudflare Tunnel binary (cloudflared)"
$cfExe = "$scriptDir\tunnel\cloudflare\cloudflared.exe"
if (-not (Test-Path $cfExe)) {
    Write-Host "Downloading cloudflared.exe..." -ForegroundColor Yellow
    curl.exe -L -o $cfExe "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
}
Print-Success "cloudflared binary ready: $cfExe"

# --- Step 5.1: Download nssm binary ---
Print-Step "Verifying Windows Service manager (nssm)"
$nssmExe = "$scriptDir\bin\nssm.exe"
if (-not (Test-Path $nssmExe)) {
    Write-Host "Downloading nssm v2.24..." -ForegroundColor Yellow
    $nssmZip = "$scriptDir\bin\nssm.zip"
    curl.exe -L -o $nssmZip "https://nssm.cc/release/nssm-2.24.zip"
    if (Test-Path $nssmZip) {
        Expand-Archive -Path $nssmZip -DestinationPath "$scriptDir\bin\nssm_temp" -Force
        Copy-Item "$scriptDir\bin\nssm_temp\nssm-2.24\win64\nssm.exe" -Destination $nssmExe -Force
        Remove-Item "$scriptDir\bin\nssm_temp", $nssmZip -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Print-Success "nssm binary ready: $nssmExe"

# --- Step 6: Configure Environment & Tokens ---
Print-Step "Configuring security authentication (Bearer Token)"
$envFile = "$scriptDir\.env"
$token = ""

if (Test-Path $envFile) {
    $existing = Get-Content $envFile | Where-Object { $_ -match "^WINMCP_AUTH_TOKEN=" }
    if ($existing) {
        $token = $existing.Split("=", 2)[1].Trim()
    }
}

if ($token) {
    Print-Success "Existing security token preserved ($($token.Substring(0, 8))...$($token.Substring($token.Length - 6)))."
} else {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $token = -join ($bytes | ForEach-Object { "{0:x2}" -f $_ })
    Print-Success "Generated secure random 256-bit Bearer token."
}

# Write .env configuration
@"
WINMCP_HOST=127.0.0.1
WINMCP_PORT=8765
WINMCP_AUTH_TOKEN=$token
WINMCP_BINARY_PATH=bin\windows-mcp-server.exe
WINMCP_TOOLSETS=all
WINMCP_LOG_DIR=logs
WINMCP_TUNNEL_MODE=$TunnelMode
WINMCP_TUNNEL_TOKEN=$TunnelToken
WINMCP_CUSTOM_DOMAIN=$CustomDomain
"@ | Out-File -FilePath $envFile -Encoding utf8 -Force

Print-Success "Settings securely saved to: $envFile"

# --- Step 7: Register Auto-start in Windows Task Scheduler & Startup Folder ---
Print-Step "Configuring 24/7 background auto-start and reboot survival"

# 0. Clean up conflicting Session 0 service if previously installed
$svc = Get-Service -Name "WinMCP-Service" -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Removing legacy Session 0 service to prevent desktop isolation conflicts..." -ForegroundColor Yellow
    & "$scriptDir\bin\nssm.exe" stop "WinMCP-Service" 2>$null
    & "$scriptDir\bin\nssm.exe" remove "WinMCP-Service" confirm 2>$null
    sc.exe delete "WinMCP-Service" 2>$null | Out-Null
}

$taskName = "WindowsMCPServer"
$runnerScript = "$scriptDir\run_winmcp.ps1"

# 1. Windows Startup Folder (shell:startup) - 100% Silent VBS Launcher
$startupFolder = [Environment]::GetFolderPath("Startup")
$vbsPath = Join-Path $startupFolder "WinMCP_AutoStart.vbs"
$vbsContent = @"
' WinMCP 100% Silent Background Launcher
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$runnerScript""", 0, False
"@
try {
    $vbsContent | Out-File -FilePath $vbsPath -Encoding ascii -Force
    Print-Success "Silent launcher configured in Windows Startup folder."
} catch {}

# 2. Windows Task Scheduler (Interactive session with Highest Privileges)
$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "//nologo `"$vbsPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Auto-starts Windows MCP Server on user logon" -Force | Out-Null
    Print-Success "Task registered in Windows Task Scheduler ($taskName) with Highest Privileges"
} catch {
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Auto-starts Windows MCP Server on user logon" -Force | Out-Null
        Print-Success "Task registered in Windows Task Scheduler ($taskName)"
    } catch {}
}

# --- Step 8: Add winmcp to User PATH ---
Print-Step "Adding winmcp command to User PATH environment variable"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notmatch [regex]::Escape($scriptDir)) {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$scriptDir", "User")
    $env:Path += ";$scriptDir"
    Print-Success "Added '$scriptDir' to User PATH. You can run 'winmcp' anywhere."
} else {
    Print-Success "winmcp is already present in User PATH."
}

# --- Step 9: Launch Server & Tunnel ---
Print-Step "Starting WinMCP Server and Tunnel now"
& "$scriptDir\run_winmcp.ps1"

# Determine endpoint URL
if ($TunnelMode -eq "Custom" -and $CustomDomain) {
    $finalPublicUrl = "https://$CustomDomain"
} else {
    $finalPublicUrl = ""
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Path "$scriptDir\logs\cloudflared_error.log") {
            $match = Get-Content "$scriptDir\logs\cloudflared_error.log" | Where-Object { $_ -match "(https://[a-zA-Z0-9-]+\.trycloudflare\.com)" } | Select-Object -Last 1
            if ($match -match "(https://[a-zA-Z0-9-]+\.trycloudflare\.com)") {
                $finalPublicUrl = $Matches[1]
                break
            }
        }
    }
    if (-not $finalPublicUrl) {
        $finalPublicUrl = "https://<PENDING_TUNNEL_URL>"
    }
}

# --- Step 10: Final Success Banner ---
Write-Host "`n======================================================================" -ForegroundColor Green
Write-Host "   WinMCP Server Installed and Started Successfully!                  " -ForegroundColor White
Write-Host "======================================================================" -ForegroundColor Green

Write-Host "`nAccess Endpoints:" -ForegroundColor Cyan
Write-Host "  * Public URL            : " -NoNewline -ForegroundColor Gray
Write-Host $finalPublicUrl -ForegroundColor White
Write-Host "  * ChatGPT Endpoint      : " -NoNewline -ForegroundColor Gray
Write-Host "$finalPublicUrl/mcp" -ForegroundColor Yellow
Write-Host "  * Claude Web SSE URL    : " -NoNewline -ForegroundColor Gray
Write-Host "$finalPublicUrl/sse?token=$token" -ForegroundColor Yellow

Write-Host "`nBearer Authentication Token:" -ForegroundColor Cyan
Write-Host "  $token" -ForegroundColor White

Write-Host "`n----------------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host "Interactive CMD Control Center Dashboard:" -ForegroundColor Green
Write-Host "  Launch anytime by running 'winmcp' or double-clicking 'winmcp.bat'" -ForegroundColor Yellow

Write-Host "`n----------------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host "1. How to connect with Claude Web (claude.ai):" -ForegroundColor White
Write-Host "  1. Open claude.ai -> Settings -> Integrations (or Connectors)."
Write-Host "  2. Click Add Custom MCP Connector."
Write-Host "  3. Paste this exact SSE URL:" -ForegroundColor Gray
Write-Host "     $finalPublicUrl/sse?token=$token" -ForegroundColor Cyan

Write-Host "`n2. How to connect with ChatGPT (Custom GPTs / Actions):" -ForegroundColor White
Write-Host "  1. In Custom GPT editor, add an Action / MCP Server."
Write-Host "  2. Server URL     : $finalPublicUrl/mcp" -ForegroundColor Cyan
Write-Host "  3. Authentication : Bearer Token"
Write-Host "  4. Secret Token   : $token"

Write-Host "`n3. Local Connection with Claude Desktop:" -ForegroundColor White
Write-Host "  Add the following to %APPDATA%\Claude\claude_desktop_config.json:" -ForegroundColor Gray
Write-Host @"
{
  "mcpServers": {
    "windows": {
      "command": "$($mcpExe.Replace('\', '\\'))",
      "args": ["stdio", "--toolsets", "all"]
    }
  }
}
"@ -ForegroundColor DarkYellow

Write-Host "`nUseful CLI Commands (run anytime in terminal):" -ForegroundColor Cyan
Write-Host "  winmcp           - Open Interactive CMD Dashboard"
Write-Host "  winmcp status    - Show status summary and public URL"
Write-Host "  winmcp stop      - Stop all WinMCP processes"
Write-Host "  winmcp start     - Launch server and tunnel"
Write-Host "  winmcp restart   - Restart server and refresh tunnel"
Write-Host "  winmcp token     - View, rotate, or set custom token"
Write-Host "  winmcp domain    - Switch or link custom domain"
Write-Host "  winmcp logs      - View recent audit logs"
Write-Host "  winmcp run       - Interactive MCP tool runner"
Write-Host "  winmcp uninstall - Completely uninstall and reset from roots"
Write-Host "======================================================================`n" -ForegroundColor Green

if (-not $NonInteractive) {
    Write-Host "Press [Enter] to open WinMCP Interactive Dashboard..." -ForegroundColor Cyan
    Read-Host
    & "$scriptDir\winmcp.ps1" menu
}
