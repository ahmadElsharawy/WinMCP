# Script to unregister WinMCP from Windows Task Scheduler
$taskName = "WindowsMCPServer"
Write-Output "Unregistering Task: $taskName..."
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Output "Task unregistered."
