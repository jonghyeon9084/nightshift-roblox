const fs=require('node:fs'),path=require('node:path');
const {execFileSync}=require('node:child_process');
const {selectModel,validateSelection,assertInactive}=require('./model-routing.cjs');
const root=path.resolve(__dirname,'..'),cli=path.join(process.env.LOCALAPPDATA,'Programs/Maestro/resources/maestro-cli.js');
function run(args){return JSON.parse(execFileSync(process.execPath,[cli,...args,'--json'],{encoding:'utf8',windowsHide:true,timeout:20000}));}
function setRole(role,tier){
 const policy=JSON.parse(fs.readFileSync(path.join(__dirname,'model-policy.json'),'utf8'));
 const selection=selectModel(policy,role,tier);
 const cache=JSON.parse(fs.readFileSync(path.join(process.env.USERPROFILE,'.codex/models_cache.json'),'utf8'));
 validateSelection(selection,cache);
 const agent=run(['list','agents']).find(a=>a.name==='NightShift-'+role);if(!agent)throw new Error('Worker is not registered');
 const groups=run(['group-chat','list']);if(!groups.success||!Array.isArray(groups.chats))throw Error('Cannot verify worker inactivity');
 assertInactive(agent.name,groups.chats);
 const result=run(['update-agent',agent.id,'--model',selection.model,'--effort',selection.effort,'--custom-args=-c model_reasoning_effort="'+selection.effort+'"']);
 if(!result.success)throw new Error('Maestro rejected model update');
 const record={at:new Date().toISOString(),actor:agent.name,model:selection.model,effort:selection.effort,tier:selection.tier,source:'configured-next-dispatch',reason:selection.reason};
 fs.mkdirSync(path.join(root,'.setup'),{recursive:true});
 fs.appendFileSync(path.join(root,'.setup/model-routing.jsonl'),JSON.stringify(record)+'\n');
 return record;
}
if(require.main===module){try{console.log(JSON.stringify(setRole(process.argv[2],process.argv[3])));}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={setRole};
