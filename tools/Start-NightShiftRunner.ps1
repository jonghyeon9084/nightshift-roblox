param([switch]$Resume)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $PSScriptRoot 'runner/resident.cjs'
$nodeExe = & (Join-Path $PSScriptRoot 'Get-NightShiftNode.ps1')
$runtimeDir = Join-Path $projectRoot '.setup/runner'
$manifest = Join-Path $PSScriptRoot 'development-pipeline.json'
if (-not (Test-Path -LiteralPath $manifest)) { throw 'tools/development-pipeline.json이 없습니다.' }
$null = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
function Test-RunnerProcess($processInfo) {
    if (-not $processInfo -or $processInfo.ExecutablePath -ne $nodeExe) { return $false }
    $entryPattern = [regex]::Escape($entry.Replace('/', '\'))
    $commandPattern = '^(?:"[^"]+"|\S+)\s+"?' + $entryPattern + '"?(?:\s+--resume)?\s*$'
    return [regex]::IsMatch([string]$processInfo.CommandLine, $commandPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
$existingHealth = $null
try { $existingHealth = Invoke-RestMethod 'http://127.0.0.1:43823/health' -TimeoutSec 2 } catch {}
if ($existingHealth) {
    $existingProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$existingHealth.pid)" -ErrorAction SilentlyContinue
    if ($existingHealth.service -ne 'nightshift-resident-runner' -or $existingHealth.root -ne $projectRoot -or -not (Test-RunnerProcess $existingProcess)) { throw '43823 포트의 프로세스가 이 프로젝트의 정확한 러너 명령과 일치하지 않습니다.' }
    if ($Resume -and $existingHealth.state.status -eq 'attention') { throw 'attention 러너를 재개하려면 Stop-NightShiftRunner.ps1 후 Start-NightShiftRunner.ps1 -Resume을 실행하세요.' }
    Write-Output "이미 상주 중: PID $($existingHealth.pid), 상태 $($existingHealth.state.status)"
    return
}
$arguments = '"' + $entry + '"'
if ($Resume) { $arguments += ' --resume' }
$process = Start-Process -FilePath $nodeExe -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtimeDir 'stdout.log') -RedirectStandardError (Join-Path $runtimeDir 'stderr.log')
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 250
    $process.Refresh()
    if ($process.HasExited) { throw "상주 러너가 종료되었습니다. .setup/runner/stderr.log를 확인하세요. ExitCode=$($process.ExitCode)" }
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:43823/health' -TimeoutSec 1
        if ($health.service -eq 'nightshift-resident-runner' -and [int]$health.pid -eq $process.Id -and $health.state) {
            Write-Output "상주 러너 시작: PID $($process.Id), 상태 $($health.state.status), 127.0.0.1:43823"
            return
        }
    } catch {}
}
throw '상주 러너 준비 확인이 끝나지 않았습니다. .setup/runner 로그를 확인하세요. 중복으로 다시 시작하지 마세요.'
