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

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir -or !(Test-Path $scriptDir)) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir

# --- Styling Helpers ---
function Print-Banner {
    Clear-Host
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "       🚀 Windows MCP Server - Turnkey Automated Installer            " -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "يحول جهاز Windows إلى MCP Server كامل للتحكم في كافة تطبيقات سطح المكتب" -ForegroundColor Gray
    Write-Host "(Word, Excel, Outlook, Telegram, المتصفحات, PowerShell, النظام بالكامل)" -ForegroundColor Gray
    Write-Host "عبر الذكاء الاصطناعي (Claude & ChatGPT) دون الحاجة لفتح بورت في الراوتر!" -ForegroundColor Yellow
    Write-Host "======================================================================`n" -ForegroundColor Cyan
}

function Print-Step {
    param([string]$Title)
    Write-Host "`n[▶] $Title..." -ForegroundColor Cyan
}

function Print-Success {
    param([string]$Msg)
    Write-Host " [✔] $Msg" -ForegroundColor Green
}

function Print-Warning {
    param([string]$Msg)
    Write-Host " [!] $Msg" -ForegroundColor Yellow
}

Print-Banner

# --- Step 1: Tunnel Mode Selection ---
if (-not $TunnelMode) {
    if ($NonInteractive) {
        $TunnelMode = "Quick"
    } else {
        Write-Host "اختر طريقة الوصول عن بُعد (Remote Access Tunnel):" -ForegroundColor White
        Write-Host "--------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host " [1] Quick Tunnel (موصى به - مجاني وفوري بدون دومين أو حساب Cloudflare)" -ForegroundColor Green
        Write-Host "     - يعمل فوراً خلف أي راوتر أو NAT."
        Write-Host "     - يعطيك رابط HTTPS مشفر صالح لـ Claude و ChatGPT مباشرة."
        Write-Host ""
        Write-Host " [2] Custom Domain Tunnel (نطاق خاص دائم)" -ForegroundColor Magenta
        Write-Host "     - يتطلب وجود دومين مضاف مسبقاً في حسابك على Cloudflare."
        Write-Host "     - يتطلب Tunnel Token من لوحة تحكم Cloudflare Zero Trust."
        Write-Host "--------------------------------------------------------" -ForegroundColor DarkCyan
        
        $choice = Read-Host "أدخل اختيارك [1 أو 2] (الافتراضي 1)"
        if ($choice -eq "2") {
            $TunnelMode = "Custom"
        } else {
            $TunnelMode = "Quick"
        }
    }
}

if ($TunnelMode -eq "Custom") {
    Write-Host "`n--- إعداد النطاق المخصص (Custom Domain Setup) ---" -ForegroundColor Magenta
    Write-Host "تعليمات مطلوبة:" -ForegroundColor Yellow
    Write-Host " 1. ادخل على Cloudflare Zero Trust Dashboard -> Networks -> Tunnels."
    Write-Host " 2. أنشئ نفق جديد وانسخ الـ Tunnel Token (يبدأ بـ eyJh...)."
    Write-Host " 3. اربط الـ Public Hostname مع: Service Type = HTTP, URL = localhost:8765"
    Write-Host "----------------------------------------------------`n" -ForegroundColor DarkGray

    if (-not $TunnelToken) {
        $TunnelToken = Read-Host "أدخل Cloudflare Tunnel Token"
    }
    if (-not $CustomDomain) {
        $CustomDomain = Read-Host "أدخل النطاق المخصص الخاص بك (مثال: mcp.yourdomain.com)"
    }
    $CustomDomain = $CustomDomain.Replace("https://", "").Replace("http://", "").Trim("/")
}

# --- Step 2: Directories Initialization ---
Print-Step "تجهيز مجلدات العمل وإعداد البيئة"
$dirs = @("$scriptDir\bin", "$scriptDir\gateway", "$scriptDir\tunnel\cloudflare", "$scriptDir\logs")
foreach ($d in $dirs) {
    if (!(Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
Print-Success "المجلدات جاهزة في: $scriptDir"

# --- Step 3: Python Environment Check ---
Print-Step "فحص بيئة Python والمكتبات"
$pythonCmd = Get-Command "python" -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    Write-Error "لم يتم العثور على Python مثبت على الجهاز! يرجى تثبيت Python 3.10+ أولاً."
    exit 1
}
Print-Success "Python مثبت: $($pythonCmd.Source)"

# Ensure Flask and Requests are installed
try {
    & python -c "import flask, requests" 2>$null
    Print-Success "المكتبات المطلوبة (Flask, Requests) متوفرة."
} catch {
    Write-Host "تثبيت المكتبات المطلوبة..." -ForegroundColor Yellow
    & python -m pip install flask requests --quiet
    Print-Success "تم تثبيت المكتبات بنجاح."
}

# --- Step 4: Download windows-mcp-server binary ---
Print-Step "التحقق من باينري المحرك الرسمي (windows-mcp-server)"
$mcpExe = "$scriptDir\bin\windows-mcp-server.exe"
if (-not (Test-Path $mcpExe)) {
    Write-Host "تنزيل windows-mcp-server v1.4.0 الرسمية..." -ForegroundColor Yellow
    $zipPath = "$scriptDir\bin\windows-mcp-server.zip"
    $dlUrl = "https://github.com/deploymenttheory/windows-mcp-server/releases/download/v1.4.0/windows-mcp-server_1.4.0_windows_amd64.zip"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $dlUrl -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath "$scriptDir\bin" -Force
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
}
Print-Success "المحرك الرسمي جاهز: $mcpExe"

# --- Step 5: Download cloudflared binary ---
Print-Step "التحقق من نفق Cloudflare Tunnel (cloudflared)"
$cfExe = "$scriptDir\tunnel\cloudflare\cloudflared.exe"
if (-not (Test-Path $cfExe)) {
    Write-Host "تنزيل cloudflared.exe عبر curl..." -ForegroundColor Yellow
    curl.exe -L -o $cfExe "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
}
Print-Success "باينري cloudflared جاهز: $cfExe"

# --- Step 5.1: Download nssm binary ---
Print-Step "التحقق من أداة خدمات الويندوز (nssm)"
$nssmExe = "$scriptDir\bin\nssm.exe"
if (-not (Test-Path $nssmExe)) {
    Write-Host "تنزيل nssm v2.24..." -ForegroundColor Yellow
    $nssmZip = "$scriptDir\bin\nssm.zip"
    curl.exe -L -o $nssmZip "https://nssm.cc/release/nssm-2.24.zip"
    if (Test-Path $nssmZip) {
        Expand-Archive -Path $nssmZip -DestinationPath "$scriptDir\bin\nssm_temp" -Force
        Copy-Item "$scriptDir\bin\nssm_temp\nssm-2.24\win64\nssm.exe" -Destination $nssmExe -Force
        Remove-Item "$scriptDir\bin\nssm_temp", $nssmZip -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Print-Success "أداة nssm جاهزة: $nssmExe"

# --- Step 6: Configure Environment & Tokens ---
Print-Step "تأمين الاتصال وتوليد مفتاح الأمان (256-bit Bearer Token)"
$envFile = "$scriptDir\.env"
$token = ""

if (Test-Path $envFile) {
    $existing = Get-Content $envFile | Where-Object { $_ -match "^WINMCP_AUTH_TOKEN=" }
    if ($existing) {
        $token = $existing.Split("=", 2)[1].Trim()
        Print-Success "تم استخدام المفتاح السري الحالي من ملف .env"
    }
}

if (-not $token) {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $token = -join ($bytes | ForEach-Object { "{0:x2}" -f $_ })
    Print-Success "تم إنشاء مفتاح أمان عشوائي فائق التشفير."
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

Print-Success "تم حفظ الإعدادات بأمان في: $envFile"

# --- Step 7: Register Auto-start in Windows Task Scheduler & Startup Folder ---
Print-Step "ضبط التشغيل التلقائي مع بدء الويندوز والعمل في الخلفية (Background Services)"
$taskName = "WindowsMCPServer"
$runnerScript = "$scriptDir\run_winmcp.ps1"

# 1. Task Scheduler
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runnerScript`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Auto-starts Windows MCP Server & Gateway on logon" -Force | Out-Null
    Print-Success "تم تسجيل مهمة التشغيل التلقائي في Task Scheduler ($taskName)"
} catch {
    Print-Warning "تعذر تسجيل المهمة المجدولة: $($_.Exception.Message)"
}

# 2. Windows Startup Folder (shell:startup)
$startupFolder = [Environment]::GetFolderPath("Startup")
$vbsPath = Join-Path $startupFolder "WinMCP_AutoStart.vbs"
$vbsContent = @"
' WinMCP Silent Background Launcher
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$runnerScript""", 0, False
"@
try {
    $vbsContent | Out-File -FilePath $vbsPath -Encoding ascii -Force
    Print-Success "تم تفعيل المشغل الصامت في مجلد بدء التشغيل (Startup Folder)"
} catch {}

# --- Step 8: Add winmcp to User PATH ---
Print-Step "إضافة أمر winmcp في موجه الأوامر"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notmatch [regex]::Escape($scriptDir)) {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$scriptDir", "User")
    $env:Path += ";$scriptDir"
    Print-Success "تم إضافة '$scriptDir' إلى PATH (يمكنك كتابة winmcp في أي وقت)."
} else {
    Print-Success "أمر winmcp متاح بالفعل في PATH."
}

# --- Step 9: Launch Server & Tunnel ---
Print-Step "بدء تشغيل الخادم والنفق السحابي الآن"
& "$scriptDir\stop_winmcp.ps1" | Out-Null
Start-Sleep -Seconds 1

# Start Gateway
$gatewayPy = "$scriptDir\gateway\server.py"
Start-Process -FilePath "python.exe" -ArgumentList "-u `"$gatewayPy`"" -RedirectStandardOutput "$scriptDir\logs\gateway.log" -RedirectStandardError "$scriptDir\logs\gateway_error.log" -WindowStyle Hidden

# Wait for local health
$isReady = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    try {
        $res = Invoke-RestMethod -Uri "http://127.0.0.1:8765/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($res.status -eq "ok") {
            $isReady = $true
            break
        }
    } catch {}
}

if (-not $isReady) {
    Write-Error "استغرق الخادم وقتاً أطول من المعتاد للبدء. تفقد السجلات في logs/gateway_error.log"
    exit 1
}
Print-Success "البوابة الوسيطة تعمل على http://127.0.0.1:8765"

# Start Tunnel
if ($TunnelMode -eq "Custom" -and $TunnelToken) {
    Write-Host "تشغيل نفق Cloudflare المخصص..." -ForegroundColor Yellow
    Start-Process -FilePath $cfExe -ArgumentList "tunnel run --token $TunnelToken" -RedirectStandardOutput "$scriptDir\logs\cloudflared_error.log" -RedirectStandardError "$scriptDir\logs\cloudflared_error.log" -WindowStyle Hidden
    $finalPublicUrl = "https://$CustomDomain"
} else {
    Write-Host "تشغيل Cloudflare Quick Tunnel..." -ForegroundColor Yellow
    Remove-Item -Path "$scriptDir\logs\cloudflared_error.log" -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath $cfExe -ArgumentList "tunnel --url http://127.0.0.1:8765" -RedirectStandardOutput "$scriptDir\logs\cloudflared_error.log" -RedirectStandardError "$scriptDir\logs\cloudflared_error.log" -WindowStyle Hidden
    
    # Wait for URL to appear in log
    $finalPublicUrl = ""
    for ($i = 0; $i -lt 25; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Path "$scriptDir\logs\cloudflared_error.log") {
            $match = Get-Content "$scriptDir\logs\cloudflared_error.log" | Where-Object { $_ -match "(https://[a-zA-Z0-9-]+\.trycloudflare\.com)" } | Select-Object -Last 1
            if ($match -match "(https://[a-zA-Z0-9-]+\.trycloudflare\.com)") {
                $finalPublicUrl = $Matches[1]
                break
            }
        }
    }
}

if (-not $finalPublicUrl) {
    $finalPublicUrl = "https://<PENDING_TUNNEL_URL>"
    Print-Warning "النفق قيد الاتصال. يمكنك كتابة 'winmcp status' بعد ثوانٍ لعرض الرابط."
} else {
    Print-Success "تم إنشاء الرابط الخارجي المشفر بنجاح: $finalPublicUrl"
}

# --- Step 10: Final Success Banner ---
Write-Host "`n`n======================================================================" -ForegroundColor Green
Write-Host "   🎉  تم تثبيت وتشغيل Windows MCP Server بنجاح فائق!                 " -ForegroundColor White
Write-Host "======================================================================" -ForegroundColor Green

Write-Host "`n📡 روابط الوصول إلى جهازك (Endpoints):" -ForegroundColor Cyan
Write-Host "  • الرابط الأساسي (Gateway)    : " -NoNewline -ForegroundColor Gray
Write-Host $finalPublicUrl -ForegroundColor White
Write-Host "  • رابط ChatGPT (Streamable)   : " -NoNewline -ForegroundColor Gray
Write-Host "$finalPublicUrl/mcp" -ForegroundColor Yellow
Write-Host "  • رابط Claude Web (SSE URL)   : " -NoNewline -ForegroundColor Gray
Write-Host "$finalPublicUrl/sse?token=$token" -ForegroundColor Yellow

Write-Host "`n🔑 مفتاح الأمان (Bearer Token):" -ForegroundColor Cyan
Write-Host "  $token" -ForegroundColor White

Write-Host "`n----------------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host "🤖 1. طريقة التوصيل مع Claude Web (claude.ai):" -ForegroundColor White
Write-Host "  1. ادخل على claude.ai -> Settings -> Integrations (أو Connectors)."
Write-Host "  2. اختر Add Custom MCP Connector."
Write-Host "  3. الصق الرابط التالي مباشرة:" -ForegroundColor Gray
Write-Host "     $finalPublicUrl/sse?token=$token" -ForegroundColor Cyan

Write-Host "`n🤖 2. طريقة التوصيل مع ChatGPT (Custom GPTs / Actions):" -ForegroundColor White
Write-Host "  1. في لوحة Custom GPTs أضف Action / MCP Endpoint."
Write-Host "  2. الرابط: $finalPublicUrl/mcp" -ForegroundColor Cyan
Write-Host "  3. نوع التوثيق: Bearer Token"
Write-Host "  4. التوكن: $token"

Write-Host "`n💻 3. طريقة التوصيل مع Claude Desktop (محلياً على نفس الجهاز):" -ForegroundColor White
Write-Host "  أضف الكود التالي في ملف claude_desktop_config.json:" -ForegroundColor Gray
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

Write-Host "`n⚡ أوامر الإدارة السريعة (في أي وقت من PowerShell):" -ForegroundColor Cyan
Write-Host "  winmcp status    - عرض حالة السيرفر والرابط الخارجي النشط"
Write-Host "  winmcp stop      - إيقاف السيرفر والنفق"
Write-Host "  winmcp start     - تشغيل السيرفر والنفق مجدداً"
Write-Host "  winmcp logs      - متابعة أوامر الـ AI لحظياً"
Write-Host "  winmcp token     - عرض مفتاح الأمان"
Write-Host "======================================================================`n" -ForegroundColor Green
