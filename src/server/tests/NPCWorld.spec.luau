-- AABB sampled geometry against actual BuildWorld. Explicit mock, not Roblox collision QA.
local assertions=0
local function check(condition,reason) assertions+=1; assert(condition,reason) end
local root=worldBuilder.build(target)
local solids={}; for _,p in ipairs(root:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then table.insert(solids,p) end end
local function bounds(p)
	local c,s=math.abs(math.cos(p.CFrame.Yaw)),math.abs(math.sin(p.CFrame.Yaw))
	return (c*p.Size.X+s*p.Size.Z)/2,p.Size.Y/2,(s*p.Size.X+c*p.Size.Z)/2
end
local cells={}
for _,p in ipairs(solids) do local x,_,z=bounds(p)
	for ix=math.floor((p.Position.X-x)/10),math.floor((p.Position.X+x)/10) do
		for iz=math.floor((p.Position.Z-z)/10),math.floor((p.Position.Z+z)/10) do
			local key=ix..":"..iz; cells[key]=cells[key] or {}; table.insert(cells[key],p)
		end
	end
end
local function nearby(x,z,halfX,halfZ)
	local out,seen={},{}
	for ix=math.floor((x-halfX)/10),math.floor((x+halfX)/10) do for iz=math.floor((z-halfZ)/10),math.floor((z+halfZ)/10) do
		for _,p in ipairs(cells[ix..":"..iz] or {}) do if not seen[p] then seen[p]=true; table.insert(out,p) end end
	end end
	return out
end
local workspace={}
function workspace:Raycast(origin,direction)
	local best
	for _,p in ipairs(nearby(origin.X,origin.Z,0,0)) do
		local x,y,z=bounds(p); local top=p.Position.Y+y
		if math.abs(origin.X-p.Position.X)<=x+0.0001 and math.abs(origin.Z-p.Position.Z)<=z+0.0001 and top<=origin.Y and top>=origin.Y+direction.Y
			and (not best or top>best.Position.Y) then best={Instance=p,Position=vec(origin.X,top,origin.Z),Normal=vec(0,1,0)} end
	end
	return best
end
function workspace:Blockcast(cf,size,direction)
	local steps=math.max(1,math.ceil(direction.Magnitude/0.1))
	for i=0,steps do local pos=cf.Position+direction*(i/steps)
		for _,p in ipairs(nearby(pos.X,pos.Z,size.X/2,size.Z/2)) do local x,y,z=bounds(p)
			if math.abs(pos.X-p.Position.X)<x+size.X/2-0.0001 and math.abs(pos.Y-p.Position.Y)<y+size.Y/2-0.0001 and math.abs(pos.Z-p.Position.Z)<z+size.Z/2-0.0001 then
				return {Instance=p}
			end
		end
	end
end
-- ADAPTER_HERE
local adapter=NPCWorld.new(root,commerce,nil)
local function path(id,route,position,points)
	for _,goal in ipairs(points) do
		local finished=false
		for _=1,3000 do
			local result=adapter:move(id,position,goal,0.25)
			check(result.Ok,"blocked "..route.StoreId.." at "..position.X..","..position.Z.." -> "..goal.X..","..goal.Z.." "..result.Code)
			position=result.Value.Position
			check(math.abs(position.Z)>=12 or math.abs(position.X)<=1.25,"body stays within six-stud crosswalk")
			if result.Value.Arrived then finished=true; break end
		end
		check(finished,"route did not terminate")
	end
	return position
end
for _,storeId in ipairs(commerce.World.StoreIds) do
	local r=adapter:route(storeId); check(r.Ok,storeId..": "..r.Code); local route=r.Value
	check((route.Checkout-root:FindFirstChild("PedestrianPaths"):FindFirstChild(storeId):FindFirstChild("Checkout").Position).Magnitude>10,"actual counter correction")
	for _,slotId in ipairs(commerce.World.ShelfSlotIds) do
		local id=storeId..slotId; check(adapter:create(id,"Normal",route.Spawn).Ok,"create fallback")
		check(adapter.rigs[id].Model:GetAttribute("FallbackRig"),"authored fallback used")
		local p=route.Spawn
		for _,points in ipairs({route.ToWait,route.Crossing,route.ToEntry}) do p=path(id,route,p,points) end
		local target=adapter:shelfTarget(route,slotId).Value
		p=path(id,route,p,adapter:browsePath(route,p,target).Value); check(adapter:at(id,target,0.35).Ok,"at actual shelf")
		local seconds=adapter:checkoutSeconds(route,target,10).Value
		check(seconds+1<commerce.NPC.SelectionLeaseSeconds,"checkout path fits selection lease")
		check(adapter:basket(id,{{ItemId="i"}},{{ItemId="i",Sku="Water"}}).Ok,"visible bag")
		p=path(id,route,p,adapter:checkoutPath(route,p).Value); check(adapter:at(id,route.Checkout,0.35).Ok,"at actual counter")
		p=path(id,route,p,adapter:exitPath(route).Value); adapter:destroy(id); check(adapter.rigs[id]==nil,"destroy")
	end
end
adapter.builder=rigBuilder
local route=adapter:route("Store01").Value
check(adapter:create("rig","Rich",route.Spawn).Ok,"authored builder")
check(adapter.rigs.rig.Model:FindFirstChild("Hat")~=nil,"rich hat from actual builder")
check(adapter.rigs.rig.Model:GetAttribute("FallbackRig")==nil,"builder used")
adapter:destroy("rig")
adapter.builder={create=function()error("broken builder")end}
check(adapter:create("fallback","Normal",route.Spawn).Ok,"builder failure fallback")
adapter:destroy("fallback")
local marker=root:FindFirstChild("PedestrianPaths"):FindFirstChild("Store01"):FindFirstChild("CrossingEntry")
marker.CFrame=CFrame.new(8,1,0)
check(not adapter:route("Store01").Ok,"off-crosswalk marker rejected")
print("NPC WORLD PASS: "..assertions.." sampled assertions; actual BuildWorld/rig/adapter, FAKE rays/AABB; Studio=false")
