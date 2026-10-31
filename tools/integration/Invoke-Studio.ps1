param([Parameter(Mandatory=$true)][string]$RequestFile)
$ErrorActionPreference='Stop'
$taskMcpPath=Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Roblox\Versions\version-7062aec9dbe74b14\StudioMCP.exe'
if (Test-Path -LiteralPath $taskMcpPath -PathType Leaf) { $env:NIGHTSHIFT_STUDIO_MCP=$taskMcpPath }
& (Join-Path $PSScriptRoot '../Invoke-Node.ps1') (Join-Path $PSScriptRoot 'studio.cjs') $RequestFile
exit $LASTEXITCODE
