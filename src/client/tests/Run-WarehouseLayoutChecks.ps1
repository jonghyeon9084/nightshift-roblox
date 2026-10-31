param([Parameter(Mandatory=$true)][string]$LuauBin)
$ErrorActionPreference='Stop'
$clientRoot=Split-Path -Parent $PSScriptRoot
$main=[IO.File]::ReadAllText((Join-Path $clientRoot 'Main.client.luau'))
$layout=[regex]::Match($main,'local function layoutPanel\(\)[\s\S]*?\r?\nend').Value
if (-not $layout) {throw 'Layout function not found'}
if ([regex]::Matches($main,'obj.AutomaticSize = Enum.AutomaticSize.Y').Count -ne 2) {throw 'Labels and touch buttons must grow with wrapped text'}
if ($main -notmatch 'scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y' -or $main -notmatch 'obj.TextWrapped = true') {throw 'Missing wrapped scroll layout'}
if ($main -notmatch 'officePrompt.KeyboardKeyCode=Enum.KeyCode.Q' -or $main -notmatch 'officePrompt.ClickablePrompt=true' -or $main -notmatch 'commerce.section="shop"') {throw 'PC keyboard/touch entry missing'}
$maxSize=[regex]::Match($main,'size.MaxSize = Vector2.new\([^\r\n]+').Value
$harness=@'
local Vector2={new=function(x,y) return {X=x,Y=y} end}
local UDim2={new=function(xs,xo,ys,yo) return {X={Scale=xs,Offset=xo},Y={Scale=ys,Offset=yo}} end}
UDim2.fromOffset=function(x,y) return UDim2.new(0,x,0,y) end
local workspace={CurrentCamera={ViewportSize={X=320,Y=568}}}
local panel,size,notice,nav,scroll={},{},{},{},{}
local collapsed=false
local panelLayoutKey
'@
$checks=@'
local count=0
for _,viewport in ipairs({{320,568},{568,320},{360,640},{640,360}}) do
 workspace.CurrentCamera.ViewportSize={X=viewport[1],Y=viewport[2]}
 panelLayoutKey=nil
 layoutPanel()
 local width=math.clamp(viewport[1]*panel.Size.X.Scale+panel.Size.X.Offset,size.MinSize.X,size.MaxSize.X)
 local height=math.clamp(viewport[2]*panel.Size.Y.Scale+panel.Size.Y.Offset,size.MinSize.Y,size.MaxSize.Y)
 assert(width+12<=viewport[1] and height+12<=viewport[2],"panel must fit viewport")
 assert(height+scroll.Size.Y.Offset>=48,"at least one touch row remains visible")
 assert(width+scroll.Size.X.Offset-8>=240,"wrapped text has usable width")
 assert(notice.Visible==(viewport[2]>=450),"short landscape frees notice space")
 count+=4
end
collapsed=true
panelLayoutKey=nil
layoutPanel()
assert(not scroll.Visible,"collapsed panel hides content")
print("Warehouse mobile layout: "..(count+1).." assertions passed using actual layoutPanel source; 4 source guards passed (no engine rendering)")
'@
$path=Join-Path $PSScriptRoot ('.warehouse-layout-'+$PID+'.luau')
try {
 [IO.File]::WriteAllText($path,($harness+"`n"+$maxSize+"`n"+$layout+"`n"+$checks),[Text.UTF8Encoding]::new($false))
 Push-Location $clientRoot
 try {
  & (Join-Path $LuauBin 'luau.exe') ('tests/.warehouse-layout-'+$PID+'.luau')
  if ($LASTEXITCODE -ne 0) {throw 'Warehouse mobile layout checks failed'}
 } finally {Pop-Location}
} finally {if (Test-Path -LiteralPath $path) {Remove-Item -LiteralPath $path}}
