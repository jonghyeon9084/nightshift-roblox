$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $projectRoot '.setup'
$nodeExe = & (Join-Path $PSScriptRoot 'Get-NightShiftNode.ps1')
$tunnelExe = Join-Path $runtimeDir 'bin/cloudflared.exe'
if (-not (Test-Path -LiteralPath $tunnelExe)) { throw '공식 cloudflared 실행 파일을 .setup/bin/cloudflared.exe에 설치해야 합니다.' }
$null = Invoke-WebRequest 'http://127.0.0.1:43821/api/state' -TimeoutSec 5
$gatewayScript = Join-Path $PSScriptRoot 'mission-control/mobile-gateway.cjs'
$gatewayReady = $false
try { $null = Invoke-WebRequest 'http://127.0.0.1:43822/' -TimeoutSec 2; $gatewayReady = $true } catch { if ([int]$_.Exception.Response.StatusCode -eq 401) { $gatewayReady = $true } }
if (-not $gatewayReady) {
    Start-Process -FilePath $nodeExe -ArgumentList ('"' + $gatewayScript + '"') -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtimeDir 'mobile-gateway.log') -RedirectStandardError (Join-Path $runtimeDir 'mobile-gateway-error.log') | Out-Null
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 250
        try { $null = Invoke-WebRequest 'http://127.0.0.1:43822/' -TimeoutSec 1; $gatewayReady = $true; break } catch { if ([int]$_.Exception.Response.StatusCode -eq 401) { $gatewayReady = $true; break } }
    }
}
if (-not $gatewayReady) { throw '모바일 게이트웨이가 준비되지 않았습니다.' }
$pidFile = Join-Path $runtimeDir 'mobile-tunnel.pid'
$existing = $null
if (Test-Path -LiteralPath $pidFile) {
    $tunnelProcessId = [int](Get-Content -LiteralPath $pidFile)
    $existing = Get-CimInstance Win32_Process -Filter "ProcessId = $tunnelProcessId" -ErrorAction SilentlyContinue
    if ($existing -and $existing.ExecutablePath -ne $tunnelExe) { $existing = $null }
}
# Resolve the address from the running tunnel's log, not an old saved link.
# A previous startup may have stopped before persisting its newly assigned URL.
$logPath = Join-Path $runtimeDir 'mobile-tunnel.log'
if ($existing) { $process = Get-Process -Id $existing.ProcessId } else {
    $process = Start-Process -FilePath $tunnelExe -ArgumentList @('tunnel','--no-autoupdate','--protocol','http2','--url','http://127.0.0.1:43822') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtimeDir 'mobile-tunnel-out.log') -RedirectStandardError $logPath
    Set-Content -LiteralPath $pidFile -Value $process.Id
}
$remoteOrigin = $null
for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 500
    if (Test-Path -LiteralPath $logPath) {
        $tunnelLogText = Get-Content -LiteralPath $logPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($tunnelLogText)) {
            $match = [regex]::Match($tunnelLogText, 'https://[a-z0-9-]+\.trycloudflare\.com')
            if ($match.Success) { $remoteOrigin = $match.Value; break }
        }
    }
    if ($process.HasExited) { throw 'Cloudflare 연결 프로세스가 종료되었습니다. .setup/mobile-tunnel.log를 확인하세요.' }
}
if (-not $remoteOrigin) { throw '모바일 주소가 아직 발급되지 않았습니다. .setup/mobile-tunnel.log를 확인하세요.' }
$access = Get-Content -LiteralPath (Join-Path $runtimeDir 'mobile-access.json') -Raw | ConvertFrom-Json
$link = if ($access.publicAccess) { "$remoteOrigin/" } else { "$remoteOrigin/access/$($access.token)" }
Set-Content -LiteralPath (Join-Path $runtimeDir 'mobile-link.txt') -Value $link
Write-Output $link
if ($access.publicAccess -and (Test-Path -LiteralPath (Join-Path $runtimeDir 'mobile-pages-enabled'))) {
    & $nodeExe (Join-Path $PSScriptRoot 'publish-mobile-site.cjs')
    if ($LASTEXITCODE -ne 0) { Write-Warning '고정 모바일 주소 갱신에 실패했습니다. 현재 임시 주소는 위에 표시되며 로컬 개발은 계속합니다.' }
}
