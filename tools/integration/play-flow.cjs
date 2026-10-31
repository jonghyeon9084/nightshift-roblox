'use strict';
const fs=require('node:fs');
const path=require('node:path');
const {transport,root}=require('./studio.cjs');
const {contentText}=require('../studio-mcp.cjs');
const logFile=path.join(root,'.setup/integration/play-flow.jsonl');
const record=(label,data)=>{const r={at:new Date().toISOString(),label,data};fs.appendFileSync(logFile,JSON.stringify(r)+'\n');console.log(JSON.stringify(r));};
async function run(){await transport().withStudio(async({studio,call,rpc})=>{
 await rpc('tools/list',{});record('target',studio);record('mode',contentText(await call('get_studio_state')));
 const lua=async code=>{const r=contentText(await call('execute_luau',{datamodel_type:'Client',code}));try{return JSON.parse(r);}catch{return r;}};
 const key=async k=>record('keyboard '+k,contentText(await call('user_keyboard_input',{datamodel_type:'Client',actions:[{action:'keyPress',key_code:k},{action:'wait',wait_time_ms:650}]})));
 const view=async()=>lua('local v=shared.NightShiftVerification; return game:GetService("HttpService"):JSONEncode({Self=v.State.Self,Store=v.State.Store,Acks=v.Acks})');
 const walk=async(x,y,z)=>{
  const result=await lua(`local c=game:GetService('Players').LocalPlayer.Character; local goal=Vector3.new(${x},${y},${z}); c:FindFirstChildOfClass('Humanoid'):MoveTo(goal); local finish=os.clock()+7; repeat task.wait(0.1) until (c:GetPivot().Position-goal).Magnitude<2 or os.clock()>finish; local d=(c:GetPivot().Position-goal).Magnitude; return game:GetService('HttpService'):JSONEncode({Distance=d,Position=tostring(c:GetPivot().Position)})`);
  record('physical Humanoid MoveTo',result);if(result.Distance>3)throw Error('Navigation did not reach waypoint');
 };
 const approach=async(name)=>{
  const insideWarehouse=await lua('local p=game:GetService("Players").LocalPlayer.Character:GetPivot().Position; return p.X>10 and p.Z < -146');
  if(insideWarehouse===true){await walk(24,3,-149);await walk(24,3,-143);}
  const p=await lua(`local s=shared.NightShiftVerification.State.Self.StoreId; local m=workspace.NightShiftWorld.Stores[s][${JSON.stringify(name)}]; local p=m.CFrame:PointToWorldSpace(Vector3.new(0,0,${name==='Counter'?-5:5})); return game:GetService('HttpService'):JSONEncode({p.X,3,p.Z})`);
  if(!Array.isArray(p))throw Error('Marker coordinates unavailable '+p);
  await walk(...p);await lua('task.wait(0.5) return true');
 };
 if(!process.argv.includes('--resume')){
 record('observer',await lua(fs.readFileSync(path.join(__dirname,'monitor-client.luau'),'utf8')));
 await key('H');await walk(0,3,-6);await key('E');
 record('hub marker result',await lua('local g=game:GetService("Players").LocalPlayer.PlayerGui.NightShiftHUD; local found=false; for _,x in ipairs(g:GetDescendants()) do if x:IsA("TextButton") and string.find(x.Text,"입장:") then found=true end end; assert(found,"Hub prompt did not open stores"); return "stores opened via E at Hub"'));
 await key('One');await lua('task.wait(1) return true');record('joined',await view());
 // Hold an actual mouse button across timer packets. Observe identity and acknowledgements.
 const held=await lua(`local v=shared.NightShiftVerification; local g=game:GetService('Players').LocalPlayer.PlayerGui.NightShiftHUD; for _,x in ipairs(g:GetDescendants()) do if x:IsA('TextButton') and string.find(x.Text,'팀 준비') then v.Held=x; v.AckStart=#v.Acks; local s=x.Parent; s.CanvasPosition=Vector2.new(0,x.AbsolutePosition.Y-s.AbsolutePosition.Y+s.CanvasPosition.Y-10); return 'LocalPlayer.PlayerGui.NightShiftHUD.Console.Content.'..x.Name end end error('Ready button missing')`);
 record('hold input',contentText(await call('user_mouse_input',{datamodel_type:'Client',actions:[{action:'mouseButtonDown',mouse_button:'left',instance_path:held},{action:'wait',wait_time_ms:1600},{action:'mouseButtonUp',mouse_button:'left'},{action:'wait',wait_time_ms:650}]})));
 record('CR-001 engine check',await lua('local v=shared.NightShiftVerification; assert(v.Held.Parent,"Held button was destroyed"); local n=#v.Acks-v.AckStart; assert(n==1,"Expected one action acknowledgement, got "..n); assert(v.Acks[#v.Acks].Ok,"Held action rejected"); return "same button retained across 1.6s hold; one successful acknowledgement"'));
 await key('P');
 }
 for(let step=0;step<42;step++){
  const v=await view();const s=v.Store;record('progress',{phase:s&&s.Phase,success:s&&s.Round&&s.Round.SuccessCount,outage:s&&s.Round&&s.Round.OutageStatus,lastAck:v.Acks&&v.Acks.at(-1)});
  if(s&&s.Phase==='Result'){record('result',s.Result);await key('E');record('free retry',await view());return;}
  if(!s||s.Phase!=='Running')throw Error('Expected Running: '+JSON.stringify(v));
  if(v.Acks.at(-1)&&!v.Acks.at(-1).Ok)throw Error('Rejected interaction; inspect console before retrying: '+JSON.stringify(v.Acks.at(-1)));
  const r=s.Round;
  if(r.OutageStatus==='Active'){
   await walk(24,3,-147);await approach('Breaker');await key('E');
   let current=await view();
   if(!current.Self.Role||current.Self.Role.RoleId!=='Breaker')throw Error('Could not claim breaker');
   for(const shape of current.Store.Round.Outage.SharedShapes)await key({Circle:'One',Triangle:'Two',Square:'Three'}[shape]);
  }else if(r.Order){
   const line=r.Order.Lines.find(l=>!['Accepted','Cancelled'].includes(l.Status));
   if(!line)throw Error('No outstanding line');
   if(line.Status==='Uncollected'){
    await approach('Shelf'+(r.ShelfProducts.indexOf(line.ProductId)+1));await key('E');
    const carrying=await view();if(!carrying.Self.Carry)throw Error('PickUp failed '+JSON.stringify(carrying.Acks.at(-1)));
   }
   await approach('Counter');
   const atCounter=await view();if(atCounter.Self.Carry)await key('E');
   await key('E');
  }else await lua('task.wait(1) return true');
 }
 throw Error('Flow exceeded bounded step count');
});}
run().catch(e=>{record('FAILED',e.stack);process.exitCode=1;});
