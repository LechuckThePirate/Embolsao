<#
.SYNOPSIS
    Run once: registers ForeverSVWatcher.ps1 to start automatically, every
    time you log into Windows -- so the Forever SavedVariables backup never
    depends on remembering to launch anything.

.NOTES
    Run this yourself from a normal PowerShell prompt (not through Claude
    Code -- that sandbox can't reach the Task Scheduler service here,
    "Access is denied"). Deliberately NOT a hidden window and NOT a VBS
    launcher: that combination (hidden PowerShell spawned via a script at
    every logon) is exactly the pattern Defender flags as a persistence
    mechanism, and it did here. A plain Scheduled Task running a minimized
    -- not hidden -- PowerShell window is the standard, non-suspicious way
    to do this; "At log on" tasks for the current user don't need elevation.
#>

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "ForeverSVWatcher.ps1"
$taskName   = "Embolsao Forever SavedVariables Watcher"

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Minimized -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

Write-Host "Installed scheduled task '$taskName' (starts at every logon)."
Write-Host "Starting it now for this session too..."
Start-ScheduledTask -TaskName $taskName

Write-Host ""
Write-Host "To check it's running:  Get-ScheduledTask -TaskName '$taskName' | Get-ScheduledTaskInfo"
Write-Host "To remove it later:     Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"
