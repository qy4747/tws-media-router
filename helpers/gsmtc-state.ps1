param(
    [ValidateRange(100, 60000)]
    [int]$PollIntervalMs = 500
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        if ($_.Name -ne "AsTask" -or -not $_.IsGenericMethod -or $_.GetParameters().Count -ne 1) {
            return $false
        }

        $parameterType = $_.GetParameters()[0].ParameterType
        return $parameterType.IsGenericType -and
            $parameterType.GetGenericTypeDefinition().FullName -eq 'Windows.Foundation.IAsyncOperation`1'
    } |
    Select-Object -First 1

if ($null -eq $asTask) {
    throw "Could not resolve AsTask(IAsyncOperation<TResult>)"
}

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
