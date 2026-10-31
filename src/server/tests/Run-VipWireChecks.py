"""Offline integration only. Freeze bytes, run actual Luau modules with mocks, fail on source drift."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, subprocess, sys
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'src/server/.validation'; OUT.mkdir(exist_ok=True)
BIN=ROOT/'tools/world/.validation/luau-0.745'
paths=sorted(set(p.relative_to(ROOT).as_posix() for base in ['src/shared','src/server','src/client','tools/world'] for p in (ROOT/base).rglob('*') if p.suffix in ['.luau','.py'] and '.validation' not in p.parts))
frozen={p:(ROOT/p).read_bytes() for p in paths}
before={p:hashlib.sha256(b).hexdigest() for p,b in frozen.items()}
started=datetime.now(timezone.utc).isoformat()
def read(p): return frozen[p].decode('utf-8-sig').replace('\r\n','\n')
modules=[('Config','src/shared/Config.luau'),('CC','src/shared/CommerceConfig.luau'),('Contract','src/shared/SoloStoreContract.luau'),('SoloProfile','src/shared/SoloStoreProfile.luau')]
modules += [(n,'src/server/Modules/'+f+'.luau') for n,f in [('U','ServerUtil'),('Profiles','ProfileService'),('Ownership','OwnershipService'),('Demand','DemandGoalService'),('Contest','ContestService'),('Commerce','CommerceService'),('Game','SoloGameService'),('Protocol','Protocol'),('NPC','NPCShoppingService')]]
modules += [('Model','src/client/Modules/CommerceState.luau'),('Client','src/client/Modules/CommerceClient.luau')]
replacements={'require(Shared.SoloStoreContract)':'Contract','require(Shared.SoloStoreProfile)':'SoloProfile','require(script.Parent.ServerUtil)':'U','require(script.Parent.DemandGoalService)':'Demand','require(script.Parent.ContestService)':'Contest','require(game:GetService("ReplicatedStorage").NightShift.Shared.SoloStoreContract)':'Contract','require(script.Parent.CommerceState)':'Model'}
def module(n,p):
 body=read(p)
 for a,b in replacements.items(): body=body.replace(a,b)
 return '\nlocal '+n+'=(function()\n'+body+'\nend)()\n'
services='local game={GetService=function() return {NightShift={Shared={}}} end}\n'+''.join(module(n,p) for n,p in modules)
services+='\n'.join(read('src/server/tests/'+p) for p in ['SoloServer.spec.luau','NPCShopping.spec.luau','VipWire.spec.luau'])
world=module('C','src/shared/CommerceConfig.luau')+read('src/server/tests/WarehouseWorld.spec.luau').replace('-- WORLD_MODULE_HERE',read('src/server/Modules/WorldAdapter.luau')).replace('-- CONTENT_MODULE_HERE',read('src/server/Modules/OperatorContent.luau')).replace('-- TRUCK_MODULE_HERE',read('tools/world/BuildDeliveryTruck.luau'))
results={}; logs=[]; bundles={}
def run(name,cmd):
 result=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,encoding='utf-8',timeout=60)
 results[name]=result.returncode; logs.append(name+'\n'+result.stdout+result.stderr); print(logs[-1]); return result.returncode
for name,body in [('wire',services),('warehouse',world)]:
 file=OUT/('vip-'+name+'.luau'); file.write_text(body,encoding='utf-8'); bundles[file.relative_to(ROOT).as_posix()]=hashlib.sha256(file.read_bytes()).hexdigest()
 if run(name+'Compile',[str(BIN/'luau-compile.exe'),'--null',str(file.relative_to(ROOT))])==0: run(name,[str(BIN/'luau.exe'),str(file.relative_to(ROOT))])
for name,path in [('ui','src/client/tests/run-solo-ui.py'),('solo','src/server/tests/Run-SoloChecks.py'),('traffic','src/server/tests/Run-TrafficChecks.py')]: run(name,[sys.executable,path])
after={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}
changed=[p for p in paths if before[p]!=after[p]]
report={'startedAtUtc':started,'finishedAtUtc':datetime.now(timezone.utc).isoformat(),'kind':'OFFLINE_ACTUAL_LUAU_MODULES_FAKE_ENGINE_STORAGE_NETWORK','results':results,'sourceHashesBefore':before,'sourceHashesAfter':after,'changedSources':changed,'sourceChangedDuringRun':bool(changed),'bundleSha256':bundles,'studioRun':False,'cloudRun':False,'warehouseAcceptanceComplete':False,'releaseReady':False}
report['passed']=not changed and len(results)==7 and all(v==0 for v in results.values())
(OUT/'vip-wire-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
(OUT/'vip-wire-checks.txt').write_text('\n'.join(logs)+'\nSource stability changed='+json.dumps(changed),encoding='utf-8')
print('VIP aggregate passed='+str(report['passed'])+' changed='+str(changed))
sys.exit(0 if report['passed'] else 1)
