# Script to register WinMCP in Windows Task Scheduler for auto-start on logon
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskName = "WindowsMCPServer"
$runnerScript = "$scriptDir\run_winmcp.ps1"

Write-Output "Registering Task Scheduler task: $taskName..."

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runnerScript`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Auto-starts Windows MCP Server & Gateway on logon" -Force | Out-Null
    Write-Output "SUCCESS: Task '$taskName' registered successfully!"
    Write-Output "The Windows MCP server will automatically start on logon."
} catch {
    Write-Error "Failed to register task: $($_.Exception.Message)"
}
