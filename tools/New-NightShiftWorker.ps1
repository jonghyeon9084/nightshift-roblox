param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z][A-Za-z0-9-]{0,35}$')][string]$Role,
    [string]$Responsibility,
    [switch]$ReadOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$maestroCli = Join-Path $env:LOCALAPPDATA 'Programs\Maestro\resources\maestro-cli.js'
$nodeExe = & (Join-Path $PSScriptRoot 'Get-NightShiftNode.ps1')
$agents = @(& $nodeExe $maestroCli list agents --json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Maestro 에이전트 목록을 읽을 수 없습니다.' }
$workerName = "NightShift-$Role"
if ($agents.name -contains $workerName) {
    $existing=$agents | Where-Object name -eq $workerName | Select-Object -First 1
    [pscustomobject]@{success=$true;reused=$true;agentId=$existing.id;name=$existing.name} | ConvertTo-Json
    return
}
$codexPath = (& $nodeExe $maestroCli settings agent get codex customPath --json | ConvertFrom-Json).value
if (-not $codexPath -or -not (Test-Path -LiteralPath $codexPath)) { throw 'Maestro의 Codex 실행 경로를 확인하세요.' }
$ownership = @{Planner='docs/design/draft.md, docs/design/plan.md, docs/design/decisions.md. 기획 초안과 수정안 작성'; DesignReview='읽기 전용 독립 기획 검토. 문제, 근거, 대안, 검증 방법을 보고하고 파일은 변경하지 않음'; Server='src/server/'; UI='src/client/'; World='tools/world/'; Review='읽기 전용 코드 검토'; Test='읽기 전용 검증 설계. Studio 조작은 메인만 수행'}
if (-not $Responsibility) { $Responsibility=$ownership[$Role] }
if (-not $Responsibility) { throw '새 전문 역할은 -Responsibility로 목적, 담당 파일, 완료 조건을 지정하세요.' }
$nudge = "프로젝트 $projectRoot 의 AGENTS.md를 먼저 읽으세요. 역할: $Role. 담당 범위: $Responsibility. 담당 밖 변경은 메인에게 요청하세요. ChatGPT 로그인 Codex만 사용하세요. API 키, 구매, 다른 제공자, 무제한 자동 반복 실행은 금지합니다. 무료 이용 조건이 확인된 에셋 또는 직접 제작만 사용합니다. 추가 전문 워커가 필요하면 목적과 완료 조건을 메인에 전달하세요."
$created = & $nodeExe $maestroCli create-agent $workerName --cwd $projectRoot --type codex --group group-328267a7-c84e-4fc2-bb1d-63fbb94bd916 --custom-path $codexPath --nudge $nudge --background --json | ConvertFrom-Json
if (-not $created.success) { throw '워커 생성에 실패했습니다.' }
if ($ReadOnly -or $Role -in @('Review','Test','DesignReview')) {
    $tabs = (& $nodeExe $maestroCli session list --json | ConvertFrom-Json).sessions | Where-Object agentId -eq $created.agentId
    foreach ($tab in $tabs) { & $nodeExe $maestroCli tab read-only $tab.tabId true --json }
}
$created | ConvertTo-Json
Write-Host '등록만 완료했습니다. AI 요청은 실행하지 않았습니다. 그룹 대화를 만들 때 이 워커를 참가자로 선택하세요.'
