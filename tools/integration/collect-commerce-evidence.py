"""Archive observed evidence without rerunning tests or changing Studio."""
from pathlib import Path
import datetime, hashlib, json, shutil
root=Path(__file__).resolve().parents[2]
dest=root/'.setup/commerce-integration/evidence-20261101'
dest.mkdir(parents=True,exist_ok=True)
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
sources=[root/'.setup/integration/events.jsonl',root/'.setup/integration/manifest.json',root/'.setup/commerce-integration/play.jsonl']
sources+=list((root/'.setup/commerce-integration').glob('*.txt'))
sources+=list((root/'.setup/commerce-integration').glob('*.png'))
events=[json.loads(line) for line in sources[0].read_text(encoding='utf-8-sig').splitlines()]
for row in events:
    if row.get('at','')>='2026-10-31T14:00:00':
        sources.extend(Path(c['path']) for c in row.get('content',[]) if c.get('type')=='image')
inventory=[]
for src in dict.fromkeys(sources):
    if not src.is_file(): continue
    target=dest/src.name
    if target.exists() and digest(target)!=digest(src):
        target=dest/(src.stem+'-'+digest(src)[:10]+src.suffix)
    if not target.exists(): shutil.copy2(src,target)
    inventory.append({'source':str(src.relative_to(root)),'file':target.name,'sha256':digest(target),'bytes':target.stat().st_size})
manifest=json.loads((root/'.setup/integration/manifest.json').read_text(encoding='utf-8-sig'))
assert all(digest(root/r['file'])==r['sha256'] for r in manifest), 'Source changed after installation'
play=[json.loads(line) for line in (root/'.setup/commerce-integration/play.jsonl').read_text(encoding='utf-8-sig').splitlines()]
result=next(r for r in play if isinstance(r.get('data'),dict) and r['data'].get('Store',{}).get('Phase')=='Result')
saved=root/'.setup/NightShift-commerce-local.rbxl'
assert saved.is_file() and saved.stat().st_size>0
report={
 'updatedUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'stageReady':False,
 'decision':'Local core and save complete; hold stage marker for failed actual two-client boot and unexplained movement recovery.',
 'studio':{'mode':'Edit','placeId':0,'probeRemnants':0,'parts':577,'lights':40,'stores':8,'adUnits':10,'baseplatePreserved':True,'originalSpawnPreserved':True,'clockTime':14.5,'lastInstallChanged':0},
 'savedPlace':{'path':str(saved),'bytes':saved.stat().st_size,'sha256':digest(saved),'modifiedUtc':datetime.datetime.fromtimestamp(saved.stat().st_mtime,datetime.timezone.utc).isoformat()},
 'worldHash':'cc7acc9f464b4d9fdacd43d5b80278104f0c30b279e4a0d31d62a768f802beb3',
 'installedSourceHashesMatch':True,'sourceCount':len(manifest),
 'actualLocalCore':{'status':'PASS','resultAt':result['at'],'result':result['data']['Self']['LastResult'],'wallet':result['data']['Commerce']['Self']['Wallet'],'xp':result['data']['Commerce']['Self']['XP'],'best':result['data']['Commerce']['Self']['Best'],'lobbyAt':'2026-10-31T14:46:44.305Z','persistenceScope':'same Play Memory session only'},
 'actualMultiplayer':{'status':'FAILED','method':'StudioTestService.ExecuteMultiplayerTestAsync(2)','apiCallOk':True,'joinedPlayers':0,'clientReports':0,'cause':'UNDETERMINED; no security/account changes or repeat launch'},
 'mobile':{'status':'PARTIAL','simulator':'Samsung Galaxy A06','landscapeViewport':[705,338],'portraitViewport':[359,718],'contentHeight':169.6,'navigationHeight':44,'rowHeight':48,'mouseScrollAndStore03Click':'PASS','physicalTouch':'UNVERIFIED'},
 'advertising':{'installation':'PASS','editPreview':'PASS after post-install reattach','playOfficialFallback':'Roblox default logo observed indoors and street','status':'Inactive','video':False,'deliveredAds':'UNVERIFIED','earnings':'UNVERIFIED'},
 'cloud':{'status':'UNVERIFIED','mode':'Memory/Temporary','dataStoreHandleError':'You must publish this place to the web to access DataStore.','cloudReadsOrWritesPerformed':False,'loadFailureDefaults':'forbidden; fake regression passed','durableRewardOutbox':False},
 'voice':{'status':'UNVERIFIED','enableDefaultVoice':True,'useAudioApi':'Enabled','maxPlayersObserved':30,'actualTwoAccountCall':False,'accountOrMicrophoneSettingsChanged':False},
 'fakeTests':{'status':'PASS','profileChecks':476,'progressionChecks':53,'commerceChecks':313,'serverCommerceChecks':179,'deliveryCases':21,'movementChecks':98,'legacyAssertions':5192,'legacyLoops':72,'clientChecks':[21,15,36,2],'boundaryRegressionEvidence':'regressions.txt'},
 'remaining':['Investigate actual two-client zero-join result','Reproduce one unexplained normal-movement recovery','Actual theft/truck/shelf/alarm/race/last-stock/multiplayer departure tests','Actual level unlock and preset restore','Cloud reconnect and durable reward failure behavior after separate authorization','Two eligible accounts voice call','Physical mobile and 16-player load'],
 'evidenceFolder':str(dest),'files':inventory,
}
out=root/'.setup/commerce-verification.json'
if out.exists(): shutil.copy2(out,dest/('previous-verification-'+digest(out)[:10]+'.json'))
out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
(dest/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'files':len(inventory),'place':report['savedPlace'],'stageReady':False},ensure_ascii=False))
