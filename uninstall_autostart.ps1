<#
.SYNOPSIS
    WinMCP Auto-Start Uninstaller
.DESCRIPTION
    Disables WinMCP auto-start from Windows Task Scheduler and Startup folder.
#>

$taskName = "WindowsMCPServer"
Write-Host "إلغاء تفعيل التشغيل التلقائي لـ WinMCP..." -ForegroundColor Yellow

# 1. Unregister Task Scheduler
try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[✔] تم حذف المهمة من Task Scheduler." -ForegroundColor Green
} catch {}

# 2. Remove Startup Folder VBS
$startupFolder = [Environment]::GetFolderPath("Startup")
$vbsPath = Join-Path $startupFolder "WinMCP_AutoStart.vbs"
if (Test-Path $vbsPath) {
    Remove-Item -Path $vbsPath -Force -ErrorAction SilentlyContinue
    Write-Host "[✔] تم حذف المشغل من مجلد Startup." -ForegroundColor Green
}

Write-Host "تم إيقاف التشغيل التلقائي بنجاح." -ForegroundColor Green
