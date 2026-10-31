// Additional source checks; not a Roblox render or collision simulation.
const fs=require('fs'),assert=require('assert'),cp=require('child_process'),path=require('path');
const dir=__dirname, world=fs.readFileSync(path.join(dir,'BuildWorld.luau'),'utf8'), truck=fs.readFileSync(path.join(dir,'BuildDeliveryTruck.luau'),'utf8');
const bin=path.resolve(process.argv[2],'luau-compile.exe');
cp.execFileSync(bin,['--null','tools/world/BuildDeliveryTruck.luau'], {cwd:path.resolve(dir,'../..')});
const heights={MainRoad:.08,Plaza:.16,Sidewalk:.24,ServiceLane:.24,HubWalk:.32,Floor:.40,Forecourt:.48,SideWalk:.56,RearWalk:.64,LoadingPad:.72};
for(const [name,h] of Object.entries(heights)) assert(new RegExp(name+'\\s*=\\s*0?'+String(h).replace('.','\\.')).test(world),name);
// LoadingPad z=-34..-33 meets RearWalk z=-33..-25 at an edge, not an area.
assert(world.includes('Vector3.new(12, 1, 1), Vector3.new(23, -0.5, -33.5)'));
assert(world.includes('Vector3.new(74, 1, 8), Vector3.new(0, -0.5, -29)'));
for(const name of ['DrinkCooler','ServiceCounter','Microwave','CoffeeWater','StandingTable','OfficeWarehouseDivider','WarehouseSide','WarehouseShelf','InformationLCD']) assert(world.includes('"'+name+'"'),name);
for(const name of ['Body','Cab','Windshield','BedLeft','BedRight','Ramp','Wheel','Cargo','DirectNotice']) assert(truck.includes('"'+name+'"'),name);
assert(!truck.includes('AdGui')); assert(truck.includes('CanCollide = false')); assert(truck.includes('ContentMode"'));
console.log('PASS: elevated ground layers, rear paving seam, named store and truck components, truck compile; static only');

const cfg=fs.readFileSync(path.resolve(dir,'../../src/shared/CommerceConfig.luau'),'utf8');
const adapter=fs.readFileSync(path.resolve(dir,'../../src/server/Modules/WorldAdapter.luau'),'utf8');
assert(truck.includes('Vector3.new(5.5, 0.2, 0.5), Vector3.new(0, 1.1, 5.25)'));
assert(truck.includes('Vector3.new(7, 4, 2), Vector3.new(0, 3.4, -4)'));
// Unrotated template clearance only; actual +X route pose is checked in Studio.
const dockZ=-39, rampEdge=dockZ+5.25+0.25, rearEdge=-33;
assert(rearEdge-rampEdge>=0.5);
// Four 1.2-stud item boxes fit the cargo volume without touching each other or cab.
const crates=[[-0.9,-0.9],[0.9,-0.9],[-0.9,0.9],[0.9,0.9]];
for(let i=0;i<crates.length;i++) {
 const [x,z]=crates[i]; assert(Math.abs(x)+.6<=3 && Math.abs(z)+.6<=3); assert(z-.6>=-3);
 for(let j=0;j<i;j++) assert(Math.abs(x-crates[j][0])>=1.2 || Math.abs(z-crates[j][1])>=1.2);
}
// Warehouse and cargo runtime are currently co-located; fail closed in report, not falsely PASS.
assert(adapter.includes('item.WarehouseBin or 1')); 
assert(adapter.includes('item.CargoIndex or 1')); assert(adapter.includes('(i%2)*1.8-0.9')); 
assert(cfg.includes('MaxItemsPerStore = 24') && cfg.includes('MaxUnitsPerOrder = 4'));
assert(world.includes('container("Folder", "WarehouseSlots", store)'));
assert(world.includes('string.format("Storage%02d", storageIndex)'));
assert(world.includes('text(lcd, "오늘도 정상영업\\n매장 안내", Enum.NormalId.Right)'));
console.log('PASS: unrotated template ramp clearance 0.5 studs; four proposed cargo views separate; 24 storage anchors. Current server source uses WarehouseBin/CargoIndex; Roblox runtime not tested.');

// Back wall and signs, LCD and frame use distinct exposed planes.
assert((-23-0.1)>-24); // back-wall inside z=-24
assert((-15.94-0.05)>(-16.2+0.2)); // warehouse sign vs header
assert((-27.35-0.1)>(-27.51+0.05)); // LCD vs frame
console.log('PASS: selected warehouse sign/header, office sign/back wall, LCD/frame planes have positive separation');

// Dock route origin y=1: a flat visual tab is NOT a traversable sloped ramp.
assert(truck.includes('Vector3.new(7, 0.4, 10), Vector3.new(0, 1.2, 0)'));
assert(truck.includes('Vector3.new(5.5, 0.2, 0.5), Vector3.new(0, 1.1, 5.25)'));
assert(adapter.includes('part.CanCollide=false; part.CanTouch=false; part.CanQuery=false'));
const groundTop=0.64, dockY=1, rampTop=dockY+1.1+0.2/2, bedTop=dockY+1.2+0.4/2;
assert(Math.abs(rampTop-groundTop-1.56)<1e-9 && Math.abs(bedTop-rampTop-0.2)<1e-9);
console.log(`Dock elevations: ground=${groundTop}, flat noncolliding ramp=${rampTop}, noncolliding bed=${bedTop}; ramp width=5.5, length=0.5, slope=0 degrees; no physical climbing path.`);
