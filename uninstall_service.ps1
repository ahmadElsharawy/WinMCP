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
    Write-Host "`n[!] Removing Windows Service requires Administrator privileges. Elevating..." -ForegroundColor Yellow
    $argsList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\uninstall_service.ps1`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argsList
    exit 0
}

$serviceName = "WinMCP-Service"
$nssmExe = "$scriptDir\bin\nssm.exe"

Write-Host "Stopping and removing Windows Service ($serviceName)..." -ForegroundColor Yellow

$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc) {
    if (Test-Path $nssmExe) {
        & "$nssmExe" stop $serviceName 2>$null
        & "$nssmExe" remove $serviceName confirm 2>$null
    } else {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $serviceName | Out-Null
    }
    Write-Host "[OK] Service '$serviceName' successfully removed." -ForegroundColor Green
} else {
    Write-Host "Service '$serviceName' is not installed." -ForegroundColor DarkGray
}
