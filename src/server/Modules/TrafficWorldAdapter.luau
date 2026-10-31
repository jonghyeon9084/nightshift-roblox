--!nonstrict
-- Uses authored world models; no Touch/network-owned physics or delivery-truck mutation.
local U=require(script.Parent.ServerUtil)
local G=require(script.Parent.TrafficGeometry)
local World={}; World.__index=World
local function unique(parent,name)
	local found
	if parent then for _,p in ipairs(parent:GetChildren()) do if p.Name==name then if found then return nil end; found=p end end end
	return found
end
local function part(p) return p and p:IsA("BasePart") and p.Anchored and G.point(p.Position) end
function World.new(root,base,builders,players)
	local self=setmetatable({root=root,base=base,builders=builders,playersService=players,models={},markers={}},World)
	local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances={root}; params.RespectCanCollide=true; self.params=params
	return self
end
function World:_capture(p)
	if not part(p) then error("MISSING_TRAFFIC_MARKER") end
	table.insert(self.markers,{Part=p,Parent=p.Parent,Name=p.Name,CFrame=p.CFrame,Size=p.Size,Collide=p.CanCollide,Touch=p.CanTouch,Query=p.CanQuery})
	return p
end
function World:layout()
	if not self.root:IsA("Model") or self.root:GetAttribute("NightShiftOwned")~=true
		or type(self.builders.Vehicle)~="table" or type(self.builders.Signals)~="table" then return U.result("MISSING_TRAFFIC_BUILDERS") end
	local traffic=unique(self.root,"Traffic"); local routes=unique(traffic,"Routes")
	local cross=unique(unique(traffic,"Crossings"),"Cross01")
	local signals=unique(unique(traffic,"Signals"),"Cross01")
	local zone=self:_capture(unique(cross,"RoadZone"))
	-- LayoutVersion=1 is axis-aligned. Reject changed geometry rather than drive a shortcut.
	if zone.CFrame~=CFrame.new(0,2,0) or zone.Size~=Vector3.new(400,4,24) then return U.result("INVALID_ROAD_ZONE") end
	local out={Routes={},Zone={X=0,Z=0,HalfX=200,HalfZ=12,MinY=0,MaxY=4}}
	for i=1,2 do
		local route=unique(routes,"Route0"..i); local nodes={}; local dir=i==1 and 1 or -1; local z=-6*dir
		for j,name in ipairs({"VehicleSpawn","VehicleStop","VehicleCrossExit","VehicleExit"}) do
			local p=self:_capture(unique(route,name)); nodes[j]=p.Position.X
			if p.CanCollide or p.CanTouch or p.CanQuery or p:GetAttribute("Order")~=j or p:GetAttribute("CrossingId")~="Cross01"
				or p:GetAttribute("RouteId")~="Route0"..i or p.Position.Z~=z or p.Position.Y~=1 then return U.result("INVALID_VEHICLE_ROUTE") end
		end
		if nodes[1]~=-195*dir or nodes[2]~=-16*dir or nodes[3]~=16*dir or nodes[4]~=195*dir then return U.result("INVALID_VEHICLE_ROUTE") end
		table.insert(out.Routes,{Id="Route0"..i,Dir=dir,Z=z,Y=0.08,Spawn=nodes[1],Stop=nodes[2],CrossExit=nodes[3],Exit=nodes[4]})
	end
	for _,name in ipairs({"StopLine","CrossingEntryNorth","CrossingExitSouth","WaitNorth","WaitSouth","DropSafeNorth","DropSafeSouth"}) do self:_capture(unique(cross,name)) end
	self.north=unique(cross,"DropSafeNorth"); self.south=unique(cross,"DropSafeSouth")
	self.vehicleLamp=self:_capture(unique(signals,"VehicleSignal")); self.walkLamp=self:_capture(unique(signals,"PedestrianSignal")); self.signals=signals
	local road=self:_capture(unique(unique(self.root,"Streets"),"MainRoad"))
	if not road.CanCollide or road.Size~=Vector3.new(400,1,24) or math.abs(road.Position.Y+road.Size.Y/2-0.08)>0.001 then return U.result("INVALID_ROAD_FLOOR") end
	if unique(self.root,"ServerRoadVehicles") then return U.result("TRAFFIC_ALREADY_OWNED") end
	local folder=Instance.new("Folder"); folder.Name="ServerRoadVehicles"; folder.Parent=self.root; self.folder=folder
	return U.result("OK",out)
end
function World:healthy()
	if not self.root.Parent or not self.folder or self.folder.Parent~=self.root then return U.result("MISSING_TRAFFIC_WORLD") end
	for _,m in ipairs(self.markers) do
		if m.Part.Parent~=m.Parent or not m.Part:IsDescendantOf(self.root) or unique(m.Parent,m.Name)~=m.Part
			or not m.Part.Anchored or m.Part.CFrame~=m.CFrame or m.Part.Size~=m.Size
			or m.Part.CanCollide~=m.Collide or m.Part.CanTouch~=m.Touch or m.Part.CanQuery~=m.Query then return U.result("TRAFFIC_MARKER_CHANGED") end
	end
	if self.phase and (self.signals:GetAttribute("Phase")~=self.phase or self.signals:GetAttribute("PhaseEndsAt")~=self.endsAt
		or self.vehicleLamp:GetAttribute("SignalState")~=(self.phase=="VehicleGreen" and "Go" or "Stop")
		or self.walkLamp:GetAttribute("SignalState")~=(self.phase=="Walk" and "Go" or "Stop")) then return U.result("TRAFFIC_SIGNAL_CHANGED") end
	for _,m in pairs(self.models) do
		if m.Parent~=self.folder then return U.result("VEHICLE_MISSING") end
		local parts=m:GetDescendants(); if #parts~=7 then return U.result("VEHICLE_CHANGED") end
		for _,p in ipairs(parts) do if not p:IsA("BasePart") or not p.Anchored or p.CanCollide or p.CanTouch or p.CanQuery then return U.result("VEHICLE_CHANGED") end end
	end
	return U.result("OK")
end
function World:signal(phase,endsAt)
	local b=self.builders.Signals
	local ok,result=false,false
	if b and type(b.apply)=="function" then ok,result=pcall(b.apply,self.root,phase,endsAt) end
	if not ok or result~=true then
		-- Best-effort red even when a builder is missing or partially fails.
		for _,lamp in ipairs({self.vehicleLamp,self.walkLamp}) do if lamp and lamp.Parent then lamp:SetAttribute("SignalState","Stop"); lamp.Color=Color3.fromRGB(220,55,55) end end
		return U.result("SIGNAL_FAILED")
	end
	self.phase=phase; self.endsAt=endsAt; return U.result("OK")
end
function World:create(v)
	if self.models[v.Id] then return U.result("DUPLICATE_VEHICLE") end
	local model=self.builders.Vehicle.create(v.Kind)
	if not model or not model:IsA("Model") then return U.result("INVALID_VEHICLE_MODEL") end
	local count=0
	for _,p in ipairs(model:GetDescendants()) do
		if not p:IsA("BasePart") or not p.Anchored or p.CanCollide or p.CanTouch or p.CanQuery
			or not G.finite(p:GetAttribute("OffsetX")) or not G.finite(p:GetAttribute("OffsetY")) or not G.finite(p:GetAttribute("OffsetZ")) then model:Destroy(); return U.result("INVALID_VEHICLE_MODEL") end
		count+=1
	end
	if count~=7 then model:Destroy(); return U.result("INVALID_VEHICLE_MODEL") end
	model.Name=v.Id; model:SetAttribute("VehicleId",v.Id); model:SetAttribute("TrafficOwned",true)
	self.models[v.Id]=model; model.Parent=self.folder
	return self:pose(v)
end
function World:pose(v)
	local model=self.models[v.Id]
	if not model or model.Parent~=self.folder then return U.result("VEHICLE_MISSING") end
	local cf=CFrame.new(v.X,v.Route.Y,v.Route.Z)*CFrame.Angles(0,v.Route.Dir==1 and 0 or math.pi,0)
	self.builders.Vehicle.pose(model,cf); model:SetAttribute("Speed",v.Speed)
	return U.result("OK")
end
function World:destroy(id)
	local model=self.models[id]; if model then model:Destroy(); self.models[id]=nil end; return U.result("OK")
end
function World:playerSample(c,t)
	local player=self.playersService:GetPlayerByUserId(c.UserId)
	if not player or c.Loaded~=true then return U.result("NO_CHARACTER") end
	local root=self.base:alive(player); local sample=self.base:observe(player,t)
	if not root or not sample or sample.invalid or sample.invalidUntil>t or sample.at~=t then return U.result("INVALID_MOVEMENT") end
	return U.result("OK",{Position=root.Position,Token=player.Character})
end
function World:safeDrop(position)
	local marker=position.Z<0 and self.north or self.south
	if not part(marker) or math.abs(marker.Position.Z)<15 then return U.result("NO_SAFE_DROP") end
	-- Markers sit exactly on the raised shop-side pavement edge. Move one stud
	-- toward the broad sidewalk, still four studs outside the road boundary.
	local p=marker.Position+Vector3.new(0,0,marker.Position.Z<0 and 1 or -1)
	local hit=workspace:Raycast(p+Vector3.new(0,3,0),Vector3.new(0,-8,0),self.params)
	if not hit or hit.Normal.Y<0.95 or (hit.Instance.Name~="Sidewalk" and hit.Instance.Name~="SideWalk") or not hit.Instance.CanCollide or not hit.Instance:IsDescendantOf(self.root)
		or math.abs(hit.Position.Y)>1 then return U.result("NO_SAFE_DROP") end
	-- Validate actual clearance for the existing 1.4-stud commodity cube.
	local center=Vector3.new(p.X,hit.Position.Y+0.8,p.Z)
	local overlap=OverlapParams.new(); overlap.FilterType=Enum.RaycastFilterType.Include; overlap.FilterDescendantsInstances={self.root}; overlap.RespectCanCollide=true
	if #workspace:GetPartBoundsInBox(CFrame.new(center),Vector3.new(1.5,1.5,1.5),overlap)>0 then return U.result("NO_SAFE_DROP") end
	return U.result("OK",CFrame.new(center))
end
function World:shutdown()
	for id in pairs(self.models) do self:destroy(id) end
	if self.folder then self.folder:Destroy(); self.folder=nil end
	return U.result("OK")
end
return World
