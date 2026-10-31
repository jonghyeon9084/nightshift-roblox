'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process');
const project=path.resolve(__dirname,'../..'), dir=__dirname, bin=path.resolve(process.argv[2]);
const source=f=>fs.readFileSync(path.join(project,f),'utf8').replace(/^\uFEFF/,'');
const reference=source('tools/world/verify-billboards.cjs');
let mock=reference.split('const mock = String.raw`')[1].split('local beforeRequire=created')[0];
mock=mock.replace('local mockFailAd = false','local mockFailAd = false\nlocal mockFailSurface = false');
mock=mock.replace('if class=="AdGui" and mockFailAd then','if class=="SurfaceGui" and mockFailSurface then error("MOCK_SURFACE_FAILURE") end\n if class=="AdGui" and mockFailAd then');
mock=mock.replace('vectorMeta.__sub =', 'vectorMeta.__add = function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end\nvectorMeta.__sub =');
mock=mock.replace('frameMeta.__mul =', 'frameMeta.__add = function(a,b) return frame(a.Position+b,a.Yaw) end\nframeMeta.__mul =');
mock=mock.replace('local Color3 =', 'local Vector2 = {new=function(x,y) return {x,y} end}\nlocal UDim2 = {fromScale=function(x,y) return {x,y} end}\nlocal Color3 =');
mock=mock.replace('local function typeof(v)', 'Enum.NormalId.Right="Right"; Enum.NormalId.Left="Left"; Enum.Material.Neon="Neon"; Enum.Material.Glass="Glass"; Enum.SurfaceGuiSizingMode={FixedSize="FixedSize"}; Enum.Font={GothamMedium="GothamMedium"}\nlocal function typeof(v)');
mock=mock.replace('return self.ClassName==class or (self.ClassName=="Part" and class=="BasePart")', 'return self.ClassName==class or ((self.ClassName=="Part" or self.ClassName=="SpawnLocation") and class=="BasePart") or (self.ClassName=="PointLight" and class=="Light") or (self.ClassName=="TextLabel" and class=="GuiObject")');
mock += `\nfunction methods:IsDescendantOf(parent) local p=self.Parent while p do if p==parent then return true end p=p.Parent end return false end\n`;
mock += `\nlocal legacy=(function()\n${source('src/shared/Config.luau')}\nend)()\nlocal commerce=(function()\n${source('src/shared/CommerceConfig.luau')}\nend)()\n`;
mock += String.raw`
local replicated=Instance.new("Folder")
local namespace=Instance.new("Folder") namespace.Name="NightShift" namespace.Parent=replicated
local shared=Instance.new("Folder") shared.Name="Shared" shared.Parent=namespace
local config=Instance.new("ModuleScript") config.Name="Config" config.Parent=shared
local cc=Instance.new("ModuleScript") cc.Name="CommerceConfig" cc.Parent=shared
local function require(module) if module==config then return legacy elseif module==cc then return commerce end error("unexpected require") end
local game={GetService=function(_,name) if name=="ReplicatedStorage" then return replicated end error(name) end}
`;
mock += `\nlocal worldBuilder=(function()\n${source('tools/world/BuildWorld.luau')}\nend)()\nlocal adBuilder=(function()\n${source('tools/world/BuildBillboards.luau')}\nend)()\nlocal truckBuilder=(function()\n${source('tools/world/BuildDeliveryTruck.luau')}\nend)()\nlocal vehicleBuilder=(function()\n${source('tools/world/BuildRoadVehicle.luau')}\nend)()\nlocal rigBuilder=(function()\n${source('tools/world/BuildCustomerRig.luau')}\nend)()\nlocal signals=(function()\n${source('tools/world/BuildTrafficSignals.luau')}\nend)()\n`;
mock += `\nlocal content=(function()\n${source('src/server/Modules/OperatorContent.luau')}\nend)()\n`;
mock += String.raw`
local target=Instance.new("Folder")
local root=worldBuilder.build(target)
local stores=root:FindFirstChild("Stores")
local function count(obj) local n=0 for _,o in ipairs(obj:GetDescendants()) do if o:IsA("BasePart") then n+=1 end end return n end
local storeTotal=0
for _,store in ipairs(stores:GetChildren()) do
 local n=count(store) storeTotal+=n
 assert(n==106,store.Name.." count "..n)
 local slots=store:FindFirstChild("WarehouseSlots") assert(#slots:GetChildren()==24)
 for i=1,24 do local slot=slots:FindFirstChild(string.format("Storage%02d",i)); assert(slot and slot:GetAttribute("StoreId")==store.Name and slot:GetAttribute("Capacity")==1) end
 local screen=store:FindFirstChild("Architecture"):FindFirstChild("InformationLCD")
 assert(screen:GetAttribute("SlotId")==store.Name..":IndoorDirect")
 local architecture=store:FindFirstChild("Architecture")
 for _,name in ipairs({"Floor","StoreSign","DrinkCooler","ServiceCounter","Microwave","CoffeeWater","StandingTable","OfficeDesk","WarehouseShelf"}) do assert(architecture:FindFirstChild(name),store.Name.." missing "..name) end
 assert(store:FindFirstChild("Counter") and store:FindFirstChild("OfficePC"))
 local silhouettes=0 for _,p in ipairs(architecture:GetChildren()) do if p.Name=="CoolerSilhouette" then assert(p:GetAttribute("DecorativeOnly") and not p.CanCollide) silhouettes+=1 end end
 assert(silhouettes==3)
 print(store.Name.." parts="..n.." warehouseAnchors="..#slots:GetChildren())
end
local worldCount=count(root); print("world="..worldCount.." common="..(worldCount-storeTotal))
local groundNames={MainRoad=true,Plaza=true,Sidewalk=true,ServiceLane=true,HubWalk=true,Floor=true,Forecourt=true,SideWalk=true,RearWalk=true,LoadingPad=true,WarehousePad=true,LaneDash=true}
local ground={} for _,p in ipairs(root:GetDescendants()) do if p:IsA("BasePart") and groundNames[p.Name] then table.insert(ground,p) end end
local function extent(p) local c,s=math.abs(math.cos(p.CFrame.Yaw)),math.abs(math.sin(p.CFrame.Yaw)); return (c*p.Size.X+s*p.Size.Z)/2,(s*p.Size.X+c*p.Size.Z)/2 end
for i,a in ipairs(ground) do for j=1,i-1 do local b=ground[j]
 local ax,az=extent(a) local bx,bz=extent(b)
 if math.abs(a.Position.X-b.Position.X)<ax+bx-0.001 and math.abs(a.Position.Z-b.Position.Z)<az+bz-0.001 then
  assert(math.abs((a.Position.Y+a.Size.Y/2)-(b.Position.Y+b.Size.Y/2))>0.001,"coplanar ground "..a.Name.."/"..b.Name)
 end
end end
print("generated ground overlapping top faces are separated PASS (fake; baseplate excluded)")
local ads=adBuilder.build(root) assert(ads.Ok,ads.Reason)
print("advertising="..ads.PartCount.." units="..ads.AdUnits.." total="..count(root))
local truck=truckBuilder.create("Store01","test")
print("truck="..count(truck))
assert(worldCount==1003 and ads.PartCount==28 and count(root)==1031 and count(truck)==13)
local paths=root:FindFirstChild("PedestrianPaths") assert(paths and #paths:GetChildren()==8)
for _,path in ipairs(paths:GetChildren()) do
 assert(#path:GetChildren()==10 and path:GetAttribute("CrossingId")=="Cross01")
 for _,node in ipairs(path:GetChildren()) do assert(not node.CanCollide and not node.CanTouch and not node.CanQuery) end
end
-- Sample a 2x2 stud footprint along every consecutive segment at <=0.5 stud.
-- This deliberately checks actual generated positions and yaw-0/180 box bounds.
local names={"SidewalkSpawn","CrossingWait","CrossingEntry","CrossingExit","StoreApproach","Entry","Browse","Checkout","StoreExit","SidewalkExit"}
local solids={} for _,p in ipairs(root:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then table.insert(solids,p) end end
local function insideXZ(p,x,z)
 local c,s=math.abs(math.cos(p.CFrame.Yaw)),math.abs(math.sin(p.CFrame.Yaw))
 return math.abs(x-p.Position.X)<=(c*p.Size.X+s*p.Size.Z)/2+0.0001 and math.abs(z-p.Position.Z)<=(s*p.Size.X+c*p.Size.Z)/2+0.0001
end
for _,path in ipairs(paths:GetChildren()) do
 for i=1,#names-1 do
  local a=path:FindFirstChild(names[i]).Position local b=path:FindFirstChild(names[i+1]).Position
  local steps=math.max(1,math.ceil(math.sqrt((b.X-a.X)^2+(b.Z-a.Z)^2)/0.5))
  for step=0,steps do local t=step/steps local x=a.X+(b.X-a.X)*t local z=a.Z+(b.Z-a.Z)*t
   for _,dx in ipairs({-1,0,1}) do for _,dz in ipairs({-1,0,1}) do
    local px,pz=x+dx,z+dz local supported=false
    for _,p in ipairs(solids) do if insideXZ(p,px,pz) then
     local low,high=p.Position.Y-p.Size.Y/2,p.Position.Y+p.Size.Y/2
     if high>1.1 and low<5.5 then error(path.Name.." blocked "..names[i].." -> "..names[i+1].." by "..p.Name) end
     if high>=-0.1 and high<=1.1 then supported=true end
    end end
    assert(supported,path.Name.." unsupported "..names[i].." -> "..names[i+1])
    assert(math.abs(pz)>=12 or math.abs(px)<=3,path.Name.." road outside crosswalk")
   end end
  end
 end
end
print("eight routes sampled with 2-stud footprint, support and road corridor PASS (fake; no swept engine collision)")
local traffic=root:FindFirstChild("Traffic") assert(traffic and traffic:FindFirstChild("Routes") and traffic:FindFirstChild("Crossings") and traffic:FindFirstChild("Signals"))
local routes=traffic:FindFirstChild("Routes")
for _,r in ipairs({{"Route01",-16,-6},{"Route02",16,6}}) do
 local route=routes:FindFirstChild(r[1]) assert(route and #route:GetChildren()==4)
 local stop=route:FindFirstChild("VehicleStop") assert(stop.Position.X==r[2] and stop.Position.Z==r[3])
 assert(math.abs(stop.Position.X)-11/2>=10 and stop:GetAttribute("Order")==2)
end
local signal=traffic:FindFirstChild("Signals"):FindFirstChild("Cross01")
local vehicleSignal=signal:FindFirstChild("VehicleSignal") local pedestrianSignal=signal:FindFirstChild("PedestrianSignal")
for _,v in ipairs({{"VehicleGreen","Go","Stop"},{"AllRedToWalk","Stop","Stop"},{"Walk","Stop","Go"},{"AllRedToVehicle","Stop","Stop"}}) do
 assert(signals.apply(root,v[1],123)) assert(vehicleSignal:GetAttribute("SignalState")==v[2] and pedestrianSignal:GetAttribute("SignalState")==v[3] and signal:GetAttribute("PhaseEndsAt")==123)
end
assert(not signals.apply(root,"invalid",0) and vehicleSignal:GetAttribute("SignalState")=="Stop" and pedestrianSignal:GetAttribute("SignalState")=="Stop")
for _,entry in ipairs({{vehicleBuilder,"Compact",7,"VehicleKind"},{vehicleBuilder,"Van",7,"VehicleKind"},{rigBuilder,"Normal",6,"CustomerKind"},{rigBuilder,"Rich",7,"CustomerKind"}}) do
 local builder,kind,n,attribute=entry[1],entry[2],entry[3],entry[4]
 local model=builder.create(kind) assert(model:GetAttribute(attribute)==kind and count(model)==n)
 builder.pose(model,CFrame.new(10,2,20)*CFrame.Angles(0,math.pi/2,0))
 for _,p in ipairs(model:GetChildren()) do
  assert(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery and not p.CastShadow)
  local expected=(CFrame.new(10,2,20)*CFrame.Angles(0,math.pi/2,0)*CFrame.new(p:GetAttribute("OffsetX"),p:GetAttribute("OffsetY"),p:GetAttribute("OffsetZ"))).Position
  assert((p.Position-expected).Magnitude<0.0001)
 end
 assert(not pcall(builder.create,"invalid"))
 print("model "..kind.." parts="..n.." pose/physics PASS (fake)")
end
print("signals four phases and invalid fail-closed PASS (fake)")
local notices=0
for _,part in ipairs(truck:GetChildren()) do if part.Name=="DirectNotice" then
 local gui=part:FindFirstChild("OperatorNotice") assert(gui and gui:GetAttribute("NightShiftDirectContentOwned") and #gui:GetChildren()==1 and gui:GetChildren()[1].ClassName=="TextLabel") notices+=1
end end
assert(notices==2)
-- Real OperatorContent implementation with simplified Instances. Exercise each face
-- first without a binder, then valid replacement, rejected input and occupied face.
truck.Parent=root
local surfaces={{stores:FindFirstChild("Store01"):FindFirstChild("Architecture"):FindFirstChild("InformationLCD"),Enum.NormalId.Right,content.resolve("LCD","Store01")}}
for _,p in ipairs(truck:GetChildren()) do if p.Name=="DirectNotice" then
 local left=p:GetAttribute("SlotId")=="Store01:TruckLeft"
 table.insert(surfaces,{p,if left then Enum.NormalId.Left else Enum.NormalId.Right,content.resolve("Truck","Store01","test",if left then "left" else "right")})
end end
local function onFace(p,face) local n=0 for _,gui in ipairs(p:GetChildren()) do if gui:IsA("SurfaceGui") and gui.Face==face then n+=1 end end return n end
for _,surface in ipairs(surfaces) do
 local p,face,notice=surface[1],surface[2],surface[3]
 assert(onFace(p,face)==1 and #p:GetChildren()[1]:GetChildren()==1)
 assert(not content.bind(root,p,face,{Ok=false}).Ok and onFace(p,face)==1)
 assert(content.bind(root,p,face,notice).Ok and onFace(p,face)==1)
 assert(content.bind(root,p,face,notice).Ok and onFace(p,face)==1)
 local stranger=Instance.new("SurfaceGui") stranger.Name="Foreign"; stranger.Face=face; stranger.Parent=p
 local rejected=content.bind(root,p,face,notice) assert(not rejected.Ok and rejected.Code=="FACE_OCCUPIED" and onFace(p,face)==2)
 stranger:Destroy(); assert(onFace(p,face)==1)
 mockFailSurface=true local ok=pcall(content.bind,root,p,face,notice) mockFailSurface=false
 assert(not ok and onFace(p,face)==0,"expected current binder failure reproduction")
 assert(content.bind(root,p,face,notice).Ok and onFace(p,face)==1)
end
truck.Parent=nil
print("LCD and truck: fallback, bind/rebind, rejected input and occupied-face preservation PASS (fake)")
print("PRODUCT FAIL REPRO: binder creation failure removes fallback on each face (fake)")
assert(worldCount-storeTotal<=commerce.Budget.CommonParts and count(root)<=commerce.Budget.TotalParts)
-- List coincident exposed box planes in the truck; transparent Cargo is a marker.
local sharedPlanes={}
local parts=truck:GetChildren()
for i=1,#parts do for j=1,i-1 do
 local a,b=parts[i],parts[j]
 if a:IsA("BasePart") and b:IsA("BasePart") and a.Name~="Cargo" and b.Name~="Cargo" then
  for _,axis in ipairs({"X","Y","Z"}) do
   local other=if axis=="X" then {"Y","Z"} elseif axis=="Y" then {"X","Z"} else {"X","Y"}
   local coplanar=false
   for _,sa in ipairs({-1,1}) do for _,sb in ipairs({-1,1}) do
    if math.abs(a.Position[axis]+sa*a.Size[axis]/2-b.Position[axis]-sb*b.Size[axis]/2)<0.00001 then coplanar=true end
   end end
   local intersects=true
   for _,k in ipairs(other) do if math.abs(a.Position[k]-b.Position[k])>=(a.Size[k]+b.Size[k])/2-0.00001 then intersects=false end end
   if coplanar and intersects then table.insert(sharedPlanes,a.Name.."/"..b.Name.." "..axis) end
  end
 end
end end
table.sort(sharedPlanes) assert(#sharedPlanes==2 and sharedPlanes[1]=="Cab/Body Y" and sharedPlanes[2]=="Ramp/Body Z",table.concat(sharedPlanes,", "))
print("truck intentional contacts: "..table.concat(sharedPlanes,", "))
`;
const out=path.join(dir,'.validation','world-mock.luau');fs.writeFileSync(out,mock);
const r=cp.execFileSync(path.join(bin,'luau.exe'),['world-mock.luau'],{cwd:path.dirname(out),encoding:'utf8',maxBuffer:1e6});console.log(r);
