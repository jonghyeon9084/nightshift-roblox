-- Injected by Run-WarehouseChecks.py. Translation-only fake Instances/vectors/rays.
-- Exercises real WorldAdapter, OperatorContent and TruckWorld code, not Studio APIs.
do
 local checks=0
 local function eq(a,b,label) checks+=1; assert(a==b,(label or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
 local vmt={}
 local function vec(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},vmt) end
 vmt.__sub=function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
 vmt.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
 vmt.__index=function(a,k) if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end end
 local Vector3={new=vec}
 local fmt={}
 local function frame(x,y,z) return setmetatable({Position=type(x)=="table" and x or vec(x,y,z)},fmt) end
 fmt.__mul=function(a,b) return frame(a.Position+b.Position) end
 fmt.__index={Lerp=function(a,b,t) return frame(a.Position.X+(b.Position.X-a.Position.X)*t,a.Position.Y+(b.Position.Y-a.Position.Y)*t,a.Position.Z+(b.Position.Z-a.Position.Z)*t) end,
  PointToObjectSpace=function(a,b) return b-a.Position end}
 local CFrame={new=frame,Angles=function() return frame() end} -- Rotation checked separately in Studio.
 local Enum={NormalId={Left="Left",Right="Right",Back="Back"},RaycastFilterType={Exclude="Exclude"}}
 local Color3={new=function(...) return {...} end,fromRGB=function(...) return {...} end}
 local UDim2={fromScale=function(...) return {...} end,fromOffset=function(...) return {...} end}
 local Vector2={new=function(...) return {...} end}
 local RaycastParams={new=function() return {} end}
 local failClass,failParent
 local mt,methods={},{}
 mt.__index=function(o,k)
  if methods[k] then return methods[k] end
  if k=="Position" then return o._p.CFrame.Position end
  if o._p[k]~=nil then return o._p[k] end
  for _,c in ipairs(o._children) do if c.Name==k then return c end end
 end
 mt.__newindex=function(o,k,v)
  if k=="Parent" then
   if v and v==failParent then error("INJECT_PARENT_FAILURE") end
   if o._p.Parent then local i=table.find(o._p.Parent._children,o); if i then table.remove(o._p.Parent._children,i) end end
   if v then table.insert(v._children,o) end
  end
  o._p[k]=v
 end
 local Instance={new=function(class) if class==failClass then error("INJECT_CREATE_FAILURE") end; return setmetatable({_p={ClassName=class,Name=class,CFrame=frame()},_children={},_attributes={}},mt) end}
 function methods:IsA(class) return self.ClassName==class or (class=="BasePart" and self.ClassName=="Part") end
 function methods:GetChildren() return table.clone(self._children) end
 function methods:GetDescendants()
  local a={}; for _,child in ipairs(self._children) do table.insert(a,child); for _,d in ipairs(child:GetDescendants()) do table.insert(a,d) end end; return a
 end
 function methods:FindFirstChild(name,recursive)
  for _,c in ipairs(recursive and self:GetDescendants() or self:GetChildren()) do if c.Name==name then return c end end
 end
 function methods:IsDescendantOf(root) local p=self.Parent; while p do if p==root then return true end; p=p.Parent end; return false end
 function methods:SetAttribute(k,v) self._attributes[k]=v end
 function methods:GetAttribute(k) return self._attributes[k] end
 function methods:Destroy() self.Parent=nil; for _,c in ipairs(self:GetChildren()) do c:Destroy() end end
 function methods:PivotTo(cf)
  local before=self.WorldPivot or frame()
  for _,p in ipairs(self:GetDescendants()) do if p:IsA("BasePart") then p.CFrame=frame(p.Position-before.Position+cf.Position) end end
  self.WorldPivot=cf
 end
 local players={list={},GetPlayers=function(self) return self.list end,GetPlayerByUserId=function(self,id) return self.list[id] end}
 local now,hit=10,nil
 local workspace={GetServerTimeNow=function() return now end,Raycast=function() return hit end}
 local game={GetService=function() return players end}
 local WorldAdapter=(function()
-- WORLD_MODULE_HERE
 end)()
 local Content=(function()
-- CONTENT_MODULE_HERE
 end)()
 local Truck=(function()
-- TRUCK_MODULE_HERE
 end)()
 local world=Instance.new("Model")
 local runtime=Instance.new("Folder"); runtime.Parent=world
 local player={UserId=1}; players.list={player}
 local root={Position=vec(),CFrame=frame()}
 local w=setmetatable({world=world,runtime=runtime,commerceConfig=C,stores={},trucks={},itemViews={},itemParts={},movement={},presentation={Content=Content,TruckBuilder=Truck}},WorldAdapter)
 function w:alive() return root end
 function w:observe() return {invalid=false,invalidUntil=0} end
 local function part(name,position,parent)
  local p=Instance.new("Part"); p.Name=name; p.CFrame=frame(position or vec()); p.Parent=parent or world; return p
 end
 w.Trucks=Instance.new("Folder"); w.Trucks.Parent=runtime
 w.Items=Instance.new("Folder"); w.Items.Parent=runtime
 local pc=part("OfficePC",vec(0,0,0))
 local drop=part("WarehouseDrop",vec(0,1,-18))
 local slot=part("Slot01",vec(0,3,0))
 w.stores.Store01={available=true,markers={OfficePC=pc,WarehouseDrop=drop},slots={Slot01=slot},route={Approach=part("Approach",vec(-36,1,-39)),Dock=part("Dock",vec(23,1,-39)),Exit=part("Exit",vec(36,1,-39))}}
 local c={UserId=1,StoreId="Store01",Loaded=true,Active=true}
 local target={StoreId="Store01",Marker="OfficePC"}
 root.Position=vec(30,0,0); eq(w:check(c,target).Code,"TOO_FAR")
 root.Position=vec(5,0,0); eq(w:check(c,target).Code,"OK")
 hit={Instance=part("Wall",vec(3,0,0)),Position=vec(3,0,0)}; eq(w:check(c,target).Code,"NO_LINE_OF_SIGHT"); hit=nil
 c.Active=false; eq(w:check(c,target).Code,"NOT_ACTIVE"); c.Active=true
 c.Loaded=false; eq(w:check(c,target).Code,"NOT_LOADED"); c.Loaded=true
 c.StoreId="Store02"; eq(w:check(c,target).Code,"NOT_OWNER"); c.StoreId="Store01"
 eq(w:createTruck("order1","Store01").Code,"OK"); eq(w:createTruck("order2","Store01").Code,"DELIVERY_FAILED")
 local truck=w.trucks.order1
 eq(truck.model:GetAttribute("PresentationKind"),"BuildDeliveryTruck")
 eq(w:moveTruck("order1","ApproachToDock",1).Code,"OK"); eq(truck.cargo.Position.X,23); eq(truck.cargo.Position.Y,4)
 eq(truck.model:GetAttribute("DeliveryPhase"),"Docked")
 local bound=0
 for _,node in ipairs(truck.model:GetDescendants()) do if node.Name=="DirectNotice" then eq(node:GetAttribute("OperatorBindingStatus"),"OK"); bound+=1 end end
 eq(bound,2)
 local boxes={}
 for i=1,4 do
  local item={ItemId="item"..i,Sku="Water",Quantity=1,OwnerStoreId="Store01",State="Truck",OrderId="order1",Revision=1,CarrierUserId=false,CargoIndex=i}
  boxes[i]=item; eq(w:renderItem(item).Code,"OK")
 end
 eq(truck.model:GetAttribute("CargoCount"),4)
 eq(math.abs((w.itemParts.item1.Position.Y-0.7)-(truck.model.Body.Position.Y+0.2))<0.001,true,"cargo unit rests on truck bed")
 local positions={}
 for _,item in ipairs(boxes) do local p=w.itemParts[item.ItemId].Position; local key=p.X..":"..p.Z; eq(positions[key],nil); positions[key]=true end
 w:moveTruck("order1","DockToExit",0.5); eq(w.itemParts.item1.Position.X,28.6)
 boxes[1].State="Carried"; boxes[1].CarrierUserId=1; boxes[1].Revision+=1; eq(w:renderItem(boxes[1]).Code,"OK")
 eq(truck.model:GetAttribute("CargoCount"),3)
 boxes[1].State="Warehouse"; boxes[1].CarrierUserId=false; boxes[1].WarehouseBin=1; eq(w:renderItem(boxes[1]).Code,"OK")
 eq(drop:GetAttribute("WarehouseCount"),1); eq(drop:GetAttribute("WarehouseCapacity"),24)
 boxes[1].State="Sold"; eq(w:renderItem(boxes[1]).Code,"OK"); eq(w.itemParts.item1,nil); eq(drop:GetAttribute("WarehouseCount"),0)
 -- A temporarily missing carrier is a render retry, never an old warehouse count.
 boxes[1].State="Warehouse"; eq(w:renderItem(boxes[1]).Code,"OK")
 local alive=w.alive; w.alive=function() return nil end
 boxes[1].State="Carried"; boxes[1].CarrierUserId=1
 eq(w:renderItem(boxes[1]).Code,"NOT_FOUND"); eq(drop:GetAttribute("WarehouseCount"),0); eq(w.itemParts.item1,nil)
 w.alive=alive; eq(w:renderItem(boxes[1]).Code,"OK")
 boxes[2].State="Carried"; boxes[2].CarrierUserId=1; eq(w:renderItem(boxes[2]).Code,"OK")
 eq((w:itemCFrame(boxes[1]).Position-w:itemCFrame(boxes[2]).Position).Magnitude>1.2,true,"two carried units separated")
 for i=1,4 do boxes[i].State="Shelf"; boxes[i].CarrierUserId=false; boxes[i].SlotId="Slot01"; eq(w:renderItem(boxes[i]).Code,"OK") end
 eq((w:itemCFrame(boxes[1]).Position-w:itemCFrame(boxes[2]).Position).Magnitude>1.2,true,"shelf units separated")
 positions={}
 for i=1,32 do
  local p=w:itemCFrame({ItemId="bin"..i,OwnerStoreId="Store01",State="Warehouse",WarehouseBin=i}).Position
  eq(math.abs(p.X)+0.6<=3,true); eq(p.Z-0.6>=-20,true); eq(p.Z+0.6<=-16,true)
  local key=p.X..":"..p.Y..":"..p.Z; eq(positions[key],nil); positions[key]=true
 end
 eq(w:destroyTruck("order1").Code,"OK"); eq(w:destroyTruck("order1").Code,"OK"); eq(w.trucks.order1,nil)
 w.presentation.TruckBuilder=nil
 eq(w:createTruck("fallback","Store01").Code,"OK"); eq(w.trucks.fallback.model:GetAttribute("PresentationKind"),"FallbackFlatbed")
 eq(w:moveTruck("fallback","ApproachToDock",1).Code,"OK"); eq(w.trucks.fallback.cargo.Position.Y,4); w:destroyTruck("fallback")
 w.presentation.TruckBuilder={create=Truck.create,pose=function() error("injected pose failure") end}
 eq(w:createTruck("failed","Store01").Code,"DELIVERY_FAILED"); eq(w.trucks.failed,nil); eq(#w.Trucks:GetChildren(),0)
 eq(next(Content.Settings.Creatives),nil); eq(next(Content.Settings.AllowedAssetIds),nil)
 eq(Content.resolve("LCD","Store01",nil,nil,"123").Code,"FEATURE_DISABLED")
 eq(Content.resolve("LCD","Store99").Code,"BAD_REQUEST")
 local lcd=part("InformationLCD"); lcd:SetAttribute("ContentMode","HouseInformation")
 local old=Instance.new("SurfaceGui"); old.Name="WorldText"; old.Face="Right"; old.Parent=lcd
 local notice=Content.resolve("LCD","Store01")
 eq(Content.bind(world,lcd,"Right",notice).Code,"OK"); eq(Content.bind(world,lcd,"Right",notice).Code,"OK"); eq(#lcd:GetChildren(),1)
 local official=Instance.new("AdGui"); official.Adornee=lcd; official.Face="Right"; official.Parent=world
 eq(Content.bind(world,lcd,"Right",notice).Code,"FACE_OCCUPIED"); eq(#lcd:GetChildren(),1); official:Destroy()
 local decal=Instance.new("Decal"); decal.Face="Right"; decal.Parent=lcd
 eq(Content.bind(world,lcd,"Right",notice).Code,"FACE_OCCUPIED")
 -- LCD and both real truck boards keep their exact existing fallback after creation/attachment failure.
 decal:Destroy()
 w.presentation.TruckBuilder=Truck
 eq(w:createTruck("failure-faces","Store01").Code,"OK")
 local candidateTruck=w.trucks["failure-faces"].model
 local faces={{Part=lcd,Face="Right",Notice=notice}}
 for _,node in ipairs(candidateTruck:GetDescendants()) do
  if node:IsA("SurfaceGui") then
   local side=node.Face=="Left" and "left" or "right"
   table.insert(faces,{Part=node.Parent,Face=node.Face,Notice=Content.resolve("Truck","Store01","failure-faces",side)})
  end
 end
 eq(#faces,3,"LCD plus two truck faces")
 for _,case in ipairs(faces) do
  local function renderer()
   local list={}; for _,node in ipairs(world:GetDescendants()) do
    if node:IsA("SurfaceGui") and (node.Adornee or node.Parent)==case.Part and node.Face==case.Face then table.insert(list,node) end
   end; return list
  end
  local old=renderer()[1]; eq(#renderer(),1)
  for _,class in ipairs({"SurfaceGui","TextLabel"}) do
   failClass=class; eq(Content.bind(world,case.Part,case.Face,case.Notice).Code,"RENDER_FAILED"); failClass=nil
   eq(#renderer(),1); eq(renderer()[1],old,"same fallback survives create failure")
  end
  failParent=case.Part; eq(Content.bind(world,case.Part,case.Face,case.Notice).Code,"RENDER_FAILED"); failParent=nil
  eq(renderer()[1],old); eq(#renderer(),1)
  for _=1,3 do eq(Content.bind(world,case.Part,case.Face,case.Notice).Code,"OK"); eq(#renderer(),1,"single renderer after rebind") end
 end
 eq(w:setWarehouseCapacity("Store01",32).Code,"OK"); eq(drop:GetAttribute("WarehouseCapacity"),32)
 local restoring={}
 for i=1,32 do restoring[i]={ItemId="restored:"..i,Sku="Water",OwnerStoreId="Store01",State="Warehouse",WarehouseBin=i,Revision=1,Quantity=1} end
 eq(w:stageInventory(c,restoring).Code,"OK"); eq(w.inventoryStages[1].folder.Parent,nil,"hidden restore staging")
 eq(w:publishInventoryStage(c).Code,"OK"); eq(drop:GetAttribute("WarehouseCount"),32)
 for _,item in ipairs(restoring) do eq(w.itemParts[item.ItemId].Parent,w.Items); eq(w.itemParts[item.ItemId]:GetAttribute("WarehouseBin"),item.WarehouseBin) end
 eq(w:itemCFrame({OwnerStoreId="Store01",State="Warehouse",WarehouseBin=33}),nil)
 eq(w:itemCFrame({OwnerStoreId="Store01",State="Warehouse",WarehouseBin=0}),nil)
 print("WAREHOUSE_WORLD_PASS "..checks.." checks: real adapter/content/truck, fake translations/rays/Instances; PC distance/LOS, item/count/bin geometry, faces; no Studio")
end
