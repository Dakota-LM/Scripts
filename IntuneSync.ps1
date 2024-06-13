#Requires -Version 5.1 -RunAsAdministrator
[CmdletBing()]
param()

$StartTime = Get-Date
Write-Host "$(($StartTime).ToString('s')) Beginning Intune Sync process."
$ProcessJob = Start-Job -ScriptBlock {
    param()
    [Windows.Management.MdmSessionManager,Windows.Management,ContentType=WindowsRuntime]
    $session = [Windows.Management.MdmSessionManager]::TryCreateSession()
    $session.StartAsync()  # $Session.State contains NotStarted, Communicating, and Completed
    while ($session.State -ne "Completed") {
        $session.State
        Start-Sleep 2
    }
}

$Process = $ProcessJob | Receive-Job
$Process
Write-Host "$((Get-Date).ToString('s')) Streaming Intune Sync Events:"

$LatestOutput = $null
$PreviousOutput = $null
$Count = 0
do {
    $LogJob = Start-Job -ScriptBlock {
        param()
        $Events = Get-WinEvent -LogName "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin" -MaxEvents 1 | Select-Object -property TimeCreated,LevelDisplayname,Id,Message
        $StringOutput = "$(([Datetime]$Events.TimeCreated).ToString('s')) Level=$($Events.LevelDisplayName) Id=$($Events.Id) Message=`"$($Events.Message)`""
        $StringOutput
    }
    $LatestOutput = $LogJob | Receive-Job
    if ($LatestOutput -match "[\s\.]+Id=209[\s\.]+") {
        Write-Host -Foreground Yellow "Previous event 209 found. Waiting 30 seconds."
        Start-Sleep -Seconds 30
        $LatestOutput = $LogJob | Receive-Job
    }else {
        Start-Sleep -Seconds 10
        $LatestOutput = $LogJob | Receive-Job
    }
    
    if ($PreviousOutput -eq $LatestOutput) {
        $LatestOutput + " (x$Count)" | Out-String | Write-Host
        $Count += 1
    }
    if ($LatestOutput -ne $PreviousOutput) {
        $LatestOutput | Out-String | Write-Host
    }
    Remove-Job $LogJob
    $PreviousOutput = $LatestOutput
    
} while ( (Get-Job -Id $ProcessJob.Id).State -eq 'Running' )
$Test = $false
Write-Host "Waiting for closing event (this could be a few minutes):`n"
while ($Test -eq $false){
    # Write-Host "Testing Loop "  #Debug
    if ($LatestOutput -notmatch "[\s\.]+Id=209[\s\.]+") {
        $LatestOutput = $LogJob | Receive-Job
        $Test = $false
    } else {
        Write-Host "Closing event (Id = 209) found. Closed at $(Get-Date -Format `"hh:mm tt`")."
        Remove-Job $LogJob -ErrorAction SilentlyContinue
        $Test = $true
    }
}

Write-Progress "Stopping Event Stream"
$Process = $null
Write-Progress "Receiving Process Job"
$finalState = (Get-Job -Id $ProcessJob.Id).State
if ($finalState -eq 'Completed') {
    $Process = Receive-Job -Job $ProcessJob
} elseif ($finalState -eq 'Failed') {
    Write-Warning "Job failed."
} else {
    Write-Warning "Job did not complete successfully. State: $finalState"
}
Write-Progress "Cleaning Up"
try {
    Stop-Job $LogJob -ErrorAction SilentlyContinue
    Remove-Job $LogJob -ErrorAction SilentlyContinue
} catch{
    Write-Verbose "Log job has already been removed, or there was an error while removing it."
}
Remove-Job $ProcessJob -ErrorAction SilentlyContinue

Write-Host "Final check for existing jobs:"
$TestJobs = Get-Job
if ($TestJobs -eq $null){
    Write-Host "No jobs found. The environment is clean."
} else {
    Write-Host "A job still exists, the task will continue to exit but you may want to check manually and close the process."
}
$EndTime = Get-Date

$Duration = $EndTime - $StartTIme
if ($Duration.TotalMinutes -ge 1) {
    Write-Host "Event stream ran for $([int]$Duration.TotalMinutes) minute(s) $($Duration.Seconds) second(s)"
} else {
    Write-Host "Event stream ran for $($Duration.TotalSeconds) second(s)"
}
Write-Warning "Please wait a few minutes before running this task again. The Intune servers may refuse attempts that are too close together."
return