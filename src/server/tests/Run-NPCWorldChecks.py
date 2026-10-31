"""Run actual NPC adapter over actual generated geometry using explicitly fake yaw/AABB APIs."""
import datetime, hashlib, json, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "src/server/.validation"
CLI = ROOT / "tools/world/.validation/luau-0.745"
def read(p): return (ROOT / p).read_text(encoding="utf-8-sig")
mock_path = "src/server/tests/NPCWorldMock.luau"
mock = read(mock_path)
mock += '''
vectorMeta.__mul=function(a,b) return vec(a.X*b,a.Y*b,a.Z*b) end
local oldVectorIndex=vectorMeta.__index
vectorMeta.__index=function(v,k) if k=="Unit" then return v*(1/v.Magnitude) end; return oldVectorIndex(v,k) end
local oldFrameIndex=frameMeta.__index
frameMeta.__index=function(v,k)
 if k=="PointToObjectSpace" then return function(a,p)return rotate(p-a.Position,-a.Yaw) end end
 if k=="PointToWorldSpace" then return function(a,p)return a.Position+rotate(p,a.Yaw) end end
 return oldFrameIndex(v,k)
end
CFrame.lookAt=function(p,q)local d=q-p; return frame(p,math.atan2(-d.X,-d.Z)) end
Color3.new=Color3.fromRGB; UDim2.fromOffset=UDim2.fromScale
Enum.RaycastFilterType={Exclude="Exclude"}; local RaycastParams={new=function() return {} end}
function methods:FindFirstChildWhichIsA(class) for _,p in ipairs(self:GetChildren()) do if p:IsA(class) then return p end end end
'''
sources = [mock_path, "src/shared/Config.luau", "src/shared/CommerceConfig.luau", "src/server/Modules/ServerUtil.luau", "tools/world/BuildWorld.luau", "tools/world/BuildCustomerRig.luau", "src/server/Modules/NPCWorldAdapter.luau", "src/server/tests/NPCWorld.spec.luau", "src/server/tests/Run-NPCWorldChecks.py"]
for name,p in [("legacy",sources[1]),("commerce",sources[2]),("U",sources[3])]:
    mock += f"\nlocal {name}=(function()\n{read(p)}\nend)()\n"
# Fake vectors/frames are tables; preserve their value semantics just as Roblox userdata.
mock += '''
local originalCopy=U.copy
U.copy=function(v) if getmetatable(v)==vectorMeta or getmetatable(v)==frameMeta then return v end; return originalCopy(v) end
local replicated=Instance.new("Folder")
local namespace=Instance.new("Folder"); namespace.Name="NightShift"; namespace.Parent=replicated
local shared=Instance.new("Folder"); shared.Name="Shared"; shared.Parent=namespace
local configModule=Instance.new("ModuleScript"); configModule.Name="Config"; configModule.Parent=shared
local commerceModule=Instance.new("ModuleScript"); commerceModule.Name="CommerceConfig"; commerceModule.Parent=shared
local game={GetService=function()return replicated end}
local function require(m) if m==configModule then return legacy elseif m==commerceModule then return commerce end; error("unexpected require") end
local target=Instance.new("Folder")
'''
for name,p in [("worldBuilder",sources[4]),("rigBuilder",sources[5])]: mock += f"\nlocal {name}=(function()\n{read(p)}\nend)()\n"
adapter = read(sources[6]).replace('local U=require(script.Parent.ServerUtil)', '')
mock += read(sources[7]).replace('-- ADAPTER_HERE', 'local NPCWorld=(function()\n'+adapter+'\nend)()')
bundle=OUT / "npc-world-tests.luau"; bundle.write_text(mock,encoding="utf-8")
result=subprocess.run([str(CLI / "luau.exe"),str(bundle.relative_to(ROOT))],cwd=ROOT,capture_output=True,text=True,encoding="utf-8")
output=result.stdout+result.stderr
(OUT / "npc-world-checks.txt").write_text(output,encoding="utf-8")
(OUT / "npc-world-report.json").write_text(json.dumps({"at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"kind":"OFFLINE_FAKE_YAW_AABB_GEOMETRY","testExit":result.returncode,"studioRun":False,"releaseReady":False,"sources":{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources}},indent=2),encoding="utf-8")
print(output); sys.exit(result.returncode)
