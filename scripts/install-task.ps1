$workspaceDir = "C:\entire-poc\entire-poc-workspace"
$entireExe    = (Get-Command entire).Source
$logDir       = "$env:USERPROFILE\.entire-poc"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$action = New-ScheduledTaskAction `
    -Execute $entireExe `
    -Argument "doctor --force" `
    -WorkingDirectory $workspaceDir

$trigger = New-ScheduledTaskTrigger `
    -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Hours 4)

Register-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -TaskName "EntirePoCDoctor" `
    -Description "Condense orphaned Entire sessions every 4h" `
    -Force
