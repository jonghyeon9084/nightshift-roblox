$nodeExe = & (Join-Path $PSScriptRoot 'Get-NightShiftNode.ps1')
& $nodeExe @args
exit $LASTEXITCODE
