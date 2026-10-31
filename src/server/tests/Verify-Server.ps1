param([string]$CompilerDirectory = 'tools/world/.validation/luau-0.745')
$ErrorActionPreference = 'Stop'
$compile = Join-Path $CompilerDirectory 'luau-compile.exe'
$runtime = Join-Path $CompilerDirectory 'luau.exe'
if (!(Test-Path -LiteralPath $compile) -or !(Test-Path -LiteralPath $runtime)) { throw 'Supply an existing official Luau CLI directory with -CompilerDirectory.' }
$sourceFiles = @('src/server/Main.server.luau', 'src/server/Modules/GameService.luau', 'src/server/Modules/Protocol.luau', 'src/server/Modules/Timer.luau', 'src/server/Modules/WorldAdapter.luau', 'src/server/tests/Service.spec.luau')
foreach ($source in $sourceFiles) {
    & $compile --null $source
    if ($LASTEXITCODE -ne 0) { throw "Compile failed: $source" }
    Write-Output "COMPILE OK $source"
}
$pieces = @('local Random = { new = function() return { NextInteger = function(_, low, _) return low end } end }')
foreach ($module in @(@('Config','src/shared/Config.luau'), @('Timer','src/server/Modules/Timer.luau'), @('Protocol','src/server/Modules/Protocol.luau'), @('Service','src/server/Modules/GameService.luau'), @('RunTests','src/server/tests/Service.spec.luau'))) {
    $body = Get-Content -LiteralPath $module[1] -Raw -Encoding UTF8
    if ($module[0] -eq 'Service') { $body = $body.Replace('local Timer = require(script.Parent.Timer)', '-- Timer supplied from actual module above.') }
    $pieces += ('local ' + $module[0] + ' = (function()' + "`n" + $body + "`nend)()")
}
$pieces += 'RunTests(Service, Protocol, Config)'
$output = 'src/server/.validation/combined-state-tests.luau'
New-Item -ItemType Directory -Path 'src/server/.validation' -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path (Get-Location) $output), ($pieces -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
& $runtime $output
if ($LASTEXITCODE -ne 0) { throw 'Pure state simulations failed.' }
