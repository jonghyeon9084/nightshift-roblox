"""Actual Luau sources, explicit fake engine; no network, Studio, or installation."""
import datetime, hashlib, json, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "src/server/.validation"
CLI = ROOT / "tools/world/.validation/luau-0.745"
OUT.mkdir(exist_ok=True)
def read(p): return (ROOT / p).read_text(encoding="utf-8-sig")
modules = [
    ("Config", "src/shared/Config.luau"), ("CC", "src/shared/CommerceConfig.luau"),
    ("Contract", "src/shared/SoloStoreContract.luau"), ("SoloProfile", "src/shared/SoloStoreProfile.luau"),
    ("U", "src/server/Modules/ServerUtil.luau"), ("Profiles", "src/server/Modules/ProfileService.luau"),
    ("Ownership", "src/server/Modules/OwnershipService.luau"), ("Demand", "src/server/Modules/DemandGoalService.luau"),
    ("Contest", "src/server/Modules/ContestService.luau"), ("Commerce", "src/server/Modules/CommerceService.luau"),
    ("Game", "src/server/Modules/SoloGameService.luau"), ("Protocol", "src/server/Modules/Protocol.luau"),
    ("NPC", "src/server/Modules/NPCShoppingService.luau"),
    ("G", "src/server/Modules/TrafficGeometry.luau"), ("Traffic", "src/server/Modules/TrafficService.luau"),
]
replacements = {
    'require(Shared.SoloStoreContract)': 'Contract', 'require(Shared.SoloStoreProfile)': 'SoloProfile',
    'require(script.Parent.ServerUtil)': 'U', 'require(script.Parent.DemandGoalService)': 'Demand',
    'require(script.Parent.ContestService)': 'Contest', 'require(script.Parent.TrafficGeometry)': 'G',
    'require(game:GetService("ReplicatedStorage").NightShift.Shared.SoloStoreContract)': 'Contract',
}
def module(name, path):
    body = read(path)
    for before, after in replacements.items(): body = body.replace(before, after)
    return f"\nlocal {name}=(function()\n{body}\nend)()\n"
specs = ["src/server/tests/SoloServer.spec.luau", "src/server/tests/NPCShopping.spec.luau", "src/server/tests/Traffic.spec.luau"]
world_files = ["src/server/tests/NPCWorldMock.luau", "tools/world/BuildWorld.luau", "tools/world/BuildRoadVehicle.luau",
               "tools/world/BuildTrafficSignals.luau", "src/server/Modules/TrafficWorldAdapter.luau", "src/server/tests/TrafficWorld.spec.luau"]
sources = list(dict.fromkeys([p for _, p in modules] + specs + world_files + ["src/server/Main.server.luau", "src/server/Modules/RuntimeBridge.luau", "src/server/tests/Run-TrafficChecks.py"]))
compiled = subprocess.run([str(CLI / "luau-compile.exe"), "--null", *[p for p in sources if p.endswith('.luau')]], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
service = 'local game={GetService=function() return {NightShift={Shared={}}} end}\n'
service += ''.join(module(n, p) for n, p in modules)
service += '\n'.join(read(p) for p in specs)
world = read(world_files[0]) + '''
vectorMeta.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
vectorMeta.__eq=function(a,b)return math.abs(a.X-b.X)<1e-6 and math.abs(a.Y-b.Y)<1e-6 and math.abs(a.Z-b.Z)<1e-6 end
frameMeta.__eq=function(a,b)return a.Position==b.Position and math.abs(a.Yaw-b.Yaw)<1e-6 end
Enum.RaycastFilterType={Include="Include"}
local RaycastParams={new=function()return {}end}; local OverlapParams={new=function()return {}end}
'''
world += module("legacy", modules[0][1]) + module("commerce", modules[1][1]) + module("U", modules[4][1]) + module("G", modules[-2][1])
world += '''
local originalCopy=U.copy
U.copy=function(v) if getmetatable(v)==vectorMeta or getmetatable(v)==frameMeta or propsByObject[v] then return v end; return originalCopy(v) end
local replicated=Instance.new("Folder")
local namespace=Instance.new("Folder"); namespace.Name="NightShift"; namespace.Parent=replicated
local shared=Instance.new("Folder"); shared.Name="Shared"; shared.Parent=namespace
local configModule=Instance.new("ModuleScript"); configModule.Name="Config"; configModule.Parent=shared
local commerceModule=Instance.new("ModuleScript"); commerceModule.Name="CommerceConfig"; commerceModule.Parent=shared
local game={GetService=function()return replicated end}
local function require(m) if m==configModule then return legacy elseif m==commerceModule then return commerce end; error("unexpected require") end
local target=Instance.new("Folder")
local workspace={}
'''
world += module("worldBuilder", world_files[1]) + module("vehicleBuilder", world_files[2]) + module("signalsBuilder", world_files[3])
world += module("TrafficWorld", world_files[4]) + module("Traffic", modules[-1][1]) + read(world_files[5])
results = {}
output = "COMPILE\n" + compiled.stdout + compiled.stderr
if compiled.returncode == 0:
    for name, body in [("services", service), ("world", world)]:
        bundle = OUT / f"traffic-{name}-tests.luau"; bundle.write_text(body, encoding="utf-8")
        result = subprocess.run([str(CLI / "luau.exe"), str(bundle.relative_to(ROOT))], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=60)
        results[name] = result.returncode
        output += f"\nOFFLINE_FAKE_ENGINE_{name.upper()}\n" + result.stdout + result.stderr
(OUT / "traffic-checks.txt").write_text(output, encoding="utf-8")
report = {"at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "kind": "OFFLINE_ACTUAL_SERVICES_FAKE_ENGINE", "studioRun": False,
          "releaseReady": False, "warehouseAcceptanceComplete": False, "compileExit": compiled.returncode, "tests": results,
          "sources": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources}}
(OUT / "traffic-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(output)
sys.exit(compiled.returncode or max(results.values(), default=1))
