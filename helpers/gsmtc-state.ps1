param(
    [ValidateRange(100, 60000)]
    [int]$PollIntervalMs = 500
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq "AsTask" -and
        $_.IsGenericMethod -and
        $_.GetParameters().Count -eq 1
    } |
    Select-Object -First 1

function Get-Manager {
    $operation = $managerType::RequestAsync()
    $task = $asTask.MakeGenericMethod($managerType).Invoke($null, @($operation))
    $task.Wait()
    return $task.Result
}

$manager = $null
$lastStatus = $null
$lastOutputAt = 0L

while ($true) {
    try {
        if ($null -eq $manager) {
            $manager = Get-Manager
        }

        $session = $manager.GetCurrentSession()
        $status = if ($null -eq $session) {
            "NoSession"
        }
        else {
            $session.GetPlaybackInfo().PlaybackStatus.ToString()
        }
    }
    catch {
        $manager = $null
        $status = "Error"
    }

    $now = [Environment]::TickCount64
    if ($status -ne $lastStatus -or ($now - $lastOutputAt) -ge 1000) {
        Write-Output $status
        $lastStatus = $status
        $lastOutputAt = $now
    }

    Start-Sleep -Milliseconds $PollIntervalMs
}
