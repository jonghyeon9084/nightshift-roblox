"""Run actual v2 Luau modules against deterministic, explicitly fake adapters."""
import datetime, hashlib, json, pathlib, re, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "src/server/.validation"
OUT.mkdir(exist_ok=True)
CLI = ROOT / "tools/world/.validation/luau-0.745"
modules = [
    ("Config", "src/shared/Config.luau"), ("CC", "src/shared/CommerceConfig.luau"),
    ("Contract", "src/shared/SoloStoreContract.luau"), ("SoloProfile", "src/shared/SoloStoreProfile.luau"),
    ("U", "src/server/Modules/ServerUtil.luau"), ("Profiles", "src/server/Modules/ProfileService.luau"),
    ("Ownership", "src/server/Modules/OwnershipService.luau"), ("Demand", "src/server/Modules/DemandGoalService.luau"),
    ("Contest", "src/server/Modules/ContestService.luau"), ("Commerce", "src/server/Modules/CommerceService.luau"),
    ("Game", "src/server/Modules/SoloGameService.luau"), ("Protocol", "src/server/Modules/Protocol.luau"),
]
replacements = {
    'require(Shared.SoloStoreContract)': 'Contract', 'require(Shared.SoloStoreProfile)': 'SoloProfile',
    'require(script.Parent.ServerUtil)': 'U', 'require(script.Parent.DemandGoalService)': 'Demand',
    'require(script.Parent.ContestService)': 'Contest',
    'require(game:GetService("ReplicatedStorage").NightShift.Shared.SoloStoreContract)': 'Contract',
}
sources = [p for _, p in modules] + ["src/server/Main.server.luau", "src/server/Modules/RuntimeBridge.luau", "src/server/Modules/WorldAdapter.luau", "src/server/tests/SoloServer.spec.luau", "src/shared/tests/SoloStoreContract.spec.luau"]
compile_result = subprocess.run([str(CLI / "luau-compile.exe"), "--null", *sources], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
pieces = ['local game={GetService=function() return {NightShift={Shared={}}} end}']
for name, path in modules:
    body = (ROOT / path).read_text(encoding="utf-8")
    for before, after in replacements.items():
        body = body.replace(before, after)
    pieces.append(f"local {name}=(function()\n{body}\nend)()")
pieces.append((ROOT / "src/server/tests/SoloServer.spec.luau").read_text(encoding="utf-8"))
pieces.append("local sharedTests=(function()\n" + (ROOT / "src/shared/tests/SoloStoreContract.spec.luau").read_text(encoding="utf-8") + "\nend)()")
pieces.append('local old=U.copy(CC); old.SchemaVersion=1; old.Capacity.SeatsPerStore=4; old.Ranking.ModeTags={"Coop","Solo","Support","Practice"}; sharedTests(CC,Config,Contract,SoloProfile,function(raw) return Profiles.normalizeLegacy(raw,old) end)')
bundle = OUT / "solo-server-tests.luau"
bundle.write_text("\n".join(pieces), encoding="utf-8")
result = subprocess.run([str(CLI / "luau.exe"), str(bundle.relative_to(ROOT))], cwd=ROOT, capture_output=True, text=True, encoding="utf-8") if compile_result.returncode == 0 else None
output = "COMPILE\n" + compile_result.stdout + compile_result.stderr + "\nOFFLINE_FAKE_ADAPTER_MODULE_TESTS\n" + (result.stdout + result.stderr if result else "NOT RUN")
(OUT / "solo-server-checks.txt").write_text(output, encoding="utf-8")
report = {"at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "kind": "OFFLINE_FAKE_ADAPTER_MODULE_TESTS", "studioRun": False, "cloudRun": False, "compileExit": compile_result.returncode, "testExit": result.returncode if result else None, "releaseReady": False,
          "sources": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources}}
(OUT / "solo-server-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(output)
sys.exit(compile_result.returncode or (result.returncode if result else 1))
