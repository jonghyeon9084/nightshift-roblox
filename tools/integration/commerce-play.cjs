'use strict';
const fs=require('node:fs'),path=require('node:path');
const {transport,root}=require('./studio.cjs');
const {contentText}=require('../studio-mcp.cjs');
const dir=path.join(root,'.setup/commerce-integration');fs.mkdirSync(dir,{recursive:true});
const record=(label,data)=>{let row={at:new Date().toISOString(),label,data};fs.appendFileSync(path.join(dir,'play.jsonl'),JSON.stringify(row)+'\n');console.log(JSON.stringify(data&&data.Commerce?{at:row.at,label,phase:data.Store&&data.Store.Phase,preparing:data.Store&&data.Store.Round&&data.Store.Round.Preparing,success:data.Store&&data.Store.Round&&data.Store.Round.SuccessCount,wallet:data.Commerce.Self.Wallet,xp:data.Commerce.Self.XP,cash:data.Commerce.Store&&data.Commerce.Store.OperatingCash,carry:data.Commerce.Self.Carry.length,items:data.Commerce.Store&&data.Commerce.Store.Items.map(i=>({state:i.State,slot:i.SlotId})),ack:data.CommerceAcks.at(-1),legacyAck:data.Acks.at(-1)}:row));};
async function run(){await transport().withStudio(async({call,studio})=>{
 const lua=async(code,dm='Client')=>{const r=contentText(await call('execute_luau',{datamodel_type:dm,code}));try{return JSON.parse(r)}catch{return r}};
 const key=async k=>{await call('user_keyboard_input',{datamodel_type:'Client',actions:[{action:'keyPress',key_code:k},{action:'wait',wait_time_ms:450}]});record('key',k)};
 const view=async()=>lua('local v=shared.CommerceVerification; local r=game.ReplicatedStorage.NightShift.Remotes; task.wait(2.1); local cs=r.GetCommerceSnapshot:InvokeServer({ProtocolVersion=1}); if cs.Ok then require(game.Players.LocalPlayer.PlayerScripts.NightShift.Modules.CommerceState).apply(v.Commerce,cs.Snapshot,os.clock()) end; return game:GetService("HttpService"):JSONEncode({Self=v.Legacy.Self,Store=v.Legacy.Store,Commerce=v.Commerce,Acks=v.Acks,CommerceAcks=v.CommerceAcks,Position=tostring(game.Players.LocalPlayer.Character:GetPivot().Position)})');
 const walk=async(x,z)=>{const r=await lua(`local c=game.Players.LocalPlayer.Character; local s=shared.CommerceVerification.Legacy.Self.StoreId; local m=workspace.NightShiftWorld.Stores[s]; local goal=m:GetPivot():PointToWorldSpace(Vector3.new(${x},4,${z})); c:FindFirstChildOfClass('Humanoid'):MoveTo(goal); local deadline=os.clock()+8; repeat task.wait(0.1) until (c:GetPivot().Position-goal).Magnitude<2 or os.clock()>deadline; local distance=(c:GetPivot().Position-goal).Magnitude; return game.HttpService:JSONEncode({Distance=distance,Position=tostring(c:GetPivot().Position)})`);record('physical walk',{x,z,...r});if(r.Distance>3)throw Error('Waypoint not reached')};
 const mode=process.argv[2];
 if(mode==='init'){record('observer',await lua(fs.readFileSync(path.join(__dirname,'commerce-observer.luau'),'utf8')));await key('M');await key('One');await lua('task.wait(2.2) return true');record('joined',await view());await key('P');await lua('task.wait(1) return true');record('practice',await view());}
 else if(mode==='key'){for(const k of process.argv.slice(3))await key(k);record('state',await view())}
 else if(mode==='walk'){for(let i=3;i<process.argv.length;i+=2)await walk(Number(process.argv[i]),Number(process.argv[i+1]));record('state',await view())}
 else if(mode==='stock'){await walk(-8,0);await walk(-8,-18);await walk(-16,-18);await key('V');await key('One');let qty=await lua("for _,x in ipairs(game.Players.LocalPlayer.PlayerGui.NightShiftHUD:GetDescendants()) do if x:IsA('TextButton') then local n=string.match(x.Text,'주문 수량 (%d)');if n then return tonumber(n) end end end");for(let n=qty;n!==4;n=n%4+1)await key('F');await key('E');record('ordered',await view());}
 else if(mode==='deliver'){
 await key('Two');await walk(-8,-18);await walk(0,-18);await walk(16,-14);await walk(26,-14);await walk(26,-30);await walk(23,-34);
 for(let i=0;i<Number(process.argv[3]||1);i++){
  await key('E');let v=await view();record('cargo pickup',v);if(v.Commerce.Self.Carry.length!==1)throw Error('Cargo pickup failed');
  await walk(26,-30);await walk(26,-14);await walk(26,0);await walk(8,0);await walk(-8,0);await walk(-19,-3);
  await key('E');v=await view();record('direct shelf placement',v);if(v.Commerce.Self.Carry.length!==0)throw Error('Shelf placement failed');
  if(i+1<Number(process.argv[3]||1)){await walk(-8,0);await walk(-8,-18);await walk(0,-18);await walk(16,-14);await walk(26,-14);await walk(26,-30);await walk(23,-34)}
 }
 }
 else if(mode==='sell'){
 await key('V');await walk(-19,-3);await key('E');record('customer claim',await view());
 await walk(-8,0);await walk(-12,4);await key('E');await key('E');record('sale',await view());
 }
 else if(mode==='loop'){
 const frontToPC=async()=>{await walk(-8,0);await walk(-8,-18);await walk(-16,-15)};
 const toCargo=async()=>{await walk(-8,-18);await walk(16,-14);await walk(26,-14);await walk(26,-30);await walk(23,-34)};
 const fromCargo=async()=>{await walk(26,-30);await walk(26,-14);await walk(26,0);await walk(-8,0);await walk(-19,-3)};
 const stock=async qty=>{await frontToPC();await key('V');await key('One');let n=await lua("for _,x in ipairs(game.Players.LocalPlayer.PlayerGui.NightShiftHUD:GetDescendants()) do if x:IsA('TextButton') then local n=string.match(x.Text,'주문 수량 (%d)');if n then return tonumber(n) end end end");if(!Number.isInteger(n))throw Error('quantity UI unavailable');while(n!==qty){await key('F');n=n%4+1}await key('E');record('ordered',await view());await key('Two');await toCargo();await lua('task.wait(12) return true')};
 const deliver=async qty=>{for(let i=0;i<qty;i++){if(i){await walk(-8,0);await toCargo()}await key('E');let v=await view();record('cargo pickup',v);if(v.Commerce.Self.Carry.length!==1)throw Error('cargo pickup failed');await fromCargo();await key('E');v=await view();record('shelf placement',v);if(v.Commerce.Self.Carry.length)throw Error('placement failed')}};
 if(!process.argv.includes('--resume')&&!process.argv.includes('--second')){await stock(4);await deliver(4)}if(!process.argv.includes('--second'))await key('V');await stock(1);await key('T');await deliver(1);await key('V');
 for(let i=0;i<(process.argv.includes('--second')?1:5);i++){
  let v=await view();if(v.Store.Round.OutageStatus==='Active'){
   await walk(-8,0);await walk(26,0);await walk(26,-14);await key('E');v=await view();record('outage role',v);
   if(!v.Self.Role)throw Error('breaker role missing');for(const shape of v.Store.Round.Outage.SharedShapes)await key({Circle:'One',Triangle:'Two',Square:'Three'}[shape]);
   await walk(26,0);await walk(-8,0);record('outage resolved',await view());
  }
  await lua('task.wait(3.3) return true');await walk(-19,-3);await key('E');v=await view();if(!v.Self.Carry)throw Error('customer claim failed');
  await walk(-8,0);await walk(-12,4);await key('E');await key('E');record('sale '+(i+1),await view());await lua('task.wait(3.3) return true');
 }
 const final=await view();record('complete local shift',final);if(process.argv.includes('--second')){await key('V');await key('Three');record('free unlock',await view());return;}if(final.Store.Phase!=='Result')throw Error('expected Result');await key('E');record('free repeat lobby',await view());
 }
 else if(mode==='code'){record(process.argv[3],await lua(fs.readFileSync(path.resolve(root,process.argv[4]),'utf8'),process.argv[5]||'Client'))}
 else if(mode==='capture'){const r=await call('screen_capture',{capture_id:'Commerce-'+Date.now()});for(const c of r.content||[])if(c.type==='image'){const file=path.join(dir,Date.now()+'.png');fs.writeFileSync(file,Buffer.from(c.data,'base64'));record('capture',file)}}
 else record('state',await view());
 });}
run().catch(e=>{record('FAILED',e.stack);process.exitCode=1});
