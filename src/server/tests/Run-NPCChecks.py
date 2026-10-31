"""Compile real sources, execute economic and NPC state machines with explicit fake engine adapters."""
import datetime, hashlib, json, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "src/server/.validation"
CLI = ROOT / "tools/world/.validation/luau-0.745"
OUT.mkdir(exist_ok=True)
modules = [
    ("Config", "src/shared/Config.luau"), ("CC", "src/shared/CommerceConfig.luau"),
    ("Contract", "src/shared/SoloStoreContract.luau"), ("SoloProfile", "src/shared/SoloStoreProfile.luau"),
    ("U", "src/server/Modules/ServerUtil.luau"), ("Profiles", "src/server/Modules/ProfileService.luau"),
    ("Ownership", "src/server/Modules/OwnershipService.luau"), ("Demand", "src/server/Modules/DemandGoalService.luau"),
    ("Contest", "src/server/Modules/ContestService.luau"), ("Commerce", "src/server/Modules/CommerceService.luau"),
    ("Game", "src/server/Modules/SoloGameService.luau"), ("Protocol", "src/server/Modules/Protocol.luau"),
    ("NPC", "src/server/Modules/NPCShoppingService.luau"),
]
replacements = {
    'require(Shared.SoloStoreContract)': 'Contract', 'require(Shared.SoloStoreProfile)': 'SoloProfile',
    'require(script.Parent.ServerUtil)': 'U', 'require(script.Parent.DemandGoalService)': 'Demand',
    'require(script.Parent.ContestService)': 'Contest',
    'require(game:GetService("ReplicatedStorage").NightShift.Shared.SoloStoreContract)': 'Contract',
}
specs = ["src/server/tests/SoloServer.spec.luau", "src/server/tests/NPCShopping.spec.luau"]
sources = [p for _, p in modules] + specs + ["src/server/Main.server.luau", "src/server/Modules/RuntimeBridge.luau", "src/server/Modules/NPCWorldAdapter.luau", "tools/world/BuildCustomerRig.luau", "src/server/tests/Run-NPCChecks.py"]
compiled = subprocess.run([str(CLI / "luau-compile.exe"), "--null", *[p for p in sources if p.endswith('.luau')]], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
pieces = ['local game={GetService=function() return {NightShift={Shared={}}} end}']
for name, path in modules:
    body = (ROOT / path).read_text(encoding="utf-8")
    for before, after in replacements.items():
        body = body.replace(before, after)
    pieces.append(f"local {name}=(function()\n{body}\nend)()")
pieces.extend((ROOT / path).read_text(encoding="utf-8") for path in specs)
bundle = OUT / "npc-shopping-tests.luau"
bundle.write_text("\n".join(pieces), encoding="utf-8")
result = subprocess.run([str(CLI / "luau.exe"), str(bundle.relative_to(ROOT))], cwd=ROOT, capture_output=True, text=True, encoding="utf-8") if compiled.returncode == 0 else None
output = "COMPILE\n" + compiled.stdout + compiled.stderr + "\nOFFLINE_FAKE_ENGINE_TESTS\n" + (result.stdout + result.stderr if result else "NOT RUN")
(OUT / "npc-shopping-checks.txt").write_text(output, encoding="utf-8")
report = {"at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "kind": "OFFLINE_FAKE_ENGINE_TESTS", "studioRun": False, "cloudRun": False, "compileExit": compiled.returncode, "testExit": result.returncode if result else None, "releaseReady": False, "warehouseAcceptanceComplete": False,
          "sources": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources}}
(OUT / "npc-shopping-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(output)
sys.exit(compiled.returncode or (result.returncode if result else 1))
