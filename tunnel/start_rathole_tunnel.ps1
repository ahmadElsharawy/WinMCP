# Starts Rathole Client for WinMCP Gateway
$baseDir = Split-Path -Parent $PSScriptRoot
$ratholeExe = Join-Path $PSScriptRoot "rathole\rathole.exe"
$config = Join-Path $PSScriptRoot "rathole\client.toml"
$logFile = Join-Path $baseDir "logs\rathole.log"

if (-not (Test-Path $config)) {
    Write-Error "Config file not found: $config"
    exit 1
}

Write-Output "Starting Rathole Client using $config..."
& $ratholeExe --client $config 2>&1 | Tee-Object -FilePath $logFile
