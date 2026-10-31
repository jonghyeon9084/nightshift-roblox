$nodeExe = & (Join-Path $PSScriptRoot 'Get-NightShiftNode.ps1')
& $nodeExe (Join-Path $env:LOCALAPPDATA 'Programs\Maestro\resources\maestro-cli.js') @args
exit $LASTEXITCODE
