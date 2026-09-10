<#
.SYNOPSIS
    WinMCP Auto-Start Uninstaller
.DESCRIPTION
    Disables WinMCP auto-start from Windows Task Scheduler and Startup folder.
#>

$taskName = "WindowsMCPServer"
Write-Host "Disabling WinMCP auto-start..." -ForegroundColor Yellow

# 1. Unregister Task Scheduler
try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[OK] Removed task from Task Scheduler." -ForegroundColor Green
} catch {}

# 2. Remove Startup Folder VBS
$startupFolder = [Environment]::GetFolderPath("Startup")
$vbsPath = Join-Path $startupFolder "WinMCP_AutoStart.vbs"
if (Test-Path $vbsPath) {
    Remove-Item -Path $vbsPath -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Removed silent launcher from Startup folder." -ForegroundColor Green
}

Write-Host "Auto-start successfully disabled." -ForegroundColor Green
