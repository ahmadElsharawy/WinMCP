<#
.SYNOPSIS
    WinMCP Windows Service Uninstaller
.DESCRIPTION
    Stops and removes the WinMCP-Service Windows Service.
#>

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir

# Check Administrator Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n[!] إزالة خدمة الويندوز تتطلب صلاحيات المسؤول. جاري طلب الصلاحيات..." -ForegroundColor Yellow
    $argsList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\uninstall_service.ps1`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argsList
    exit 0
}

$serviceName = "WinMCP-Service"
$nssmExe = "$scriptDir\bin\nssm.exe"

Write-Host "إيقاف وحذف خدمة Windows ($serviceName)..." -ForegroundColor Yellow

$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc) {
    if (Test-Path $nssmExe) {
        & "$nssmExe" stop $serviceName 2>$null
        & "$nssmExe" remove $serviceName confirm 2>$null
    } else {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $serviceName | Out-Null
    }
    Write-Host "[✔] تم حذف خدمة $serviceName بنجاح." -ForegroundColor Green
} else {
    Write-Host "الخدمة $serviceName غير موجودة بالفعل." -ForegroundColor DarkGray
}
