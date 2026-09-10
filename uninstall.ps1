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

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir -or !(Test-Path $scriptDir)) { $scriptDir = (Get-Location).Path }
Set-Location $scriptDir

function Print-Banner {
    Clear-Host
    Write-Host "======================================================================" -ForegroundColor Red
    Write-Host "       WinMCP - Complete Root Uninstaller & Purge                     " -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Red
    Write-Host "This uninstaller will clean all WinMCP components from your system:" -ForegroundColor Gray
    Write-Host "  * Terminate all active processes (Server, Gateway, Cloudflare)." -ForegroundColor Gray
    Write-Host "  * Remove native Windows Service (WinMCP-Service) if installed." -ForegroundColor Gray
    Write-Host "  * Remove auto-start task from Windows Task Scheduler." -ForegroundColor Gray
    Write-Host "  * Remove silent launcher from Windows Startup folder." -ForegroundColor Gray
    Write-Host "  * Remove project path from User PATH environment variable." -ForegroundColor Gray
    Write-Host "  * Delete configuration (.env), all logs, caches, and temporary data." -ForegroundColor Gray
    Write-Host "======================================================================`n" -ForegroundColor Red
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

Print-Banner

$deleteMode = 1 # 1: Reset & Clean for Reinstall, 2: Complete Purge & Delete Folder, 3: Cancel

if (-not $Force) {
    Write-Host "Choose an uninstallation mode:" -ForegroundColor White
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [1] Reset & Clean (Recommended for clean reinstall)" -ForegroundColor Green
    Write-Host "     * Stops everything, removes services, tasks, PATH, .env, and logs."
    Write-Host "     * Keeps source code ready to run install.bat / install.ps1 from scratch."
    Write-Host ""
    Write-Host " [2] Complete Purge & Delete Folder" -ForegroundColor Red
    Write-Host "     * Uninstalls all components and permanently deletes the project directory."
    Write-Host ""
    Write-Host " [3] Cancel" -ForegroundColor DarkGray
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkCyan
    
    $inputChoice = Read-Host "Enter your choice [1, 2, or 3] (Default: 1)"
    if ($inputChoice -eq "2") {
        $deleteMode = 2
    } elseif ($inputChoice -eq "3") {
        Write-Host "`nUninstallation canceled." -ForegroundColor Yellow
        exit 0
    } else {
        $deleteMode = 1
    }
} else {
    if ($PurgeFolder) { $deleteMode = 2 } else { $deleteMode = 1 }
}

# --- Step 1: Stop All Running Processes ---
Print-Step "1. Stopping all active processes"
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
Print-Success "All active processes stopped."

# --- Step 2: Uninstall Windows Service (if installed) ---
Print-Step "2. Checking and removing Windows Service (WinMCP-Service)"
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
    Print-Success "Removed WinMCP-Service from Windows Services."
} else {
    Print-Success "WinMCP-Service is not installed."
}

# --- Step 3: Remove Windows Task Scheduler Task ---
Print-Step "3. Removing auto-start task from Task Scheduler"
$task = Get-ScheduledTask -TaskName "WindowsMCPServer" -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName "WindowsMCPServer" -Confirm:$false -ErrorAction SilentlyContinue
    Print-Success "Removed scheduled task (WindowsMCPServer)."
} else {
    Print-Success "No scheduled task found with this name."
}

# --- Step 4: Remove Silent Launcher from Windows Startup Folder ---
Print-Step "4. Removing launcher from Windows Startup folder"
$startupFolder = [Environment]::GetFolderPath("Startup")
$vbsPath = Join-Path $startupFolder "WinMCP_AutoStart.vbs"
if (Test-Path $vbsPath) {
    Remove-Item -Path $vbsPath -Force -ErrorAction SilentlyContinue
    Print-Success "Removed silent launcher (WinMCP_AutoStart.vbs)."
} else {
    Print-Success "No launcher found in Startup folder."
}

# --- Step 5: Clean Project Directory from User PATH ---
Print-Step "5. Cleaning project directory from User PATH environment variable"
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
        Print-Success "Removed project directory from User PATH."
    } else {
        Print-Success "Project directory was not in User PATH."
    }
}

# --- Step 6: Delete Runtime Configurations, Logs, and Caches ---
Print-Step "6. Purging configuration (.env), logs, and temporary caches"
$envFile = "$scriptDir\.env"
if (Test-Path $envFile) {
    Remove-Item -Path $envFile -Force -ErrorAction SilentlyContinue
    Print-Success "Deleted configuration file (.env)."
}

$logDir = "$scriptDir\logs"
if (Test-Path $logDir) {
    Get-ChildItem -Path $logDir -Recurse -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Print-Success "Cleared all runtime logs."
}

# Remove Python cache
Get-ChildItem -Path $scriptDir -Filter "__pycache__" -Recurse -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
# Remove test scratch
$scratchDir = "$scriptDir\test_scratch"
if (Test-Path $scratchDir) { Remove-Item -Path $scratchDir -Recurse -Force -ErrorAction SilentlyContinue }

Print-Success "Purged all caches and temporary files."

# --- Step 7: Handle Full Purge or Reset Complete ---
Write-Host "`n======================================================================" -ForegroundColor Green
if ($deleteMode -eq 2) {
    Write-Host "       [OK] System cleaned! Deleting project folder...                 " -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "`nClosing window and permanently deleting: $scriptDir..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    $cmd = "ping 127.0.0.1 -n 3 > nul & rmdir /s /q `"$scriptDir`""
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -WindowStyle Hidden
    exit 0
} else {
    Write-Host "       [OK] WinMCP completely uninstalled and reset from roots!       " -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "System is now 100% clean of any background services, tasks, or configs." -ForegroundColor White
    Write-Host "You can reinstall anytime by running:" -ForegroundColor Cyan
    Write-Host "  * Double-click: install.bat" -ForegroundColor Yellow
    Write-Host "  * CLI:          powershell .\install.ps1" -ForegroundColor Yellow
    Write-Host "======================================================================`n" -ForegroundColor Green
}
