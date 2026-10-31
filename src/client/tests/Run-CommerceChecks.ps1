param([string]$LuauBin)
$ErrorActionPreference='Stop'
# Active v2 suite. Historical v1 Commerce*.spec files are not v2 contract tests.
$runner=Join-Path $PSScriptRoot 'run-solo-ui.py'
if ($LuauBin) { & python $runner --luau-bin $LuauBin } else { & python $runner }
if ($LASTEXITCODE -ne 0) { throw 'Solo-store v2 UI offline checks failed' }
