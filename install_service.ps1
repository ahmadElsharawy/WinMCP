<#
.SYNOPSIS
    WinMCP Windows Service Installer (via NSSM)
.DESCRIPTION
    Installs and starts Windows MCP Server as a native Windows Service (WinMCP-Service)
    that runs 24/7 in the background and auto-starts on system boot even before user logon.
#>

param(
    [switch]$Force
)

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir

# Check Administrator Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n[!] تتطلب خدمة الويندوز صلاحيات المسؤول (Administrator). جاري طلب الصلاحيات..." -ForegroundColor Yellow
    $argsList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\install_service.ps1`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argsList
    exit 0
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "    تثبيت WinMCP كخدمة نظام ويندوز دائمة (Windows Service)  " -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Cyan

$serviceName = "WinMCP-Service"
$nssmExe = "$scriptDir\bin\nssm.exe"
$runnerScript = "$scriptDir\run_winmcp.ps1"
$logDir = "$scriptDir\logs"

if (-not (Test-Path $nssmExe)) {
    Write-Host "تنزيل أداة nssm.exe..." -ForegroundColor Yellow
    $nssmZip = "$scriptDir\bin\nssm.zip"
    curl.exe -L -o $nssmZip "https://nssm.cc/release/nssm-2.24.zip"
    if (Test-Path $nssmZip) {
        Expand-Archive -Path $nssmZip -DestinationPath "$scriptDir\bin\nssm_temp" -Force
        Copy-Item "$scriptDir\bin\nssm_temp\nssm-2.24\win64\nssm.exe" -Destination $nssmExe -Force
        Remove-Item "$scriptDir\bin\nssm_temp", $nssmZip -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# 1. Stop existing service if running
$existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "إيقاف الخدمة الحالية..." -ForegroundColor Yellow
    & "$nssmExe" stop $serviceName 2>$null
    & "$nssmExe" remove $serviceName confirm 2>$null
    Start-Sleep -Seconds 2
}

# 2. Install Service via NSSM
Write-Host "تسجيل الخدمة في نظام Windows Services..." -ForegroundColor Cyan
$psExe = (Get-Command "powershell.exe").Source

& "$nssmExe" install $serviceName "$psExe" "-NoProfile -ExecutionPolicy Bypass -File `"$runnerScript`""
& "$nssmExe" set $serviceName AppDirectory "$scriptDir"
& "$nssmExe" set $serviceName DisplayName "Windows MCP Server Gateway"
& "$nssmExe" set $serviceName Description "Windows MCP Server Background Gateway and Cloudflare Tunnel Service"
& "$nssmExe" set $serviceName Start SERVICE_AUTO_START
& "$nssmExe" set $serviceName AppStdout "$logDir\service.log"
& "$nssmExe" set $serviceName AppStderr "$logDir\service_error.log"

# 3. Start the service
Write-Host "بدء تشغيل الخدمة الآن..." -ForegroundColor Cyan
& "$nssmExe" start $serviceName

Start-Sleep -Seconds 3
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($svc -and $svc.Status -eq "Running") {
    Write-Host "`n[✔] تم تثبيت وتشغيل خدمة WinMCP بنجاح فائق!" -ForegroundColor Green
    Write-Host "  - اسم الخدمة: $serviceName" -ForegroundColor White
    Write-Host "  - نوع البدء: تلقائي مع إقلاع الجهاز (SERVICE_AUTO_START)" -ForegroundColor White
    Write-Host "  - تعمل دائماً في الخلفية وتستمر حتى بعد الريستارت." -ForegroundColor White
} else {
    Write-Host "`n[!] تم تسجيل الخدمة وحالتها الحالية: $($svc.Status)" -ForegroundColor Yellow
    Write-Host "تفقد السجلات في: $logDir\service_error.log" -ForegroundColor DarkGray
}

Write-Host "========================================================`n" -ForegroundColor Cyan
