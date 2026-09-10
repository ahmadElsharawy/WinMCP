<#
.SYNOPSIS
    WinMCP - Complete Root Uninstaller & Purge
.DESCRIPTION
    Completely stops, unregisters and purges Windows MCP Server from the machine:
    - Stops all active processes (windows-mcp-server, cloudflared, python gateway).
    - Uninstalls native Windows Service (WinMCP-Service).
    - Unregisters Task Scheduler task (WindowsMCPServer).
    - Removes silent launcher from Startup folder (WinMCP_AutoStart.vbs).
    - Cleans User PATH environment variable.
    - Purges .env configuration, logs, pycache, and temporary files.
    - Optionally purges project directory.
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [switch]$PurgeFolder
)

$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir -or !(Test-Path $scriptDir)) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir

function Print-Banner {
    Clear-Host
    Write-Host "======================================================================" -ForegroundColor Red
    Write-Host "       🗑️  Windows MCP Server - معالج حذف المشروع من كامل جذوره         " -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Red
    Write-Host "يقوم هذا المعالج بإزالة كافة آثار وخيوط WinMCP من النظام:" -ForegroundColor Gray
    Write-Host " • إيقاف وإنهاء كافة العمليات النشطة (Server, Gateway, Cloudflare)." -ForegroundColor Gray
    Write-Host " • إزالة خدمة الويندوز الرسمية (WinMCP-Service) إن كانت مثبتة." -ForegroundColor Gray
    Write-Host " • حذف مهمة التشغيل التلقائي من مجدول مهام ويندوز (Task Scheduler)." -ForegroundColor Gray
    Write-Host " • حذف المشغل الصامت من مجلد بدء التشغيل (Startup Folder)." -ForegroundColor Gray
    Write-Host " • تنظيف وإزالة مسار المشروع من متغيرات النظام (User PATH)." -ForegroundColor Gray
    Write-Host " • حذف ملف الإعدادات (.env) وكافة السجلات (logs) وملفات الكاش." -ForegroundColor Gray
    Write-Host "======================================================================`n" -ForegroundColor Red
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

$deleteMode = 1 # 1: Reset & Clean for Reinstall, 2: Complete Purge & Delete Folder, 3: Cancel

if (-not $Force) {
    Write-Host "اختر نوع الحذف المطلوب:" -ForegroundColor White
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [1] تصفير النظام وإزالة الخدمات لبدء تجربة جديدة نظيفة (Reset & Clean)" -ForegroundColor Green
    Write-Host "     • يوقف كل شيء، ويحذف خدمات الويندوز، والمهمات، والـ PATH، وملف .env، والسجلات."
    Write-Host "     • يترك كود المشروع جاهزاً لتشغيل install.bat والتثبيت من الصفر."
    Write-Host ""
    Write-Host " [2] حذف كامل ونهائي مع مسح مجلد المشروع بالكامل من القرص (Full Purge)" -ForegroundColor Red
    Write-Host "     • يزيل كل شيء من النظام بالإضافة إلى حذف مجلد WinMCP نهائياً."
    Write-Host ""
    Write-Host " [3] إلغاء العملية والرجوع (Cancel)" -ForegroundColor DarkGray
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkCyan
    
    $inputChoice = Read-Host "أدخل اختيارك [1 أو 2 أو 3] (الافتراضي 1)"
    if ($inputChoice -eq "2") {
        $deleteMode = 2
    } elseif ($inputChoice -eq "3") {
        Write-Host "`nتم إلغاء عملية الحذف." -ForegroundColor Yellow
        exit 0
    } else {
        $deleteMode = 1
    }
} else {
    if ($PurgeFolder) { $deleteMode = 2 } else { $deleteMode = 1 }
}

# --- Step 1: Stop All Running Processes ---
Print-Step "1. إيقاف وإنهاء كافة العمليات الجارية"
$procsToKill = @("windows-mcp-server", "cloudflared", "rathole")
foreach ($p in $procsToKill) {
    Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

# Stop python processes running server.py
Get-CimInstance Win32_Process -Filter "Name = 'python.exe' or Name = 'pythonw.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "gateway\\server\.py" } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Print-Success "تم إيقاف كافة العمليات النشطة."

# --- Step 2: Uninstall Windows Service (if installed) ---
Print-Step "2. التحقق من وحذف خدمة الويندوز (WinMCP-Service)"
$svc = Get-Service -Name "WinMCP-Service" -ErrorAction SilentlyContinue
if ($svc) {
    $nssmExe = "$scriptDir\bin\nssm.exe"
    if (Test-Path $nssmExe) {
        & "$nssmExe" stop "WinMCP-Service" 2>$null
        & "$nssmExe" remove "WinMCP-Service" confirm 2>$null
    } else {
        Stop-Service -Name "WinMCP-Service" -Force -ErrorAction SilentlyContinue
        sc.exe delete "WinMCP-Service" | Out-Null
    }
    Print-Success "تم حذف خدمة WinMCP-Service من نظام الويندوز."
} else {
    Print-Success "خدمة WinMCP-Service غير مثبتة."
}

# --- Step 3: Remove Windows Task Scheduler Task ---
Print-Step "3. إزالة مهمة التشغيل التلقائي من Task Scheduler"
$task = Get-ScheduledTask -TaskName "WindowsMCPServer" -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName "WindowsMCPServer" -Confirm:$false -ErrorAction SilentlyContinue
    Print-Success "تم حذف المهمة المجدولة (WindowsMCPServer)."
} else {
    Print-Success "لا توجد مهمة مجدولة مسجلة بهذا الاسم."
}

# --- Step 4: Remove Silent Launcher from Windows Startup Folder ---
Print-Step "4. إزالة المشغل من مجلد بدء التشغيل (Startup Folder)"
$startupFolder = [Environment]::GetFolderPath("Startup")
$vbsPath = Join-Path $startupFolder "WinMCP_AutoStart.vbs"
if (Test-Path $vbsPath) {
    Remove-Item -Path $vbsPath -Force -ErrorAction SilentlyContinue
    Print-Success "تم حذف المشغل الصامت (WinMCP_AutoStart.vbs)."
} else {
    Print-Success "المشغل غير موجود في مجلد Startup."
}

# --- Step 5: Clean Project Directory from User PATH ---
Print-Step "5. إزالة أمر winmcp ومسار المشروع من متغيرات النظام (User PATH)"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath) {
    $cleanPathElements = @()
    $modified = $false
    foreach ($entry in $userPath.Split(";")) {
        $trimmed = $entry.Trim()
        if ($trimmed) {
            if ($trimmed.TrimEnd("\") -eq $scriptDir.TrimEnd("\")) {
                $modified = $true
            } else {
                $cleanPathElements += $trimmed
            }
        }
    }
    if ($modified) {
        $newUserPath = $cleanPathElements -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Print-Success "تم تنظيف User PATH وحذف مسار المشروع منه."
    } else {
        Print-Success "مسار المشروع غير مسجل في User PATH."
    }
}

# --- Step 6: Delete Runtime Configurations, Logs, and Caches ---
Print-Step "6. تصفير ملفات الإعدادات والسجلات وملفات الكاش"
$envFile = "$scriptDir\.env"
if (Test-Path $envFile) {
    Remove-Item -Path $envFile -Force -ErrorAction SilentlyContinue
    Print-Success "تم حذف ملف الإعدادات (.env)."
}

$logDir = "$scriptDir\logs"
if (Test-Path $logDir) {
    Get-ChildItem -Path $logDir -Recurse -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Print-Success "تم تفريغ كافة سجلات التشغيل (logs)."
}

# Remove Python cache
Get-ChildItem -Path $scriptDir -Filter "__pycache__" -Recurse -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
# Remove test scratch
$scratchDir = "$scriptDir\test_scratch"
if (Test-Path $scratchDir) { Remove-Item -Path $scratchDir -Recurse -Force -ErrorAction SilentlyContinue }

Print-Success "تم مسح كافة ملفات الكاش والبيانات المؤقتة."

# --- Step 7: Handle Full Purge or Reset Complete ---
Write-Host "`n======================================================================" -ForegroundColor Green
if ($deleteMode -eq 2) {
    Write-Host "       [✔] تم تنظيف النظام بالكامل! جاري مسح مجلد المشروع...           " -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "`nسيتم إغلاق النافذة وحذف المجلد $scriptDir نهائياً من القرص..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    # Self-deleting batch command outside the directory
    $cmd = "ping 127.0.0.1 -n 3 > nul & rmdir /s /q `"$scriptDir`""
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -WindowStyle Hidden
    exit 0
} else {
    Write-Host "       [✔] تم حذف المشروع من كامل جذوره وتصفير النظام بنجاح!          " -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "النظام الآن نظيف 100% وخالٍ من أي خدمات أو عمليات أو تسجيلات في الخلفية." -ForegroundColor White
    Write-Host "يمكنك الآن تجربة المشروع من جديد في أي وقت بتشغيل:" -ForegroundColor Cyan
    Write-Host "  👉 install.bat (بالنقر المزدوج) أو .\install.ps1 (عبر موجه الأوامر)" -ForegroundColor Yellow
    Write-Host "======================================================================`n" -ForegroundColor Green
}
