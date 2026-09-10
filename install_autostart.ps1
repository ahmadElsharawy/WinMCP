<#
.SYNOPSIS
    WinMCP Interactive Auto-Start Installer (Task Scheduler & Startup)
.DESCRIPTION
    Configures WinMCP to start automatically on Windows logon/boot in the background.
    Preserves full interactive user session access for Word, Excel, Outlook, Telegram,
    browsers, and desktop UI automation.
#>

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "    تفعيل التشغيل التلقائي مع الويندوز (Interactive Auto-Start)" -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Cyan

$taskName = "WindowsMCPServer"
$runnerScript = "$scriptDir\run_winmcp.ps1"

# 1. Register in Windows Task Scheduler
Write-Host "[1/2] تسجيل المهمة في مجدول مهام ويندوز (Task Scheduler)..." -ForegroundColor Cyan
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runnerScript`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Auto-starts Windows MCP Server on user logon" -Force | Out-Null
    Write-Host " [✔] تم تسجيل المهمة المجدولة بنجاح ($taskName)." -ForegroundColor Green
} catch {
    Write-Host " [!] تنبيه في مجدول المهام: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 2. Add Silent VBS Launcher to Windows Startup Folder (shell:startup)
Write-Host "[2/2] إنشاء مشغل صامت في مجلد بدء التشغيل (Startup Folder)..." -ForegroundColor Cyan
$startupFolder = [Environment]::GetFolderPath("Startup")
$vbsPath = Join-Path $startupFolder "WinMCP_AutoStart.vbs"

$vbsContent = @"
' WinMCP Silent Background Launcher
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$runnerScript""", 0, False
"@

try {
    $vbsContent | Out-File -FilePath $vbsPath -Encoding ascii -Force
    Write-Host " [✔] تم إنشاء المشغل الصامت في: $vbsPath" -ForegroundColor Green
} catch {
    Write-Host " [!] لم نتمكن من الكتابة في مجلد Startup: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n[✔] سيعمل WinMCP تلقائياً في الخلفية في كل مرة تفتح فيها الويندوز أو تعيد تشغيله!" -ForegroundColor Green
Write-Host "========================================================`n" -ForegroundColor Cyan
