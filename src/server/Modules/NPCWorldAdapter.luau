--!nonstrict
-- Engine-only presentation/geometry. No income is awarded here.
local U=require(script.Parent.ServerUtil)
local World={}; World.__index=World
local function vec(a) return Vector3.new(a[1],a[2],a[3]) end
local function unique(parent,name)
	local found
	if not parent then return nil end
	for _,child in ipairs(parent:GetChildren()) do if child.Name==name then if found then return nil end; found=child end end
	return found
end
local function point(part) return part and part:IsA("BasePart") and part.Anchored and part.Position end
local function fallback(kind)
	local model=Instance.new("Model"); model.Name="Customer"..kind
	local shirt=kind=="Rich" and Color3.fromRGB(68,63,95) or Color3.fromRGB(83,143,125)
	for _,s in ipairs({{"Torso",{2,2,1},{0,3,0},shirt},{"Head",{1.4,1.4,1.4},{0,4.8,0},Color3.fromRGB(220,181,151)},
		{"LeftArm",{0.7,2,0.8},{-1.4,3,0},shirt},{"RightArm",{0.7,2,0.8},{1.4,3,0},shirt},
		{"LeftLeg",{0.8,2,0.8},{-0.55,1,0},shirt},{"RightLeg",{0.8,2,0.8},{0.55,1,0},shirt}}) do
		local p=Instance.new("Part"); p.Name=s[1]; p.Size=vec(s[2]); p.Color=s[4]; p.Anchored=true
		p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
		p:SetAttribute("OffsetX",s[3][1]); p:SetAttribute("OffsetY",s[3][2]); p:SetAttribute("OffsetZ",s[3][3]); p.Parent=model
	end
	model:SetAttribute("FallbackRig",true); return model
end
function World.new(root,config,builderModule)
	local self=setmetatable({root=root,config=config,rigs={},routes={}},World)
	if builderModule and builderModule:IsA("ModuleScript") then local ok,b=pcall(require,builderModule); if ok and type(b)=="table" and type(b.create)=="function" then self.builder=b end end
	local folder=Instance.new("Folder"); folder.Name="ServerCustomers"; folder.Parent=root; self.folder=folder
	local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={folder}
	params.RespectCanCollide=true; self.params=params
	return self
end
function World:_ground(p)
	local hit=workspace:Raycast(p+Vector3.new(0,2,0),Vector3.new(0,-6,0),self.params)
	if not hit or not hit.Instance:IsDescendantOf(self.root) or hit.Normal.Y<0.9 or math.abs(hit.Position.Y-p.Y)>2 then return nil end
	return Vector3.new(p.X,hit.Position.Y+0.03,p.Z)
end
function World:route(storeId)
	local path=unique(unique(self.root,self.config.Traffic.PathRoot),storeId)
	local store=unique(unique(self.root,"Stores"),storeId); local counter=unique(store,"Counter")
	if not path or path:GetAttribute("StoreId")~=storeId or not point(counter) then return U.result("MISSING_NPC_ROUTE") end
	local nodes={}
	for i,name in ipairs(self.config.Traffic.PedestrianRoute) do
		local node=unique(path,name); local p=point(node)
		local surface=(i==3 or i==4) and "Crosswalk" or (i>=6 and i<=9) and "Interior" or "Sidewalk"
		if not p or node.CanCollide or node.CanTouch or node.CanQuery or node:GetAttribute("StoreId")~=storeId or node:GetAttribute("NodeId")~=name or node:GetAttribute("Order")~=i
			or node:GetAttribute("Surface")~=surface or node:GetAttribute("NextNodeId")~=(self.config.Traffic.PedestrianRoute[i+1] or false) then return U.result("INVALID_NPC_ROUTE") end
		nodes[name]=self:_ground(p); if not nodes[name] then return U.result("NO_WALK_FLOOR") end
	end
	local def=self.config.World.Stores[storeId]
	local pivot=CFrame.new(vec(def.Position))*CFrame.Angles(0,math.rad(def.YawDegrees),0)
	local function localPoint(x,z) return self:_ground((pivot*CFrame.new(x,1,z)).Position) end
	local checkout=self:_ground(counter.CFrame:PointToWorldSpace(Vector3.new(0,-2,counter.Size.Z/2+2.5)))
	-- The collidable Spawn pad occupies x=-4..4,z=11..17. Walk its right aisle.
	local center=localPoint(0,3); local front=localPoint(0,20)
	local rightFront=localPoint(6.5,20); local rightBack=localPoint(6.5,3); local counterFront=localPoint(-12,20)
	if not checkout or not center or not front or not rightFront or not rightBack or not counterFront then return U.result("INVALID_CHECKOUT_PATH") end
	local crossing=path:GetAttribute("CrossingId")
	if crossing~="Cross01" and crossing~=false then return U.result("INVALID_NPC_ROUTE") end
	-- Explicit corridor checks, never a direct spawn-to-store road shortcut.
	local roadHalf=self.config.World.RoadWidth/2
	for _,name in ipairs({"SidewalkSpawn","CrossingWait","StoreApproach","SidewalkExit"}) do
		if math.abs(nodes[name].Z)<roadHalf+1.75 then return U.result("INVALID_SIDEWALK") end
	end
	if crossing then
		if math.abs(nodes.CrossingWait.X)>0.1 or math.abs(nodes.CrossingEntry.X)>0.1 or math.abs(nodes.CrossingExit.X)>0.1
			or nodes.CrossingWait.Z*nodes.CrossingExit.Z>=0 or nodes.CrossingExit.Z*nodes.StoreApproach.Z<=0 then return U.result("INVALID_CROSSWALK") end
	elseif nodes.CrossingWait.Z*nodes.StoreApproach.Z<=0 then return U.result("INVALID_SIDEWALK") end
	if nodes.SidewalkSpawn.Z*nodes.CrossingWait.Z<=0 or (nodes.StoreApproach-nodes.SidewalkExit).Magnitude>0.1 then return U.result("INVALID_SIDEWALK") end
	local route={StoreId=storeId,Pivot=pivot,Spawn=nodes.SidewalkSpawn,ToWait={nodes.CrossingWait},CrossingId=crossing,
		Crossing={nodes.CrossingEntry,nodes.CrossingExit},CrossingSeconds=((nodes.CrossingEntry-nodes.CrossingWait).Magnitude+(nodes.CrossingExit-nodes.CrossingEntry).Magnitude)/10+1,
		ToEntry={nodes.StoreApproach,nodes.Entry,front,rightFront,rightBack,center},Center=center,Front=front,Checkout=checkout,
		RightFront=rightFront,RightBack=rightBack,CounterFront=counterFront,
		Exit={counterFront,front,nodes.StoreExit,nodes.SidewalkExit},Slots={}}
	local slots=unique(store,"ShelfSlots")
	for _,id in ipairs(self.config.World.ShelfSlotIds) do
		local slot=unique(slots,id); if not point(slot) or slot:GetAttribute("SlotId")~=id then return U.result("INVALID_SHELF_PATH") end
		local p=pivot:PointToObjectSpace(slot.Position); local target=localPoint(p.X,-3.5)
		if not target then return U.result("NO_WALK_FLOOR") end
		route.Slots[id]=target
	end
	return U.result("OK",route)
end
function World:shelfTarget(route,slot) return route.Slots[slot] and U.result("OK",route.Slots[slot]) or U.result("INVALID_SHELF_PATH") end
function World:browsePath(route,position,target)
	local localTarget=route.Pivot:PointToObjectSpace(target)
	local aisle=self:_ground((route.Pivot*CFrame.new(localTarget.X,1,3)).Position)
	if not aisle then return U.result("NO_WALK_FLOOR") end
	if (position-route.Center).Magnitude<0.35 then return U.result("OK",{aisle,target}) end
	return U.result("OK",{route.CounterFront,route.Front,route.RightFront,route.RightBack,route.Center,aisle,target})
end
function World:checkoutPath(route,position)
	local p=route.Pivot:PointToObjectSpace(position)
	local aisle=self:_ground((route.Pivot*CFrame.new(p.X,1,3)).Position)
	if not aisle then return U.result("NO_WALK_FLOOR") end
	return U.result("OK",{aisle,route.Center,route.RightBack,route.RightFront,route.Front,route.CounterFront,route.Checkout})
end
function World:checkoutSeconds(route,position,speed)
	local path=self:checkoutPath(route,position); if not path.Ok then return path end
	local distance=0; for _,p in ipairs(path.Value) do distance+=(p-position).Magnitude; position=p end
	return U.result("OK",distance/speed+0.4)
end
function World:exitPath(route) return U.result("OK",route.Exit) end
function World:visitSeconds(storeId,speed)
	local r=self:route(storeId); if not r.Ok then return r end
	local route=r.Value; local distance=0; local p=route.Spawn
	for _,path in ipairs({route.ToWait,route.Crossing,route.ToEntry}) do for _,target in ipairs(path) do distance+=(target-p).Magnitude; p=target end end
	-- Full signal cycle allowance + shelf travel/selection; early arrival waits at shelf.
	return U.result("OK",distance/speed+38+12)
end
function World:_pose(r,p,direction)
	local flat=Vector3.new(direction.X,0,direction.Z)
	local frame=flat.Magnitude>0.001 and CFrame.lookAt(p,p+flat) or CFrame.new(p)
	for _,part in ipairs(r.Model:GetChildren()) do if part:IsA("BasePart") then
		part.CFrame=frame*CFrame.new(part:GetAttribute("OffsetX"),part:GetAttribute("OffsetY"),part:GetAttribute("OffsetZ"))
	end end
	r.Position=p
end
function World:create(id,kind,p)
	if self.rigs[id] then return U.result("INVALID_NPC") end
	local model
	if self.builder then local ok,m=pcall(self.builder.create,kind); if ok and typeof(m)=="Instance" and m:IsA("Model") then model=m end end
	if model then
		local valid=true; local parts=0
		for _,d in ipairs(model:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then valid=false end
			if d:IsA("BasePart") then
				parts+=1
				if d.Parent~=model or not d.Anchored or d.CanCollide then valid=false end
				for _,axis in ipairs({"X","Y","Z"}) do if type(d:GetAttribute("Offset"..axis))~="number" then valid=false end end
				d.CanTouch=false; d.CanQuery=false
			end
		end
		if not valid or parts<2 then model:Destroy(); model=nil end
	end
	model=model or fallback(kind); model.Name=id; model:SetAttribute("NpcId",id); model:SetAttribute("CustomerKind",kind); model.Parent=self.folder
	local head=model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart")
	local gui=Instance.new("BillboardGui"); gui.Size=UDim2.fromOffset(150,36); gui.StudsOffset=Vector3.new(0,2,0); gui.MaxDistance=50; gui.Parent=head
	local label=Instance.new("TextLabel"); label.Size=UDim2.fromScale(1,1); label.BackgroundTransparency=1; label.TextColor3=Color3.new(1,1,1); label.TextStrokeTransparency=0.4
	label.TextSize=15; label.Text=kind=="Rich" and "큰손 손님" or "손님"; label.Parent=gui
	self.rigs[id]={Model=model,Position=p,Label=label,Kind=kind}; self:_pose(self.rigs[id],p,Vector3.new(0,0,-1))
	return U.result("OK")
end
function World:move(id,from,target,maxDistance)
	local r=self.rigs[id]; if not r or not r.Model.Parent or (r.Position-from).Magnitude>0.05 then return U.result("INVALID_NPC") end
	local delta=target-from; local distance=delta.Magnitude
	local nextP=distance<=maxDistance and target or from+delta.Unit*maxDistance
	if distance<0.001 then nextP=target end
	local floor=self:_ground(nextP); if not floor then return U.result("NO_WALK_FLOOR") end
	local direction=floor-from
	if direction.Magnitude>0.001 then
		-- Square footprint covers rotated arms and shopping bag, including Rich hat height.
		local hit=workspace:Blockcast(CFrame.new(from+Vector3.new(0,3.2,0)),Vector3.new(4.6,5.8,4.6),direction,self.params)
		if hit then return U.result("PATH_BLOCKED") end
	end
	self:_pose(r,floor,delta)
	return U.result("OK",{Position=floor,Arrived=(Vector3.new(floor.X,0,floor.Z)-Vector3.new(target.X,0,target.Z)).Magnitude<0.05})
end
function World:at(id,position,tolerance)
	local r=self.rigs[id]; local torso=r and r.Model:FindFirstChild("Torso")
	if not r or not r.Model.Parent or not torso or (r.Position-position).Magnitude>tolerance then return U.result("INVALID_NPC") end
	return (torso.Position-(position+Vector3.new(0,3,0))).Magnitude<tolerance and U.result("OK") or U.result("INVALID_NPC")
end
function World:label(id,phase,slotId)
	local r=self.rigs[id]; if not r then return U.result("INVALID_NPC") end
	r.Model:SetAttribute("ShoppingPhase",phase); r.Model:SetAttribute("ShelfSlotId",slotId or false)
	local labels={Browse="상품을 고르는 중",Checkout="계산 중",WaitingSignal="보행 신호 대기",Done="감사합니다"}
	r.Label.Text=(r.Kind=="Rich" and "큰손 · " or "")..(labels[phase] or "매장 방문")
	return U.result("OK")
end
function World:basket(id,items,inventory)
	local r=self.rigs[id]; if not r then return U.result("INVALID_NPC") end
	local old=r.Model:FindFirstChild("ShoppingBag"); if old then old:Destroy() end
	if #items>0 then
		local bag=Instance.new("Part"); bag.Name="ShoppingBag"; bag.Size=Vector3.new(1,1.2,0.8); bag.Color=Color3.fromRGB(225,203,158)
		bag.Anchored=true; bag.CanCollide=false; bag.CanTouch=false; bag.CanQuery=false
		bag:SetAttribute("OffsetX",1.6); bag:SetAttribute("OffsetY",1.4); bag:SetAttribute("OffsetZ",-0.5); bag:SetAttribute("Units",#items)
		local skus={}; for _,selected in ipairs(items) do for _,i in ipairs(inventory) do if i.ItemId==selected.ItemId then table.insert(skus,i.Sku) end end end
		bag:SetAttribute("Skus",table.concat(skus,",")); bag.Parent=r.Model; self:_pose(r,r.Position,Vector3.new(0,0,-1))
	end
	return U.result("OK")
end
function World:destroy(id)
	local r=self.rigs[id]; if r then r.Model:Destroy(); self.rigs[id]=nil end; return U.result("OK")
end
return World
