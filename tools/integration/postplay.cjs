'use strict';
const fs=require('node:fs');const path=require('node:path');
const {transport,root}=require('./studio.cjs');const {contentText}=require('../studio-mcp.cjs');
const record=(label,data)=>{const r={at:new Date().toISOString(),label,data};fs.appendFileSync(path.join(root,'.setup/integration/postplay.jsonl'),JSON.stringify(r)+'\n');console.log(JSON.stringify(r));};
(async()=>{await transport().withStudio(async({call,rpc})=>{
 await rpc('tools/list',{});
 const lua=async code=>{const t=contentText(await call('execute_luau',{datamodel_type:'Client',code}));try{return JSON.parse(t);}catch{return t;}};
 const key=async k=>call('user_keyboard_input',{datamodel_type:'Client',actions:[{action:'keyPress',key_code:k},{action:'wait',wait_time_ms:900}]});
 for(const [keyName,id] of [['Two','Store02'],['Three','Store03'],['Four','Store04']]){
  await key('X');await key('M');await key(keyName);await lua('task.wait(1) return true');
  record('join '+id,await lua(`local v=shared.NightShiftVerification.State; assert(v.Self.StoreId=='${id}' and v.Self.Loaded,'Join/load failed'); return game:GetService('HttpService'):JSONEncode({Store=v.Self.StoreId,Loaded=v.Self.Loaded,Phase=v.Store.Phase,Position=tostring(game:GetService('Players').LocalPlayer.Character:GetPivot().Position)})`));
 }
 record('synthetic rebind',await lua(fs.readFileSync(path.join(__dirname,'rebind-check.luau'),'utf8')));
 await key('X');await key('H');
 await lua('local c=game:GetService("Players").LocalPlayer.Character; c.Humanoid:MoveTo(Vector3.new(0,3,-6)); task.wait(1) return true');
 await key('E');
 record('Hub prompt after rejoin',await lua('local h=workspace.NightShiftWorld.Hub.StoreSelect; local count=0; for _,c in ipairs(h:GetChildren()) do if c.Name=="NightShiftStorePrompt" then count+=1 end end; assert(count==1); return game:GetService("HttpService"):JSONEncode({PromptCount=count,StoreId=shared.NightShiftVerification.State.Self.StoreId})'));
 record('final play console',contentText(await call('get_console_output')));
});})().catch(e=>{record('FAILED',e.stack);process.exitCode=1;});
