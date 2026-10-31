from pathlib import Path
from datetime import datetime,timezone
import subprocess,json,hashlib,re,argparse
parser=argparse.ArgumentParser(); parser.add_argument("--luau-bin"); args=parser.parse_args()
root=Path(__file__).resolve().parents[3]
out=root/'src/client/.validation'; out.mkdir(exist_ok=True)
bins=Path(args.luau_bin).resolve() if args.luau_bin else root/'tools/world/.validation/luau-0.745'
files=['src/client/Main.client.luau','src/client/Modules/CommerceState.luau','src/client/Modules/CommerceClient.luau','src/client/tests/SoloStoreUI.spec.luau']
# Freeze all inputs before building the executed bundle. Never label later bytes as tested.
source_files=files+['src/shared/CommerceConfig.luau','src/shared/SoloStoreContract.luau',
 'src/server/Modules/ServerUtil.luau','src/server/Modules/SoloGameService.luau',
 'src/server/Modules/DemandGoalService.luau','src/server/Modules/ContestService.luau',
 'src/server/Main.server.luau','src/server/Modules/CommerceService.luau',
 'docs/implementation/solo-store-contract.md','src/client/tests/run-solo-ui.py']
started=datetime.now(timezone.utc).isoformat()
frozen={f:(root/f).read_bytes() for f in source_files}
before={f:hashlib.sha256(v).hexdigest() for f,v in frozen.items()}
def read(f): return frozen[f].decode('utf-8-sig')
chunks=[]
for name,f in [('C','src/shared/CommerceConfig.luau'),('K','src/shared/SoloStoreContract.luau'),('M',files[1]),('Client',files[2]),('U','src/server/Modules/ServerUtil.luau'),('G','src/server/Modules/SoloGameService.luau'),('D','src/server/Modules/DemandGoalService.luau'),('T','src/server/Modules/ContestService.luau'),('test',files[3])]:
 body=read(f)
 if name=='M': body=body.replace('require(game:GetService("ReplicatedStorage").NightShift.Shared.SoloStoreContract)','K')
 if name=='Client': body=body.replace('local Model = require(script.Parent.CommerceState)','local Model = M')
 if name in ['G','D','T']:
  body=body.replace('local U=require(script.Parent.ServerUtil)','local U=U').replace('local Shared=game:GetService("ReplicatedStorage").NightShift.Shared','').replace('local C=require(Shared.SoloStoreContract)','local C=K')
 chunks.append('local '+name+'=(function()\n'+body+'\nend)()')
bundle=out/'solo-ui-bundle.luau'; bundle.write_text('\n'.join(chunks)+'\ntest(M,Client,C,K,G,D,T,U)\n',encoding='utf-8')
compile=subprocess.run([str(bins/'luau-compile.exe'),'--null',*files],cwd=root,capture_output=True,text=True,encoding='utf-8')
run=subprocess.run([str(bins/'luau.exe'),str(bundle.relative_to(root))],cwd=root,capture_output=True,text=True,encoding='utf-8') if compile.returncode==0 else None
text=compile.stdout+compile.stderr+(run.stdout+run.stderr if run else '')
# Source-level wiring guard; does not assert Roblox rendering.
main=read(files[0]); client=read(files[2])
checks={
 'runtime_binding':all(t in main for t in ['commerce:bind(folder)','commerce:tick()','commerce:render(']),
 'owner_v2_only':'SeatGeneration' not in main+client,
 'no_employee_actions':not re.search(r'JoinStore|LeaveStore|RequestSolo|CancelSolo|SecureTheft',main+client),
 'back_and_keyboard':all(t in main for t in ['KeyCode.Backspace','KeyCode.Tab','GetFocusedTextBox','Activated:Connect']),
 'pc_prompt':all(t in main for t in ['ProximityPrompt','MaxActivationDistance=10','RequiresLineOfSight=true']),
 'no_external_purchases':not re.search(r'MarketplaceService|PromptProductPurchase|HttpService|VoiceChatService',main+client),
 'centralized_commerce':client.count(':FireServer(')==1 and client.count(':InvokeServer(')==1,
 'retired_roles_removed':not re.search(r'ClaimRole|ShareSegment|RenewRole|ReleaseRole',main),
 'authoritative_round': 'RoundId=me.RoundId or false' in main+client and 'LegacyStore()' not in client,
 'utf8_valid':all('\ufffd' not in read(f) for f in files),
}
after={f:hashlib.sha256((root/f).read_bytes()).hexdigest() for f in source_files}
changed=[f for f in source_files if before[f]!=after[f]]
finished=datetime.now(timezone.utc).isoformat()
text+='\n'+json.dumps(checks,ensure_ascii=False,indent=2)+'\n'
text+='Source stability: '+('PASS' if not changed else 'FAIL')+'; '+str(len(source_files))+' inputs; changed='+json.dumps(changed)+'\n'
(out/'solo-ui-checks.txt').write_text(text,encoding='utf-8')
report={'generatedAtUtc':finished,'startedAtUtc':started,'finishedAtUtc':finished,
 'kind':'OFFLINE_PURE_LUAU_AND_CONTROLLER_MOCKS_WITH_REAL_SERVER_SERIALIZERS',
 'serverSerializersRun':True,'dependencyMocksRun':True,'studioRun':False,'realServerRun':False,
 'cloudRun':False,'touchDeviceRun':False,'warehouseAcceptanceComplete':False,'releaseReady':False,
 'compileExitCode':compile.returncode,'testExitCode':run.returncode if run else None,'staticChecks':checks,
 'sources':before,'sourceHashesBefore':before,'sourceHashesAfter':after,
 'sourceChangedDuringRun':bool(changed),'changedSources':changed,
 'bundleSha256':hashlib.sha256(bundle.read_bytes()).hexdigest(),
 'sourceUse':{'executedInBundle':['src/client/Modules/CommerceState.luau','src/client/Modules/CommerceClient.luau',
 'src/client/tests/SoloStoreUI.spec.luau','src/shared/CommerceConfig.luau','src/shared/SoloStoreContract.luau',
 'src/server/Modules/ServerUtil.luau','src/server/Modules/SoloGameService.luau',
 'src/server/Modules/DemandGoalService.luau','src/server/Modules/ContestService.luau'],
 'compileAndStaticOnly':['src/client/Main.client.luau'],
 'auditOnly':['src/server/Main.server.luau','src/server/Modules/CommerceService.luau','docs/implementation/solo-store-contract.md']},
 'output':'src/client/.validation/solo-ui-checks.txt'}
(out/'solo-ui-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
audit_path=out/'solo-ui-contract-audit.json'
audit={'kind':'CURRENT_SOURCE_CONTRACT_AUDIT','generatedAtUtc':finished,
 'runReport':'src/client/.validation/solo-ui-report.json','sourceHashesBefore':before,'sourceHashesAfter':after,
 'sourceChangedDuringRun':bool(changed),'changedSources':changed,'actualNetworkRun':False,
 'activeEntry':'Main -> SoloGameService:commercePacket -> CommerceClient:receive -> CommerceState.apply',
 'progressFields':['Self.RareDiscoveries','Self.UnlockedTools','Self.EquippedTool','Self.Presets','Self.RoundId'],
 'customerEvents':'CustomerEvents.Cursor/Entries; owner+store+generation+epoch+round scoped; transient 20s; maximum 32 entries',
 'vipIntegrationEvidence':'src/server/.validation/vip-wire-report.json',
 'historicalAttentionPreserved':'docs/implementation/solo-store-ui.md',
 'remaining':'Studio/real network/devices/saved Place not run'}
audit_path.write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
print(text)
raise SystemExit(compile.returncode or (run.returncode if run else 1) or (0 if all(checks.values()) and not changed else 1))
