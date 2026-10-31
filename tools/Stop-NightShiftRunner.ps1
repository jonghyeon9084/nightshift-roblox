$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $PSScriptRoot 'runner/resident.cjs'
$nodeExe = & (Join-Path $PSScriptRoot 'Get-NightShiftNode.ps1')
$health = $null
try { $health = Invoke-RestMethod 'http://127.0.0.1:43823/health' -TimeoutSec 2 } catch {}
if (-not $health) { Write-Output '이 프로젝트의 상주 러너가 응답하지 않습니다. 프로세스를 강제 종료하지 않았습니다.'; return }
$runnerProcessId = [int]$health.pid
$processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $runnerProcessId" -ErrorAction SilentlyContinue
$entryPattern = [regex]::Escape($entry.Replace('/', '\'))
$commandPattern = '^(?:"[^"]+"|\S+)\s+"?' + $entryPattern + '"?(?:\s+--resume)?\s*$'
if ($health.service -ne 'nightshift-resident-runner' -or $health.root -ne $projectRoot -or -not $processInfo -or $processInfo.ExecutablePath -ne $nodeExe -or -not [regex]::IsMatch([string]$processInfo.CommandLine, $commandPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    throw '실행 파일·프로젝트·정확한 명령줄 확인에 실패했습니다. 다른 프로세스는 종료하지 않습니다.'
}
$null = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:43823/stop' -Headers @{ 'X-Runner-Pid' = [string]$runnerProcessId } -TimeoutSec 3
for ($attempt = 0; $attempt -lt 160; $attempt++) {
    if (-not (Get-Process -Id $runnerProcessId -ErrorAction SilentlyContinue)) {
        Write-Output "상주 러너 정상 종료: PID $runnerProcessId. Maestro와 진행 중 작업은 유지됩니다."
        return
    }
    Start-Sleep -Milliseconds 250
}
throw '러너가 이미 발행한 CLI 호출을 정리 중입니다. 강제 종료하지 않았습니다. .setup/runner/state.json을 확인하세요.'
