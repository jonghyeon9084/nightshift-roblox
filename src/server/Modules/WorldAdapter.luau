--!nonstrict
local Players = game:GetService("Players")
local WorldAdapter = {}
WorldAdapter.__index = WorldAdapter
local function vec(a) return Vector3.new(a[1], a[2], a[3]) end
local function unique(parent, name, class)
	local found
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			if found or child.ClassName ~= class then return nil end
			found = child
		end
	end
	return found
end
function WorldAdapter.new(world, config, commerceConfig, presentation)
	assert(world:IsA("Model") and world.Name == config.World.Name and world:GetAttribute(config.World.OwnerAttribute) == true, "Invalid NightShiftWorld ownership")
	local hub, stores = unique(world, "Hub", "Model"), unique(world, "Stores", "Folder")
	assert(hub and stores, "NightShiftWorld root structure missing")
	local self = setmetatable({ world = world, config = config, stores = {}, hub = hub, commerceConfig=commerceConfig, trucks={}, itemParts={}, itemViews={}, movement={} }, WorldAdapter)
	self.presentation=presentation or {}
	self.hubSpawn = unique(hub, "Spawn", "SpawnLocation")
	assert(self.hubSpawn and (self.hubSpawn.Position - vec(config.World.HubSpawn)).Magnitude < 0.05, "Invalid Hub Spawn")
	assert(unique(hub, "StoreSelect", "Part"), "Invalid Hub StoreSelect")
	assert(self:safe(self.hubSpawn), "Hub Spawn is obstructed or has no floor")
	for _, storeId in ipairs(config.World.StoreIds) do
		local model = unique(stores, storeId, "Model")
		local entry = { model = model, markers = {}, lights = {}, available = true, reason = false }
		local def = config.World.Stores[storeId]
		local pivot = CFrame.new(vec(def.Position)) * CFrame.Angles(0, math.rad(def.YawDegrees), 0)
		if not model or model:GetAttribute("StoreId") ~= storeId then
			entry.available, entry.reason = false, "점포 모델 또는 StoreId 오류"
		else
			for _, name in ipairs(config.World.MarkerOrder) do
				local spec = config.World.Markers[name]
				local marker = unique(model, name, spec.ClassName)
				local expected = pivot * CFrame.new(vec(spec.Position))
				if not marker or marker:GetAttribute("StoreId") ~= storeId or not marker.Anchored
					or marker.CanTouch or marker.CastShadow or (marker.Size - vec(spec.Size)).Magnitude > 0.05
					or (marker.Position - expected.Position).Magnitude > 0.05
					or marker.CFrame.LookVector:Dot(expected.LookVector) < 0.999
					or marker.CFrame.UpVector:Dot(expected.UpVector) < 0.999
					or (name == "Entry" and (marker.CanCollide or marker.Transparency ~= 1))
					or (name ~= "Entry" and not (commerceConfig and string.match(name,"^Shelf")) and not marker.CanCollide)
					or (name == "Spawn" and (marker.Enabled or not marker.Neutral or marker.Duration ~= 0)) then
					entry.available, entry.reason = false, "필수 마커 오류: " .. name
					break
				end
				entry.markers[name] = marker
			end
			if entry.available and (not self:safe(entry.markers.Spawn) or not self:safe(entry.markers.Entry)) then
				entry.available, entry.reason = false, "Spawn/Entry 바닥 또는 안전 공간 오류"
			end
			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("Light") and (not commerceConfig or descendant:GetAttribute("OutageControlled") == true) then entry.lights[descendant] = descendant.Enabled end
			end
		end
        if commerceConfig and entry.available then
            entry.slots,entry.route={},{}
            local function validate(parent,name,position,size,attribute,value)
                local part=parent and unique(parent,name,"Part")
                local expected=pivot*CFrame.new(vec(position))
                if not part or part:GetAttribute("StoreId")~=storeId or not part.Anchored or part.CanCollide or part.CanTouch or part.CastShadow
                    or (part.Position-expected.Position).Magnitude>0.05 or (part.Size-vec(size)).Magnitude>0.05
                    or part.CFrame.LookVector:Dot(expected.LookVector)<0.999 or (attribute and part:GetAttribute(attribute)~=value) then
                    entry.available,entry.reason=false,"상거래 마커 오류: "..name; return nil
                end
                return part
            end
            for _,name in ipairs(commerceConfig.World.MarkerOrder) do local def=commerceConfig.World.Markers[name]
                entry.markers[name]=validate(model,name,def.Position,def.Size)
            end
            local slots=unique(model,"ShelfSlots","Folder")
            for i,name in ipairs(commerceConfig.World.ShelfSlotIds) do
                entry.slots[name]=validate(slots,name,commerceConfig.World.ShelfSlotPositions[i],commerceConfig.World.ShelfSlotSize,"SlotId",name)
                if entry.slots[name] and entry.slots[name]:GetAttribute("Capacity")~=commerceConfig.World.ShelfSlotCapacity then entry.available=false end
            end
            local route=unique(model,"TruckRoute","Folder")
            for i,name in ipairs(commerceConfig.World.TruckRouteOrder) do
                entry.route[name]=validate(route,name,commerceConfig.World.TruckRoutePositions[name],{1,1,1},"RouteId",name)
                if entry.route[name] and entry.route[name]:GetAttribute("Order")~=i then entry.available=false end
            end
            if not entry.available and not entry.reason then entry.reason="상거래 용량/경로 순서 오류" end
        end
        self.stores[storeId] = entry
	end
    if commerceConfig then
        assert(world:GetAttribute("CommerceLayoutVersion")==commerceConfig.World.LayoutVersion,"COMMERCE_LAYOUT_MISMATCH")
        self.runtime=unique(world,"CommerceRuntime","Folder"); assert(self.runtime,"Missing CommerceRuntime")
        for _,name in ipairs({"Trucks","Items"}) do
            local folder=unique(self.runtime,name,"Folder")
            if not folder then assert(not self.runtime:FindFirstChild(name),"Runtime collision"); folder=Instance.new("Folder"); folder.Name=name; folder.Parent=self.runtime end
            self[name]=folder
        end
    end
    if commerceConfig and self.presentation.Content then
        for storeId,store in pairs(self.stores) do
            local lcd=store.model and store.model:FindFirstChild("InformationLCD",true)
            if lcd then
                local content=self.presentation.Content
                local bound=content.bind(world,lcd,Enum.NormalId.Right,content.resolve("LCD",storeId))
                lcd:SetAttribute("OperatorBindingStatus",bound.Code)
            end
        end
    end
    if commerceConfig then for storeId,store in pairs(self.stores) do if store.available then self:refreshInventory(storeId) end end end
    return self
end
function WorldAdapter:safe(marker, character)
	if not marker or not marker:IsDescendantOf(self.world) then return false end
	local destination = marker.CFrame * CFrame.new(0, self.config.World.SpawnLift, 0)
	local exclude = {}
	-- Players do not make a correctly built spawn permanently Unavailable.
	for _, player in ipairs(Players:GetPlayers()) do if player.Character then table.insert(exclude, player.Character) end end
	if character then table.insert(exclude, character) end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclude
	overlap.RespectCanCollide = true
	for _, part in ipairs(workspace:GetPartBoundsInBox(destination, Vector3.new(4, 5.5, 4), overlap)) do
		if part.CanCollide then return false end
	end
	local ray = RaycastParams.new()
	-- Check our supporting floor explicitly. A preserved Baseplate/SpawnLocation
	-- may be coplanar and win the nearest-hit tie; it must not hide our floor.
	-- Clearance above still tests ALL collidable scene geometry (except players).
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = { self.world }
	ray.RespectCanCollide = true
	local floor = workspace:Raycast(destination.Position, Vector3.new(0, -8, 0), ray)
	if not floor or not floor.Instance:IsDescendantOf(self.world) or floor.Normal.Y < 0.8 then return false end
	return destination
end
function WorldAdapter:alive(player)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local human = character and character:FindFirstChildOfClass("Humanoid")
	return root and root:IsA("BasePart") and human and human.Health > 0 and root or nil
end
function WorldAdapter:near(player, storeId, markerName)
	local entry = self.stores[storeId]
	local marker = entry and entry.markers[markerName]
	local root = self:alive(player)
	return root ~= nil and marker ~= nil and marker:IsDescendantOf(self.world)
		and (root.Position - marker.Position).Magnitude <= self.config.Interaction.Distance
end
function WorldAdapter:inside(player, storeId)
	local root = self:alive(player)
	if not root then return false end
	local spec = self.config.World.Stores[storeId]
	local pivot = CFrame.new(vec(spec.Position)) * CFrame.Angles(0, math.rad(spec.YawDegrees), 0)
	local localPosition = pivot:PointToObjectSpace(root.Position)
	local size = self.config.World.StoreSize
	return math.abs(localPosition.X) <= size[1] / 2 and math.abs(localPosition.Z) <= size[3] / 2
		and localPosition.Y >= 0 and localPosition.Y <= size[2]
end
function WorldAdapter:move(player, storeId, markerName)
	if not self:alive(player) then return false end
	local marker = storeId and self.stores[storeId].markers[markerName] or self.hubSpawn
	local destination = self:safe(marker, player.Character)
	if not destination then return false end
	player.Character:PivotTo(destination)
	local root = self:alive(player)
	if root then
        local now=workspace:GetServerTimeNow()
        self.movement[player.UserId]={position=root.Position,at=now,credit=self.commerceConfig and self.commerceConfig.Interaction.MovementSlack or 0,
            invalidUntil=now+(self.commerceConfig and self.commerceConfig.Interaction.RecoveryGraceSeconds or 0)}
        root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
    end
	return true
end
function WorldAdapter:setOutage(storeId, active)
	local entry = self.stores[storeId]
	for light, original in pairs(entry.lights) do
		if light:IsDescendantOf(entry.model) then light.Enabled = not active and original end
	end
	entry.model:SetAttribute("OutageActive", active)
end
function WorldAdapter:setLayout(storeId, products)
 if self.commerceConfig then return end
	for index, product in ipairs(products) do
		local shelf = self.stores[storeId].markers["Shelf" .. index]
		shelf:SetAttribute("ProductId", product)
		shelf:SetAttribute("ProductName", self.config.Products[product].Name)
		shelf:SetAttribute("ProductGlyph", self.config.Products[product].Glyph)
	end
end
local function result(code) return {Ok=code=="OK",Code=code,Value=false} end
function WorldAdapter:observe(player, now)
 local root=self:alive(player); if not root then return nil end
 local old=self.movement[player.UserId]; local cfg=self.commerceConfig.Interaction
 if not old then
  old={position=root.Position,at=now,credit=cfg.MovementSlack,invalidUntil=now+cfg.RecoveryGraceSeconds}
  self.movement[player.UserId]=old
 elseif not old.invalid then
  local distance=(root.Position-old.position).Magnitude
  local available=(old.credit or 0)+cfg.MaxSpeed*math.max(0,now-old.at)
  if distance>available then
   old.invalid=true -- Latched until authoritative recovery; waiting cannot legitimize a teleport.
  else
   old.credit=math.min(cfg.MovementSlack,available-distance)
   old.position=root.Position; old.at=now
  end
 end
 return old
end
function WorldAdapter:sample(now)
 for _,player in ipairs(Players:GetPlayers()) do self:observe(player,now) end
 for id,part in pairs(self.itemParts) do
  local cf=self:itemCFrame(self.itemViews[id]); if cf and part.Parent then part.CFrame=cf end
 end
end
function WorldAdapter:invalidMovement(player)
 local state=self.movement[player.UserId]
 return state and state.invalid==true
end
function WorldAdapter:outOfBounds(player)
 local root=self:alive(player)
 return root and (root.Position.Y < -30 or math.abs(root.Position.X)>600 or math.abs(root.Position.Z)>600)
end
function WorldAdapter:itemCFrame(item)
 if not item then return nil end
 if item.State=="Recoverable" then return item.DropCFrame or nil end
 if item.CarrierUserId then
  local root=self:alive(Players:GetPlayerByUserId(item.CarrierUserId))
  local rank=1
  for id,other in pairs(self.itemViews) do if id<item.ItemId and other.CarrierUserId==item.CarrierUserId then rank+=1 end end
  return root and root.CFrame*CFrame.new((rank-1)*1.4,0,-2)
 end
 local store=self.stores[item.OwnerStoreId]
 if not store or not store.available then return nil end
 if item.State=="Truck" then
  local truck=self.trucks[item.OrderId]; local i=(item.CargoIndex or 1)-1
  return truck and truck.cargo.CFrame*CFrame.new((i%2)*1.8-0.9,-0.9,math.floor(i/2)*1.8-0.9)
 end
 if item.State=="Shelf" then
  local slot=store.slots[item.SlotId]; local rank=0
  for id,other in pairs(self.itemViews) do
   if id<item.ItemId and other.State=="Shelf" and other.OwnerStoreId==item.OwnerStoreId and other.SlotId==item.SlotId then rank+=1 end
  end
  -- Two-by-two units fit the narrower rack; retain authoritative SlotId markers.
  local slotIndex=tonumber(string.match(item.SlotId or "","%d+")) or 1
  local inset=slotIndex%2==1 and 1 or -1
  return slot and slot.CFrame*CFrame.new(inset+(rank%2-0.5)*1.3,0,(math.floor(rank/2)-0.5)*1.3)
 end
 if item.State=="Warehouse" then
  local bin=item.WarehouseBin or 1
  if type(bin)~="number" or bin%1~=0 or bin<1 or bin>32 then return nil end
  local i=bin-1
  -- 24/32 unit bins: 4 columns x 2 rows x 3/4 tiers, all inside x=-3..3.
  return store.markers.WarehouseDrop.CFrame*CFrame.new((i%4-1.5)*1.5,0.8+math.floor(i/8)*1.5,(math.floor(i/4)%2)*1.5-0.75)
 end
 return nil
end
function WorldAdapter:check(context,target)
 if target.Marker=="OfficePC" then
  if context.StoreId~=target.StoreId then return result("NOT_OWNER") end
  if not context.Loaded then return result("NOT_LOADED") end
  if not context.Active then return result("NOT_ACTIVE") end
 end
 local player=Players:GetPlayerByUserId(context.UserId); local root=self:alive(player)
 if not root then return result("NOT_ACTIVE") end
 local now=workspace:GetServerTimeNow()
 local sample=self:observe(player,now)
 if not sample or sample.invalid or sample.invalidUntil>now then return result("INVALID_MOVEMENT") end
 local part
 if target.ItemId then part=self.itemParts[target.ItemId]
 elseif target.OrderId then local truck=self.trucks[target.OrderId]; part=truck and truck.cargo
 else local store=self.stores[target.StoreId]
  if not store or not store.available then return result("STORE_UNAVAILABLE") end
  part=target.SlotId and store.slots[target.SlotId] or store.markers[target.Marker]
 end
 if not part or not part:IsDescendantOf(self.world) then return result("NOT_FOUND") end
 if (root.Position-part.Position).Magnitude>self.commerceConfig.Interaction.Distance then return result("TOO_FAR") end
 local ray=RaycastParams.new(); ray.FilterType=Enum.RaycastFilterType.Exclude
 local exclude={self.runtime}; for _,p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(exclude,p.Character) end end
 ray.FilterDescendantsInstances=exclude; ray.RespectCanCollide=true
 local hit=workspace:Raycast(root.Position,part.Position-root.Position,ray)
 if hit and hit.Instance~=part and (hit.Position-part.Position).Magnitude>1.5 then return result("NO_LINE_OF_SIGHT") end
 return result("OK")
end
function WorldAdapter:renderItem(item)
 local id=item.ItemId
 local old=self.itemViews[id]
 if item.State=="Sold" or item.State=="Expired" or item.State=="Recalled" then
  if self.itemParts[id] then self.itemParts[id]:Destroy() end
  self.itemParts[id],self.itemViews[id]=nil,nil; self:refreshInventory(old and old.OwnerStoreId or item.OwnerStoreId); return result("OK")
 end
 -- Cache the committed ledger view even if its character/truck is temporarily
 -- missing; counts must not keep the previous state while rendering retries.
 self.itemViews[id]=table.clone(item)
 if item.State=="SafeStorage" then
  if self.itemParts[id] then self.itemParts[id]:Destroy(); self.itemParts[id]=nil end
  self:refreshInventory(item.OwnerStoreId); return result("OK")
 end
 local cf=self:itemCFrame(item); if not cf then
  if self.itemParts[id] then self.itemParts[id]:Destroy(); self.itemParts[id]=nil end
  self:refreshInventory(item.OwnerStoreId)
  if old and old.OwnerStoreId~=item.OwnerStoreId then self:refreshInventory(old.OwnerStoreId) end
  return result("NOT_FOUND")
 end
 local part=self.itemParts[id]
 if not part then
  part=Instance.new("Part"); part.Name=id; part.Size=Vector3.new(1.2,1.4,1.2)
  part.Anchored=true; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false; part.CastShadow=false
  local gui=Instance.new("BillboardGui"); gui.Name="ItemLabel"; gui.Size=UDim2.fromOffset(110,32); gui.StudsOffset=Vector3.new(0,1.4,0); gui.MaxDistance=40; gui.Parent=part
  local label=Instance.new("TextLabel"); label.Name="Caption"; label.Size=UDim2.fromScale(1,1); label.BackgroundTransparency=0.25; label.TextColor3=Color3.new(1,1,1)
  label.TextSize=14; label.Text=self.commerceConfig.Products[item.Sku].Name; label.Parent=gui
  part.Parent=self.Items; self.itemParts[id]=part
 end
 for _,key in ipairs({"ItemId","Sku","OwnerUserId","OwnerStoreId","State","Revision","SlotId","CarrierUserId","Stolen","OrderId","WarehouseBin","CargoIndex","Quantity"}) do part:SetAttribute(key,item[key]) end
 part.Color=self.commerceConfig.Products[item.Sku].Rarity=="Rare" and Color3.fromRGB(220,175,60) or Color3.fromRGB(75,170,185)
 part.ItemLabel.Caption.Text=self.commerceConfig.Products[item.Sku].Name..(item.State=="Warehouse" and string.format(" · %02d칸",item.WarehouseBin or 1) or " · 1개")
 part.CFrame=cf
 self:refreshInventory(item.OwnerStoreId)
 if old and old.OwnerStoreId~=item.OwnerStoreId then self:refreshInventory(old.OwnerStoreId) end
 return result("OK")
end
function WorldAdapter:refreshInventory(storeId)
 local store=self.stores[storeId]; if not store or not store.available then return end
 local count=0
 for _,item in pairs(self.itemViews) do if item.OwnerStoreId==storeId and item.State=="Warehouse" then count+=1 end end
 local marker=store.markers.WarehouseDrop
 local capacity=store.warehouseCapacity or self.commerceConfig.Wholesale.MaxItemsPerStore
 marker:SetAttribute("WarehouseCount",count); marker:SetAttribute("WarehouseCapacity",capacity)
 local gui=marker:FindFirstChild("WarehouseCount")
 if not gui then
  gui=Instance.new("BillboardGui"); gui.Name="WarehouseCount"; gui.Size=UDim2.fromOffset(170,30); gui.StudsOffset=Vector3.new(0,2.8,0); gui.MaxDistance=20
  local label=Instance.new("TextLabel"); label.Name="Count"; label.Size=UDim2.fromScale(1,1); label.BackgroundTransparency=0.25
  label.TextColor3=Color3.new(1,1,1); label.TextSize=14; label.Parent=gui; gui.Parent=marker
 end
 gui.Count.Text=string.format("창고 %d / %d · 직접 운반",count,capacity)
 for _,truck in pairs(self.trucks) do if truck.storeId==storeId then
  local remaining=0
  for _,item in pairs(self.itemViews) do if item.OrderId==truck.model.Name and item.State=="Truck" then remaining+=1 end end
  truck.model:SetAttribute("CargoCount",remaining)
 end end
end
-- Hidden staging is discarded on any restore error. Publishing creates no new IDs.
function WorldAdapter:stageInventory(context,items)
 self.inventoryStages=self.inventoryStages or {}
 self:discardInventoryStage(context)
 local stage={folder=Instance.new("Folder"),parts={},views={}}
 local parts,views,folder=self.itemParts,self.itemViews,self.Items
 self.itemParts,self.itemViews,self.Items=stage.parts,stage.views,stage.folder
 local ok,err=pcall(function()
  for _,item in ipairs(items) do
   if item.State~="SafeStorage" then assert(self:renderItem(item).Ok,"restore presentation failed")
   else self.itemViews[item.ItemId]=table.clone(item) end
  end
 end)
 self.itemParts,self.itemViews,self.Items=parts,views,folder
 if not ok then stage.folder:Destroy(); return result("RESTORE_FAILED") end
 self.inventoryStages[context.UserId]=stage
 return result("OK")
end
function WorldAdapter:discardInventoryStage(context)
 local stage=self.inventoryStages and self.inventoryStages[context.UserId]
 if stage then
  for id,part in pairs(stage.parts) do
   if self.itemParts[id]==part then self.itemParts[id]=nil; self.itemViews[id]=nil end
   part:Destroy()
  end
  stage.folder:Destroy(); self.inventoryStages[context.UserId]=nil
 end
 return result("OK")
end
function WorldAdapter:setWarehouseCapacity(storeId,capacity)
 local store=self.stores[storeId]; if not store then return result("NOT_FOUND") end
 if store.warehouseCapacity~=capacity then store.warehouseCapacity=capacity; self:refreshInventory(storeId) end
 return result("OK")
end
function WorldAdapter:publishInventoryStage(context)
 local stage=self.inventoryStages and self.inventoryStages[context.UserId]
 if not stage then return result("RESTORE_FAILED") end
 for id,part in pairs(stage.parts) do self.itemParts[id]=part; part.Parent=self.Items end
 for id,item in pairs(stage.views) do self.itemViews[id]=item end
 stage.folder:Destroy(); self.inventoryStages[context.UserId]=nil
 self:refreshInventory(context.StoreId)
 return result("OK")
end
function WorldAdapter:renderOwner(storeId,displayName,userId,generation)
 local store=self.stores[storeId]; if not store or not store.model then return result("NOT_FOUND") end
 store.model:SetAttribute("OwnerUserId",userId or false)
 store.model:SetAttribute("OwnerGeneration",generation)
 store.model:SetAttribute("DisplayName",displayName)
 local sign=store.model:FindFirstChild("StoreSign",true)
 local label=sign and sign:FindFirstChildWhichIsA("TextLabel",true)
 if label then label.RichText=false; label.Text=displayName~="" and (displayName.."의 편의점") or "빈 편의점" end
 return result("OK")
end
function WorldAdapter:setAlarm(storeId,alarm)
 local store=self.stores[storeId]; local marker=store and store.markers.Alarm
 local light=marker and marker:FindFirstChildOfClass("PointLight")
 if not light then return result("NOT_FOUND") end
 light.Enabled=alarm~=false; marker:SetAttribute("AlarmActive",alarm~=false); return result("OK")
end
function WorldAdapter:createTruck(orderId,storeId)
 if self.trucks[orderId] then return self.trucks[orderId].storeId==storeId and result("OK") or result("DELIVERY_FAILED") end
 local store=self.stores[storeId]; if not store or not store.available then return result("DELIVERY_FAILED") end
 for _,truck in pairs(self.trucks) do if truck.storeId==storeId then return result("DELIVERY_FAILED") end end
 local builder=self.presentation and self.presentation.TruckBuilder
 local model,cargo
 if builder then
  -- Concrete TruckWorld API: create(storeId,orderId) -> model,body,cargo;
  -- pose(model,routeFrame) applies the builder's per-part local offsets.
  local built,m,_,c=pcall(builder.create,storeId,orderId)
  if not built or not m or not m:IsA("Model") then return result("DELIVERY_FAILED") end
  model,cargo=m,c
  if not cargo or cargo~=unique(model,"Cargo","Part") or (cargo.Position-vec(self.commerceConfig.World.CargoOffset)).Magnitude>0.05
   or type(builder.pose)~="function" then model:Destroy(); return result("DELIVERY_FAILED") end
  for _,node in ipairs(model:GetDescendants()) do
   if node:IsA("LuaSourceContainer") or node:IsA("RemoteEvent") or node:IsA("RemoteFunction") or node:IsA("AdGui") then model:Destroy(); return result("DELIVERY_FAILED") end
  end
 else
  -- Functional flatbed until Integrator installs TruckWorld's authored template.
  model=Instance.new("Model")
  local function block(name,size,offset)
   local part=Instance.new("Part"); part.Name=name; part.Size=size; part.CFrame=CFrame.new(offset)
   part.Color=Color3.fromRGB(67,89,115); part.Parent=model; return part
  end
  block("Body",Vector3.new(7,0.5,10),Vector3.new(0,0.6,0))
  block("Cab",Vector3.new(7,3,3),Vector3.new(0,2,-3.5))
  block("Bed",Vector3.new(6,0.3,6),Vector3.new(0,1.25,0))
  cargo=block("Cargo",Vector3.new(6,2,6),vec(self.commerceConfig.World.CargoOffset))
  model.WorldPivot=CFrame.new()
 end
 model.Name=orderId; model:SetAttribute("StoreId",storeId); model:SetAttribute("OrderId",orderId)
 model:SetAttribute("CargoCount",0); model:SetAttribute("PresentationKind",builder and "BuildDeliveryTruck" or "FallbackFlatbed")
 for _,part in ipairs(model:GetDescendants()) do if part:IsA("BasePart") then
  part.Anchored=true; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false; part.CastShadow=false
 end end
 cargo.Transparency=1
 cargo:SetAttribute("StoreId",storeId); cargo:SetAttribute("OrderId",orderId); cargo.Parent=model
 self.trucks[orderId]={model=model,cargo=cargo,storeId=storeId,builder=builder}; model.Parent=self.Trucks
 local moved=self:moveTruck(orderId,"ApproachToDock",0)
 if not moved.Ok then self:destroyTruck(orderId); return moved end
 local content=self.presentation and self.presentation.Content
 if content then for _,board in ipairs(model:GetDescendants()) do
  if board:IsA("BasePart") and board.Name=="DirectNotice" then
   local id=board:GetAttribute("SlotId")
   local side=id==storeId..":TruckLeft" and "left" or (id==storeId..":TruckRight" and "right" or nil)
   if side then
    local face=side=="left" and Enum.NormalId.Left or Enum.NormalId.Right
    local bound=content.bind(self.world,board,face,content.resolve("Truck",storeId,orderId,side))
    board:SetAttribute("OperatorBindingStatus",bound.Code)
   end
  end
 end end
 return result("OK")
end
function WorldAdapter:moveTruck(orderId,segment,alpha)
 local truck=self.trucks[orderId]; if not truck then return result("DELIVERY_FAILED") end
 if type(alpha)~="number" or alpha~=alpha or alpha<0 or alpha>1 then return result("DELIVERY_FAILED") end
 local route=self.stores[truck.storeId].route
 local a,b
 if segment=="ApproachToDock" then a,b=route.Approach,route.Dock elseif segment=="DockToExit" then a,b=route.Dock,route.Exit else return result("DELIVERY_FAILED") end
 if not a or not b or not a.Parent or not b.Parent then return result("DELIVERY_FAILED") end
 local cf=a.CFrame:Lerp(b.CFrame,alpha)
 if truck.builder then
  local posed=pcall(truck.builder.pose,truck.model,cf); if not posed then return result("DELIVERY_FAILED") end
 else truck.model:PivotTo(cf) end
 truck.model:SetAttribute("RouteSegment",segment); truck.model:SetAttribute("RouteAlpha",alpha)
 truck.model:SetAttribute("DeliveryPhase",segment=="DockToExit" and "Exiting" or (alpha==1 and "Docked" or "InTransit"))
 -- Move already-rendered units with their truck in the same engine step.
 for id,item in pairs(self.itemViews) do if item.OrderId==orderId and item.State=="Truck" then
  local part=self.itemParts[id]; if part and part.Parent then part.CFrame=self:itemCFrame(item) end
 end end
 return result("OK")
end
function WorldAdapter:destroyTruck(orderId)
 local truck=self.trucks[orderId]; if truck then truck.model:Destroy(); self.trucks[orderId]=nil end
 return result("OK")
end
return WorldAdapter
