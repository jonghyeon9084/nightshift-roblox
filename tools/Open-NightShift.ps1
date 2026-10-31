$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$maestroExe = Join-Path $env:LOCALAPPDATA 'Programs\Maestro\Maestro.exe'
$nodeExe = & (Join-Path $PSScriptRoot 'Get-NightShiftNode.ps1')
if (-not (Get-Process Maestro -ErrorAction SilentlyContinue)) { Start-Process -FilePath $maestroExe }
$mapUrl = 'http://127.0.0.1:43821'
$mapReady = $false
try { $null = Invoke-RestMethod "$mapUrl/api/state" -TimeoutSec 2; $mapReady = $true } catch { }
if (-not $mapReady) {
    $serverPath = Join-Path $PSScriptRoot 'mission-control\server.cjs'
    $logDir = Join-Path $projectRoot '.setup'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    Start-Process -FilePath $nodeExe -ArgumentList ('"' + $serverPath + '"') -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir 'map-server.log') -RedirectStandardError (Join-Path $logDir 'map-server-error.log')
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        Start-Sleep -Milliseconds 500
        try { $null = Invoke-RestMethod "$mapUrl/api/state" -TimeoutSec 2; $mapReady = $true; break } catch { }
    }
}
if (-not $mapReady) { throw '지도 서버를 열지 못했습니다. .setup/map-server-error.log를 확인하세요.' }
if (Test-Path -LiteralPath (Join-Path $projectRoot '.setup/mobile-access.json')) {
    & (Join-Path $PSScriptRoot 'Start-NightShiftMobile.ps1')
}
& (Join-Path $PSScriptRoot 'Start-NightShiftRunner.ps1')
& (Join-Path $PSScriptRoot 'Invoke-Maestro.ps1') open-browser $mapUrl --agent 4ec6f362-5bd9-4362-9b97-9cbcbfb92b6e --focus --json
