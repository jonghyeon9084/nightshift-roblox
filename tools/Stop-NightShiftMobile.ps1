$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
foreach ($name in @('mobile-tunnel','mobile-gateway')) {
    $pidFile = Join-Path $projectRoot ".setup/$name.pid"
    if (-not (Test-Path -LiteralPath $pidFile)) { continue }
    $ownedProcessId = [int](Get-Content -LiteralPath $pidFile)
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ownedProcessId" -ErrorAction SilentlyContinue
    if (-not $process) { continue }
    $expected = if ($name -eq 'mobile-tunnel') { Join-Path $projectRoot '.setup/bin/cloudflared.exe' } else { Join-Path $PSScriptRoot 'mission-control/mobile-gateway.cjs' }
    if ($process.ExecutablePath -eq $expected -or ($process.Name -eq 'node.exe' -and $process.CommandLine.Contains($expected))) { Stop-Process -Id $ownedProcessId }
}
Write-Output '모바일 연결을 종료했습니다. 로컬 지도·Maestro·Studio는 유지됩니다.'
