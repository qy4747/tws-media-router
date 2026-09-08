param(
    [int]$Seconds = 0
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$BuildFile = Join-Path $ProjectDir "build\detector\netease-play-state.js"

if (-not (Test-Path $BuildFile)) {
    throw "Build output not found. Run 'npm run build' first."
}

$router = Get-CimInstance Win32_Process |
    Where-Object {
        $_.Name -eq "AutoHotkey64.exe" -and
        $_.CommandLine -match "tws-media-router\.ahk"
    } |
    Sort-Object CreationDate -Descending |
    Select-Object -First 1

if (-not $router) {
    throw "Running tws-media-router.ahk was not found. Start the router first."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$captureDir = Join-Path $PSScriptRoot "captures\$stamp"
New-Item -ItemType Directory -Force -Path $captureDir | Out-Null

$flag = Join-Path $env:TEMP "tws-media-router-trace.flag"
$routerTrace = Join-Path $env:TEMP ("tws-media-router-trace-{0}.log" -f $router.ProcessId)
$elogTrace = Join-Path $captureDir "elog.log"
$routerOut = Join-Path $captureDir "router.log"
$merged = Join-Path $captureDir "merged.log"
$metadata = Join-Path $captureDir "metadata.txt"

Remove-Item $routerTrace -Force -ErrorAction SilentlyContinue
New-Item -ItemType File -Force -Path $flag | Out-Null

$monitorScript = Join-Path $PSScriptRoot "smtc-elog-monitor.mjs"
$node = Start-Process -FilePath "node" `
    -ArgumentList @($monitorScript, $elogTrace) `
    -WorkingDirectory $ProjectDir `
    -WindowStyle Hidden `
    -PassThru

try {
    $branch = (& git -C $ProjectDir branch --show-current 2>$null)
    $head = (& git -C $ProjectDir rev-parse HEAD 2>$null)
    @(
        "captured_at=$(Get-Date -Format o)"
        "router_pid=$($router.ProcessId)"
        "branch=$branch"
        "head=$head"
    ) | Set-Content -Path $metadata -Encoding utf8

    Write-Host ""
    Write-Host "SMTC latency capture is running."
    Write-Host "Operate the earbuds normally, especially the slow second Next and any rapid/mixed inputs."

    if ($Seconds -gt 0) {
        Write-Host "Capturing for $Seconds second(s)..."
        Start-Sleep -Seconds $Seconds
    } else {
        Read-Host "Press Enter when the reproduction is complete"
    }
}
finally {
    Remove-Item $flag -Force -ErrorAction SilentlyContinue

    if ($node -and -not $node.HasExited) {
        Stop-Process -Id $node.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 100
    }
}

if (Test-Path $routerTrace) {
    Copy-Item $routerTrace $routerOut -Force
} else {
    New-Item -ItemType File -Force -Path $routerOut | Out-Null
}

$all = @()
if (Test-Path $elogTrace) { $all += Get-Content $elogTrace }
if (Test-Path $routerOut) { $all += Get-Content $routerOut }

$all |
    Where-Object { $_ -match '^\d+\|' } |
    Sort-Object { [int64](($_ -split '\|', 2)[0]) } |
    Set-Content -Path $merged -Encoding utf8

Write-Host ""
Write-Host "Capture complete:"
Write-Host $captureDir
Write-Host ""
Write-Host "Give Codex these two files first:"
Write-Host "  $merged"
Write-Host "  $metadata"
