from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[2]
out=root/'.setup/commerce-integration'; out.mkdir(parents=True,exist_ok=True)
mods=[('L','src/shared/Config.luau'),('C','src/shared/CommerceConfig.luau')]+[(n,'src/server/Modules/'+f+'.luau') for n,f in [('Timer','Timer'),('Protocol','Protocol'),('Profiles','ProfileService'),('Progression','ProgressionService'),('Delivery','DeliveryService'),('Commerce','CommerceService'),('Ranking','RankingService'),('GameService','GameService')]]
chunks=['local Random={new=function() return {NextInteger=function(_,a,b) return a end} end}']
for name,file in mods:
 body=(root/file).read_text(encoding='utf-8-sig').replace('local Timer = require(script.Parent.Timer)','-- injected actual Timer')
 chunks.append('local '+name+'=(function()\n'+body+'\nend)()')
for spec,args in [('ProfileService','Profiles,C'),('ProgressionService','Progression,C'),('CommerceService','Commerce,C'),('ServerCommerce','GameService,Protocol,L,C,Profiles,Progression,Delivery,Commerce,Ranking'),('CommerceCritical','Profiles,Progression,Delivery,Commerce,C,GameService')]:
 chunks.append('do local test=(function()\n'+(root/('src/server/tests/'+spec+'.spec.luau')).read_text(encoding='utf-8-sig')+'\nend)(); test('+args+') end')
delivery=(root/'src/server/tests/DeliveryService.spec.luau').read_text(encoding='utf-8-sig').replace('require("../Modules/DeliveryService")','Delivery').replace('require("../../shared/CommerceConfig")','C')
chunks.append('do\n'+delivery+'\nend')
world=(root/'src/server/Modules/WorldAdapter.luau').read_text(encoding='utf-8-sig')
movement=(root/'src/server/tests/MovementBudget.spec.luau').read_text(encoding='utf-8-sig')
chunks.append('do\nlocal players={list={}}; function players:GetPlayers() return self.list end\nlocal game={GetService=function() return players end}\nlocal WorldAdapter=(function()\n'+world+'\nend)()\nlocal test=(function()\n'+movement+'\nend)(); test(WorldAdapter,C,players) end')
(out/'regressions.luau').write_text('\n'.join(chunks),encoding='utf-8')
r=subprocess.run([str(root/'tools/world/.validation/luau-0.745/luau.exe'),'regressions.luau'],cwd=out,text=True,capture_output=True)
(out/'regressions.txt').write_text(r.stdout+r.stderr,encoding='utf-8'); print(r.stdout+r.stderr); raise SystemExit(r.returncode)
