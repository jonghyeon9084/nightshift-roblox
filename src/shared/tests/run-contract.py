"""Execute real shared Luau modules; read legacy normalizer without editing it."""
from pathlib import Path
import subprocess
import hashlib
import json
from datetime import datetime, timezone

root = Path(__file__).resolve().parents[3]
out = root / "src/shared/.validation"
out.mkdir(exist_ok=True)
bins = root / "tools/world/.validation/luau-0.745"
sources = ["src/shared/Config.luau", "src/shared/CommerceConfig.luau",
           "src/shared/SoloStoreContract.luau", "src/shared/SoloStoreProfile.luau",
           "src/shared/tests/SoloStoreContract.spec.luau"]
chunks = []
for name, file in zip(["L", "C", "K", "P", "test"], sources):
    body = (root / file).read_text(encoding="utf-8-sig")
    chunks.append(f"local {name}=(function()\n{body}\nend)()")
legacy_file = "src/server/Modules/ProfileService.luau"
legacy = (root / legacy_file).read_text(encoding="utf-8-sig").split("local function defaults(config)")[0]
if "local function normalize(raw, config)" not in legacy:
    raise RuntimeError("Legacy normalizer changed; review runner injection")
chunks.append("local legacyNormalize=(function()\n" + legacy + "\nreturn normalize\nend)()")
chunks.append('''local old=K.copy(C); old.SchemaVersion=1; old.Capacity.SeatsPerStore=4
old.Ranking.ModeTags={"Coop","Solo","Support","Practice"}
test(C,L,K,P,function(raw) return legacyNormalize(raw,old) end)''')
bundle = out / "contract-checks.luau"
bundle.write_text("\n".join(chunks), encoding="utf-8")
compile_result = subprocess.run([str(bins / "luau-compile.exe"), "--null", *sources], cwd=root, capture_output=True, text=True)
run_result = subprocess.run([str(bins / "luau.exe"), str(bundle.relative_to(root))], cwd=root, capture_output=True, text=True) if compile_result.returncode == 0 else None
output = compile_result.stdout + compile_result.stderr
if run_result:
    output += run_result.stdout + run_result.stderr
(out / "contract-checks.txt").write_text(output, encoding="utf-8")
report = {"generatedAtUtc": datetime.now(timezone.utc).isoformat(), "kind": "OFFLINE_PURE_LUAU",
          "studioRun": False, "cloudRun": False, "serviceMocksRun": False,
          "compileExitCode": compile_result.returncode, "testExitCode": run_result.returncode if run_result else None,
          "releaseReady": False, "warehouseAcceptanceComplete": False,
          "sources": {f: hashlib.sha256((root / f).read_bytes()).hexdigest() for f in [*sources, legacy_file]},
          "output": "src/shared/.validation/contract-checks.txt"}
(out / "contract-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(output)
raise SystemExit(compile_result.returncode or (run_result.returncode if run_result else 1))
