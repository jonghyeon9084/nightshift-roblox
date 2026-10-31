// Offline source/geometry inspection only. Does not require or execute the Roblox module.
// Usage: tools/Invoke-Node.ps1 tools/world/verify-world.cjs <official-luau-bin-directory>
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const project = path.resolve(__dirname, '../..');
const bin = path.resolve(process.argv[2]);
const worldFile = path.join(__dirname, 'BuildWorld.luau');
const configFile = path.join(project, 'src/shared/Config.luau');
cp.execFileSync(path.join(bin, 'luau-compile.exe'), ['--null', path.relative(project, worldFile)], {cwd:project,stdio:'pipe'});
function ast(file) { return JSON.parse(cp.execFileSync(path.join(bin, 'luau-ast.exe'), [path.relative(project,file)], {cwd:project,encoding:'utf8', maxBuffer:8e6})).root; }
function value(n, env = {}) {
  if (!n) return undefined;
  switch (n.type) {
    case 'AstExprConstantNumber': case 'AstExprConstantString': case 'AstExprConstantBool': return n.value;
    case 'AstExprLocal': return env[n.local.name];
    case 'AstExprUnary': return n.op === 'Minus' ? -value(n.expr, env) : undefined;
    case 'AstExprBinary': return n.op === 'Add' ? value(n.left,env) + value(n.right,env) : undefined;
    case 'AstExprTable': {
      if (n.items.every(x => x.kind === 'item')) return n.items.map(x => value(x.value,env));
      return Object.fromEntries(n.items.map(x => [value(x.key,env), value(x.value,env)]));
    }
    case 'AstExprCall':
      if (n.func.type === 'AstExprIndexName' && n.func.index === 'new' && n.func.expr.global === 'Vector3') return n.args.map(x=>value(x,env));
  }
}
const configAst = ast(configFile);
const cfg = value(configAst.body.find(n => n.type === 'AstStatLocal' && n.vars[0].name === 'Config').values[0]);
assert.equal(cfg.World.StoreIds.length,4);
const worldAst = ast(worldFile);
const storeFunction = worldAst.body.find(n => n.type === 'AstStatLocalFunction' && n.name.name === 'makeStore');
assert(storeFunction, 'makeStore function missing');
const boxes = [];
function visit(n, env = {}) {
  if (!n || typeof n !== 'object') return;
  if (n.type === 'AstStatForIn') {
    const call = n.values[0];
    const entries = call && call.type === 'AstExprCall' ? value(call.args[0],env) : undefined;
    if (Array.isArray(entries)) {
      entries.forEach((v,i) => visit(n.body, {...env,[n.vars[0].name]:i+1,[n.vars[1].name]:v}));
      return;
    }
  }
  if (n.type === 'AstExprCall' && n.func.type === 'AstExprLocal' && n.func.local.name === 'block') {
    const [name,size,pos] = n.args.map(x=>value(x,env));
    if (Array.isArray(size) && Array.isArray(pos) && [...size,...pos].every(Number.isFinite)) {
      boxes.push({name,size,pos,solid: value(n.args[4],env) !== false});
    }
  }
  for (const [key,v] of Object.entries(n)) {
    if (key === 'local' || key === 'luauType') continue;
    if (Array.isArray(v)) v.forEach(x=>visit(x,env));
    else if (v && typeof v === 'object') visit(v,env);
  }
}
visit(storeFunction.func.body,{index:1});
for (const [name,spec] of Object.entries(cfg.World.Markers)) boxes.push({name,size:spec.Size,pos:spec.Position,solid:name!=='Entry'});
assert.equal(boxes.filter(b=>b.name==='Window').length,2,'Both window bays must be inspected');
assert.equal(boxes.filter(b=>b.name==='StorageBox').length,2,'Both warehouse boxes must be inspected');
const obstacles = boxes.filter(b=>b.solid && b.pos[1]+b.size[1]/2>1.1 && b.pos[1]-b.size[1]/2<6.5);
function blocked(x,z,r=2) {
  return obstacles.some(b=>Math.abs(x-b.pos[0])<b.size[0]/2+r-0.01 && Math.abs(z-b.pos[2])<b.size[2]/2+r-0.01);
}
const key = (x,z)=>`${x},${z}`;
const reachable = new Set([key(0,20)]), queue = [[0,20]];
for(let i=0;i<queue.length;i++) {
  const [x,z]=queue[i];
  for(const [dx,dz] of [[2,0],[-2,0],[0,2],[0,-2]]) {
    const nx=x+dx,nz=z+dz,k=key(nx,nz);
    if(nx< -26 || nx>26 || nz< -22 || nz>28 || reachable.has(k) || blocked(nx,nz)) continue;
    reachable.add(k);queue.push([nx,nz]);
  }
}
const reachableMarkers = [];
for(const name of cfg.World.MarkerOrder) {
  const spec=cfg.World.Markers[name];
  assert(queue.some(([x,z])=>Math.hypot(x-spec.Position[0],z-spec.Position[2])<=6),`No 4-stud-wide approach to ${name}`);
  reachableMarkers.push(name);
}
function overlap(a,b) {return a.pos.every((v,i)=>Math.abs(v-b.pos[i])<(a.size[i]+b.size[i])/2-0.001);}
for(const name of ['Spawn','Entry']) {
  const m=cfg.World.Markers[name];
  const clearance={pos:[m.Position[0],m.Position[1]+cfg.World.SpawnLift,m.Position[2]],size:[4,5.5,4]};
  assert(!boxes.some(b=>b.solid && overlap(clearance,b)),`${name} clearance obstructed`);
}
// Hub/road connection: store local +Z reaches 108; store offset is 140, Hub half-width is 32.
const source=fs.readFileSync(worldFile,'utf8');
assert(source.includes('CFrame.new(0, -0.5, 66)') && source.includes('RoadWidth, 1, 84'));
assert.equal(140-(66+84/2),cfg.World.HubSize[0]/2);
for(const token of ['WaitForChild','task.wait','ClearAllChildren','InsertService','MarketplaceService','GetService("Lighting")']) assert(!source.includes(token),`Forbidden operation ${token}`);
assert(source.includes('marker:SetAttribute("StoreId", storeId)'));
assert(source.includes('light:SetAttribute("OutageControlled", true)'));
assert(source.indexOf('root.Parent = parent')>source.indexOf('checkBudget(root, config)'));
const report={kind:'OFFLINE_STATIC_INSPECTION_NOT_ROBLOX_EXECUTION', compiler:'Luau 0.745 --null', compile:'PASS', inspectedStoreBoxes:boxes.length, reachableMarkers, routeWidthStuds:4, spawnEntryClearance:'PASS', hubRoadSeam:'PASS', forbiddenOperations:'PASS', counts:'Source ledger estimate: 220 BaseParts (33/store, 88 common), 20 Lights (3/store, 8 common), 30 SurfaceGuis + 30 TextLabels; runtime census still required.'};
const out=path.join(__dirname,'.validation','static-report.json');
fs.mkdirSync(path.dirname(out),{recursive:true}); fs.writeFileSync(out,JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
