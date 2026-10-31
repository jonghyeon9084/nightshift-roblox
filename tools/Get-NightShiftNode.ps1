$command = Get-Command node -CommandType Application -ErrorAction SilentlyContinue
if ($command) { return $command.Source }
$bundledNode = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
if (Test-Path -LiteralPath $bundledNode -PathType Leaf) { return $bundledNode }
throw '설치된 Node 런타임을 찾을 수 없습니다. Codex 런타임 경로를 확인하세요.'
