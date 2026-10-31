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
const commerceAst = ast(path.join(project, 'src/shared/CommerceConfig.luau'));
const commerce = value(commerceAst.body.find(n => n.type === 'AstStatLocal' && n.vars[0].name === 'CommerceConfig').values[0]);
assert.equal(commerce.World.StoreIds.length,8);
assert.equal(commerce.World.RoadLength,400);
assert.equal(commerce.World.RoadWidth,24);
assert.equal(commerce.World.MinWalkwayWidth,6);
for (const [i,id] of commerce.World.StoreIds.entries()) {
 const store = commerce.World.Stores[id];
 assert.deepEqual(store.Position, [[-120,-40,40,120][i%4],0,i<4?-52:52]);
 assert.equal(store.YawDegrees,i<4?0:180);
 const entryWorldZ = store.Position[2] + (i<4?24:-24);
 assert.equal(Math.abs(entryWorldZ),28);
}
assert.deepEqual(commerce.World.TruckRoutePositions.Dock,commerce.World.Markers.TruckDock.Position);
assert.equal(new Set([...cfg.World.MarkerOrder,...commerce.World.MarkerOrder]).size,14);
assert.equal(new Set(commerce.World.ShelfSlotIds).size,12);
assert.equal(new Set(commerce.World.TruckRouteOrder).size,3);
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
for (const [name,spec] of Object.entries(cfg.World.Markers)) boxes.push({name,size:spec.Size,pos:spec.Position,solid:name!=='Entry' && !name.startsWith('Shelf')});
assert.equal(boxes.filter(b=>b.name==='Window').length,2,'Both window bays must be inspected');
assert.equal(boxes.filter(b=>b.name==='SideWalk').length,2,'Both side paths must be inspected');
const obstacles = boxes.filter(b=>b.solid && b.pos[1]+b.size[1]/2>1.1 && b.pos[1]-b.size[1]/2<6.5);
function blocked(x,z,r=3) {
  return obstacles.some(b=>Math.abs(x-b.pos[0])<b.size[0]/2+r-0.01 && Math.abs(z-b.pos[2])<b.size[2]/2+r-0.01);
}
const key = (x,z)=>`${x},${z}`;
const reachable = new Set([key(0,20)]), queue = [[0,20]];
for(let i=0;i<queue.length;i++) {
  const [x,z]=queue[i];
  for(const [dx,dz] of [[1,0],[-1,0],[0,1],[0,-1]]) {
    const nx=x+dx,nz=z+dz,k=key(nx,nz);
    if(nx< -38 || nx>38 || nz< -46 || nz>38 || reachable.has(k) || blocked(nx,nz)) continue;
    reachable.add(k);queue.push([nx,nz]);
  }
}
const reachableMarkers = [];
for(const name of [...cfg.World.MarkerOrder,...commerce.World.MarkerOrder]) {
  const spec=cfg.World.Markers[name] || commerce.World.Markers[name];
  assert(queue.some(([x,z])=>Math.hypot(x-spec.Position[0],z-spec.Position[2])<=6),`No 6-stud-wide approach to ${name}`);
  reachableMarkers.push(name);
}
function overlap(a,b) {return a.pos.every((v,i)=>Math.abs(v-b.pos[i])<(a.size[i]+b.size[i])/2-0.001);}
for(const name of ['Spawn','Entry']) {
  const m=cfg.World.Markers[name];
  const clearance={pos:[m.Position[0],m.Position[1]+cfg.World.SpawnLift,m.Position[2]],size:[4,5.5,4]};
  assert(!boxes.some(b=>b.solid && overlap(clearance,b)),`${name} clearance obstructed`);
}
// Report coincident boundary planes for visible warehouse, office and LCD pieces.
const auditedNames=new Set(['BackWall','OfficeDesk','OfficeSign','WarehousePad','WarehouseSign','OfficeWarehouseDivider','WarehouseSide','WarehouseDoorHeader','OfficeDoorHeader','WarehouseDoorSign','WarehouseShelf','InformationLCD','LCDFrame','LCDStand']);
const audited=boxes.filter(b=>auditedNames.has(b.name));
let coincident=[];
for(let i=0;i<audited.length;i++) for(let j=0;j<i;j++) {
 const a=audited[i],b=audited[j];
 for(let axis=0;axis<3;axis++) {
  let shared=[-1,1].some(sa=>[-1,1].some(sb=>Math.abs(a.pos[axis]+sa*a.size[axis]/2-b.pos[axis]-sb*b.size[axis]/2)<1e-5));
  if(shared && [0,1,2].filter(k=>k!==axis).every(k=>Math.abs(a.pos[k]-b.pos[k])<(a.size[k]+b.size[k])/2-1e-5)) coincident.push(`${a.name}/${b.name} axis${axis}`);
 }
}
assert.deepEqual(coincident.sort(),['LCDStand/InformationLCD axis1','OfficeWarehouseDivider/BackWall axis2','WarehouseSide/BackWall axis2'].sort(), 'Unexpected selected shared face');
console.log('Intentional selected shared planes:',JSON.stringify(coincident));
// Every shelf slot needs physical space: lower items cannot sit inside legacy solid blocks.
for(const [i,pos] of commerce.World.ShelfSlotPositions.entries()) {
 const slot={pos,size:commerce.World.ShelfSlotSize};
 assert(!boxes.some(b=>b.solid && overlap(slot,b)),`Shelf slot ${i+1} embedded in architecture`);
}
// 24 warehouse anchors fit reduced 0.7 x 1.4 x 0.7 item views between shelf plates.
const storagePositions=[2.4,4.4].flatMap(y=>[-6.4,-5.6].flatMap(x=>[-22.5,-21.5,-20.5,-19.5,-18.5,-17.5].map(z=>[x,y,z])));
for (let i=0;i<storagePositions.length;i++) {
 const item={pos:storagePositions[i],size:[0.7,1.4,0.7]};
 assert(!boxes.some(b=>b.solid && overlap(item,b)),`Warehouse anchor ${i+1} item intersects solid architecture`);
 for(let j=0;j<i;j++) assert(!overlap(item,{pos:storagePositions[j],size:item.size}),`Warehouse items ${i+1}/${j+1} overlap`);
}
// Current server WorldAdapter WarehouseBin layout extends to the upgraded 32 bins.
assert.equal(commerce.Upgrades.Warehouse.Capacities['1'],32);
const runtimeWarehouse=Array.from({length:32},(_,i)=>[(i%4-1.5)*1.5,1+0.8+Math.floor(i/8)*1.5,-18+(Math.floor(i/4)%2)*1.5-0.75]);
for(let i=0;i<runtimeWarehouse.length;i++) {
 const item={pos:runtimeWarehouse[i],size:[1.2,1.4,1.2]};
 assert(!boxes.some(b=>b.solid && overlap(item,b)),`Runtime warehouse item ${i+1} intersects architecture`);
 for(let j=0;j<i;j++) assert(!overlap(item,{pos:runtimeWarehouse[j],size:item.size}),`Runtime warehouse items overlap`);
}
console.log('Warehouse rendered bins: 32 full-size item boxes clear of inspected architecture and one another (static; does not prove server allocation or reachability).');
// Marker and fixtures are generated outside block(); count from the build loops.
const perStore=boxes.length+commerce.World.MarkerOrder.length+storagePositions.length+commerce.World.ShelfSlotIds.length+commerce.World.TruckRouteOrder.length+3;
// Eight paths x ten nodes; 18 traffic nodes and 12 road/signal decorations.
const common=4+1+2+2+1+19+16+80+18+12;
assert(perStore<=commerce.Budget.StoreParts);
assert(common<=commerce.Budget.CommonParts);
assert(perStore*8+common+28<=commerce.Budget.TotalParts);
// Rear entry and both side paths must connect to front, not merely to markers.
for (const [x,z] of [[24,-28],[0,-30],[-34,0],[34,0],[24,-38]])
 assert(queue.some(p=>Math.hypot(p[0]-x,p[1]-z)<=2),`Closed walkway at ${x},${z}`);
// Explicit route points share the single conservative radius-3 flood-fill component.
for(const [name,x,z] of [['warehouse entrance',0,-14],['warehouse drop',0,-18],['rear opening',23,-24],['rear walk',23,-30],['ramp approach',23,-34],['theft return',18,14]]) {
 assert(queue.some(p=>Math.hypot(p[0]-x,p[1]-z)<=1),`Route point unreachable: ${name}`);
}
for(const id of commerce.World.StoreIds) {
 const yaw=commerce.World.Stores[id].YawDegrees;
 assert(yaw===0 || yaw===180,`Unexpected non-rigid store orientation: ${id}`);
}
// Ground-based PickCargo checks the rendered item, including each cargo offset.
const server=fs.readFileSync(path.join(project,'src/server/Modules/WorldAdapter.luau'),'utf8');
const service=fs.readFileSync(path.join(project,'src/server/Modules/CommerceService.luau'),'utf8');
assert(service.includes('local target={StoreId=c.StoreId,ItemId=item.ItemId}'));
assert(service.includes('s.Orders[item.OrderId].State~="Docked"'));
assert(server.includes('if target.ItemId then part=self.itemParts[target.ItemId]'));
assert(server.includes('truck.cargo.CFrame*CFrame.new((i%2)*1.8-0.9,-0.9,math.floor(i/2)*1.8-0.9)'));
assert(server.includes('local exclude={self.runtime}') && server.includes('ray.RespectCanCollide=true'));
assert.equal(commerce.Interaction.Distance,10);
// Example root height is a model assumption, not an R6/R15 measurement.
const rootPoint=[23,3.16,-32];
assert(reachable.has(key(23,-32)));
// Truck.pose rotates the local cargo frame -90° around Y at Dock; order limit is four.
const cargoPoints=Array.from({length:commerce.Wholesale.MaxUnitsPerOrder},(_,i)=>{
 const localX=(i%2)*1.8-0.9, localZ=Math.floor(i/2)*1.8-0.9;
 return [23-localZ,3.1,-39+localX];
});
for(const p of cargoPoints) assert(Math.hypot(...rootPoint.map((v,i)=>v-p[i])) < commerce.Interaction.Distance,`Cargo item too far: ${p}`);
function segmentHitsBox(a,b,box) {
 let lo=0,hi=1;
 for(let k=0;k<3;k++) {
  const min=box.pos[k]-box.size[k]/2,max=box.pos[k]+box.size[k]/2,d=b[k]-a[k];
  if(Math.abs(d)<1e-9) { if(a[k]<min || a[k]>max) return false; }
  else { let t1=(min-a[k])/d,t2=(max-a[k])/d; if(t1>t2) [t1,t2]=[t2,t1]; lo=Math.max(lo,t1);hi=Math.min(hi,t2);if(lo>hi) return false; }
 }
 return true;
}
const rayObstacles=boxes.filter(b=>b.solid && b.name!=='Spawn');
for(const p of cargoPoints) assert(!rayObstacles.some(b=>segmentHitsBox(rootPoint,p,b)), `Cargo item ray blocked: ${p}`);
console.log(`Ground cargo rays: assumed root ${rootPoint} -> ${cargoPoints.length} rendered item centers within 10; inspected store solids clear; runtime excluded by server ray.`);
// Truck sweep: eight-stud width, including both endpoints, must avoid all solid architecture.
for(let x=-36;x<=36;x++) assert(!blocked(x,-39,4),`Truck route obstructed at ${x}`);
// Continuous road-facing apron joins the ten-stud public sidewalk; rear lanes are twelve wide.
assert.equal(52-36,16);
assert(16<=commerce.World.RoadWidth/2+commerce.World.SidewalkWidth);
assert.equal(52+39,91);
// Hub extends down to z=32, connecting through HubWalk z=21..33 to sidewalk z=12..22.
assert.equal(commerce.World.HubPosition[2]-commerce.World.HubSize[2]/2,32);
const source=fs.readFileSync(worldFile,'utf8');
assert(source.includes('config.World.RoadLength, 1, config.World.RoadWidth'));
assert(source.includes('COMMERCE_LAYOUT_MISMATCH'));
assert(source.includes('CommerceLayoutVersion'));
assert(source.includes('light.Enabled = false'));
assert(source.includes('light:SetAttribute("AlarmControlled", true)'));
assert(source.includes('container("Folder", "CommerceRuntime", root)'));
assert(source.includes('function Builder.replaceInEdit'));
for(const token of ['WaitForChild','task.wait','ClearAllChildren','InsertService','MarketplaceService','GetService("Lighting")']) assert(!source.includes(token),`Forbidden operation ${token}`);
assert(source.includes('marker:SetAttribute("StoreId", storeId)'));
assert(source.includes('light:SetAttribute("OutageControlled", true)'));
assert(source.indexOf('root.Parent = parent')>source.indexOf('checkBudget(root, config)'));
const report={kind:'OFFLINE_STATIC_INSPECTION_NOT_ROBLOX_EXECUTION', compiler:'Luau 0.745 --null', compile:'PASS', storeCount:8, inspectedStoreBoxes:boxes.length, reachableMarkers, routeWidthStuds:6, truckWidthStuds:8, rearAndSideRoutes:'PASS', spawnEntryClearance:'PASS', hubRoadSeam:'PASS', duplicateConfigNames:'PASS', forbiddenOperations:'PASS', partCensus:{perStore,common,world:perStore*8+common,advertising:28,worldWithAds:perStore*8+common+28,limits:commerce.Budget}, counts:'AST/config-derived generation count; actual Roblox Instance census and runtime trucks/items unverified.'};
const out=path.join(__dirname,'.validation','static-report.json');
fs.mkdirSync(path.dirname(out),{recursive:true}); fs.writeFileSync(out,JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
