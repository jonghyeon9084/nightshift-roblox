-- Actual authored world, vehicle, signal and adapter; fake Instance/ray/overlap.
local checks=0
local function check(b,label) checks+=1; assert(b,label) end
local root=worldBuilder.build(target)
local solids={}
for _,p in ipairs(root:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then table.insert(solids,p) end end
local function extents(p)
	local c,s=math.abs(math.cos(p.CFrame.Yaw)),math.abs(math.sin(p.CFrame.Yaw))
	return (c*p.Size.X+s*p.Size.Z)/2,p.Size.Y/2,(s*p.Size.X+c*p.Size.Z)/2
end
function workspace:Raycast(origin,direction)
	local best
	for _,p in ipairs(solids) do local x,y,z=extents(p); local top=p.Position.Y+y
		if math.abs(origin.X-p.Position.X)<=x and math.abs(origin.Z-p.Position.Z)<=z and top<=origin.Y and top>=origin.Y+direction.Y
			and (not best or top>best.Position.Y) then best={Instance=p,Position=vec(origin.X,top,origin.Z),Normal=vec(0,1,0)} end
	end
	return best
end
local overlapBlocked=false
function workspace:GetPartBoundsInBox(cf,size)
	if overlapBlocked then return {root} end
	local out={}
	for _,p in ipairs(solids) do local x,y,z=extents(p)
		if math.abs(cf.Position.X-p.Position.X)<size.X/2+x and math.abs(cf.Position.Y-p.Position.Y)<size.Y/2+y
			and math.abs(cf.Position.Z-p.Position.Z)<size.Z/2+z then table.insert(out,p) end
	end
	return out
end
local base={alive=function() return {Position=vec(-100,3,-6)} end,observe=function(_,p,t) return {at=t,invalidUntil=0} end}
local player={Character=Instance.new("Model")}
local players={GetPlayerByUserId=function()return player end}
local adapter=TrafficWorld.new(root,base,{Vehicle=vehicleBuilder,Signals=signalsBuilder},players)
local layout=adapter:layout(); check(layout.Ok,"authored layout accepted"); check(#layout.Value.Routes==2,"two routes")
check(adapter:healthy().Ok,"initial markers")
for _,side in ipairs({-1,1}) do
	local safe=adapter:safeDrop(vec(10,3,side*6)); check(safe.Ok,"safe authored sidewalk floor: "..safe.Code.." side="..side)
	check(math.abs(safe.Value.Position.Z)==16,"outside road with bounded marker offset"); check(safe.Value.Position.Y>=1.04 and safe.Value.Position.Y<=1.361,"cube above authored pavement layers")
end
overlapBlocked=true; check(not adapter:safeDrop(vec(0,3,-6)).Ok,"blocked drop returns safe storage"); overlapBlocked=false
for i,route in ipairs(layout.Value.Routes) do
	local v={Id="test:"..i,Route=route,Kind=i==1 and "Compact" or "Van",X=route.Stop,Speed=0}
	check(adapter:create(v).Ok,"actual model creation"); local model=adapter.models[v.Id]
	check(#model:GetDescendants()==7,"seven authored parts")
	for _,p in ipairs(model:GetDescendants()) do check(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery,"no delivery/character physical interference") end
	local body=model:FindFirstChild("Body"); local front=v.X*route.Dir+body.Size.X/2
	check(front< -10,"front stays behind stop line")
	v.X=0; v.Speed=18; check(adapter:pose(v).Ok,"actual pose")
	check(math.abs(body.Position.X)<1e-6 and body.Position.Z==route.Z,"correct lane")
	body.CanCollide=true; check(not adapter:healthy().Ok,"changed vehicle physics fails closed"); body.CanCollide=false
	check(adapter:destroy(v.Id).Ok,"destroy model")
end
for _,phase in ipairs({"VehicleGreen","AllRedToWalk","Walk","AllRedToVehicle"}) do
	check(adapter:signal(phase,20).Ok,"actual signal apply"); check(adapter:healthy().Ok,"signal expected state")
	check(not (adapter.vehicleLamp:GetAttribute("SignalState")=="Go" and adapter.walkLamp:GetAttribute("SignalState")=="Go"),"no both green")
end
local sample=adapter:playerSample({UserId=1,Loaded=true},5); check(sample.Ok and sample.Value.Token==player.Character,"server character sample")
base.observe=function()return {invalid=true,at=5,invalidUntil=0}end
check(not adapter:playerSample({UserId=1,Loaded=true},5).Ok,"invalid motion rejected")
-- Truck path is behind each shop at z=±91; road traffic stays at z=±6.
for _,id in ipairs(commerce.World.StoreIds) do
	local store=root:FindFirstChild("Stores"):FindFirstChild(id)
	for _,p in ipairs(store:FindFirstChild("TruckRoute"):GetChildren()) do check(math.abs(p.Position.Z)>70,"delivery route disjoint from road traffic") end
end
local old=adapter.vehicleLamp.CFrame; adapter.vehicleLamp.CFrame=CFrame.new(999,8,0)
check(not adapter:healthy().Ok,"moved marker fails closed"); adapter.vehicleLamp.CFrame=old
adapter.walkLamp:SetAttribute("SignalState","Go"); check(not adapter:healthy().Ok,"changed signal fails closed")
check(adapter:signal("AllRedToVehicle",30).Ok,"restore red")
adapter:shutdown(); check(root:FindFirstChild("ServerRoadVehicles")==nil,"folder cleanup")
local missing=TrafficWorld.new(root,base,{},players); check(not missing:layout().Ok,"missing builders fail closed")
-- Service + actual world adapter + actual builders over three cycles.
local t,serial=0,0
adapter=TrafficWorld.new(root,base,{Vehicle=vehicleBuilder,Signals=signalsBuilder},players)
local traffic=Traffic.new({Config=commerce,World=adapter,Now=function()return t end,NewId=function(p)serial+=1;return p..":"..serial end,
	Bridge={contexts=function()return {}end,submit=function()error("no players")end}})
check(traffic.ready,"whole authored traffic pipeline initialized")
for i=1,2400 do t=i*0.06; traffic:tick(t); check(traffic.ready,"pipeline healthy") end
traffic:shutdown(); check(root:FindFirstChild("ServerRoadVehicles")==nil,"whole pipeline cleanup")
print("Traffic authored world / fake engine PASS "..checks.." assertions")
