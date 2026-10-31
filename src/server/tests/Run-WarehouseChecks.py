"""Offline checks only. Outputs stay inside src/server/.validation."""
from pathlib import Path
import subprocess
import hashlib

root = Path(__file__).resolve().parents[3]
out = root / 'src/server/.validation'
out.mkdir(exist_ok=True)
bin_dir = root / 'tools/world/.validation/luau-0.745'
files = list((root / 'src/server').glob('**/*.luau'))
files = [p for p in files if '.validation' not in p.parts]
subprocess.run([str(bin_dir/'luau-compile.exe'), '--null', *[str(p.relative_to(root)) for p in files]], check=True, cwd=root)
chunks = ['local Random={new=function() return {NextInteger=function(_,a,b) return a end} end}']
modules = [('L','src/shared/Config.luau'), ('C','src/shared/CommerceConfig.luau')]
modules += [(name, 'src/server/Modules/'+file+'.luau') for name,file in [
    ('Timer','Timer'), ('Protocol','Protocol'), ('Profiles','ProfileService'), ('Progression','ProgressionService'),
    ('Delivery','DeliveryService'), ('Commerce','CommerceService'), ('Ranking','RankingService'), ('GameService','GameService'), ('Content','OperatorContent')]]
for name,file in modules:
    body=(root/file).read_text(encoding='utf-8-sig').replace('local Timer = require(script.Parent.Timer)','-- injected actual Timer')
    chunks.append('local '+name+'=(function()\n'+body+'\nend)()')
for spec,args in [('ProfileService','Profiles,C'),('ProgressionService','Progression,C'),('CommerceService','Commerce,C'),
                  ('ServerCommerce','GameService,Protocol,L,C,Profiles,Progression,Delivery,Commerce,Ranking'),
                  ('CommerceCritical','Profiles,Progression,Delivery,Commerce,C,GameService'),('WarehouseServer','Commerce,Delivery,C'),('StudioUserIds','Profiles,Commerce,Ranking,C')]:
    chunks.append('do local test=(function()\n'+(root/('src/server/tests/'+spec+'.spec.luau')).read_text(encoding='utf-8-sig')+'\nend)(); test('+args+') end')
delivery=(root/'src/server/tests/DeliveryService.spec.luau').read_text(encoding='utf-8-sig').replace('require("../Modules/DeliveryService")','Delivery').replace('require("../../shared/CommerceConfig")','C')
chunks.append('do\n'+delivery+'\nend')
world=(root/'src/server/Modules/WorldAdapter.luau').read_text(encoding='utf-8-sig')
movement=(root/'src/server/tests/MovementBudget.spec.luau').read_text(encoding='utf-8-sig')
chunks.append('do\nlocal players={list={}}; function players:GetPlayers() return self.list end\nlocal game={GetService=function() return players end}\nlocal WorldAdapter=(function()\n'+world+'\nend)()\nlocal test=(function()\n'+movement+'\nend)(); test(WorldAdapter,C,players) end')
mock=(root/'src/server/tests/WarehouseWorld.spec.luau').read_text(encoding='utf-8-sig')
truck=(root/'tools/world/BuildDeliveryTruck.luau').read_text(encoding='utf-8-sig')
chunks.append(mock.replace('-- WORLD_MODULE_HERE',world).replace('-- CONTENT_MODULE_HERE',(root/'src/server/Modules/OperatorContent.luau').read_text(encoding='utf-8-sig')).replace('-- TRUCK_MODULE_HERE',truck))
output=out/'warehouse-checks.luau'
output.write_text('\n'.join(chunks),encoding='utf-8')
r=subprocess.run([str(bin_dir/'luau.exe'),str(output.relative_to(root))],cwd=root,text=True,capture_output=True,encoding='utf-8')
evidence='BuildDeliveryTruck source SHA256: '+hashlib.sha256(truck.encode('utf-8')).hexdigest()+'\n'
(out/'warehouse-checks.txt').write_text(evidence+r.stdout+r.stderr,encoding='utf-8')
print(r.stdout+r.stderr)
raise SystemExit(r.returncode)
