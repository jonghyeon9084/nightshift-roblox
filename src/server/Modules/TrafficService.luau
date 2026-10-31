--!nonstrict
local U=require(script.Parent.ServerUtil)
local G=require(script.Parent.TrafficGeometry)
local Traffic={}; Traffic.__index=Traffic
local MAX_SPEED,ACCEL,BRAKE,INTERVAL=18,12,16,0.05
function Traffic.new(d)
	local self=setmetatable({config=d.Config,world=d.World,bridge=d.Bridge,now=d.Now,newId=d.NewId,
		vehicles={},occupancy={},proofs={},players={},cooldown={},phase="AllRedToVehicle",endsAt=d.Now()+d.Config.Traffic.AllRedSeconds,
		last=d.Now(),revision=1,ready=false,closed=false,reason=false},Traffic)
	local layout=U.call(self.world,"layout")
	if not layout.Ok or #layout.Value.Routes~=2 or d.Config.Traffic.MaxVehicles<2 then self:fail("INVALID_TRAFFIC_LAYOUT"); return self end
	self.layout=layout.Value
	for i,r in ipairs(self.layout.Routes) do
		local v={Id=d.NewId("vehicle"),Route=r,X=r.Spawn,Speed=0,HalfLength=i==1 and 4 or 5.5,Kind=i==1 and "Compact" or "Van"}
		table.insert(self.vehicles,v)
		if not U.call(self.world,"create",v).Ok then self:fail("VEHICLE_CREATE_FAILED"); return self end
	end
	self.ready=true
	if not U.call(self.world,"signal",self.phase,self.endsAt).Ok then self:fail("SIGNAL_FAILED") end
	return self
end
function Traffic:fail(reason)
	self.ready=false; self.reason=reason; self.phase="AllRedToVehicle"; self.endsAt=self.now()
	self.revision+=1
	for _,v in ipairs(self.vehicles) do v.Speed=0 end
	U.call(self.world,"signal",self.phase,self.endsAt)
end
function Traffic:snapshot()
	return {Revision=self.revision,Signals={{CrossingId="Cross01",Phase=self.phase,PhaseEndsAt=self.endsAt,
		VehicleGo=self.ready and self.phase=="VehicleGreen",PedestrianGo=self.ready and self.phase=="Walk"}}}
end
function Traffic:_display()
	self.revision+=1
	if not U.call(self.world,"signal",self.phase,self.endsAt).Ok then self:fail("SIGNAL_FAILED"); return false end
	return true
end
function Traffic:_clear()
	for _,v in ipairs(self.vehicles) do
		if not v.Hidden and v.X*v.Route.Dir>v.Route.Stop*v.Route.Dir and v.X*v.Route.Dir<v.Route.CrossExit*v.Route.Dir then return false end
	end
	return true
end
function Traffic:_phase(t)
	if t<self.endsAt then return true end
	local cfg=self.config.Traffic; local phase,duration
	if self.phase=="VehicleGreen" then phase,duration="AllRedToWalk",cfg.AllRedSeconds
	elseif self.phase=="AllRedToWalk" then
		if not self:_clear() then self.endsAt=t+INTERVAL; return self:_display() end
		phase,duration="Walk",cfg.WalkSeconds
	elseif self.phase=="Walk" then phase,duration="AllRedToVehicle",cfg.AllRedSeconds
	else
		if next(self.occupancy) then self.endsAt=t+INTERVAL; return self:_display() end
		phase,duration="VehicleGreen",cfg.VehicleGreenSeconds
	end
	self.phase=phase; self.endsAt=t+duration
	return self:_display()
end
function Traffic:requestCrossing(id,crossing,t,seconds)
	if not self.ready or self.closed or type(id)~="string" or #id>128 or crossing~="Cross01" or not G.finite(t)
		or math.abs(self.now()-t)>0.1 or not G.finite(seconds) or seconds<=0 or seconds>self.config.Traffic.WalkSeconds then return U.result("WAIT_SIGNAL") end
	if self.occupancy[id] then return U.result("OK") end
	local n=0; for _ in pairs(self.occupancy) do n+=1 end
	if n>=16 or self.phase~="Walk" or t+seconds+0.25>self.endsAt or not self:_clear()
		or not U.call(self.world,"healthy").Ok then return U.result("WAIT_SIGNAL") end
	-- No expiry: a slow/blocked pedestrian never loses its reservation under a car.
	-- NPC cleanup removes its rig before releasing this exact reservation.
	self.occupancy[id]=crossing; return U.result("OK")
end
function Traffic:releaseCrossing(id,crossing)
	if self.occupancy[id]==crossing then self.occupancy[id]=nil end
	return U.result("OK")
end
function Traffic:_move(v,t,dt)
	local r=v.Route
	if v.Hidden then
		if t>=v.RespawnAt then
			v.X=r.Spawn; v.Speed=0; v.Hidden=false
			if not U.call(self.world,"create",v).Ok then self:fail("VEHICLE_CREATE_FAILED") end
		end
		return nil -- Never sweep from exit to spawn or collide on spawn.
	end
	local before=v.X; local distance=(r.Stop-v.X)*r.Dir
	local permitted=self.phase=="VehicleGreen" and self.endsAt-t>5 and not next(self.occupancy)
	local speed=MAX_SPEED
	if distance>=-0.0001 and not permitted then speed=math.min(speed,math.sqrt(2*BRAKE*math.max(0,distance))) end
	if v.Speed<speed then v.Speed=math.min(speed,v.Speed+ACCEL*dt) else v.Speed=math.max(speed,v.Speed-BRAKE*dt) end
	local step=v.Speed*dt
	if distance>=0 and not permitted and step>=distance then step=distance; v.Speed=0 end
	v.X+=step*r.Dir
	if (r.Exit-v.X)*r.Dir<=0 then
		v.X=r.Exit; v.Speed=0; v.Hidden=true; v.RespawnAt=t+2
		if not U.call(self.world,"destroy",v.Id).Ok then self:fail("VEHICLE_DESTROY_FAILED") end
		return nil
	end
	if not U.call(self.world,"pose",v).Ok then self:fail("VEHICLE_POSE_FAILED"); return nil end
	return before
end
function Traffic:validate(c,collision)
	local p=self.proofs[collision.CollisionId]; local t=self.now()
	if not self.ready or not p or not U.same(c,p.Context) or not U.same(collision,p.Collision)
		or t-p.At>0.25 or t<p.At then return U.result("INVALID_COLLISION") end
	local s=U.call(self.world,"playerSample",c,t)
	if not s.Ok or s.Value.Token~=p.Token or not G.road(s.Value.Position,self.layout.Zone) then return U.result("INVALID_COLLISION") end
	local a,b=s.Value.Position,collision.ServerPosition
	local delta=(a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2
	if delta>(self.config.Interaction.MaxSpeed*(t-p.At)+self.config.Interaction.MovementSlack)^2 then return U.result("INVALID_COLLISION") end
	return U.result("OK")
end
function Traffic:_contacts(v,before,samples,t)
	if v.Hidden or math.abs(v.X-before)/self.dt<self.config.Traffic.MinCollisionSpeed then return end
	for uid,s in pairs(samples) do local old=self.players[uid]
		if old and old.Token==s.Token and old.Generation==s.Context.OwnerGeneration and t-old.At<=0.25
			and G.road(old.Position,self.layout.Zone) and G.road(s.Position,self.layout.Zone)
			and (not self.cooldown[uid] or t>=self.cooldown[uid])
			and G.sweep(old.Position,s.Position,before,v.X,v.Route,v.HalfLength,self.config.Traffic.MaxCollisionDistance) then
			local safe=U.call(self.world,"safeDrop",s.Position)
			local col={CollisionId=self.newId("collision"),VehicleId=v.Id,ObservedAt=t,ServerPosition=s.Position,
				SafeDropCFrame=safe.Ok and safe.Value or false,Speed=math.abs(v.X-before)/self.dt}
			self.proofs[col.CollisionId]={Context=U.copy(s.Context),Collision=U.copy(col),At=t,Token=s.Token}
			self.cooldown[uid]=t+self.config.Traffic.CollisionCooldownSeconds -- also across different cars
			self.bridge.submit("ForceDrop",s.Context,col)
		end
	end
end
function Traffic:tick(t)
	if self.closed or not self.ready or not G.finite(t) or t-self.last<INTERVAL then return end
	self.dt=math.min(0.1,t-self.last); self.last=t
	if not U.call(self.world,"healthy").Ok then self:fail("TRAFFIC_WORLD_CHANGED"); return end
	if not self:_phase(t) then return end
	local samples={}
	for _,c in ipairs(self.bridge.contexts()) do
		local s=U.call(self.world,"playerSample",c,t)
		if s.Ok then local value=s.Value; value.Context=c; value.Generation=c.OwnerGeneration; value.At=t; samples[c.UserId]=value end
	end
	for _,v in ipairs(self.vehicles) do
		local before=self:_move(v,t,self.dt)
		if not self.ready then break end
		if before then self:_contacts(v,before,samples,t) end
	end
	self.players=samples
	for id,p in pairs(self.proofs) do if t-p.At>0.25 then self.proofs[id]=nil end end
	for uid,untilAt in pairs(self.cooldown) do if t>=untilAt then self.cooldown[uid]=nil end end
end
function Traffic:shutdown()
	if self.closed then return end
	self.closed=true; self:fail("SHUTDOWN")
	U.call(self.world,"shutdown"); self.vehicles={}; self.players={}; self.proofs={}; self.cooldown={}; self.occupancy={}
end
return Traffic
