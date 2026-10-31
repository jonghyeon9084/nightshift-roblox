param([Parameter(Mandatory=$true)][string]$LuauBin)
$ErrorActionPreference = 'Stop'
$clientRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $clientRoot)
$mainPath = Join-Path $clientRoot 'Main.client.luau'
$modulePath = Join-Path $clientRoot 'Modules/StateStore.luau'
$specPath = Join-Path $PSScriptRoot 'StateStore.spec.luau'
$trayModulePath = Join-Path $clientRoot 'Modules/TrayView.luau'
$traySpecPath = Join-Path $PSScriptRoot 'TrayView.spec.luau'
$configPath = Join-Path $projectRoot 'src/shared/Config.luau'
$mainText = [IO.File]::ReadAllText($mainPath)
$configText = [IO.File]::ReadAllText($configPath)
$actionBlock = ($configText -split 'Actions = \{', 2)[1] -split '\},', 2
$allowed = @([regex]::Matches($actionBlock[0], '"([A-Za-z]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$used = @([regex]::Matches($mainText, 'send\("([A-Za-z]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (Compare-Object $allowed $used) { throw 'Client and Config actions differ' }
if ([regex]::Matches($mainText, ':FireServer\(').Count -ne 1) { throw 'Uncentralized action send' }
if ([regex]::Matches($mainText, ':InvokeServer\(').Count -ne 1) { throw 'Uncentralized snapshot invoke' }
if ($mainText -match 'MarketplaceService|HttpService|LoadAsset|TODO') { throw 'Unexpected API or unfinished implementation' }
if ($mainText.Replace(':WaitForChild("PlayerGui", 10)', '') -match 'WaitForChild\(') { throw 'Unexpected WaitForChild' }
if ($mainText -notmatch 'Config.World.TrayOffsets\[index\]' -or $mainText -notmatch 'trayGui.Adornee = anchor') { throw 'Missing configured tray positioning' }
if ($mainText -notmatch 'local function clearMarkers\(\)\s+clearTrays\(\)') { throw 'Marker cleanup must clear trays' }
if ($mainText -notmatch 'if packet.Store ~= nil then refreshLabels\(\) end\s+syncTrays\(\)') { throw 'State updates must refresh trays' }
foreach ($sourcePath in @($mainPath, $modulePath, $specPath, $trayModulePath, $traySpecPath)) {
    $sourceText = [IO.File]::ReadAllText($sourcePath, [Text.UTF8Encoding]::new($false, $true))
    if ($sourceText -match '(?m)[ \t]+\r?$') { throw "Trailing whitespace: $sourcePath" }
}
Push-Location $clientRoot
try {
& (Join-Path $LuauBin 'luau-compile.exe') --null Main.client.luau Modules/StateStore.luau Modules/TrayView.luau Modules/LoadReporter.luau tests/StateStore.spec.luau tests/TrayView.spec.luau tests/LoadReporter.spec.luau
if ($LASTEXITCODE -ne 0) { throw 'Luau compile failed' }
& (Join-Path $LuauBin 'luau-analyze.exe') Modules/StateStore.luau Modules/TrayView.luau Modules/LoadReporter.luau
if ($LASTEXITCODE -ne 0) { throw 'Pure client module analysis failed' }
# Inline the actual module source for CLI portability: this avoids require's
# path resolution differences on Windows workspaces containing Korean names.
foreach ($moduleName in @('StateStore', 'TrayView', 'LoadReporter')) {
$moduleText = [IO.File]::ReadAllText((Join-Path $clientRoot ('Modules/' + $moduleName + '.luau')))
$specText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot ($moduleName + '.spec.luau')))
$requireText = 'local ' + $moduleName + ' = require("../Modules/' + $moduleName + '")'
$combinedText = $specText.Replace($requireText, 'local ' + $moduleName + " = (function()`n" + $moduleText + "`nend)()")
$combinedPath = Join-Path $PSScriptRoot ('.combined-' + $PID + '.luau')
try {
    [IO.File]::WriteAllText($combinedPath, $combinedText, [Text.UTF8Encoding]::new($false))
    & (Join-Path $LuauBin 'luau.exe') ('tests/.combined-' + $PID + '.luau')
    if ($LASTEXITCODE -ne 0) { throw 'Pure reducer checks failed' }
} finally {
    if (Test-Path -LiteralPath $combinedPath) { Remove-Item -LiteralPath $combinedPath }
}
}
Write-Output ('PASS: ' + $allowed.Count + ' contract actions; centralized remotes; UTF-8; whitespace; bounded WaitForChild; API restrictions')
Write-Output 'PASS: configured tray offsets; state refresh and marker cleanup wiring (static source checks only)'
Write-Output 'Roblox engine, Studio, network, touch and performance checks were NOT executed.'
} finally {
    Pop-Location
}
