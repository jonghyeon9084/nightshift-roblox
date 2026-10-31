$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $projectRoot '.setup\map-server.pid'
if (-not (Test-Path -LiteralPath $pidFile)) { Write-Host '지도 서버 실행 기록이 없습니다.'; return }
$mapProcessId = [int](Get-Content -LiteralPath $pidFile)
$mapProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $mapProcessId" -ErrorAction SilentlyContinue
$expectedScript = Join-Path $PSScriptRoot 'mission-control\server.cjs'
if ($mapProcess -and $mapProcess.Name -eq 'node.exe' -and $mapProcess.CommandLine.Contains($expectedScript)) {
    Stop-Process -Id $mapProcessId
    Write-Host 'NightShift 지도 서버를 종료했습니다. Maestro와 Roblox Studio는 계속 실행됩니다.'
} else { Write-Host '해당 지도 서버가 실행 중이 아니므로 종료할 프로세스가 없습니다.' }
