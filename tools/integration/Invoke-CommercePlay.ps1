param([Parameter(ValueFromRemainingArguments=$true)][string[]]$TaskArguments)
$env:NIGHTSHIFT_STUDIO_MCP=Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Roblox\Versions\version-7062aec9dbe74b14\StudioMCP.exe'
& (Join-Path $PSScriptRoot '../Invoke-Node.ps1') (Join-Path $PSScriptRoot 'commerce-play.cjs') @TaskArguments
exit $LASTEXITCODE
