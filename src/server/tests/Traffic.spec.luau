-- Appended to SoloServer tests: actual services + fake engine/time, no Studio claims.
local startChecks=checks
local function trafficFixture()
	local f=fixture(); local c=f:add(1); local t=0
	local w={models={},signals={},healthyFlag=true,position={X=-100,Y=3,Z=-6},token="character:1",sample=true,safe=true}
	function w:layout() return U.result("OK",{Zone={X=0,Z=0,HalfX=200,HalfZ=12,MinY=0,MaxY=4},Routes={
		{Id="Route01",Dir=1,Z=-6,Y=0.08,Spawn=-195,Stop=-16,CrossExit=16,Exit=195},
		{Id="Route02",Dir=-1,Z=6,Y=0.08,Spawn=195,Stop=16,CrossExit=-16,Exit=-195}}}) end
	function w:healthy() return U.result(self.healthyFlag and "OK" or "BROKEN") end
	function w:signal(phase,endsAt) self.phase=phase; self.endsAt=endsAt; table.insert(self.signals,phase); return U.result(self.badSignal and "BAD" or "OK") end
	function w:create(v) self.models[v.Id]=U.copy(v); return U.result("OK") end
	function w:pose(v) self.models[v.Id]=U.copy(v); return U.result("OK") end
	function w:destroy(id) self.models[id]=nil; return U.result("OK") end
	function w:shutdown() self.models={}; return U.result("OK") end
	function w:playerSample() return self.sample and U.result("OK",{Position=self.position,Token=self.token}) or U.result("INVALID_MOVEMENT") end
	function w:safeDrop() return self.safe and U.result("OK","fake-safe-floor") or U.result("NO_SAFE_DROP") end
	local queue,history={},{}
	local bridge={contexts=function() return {U.copy(c)} end}
	function bridge.submit(kind,ctx,col) eq(kind,"ForceDrop"); table.insert(queue,{Context=ctx,Collision=col}); table.insert(history,U.copy(col)) end
	local service=Traffic.new({Config=f.config,World=w,Bridge=bridge,Now=function() return t end,NewId=f.id})
	f.co.collisionAuthority=service
	function f:advance(value,drain)
		t=value; self:time(t)
		if drain~=false then for _,q in ipairs(queue) do q.Result=self.co:forceDrop(q.Context,q.Collision) end; queue={} end
		service:tick(t)
	end
	return f,c,w,service,history,function() return queue end
end
-- Slab sweep catches tunnelling and rejects adjacent/vertical/far points.
do
	local r={Y=0.08,Z=-6}
	eq(G.sweep({X=-10,Y=3,Z=-6},{X=10,Y=3,Z=-6},0,0,r,4,8),true)
	eq(G.sweep({X=0,Y=3,Z=17},{X=0,Y=3,Z=17},-2,2,r,5.5,8),false)
	eq(G.sweep({X=0,Y=30,Z=-6},{X=0,Y=30,Z=-6},-2,2,r,5.5,8),false)
	eq(G.sweep({X=0/0,Y=3,Z=-6},{X=0,Y=3,Z=-6},-2,2,r,4,8),false)
end
-- Three complete cycles; real service advances two opposing vehicles and stops before line.
do
	local f,c,w,s=trafficFixture(); eq(s.ready,true); eq(#s.vehicles,2)
	local phases={}; local crossed={}; local stopped={}; local wraps={}
	for step=1,2600 do local t=step*0.06
		local previous={}; for i,v in ipairs(s.vehicles) do previous[i]={X=v.X,Hidden=v.Hidden} end
		f:advance(t); phases[s.phase]=(phases[s.phase] or 0)+1
		local snapshot=s:snapshot(); eq(#snapshot.Signals,1); eq(snapshot.Signals[1].VehicleGo and snapshot.Signals[1].PedestrianGo,false)
		eq(w.phase,s.phase); eq(w.endsAt,s.endsAt)
		for i,v in ipairs(s.vehicles) do
			if not previous[i].Hidden and not v.Hidden then
				eq(math.abs(v.X-previous[i].X)<=1.801,true,"bounded speed/no warp")
				if previous[i].X*v.Route.Dir<=-16 and v.X*v.Route.Dir> -16 then eq(s.phase,"VehicleGreen","entry only green"); crossed[i]=true end
			end
			if s.phase=="Walk" then eq(v.Hidden or math.abs(v.X)>=16,true,"crosswalk empty in walk") end
			if math.abs(v.X-v.Route.Stop)<0.001 and v.Speed==0 then stopped[i]=true end
			if v.Hidden then wraps[i]=true end
		end
	end
	for _,p in ipairs({"VehicleGreen","AllRedToWalk","Walk","AllRedToVehicle"}) do eq((phases[p] or 0)>0,true,p) end
	for i=1,2 do eq(crossed[i],true); eq(stopped[i],true); eq(wraps[i],true) end
	s:shutdown(); s:shutdown(); eq(count(w.models),0); eq(count(s.proofs),0)
end
-- Red denies entry, valid grant is atomic/idempotent; late/invalid requests denied.
do
	local f,c,w,s=trafficFixture()
	code(s:requestCrossing("npc","Cross01",0,4),"WAIT_SIGNAL")
	for i=1,450 do f:advance(i*0.06) end
	eq(s.phase,"Walk"); ok(s:requestCrossing("npc","Cross01",27,4)); ok(s:requestCrossing("npc","Cross01",27,4)); eq(count(s.occupancy),1)
	code(s:requestCrossing("bad","Other",27,4),"WAIT_SIGNAL")
	code(s:requestCrossing("bad","Cross01",27,0/0),"WAIT_SIGNAL")
	code(s:requestCrossing("late","Cross01",27,12),"WAIT_SIGNAL")
	for i=451,900 do f:advance(i*0.06) end
	eq(s.phase,"AllRedToVehicle","occupant extends red beyond nominal 3 seconds")
	ok(s:releaseCrossing("npc","Other")); eq(count(s.occupancy),1)
	ok(s:releaseCrossing("npc","Cross01")); ok(s:releaseCrossing("npc","Cross01")); f:advance(54.1); eq(s.phase,"VehicleGreen")
	w.healthyFlag=false; f:advance(54.2); eq(s.ready,false); eq(s.phase,"AllRedToVehicle")
	code(s:requestCrossing("npc","Cross01",54.2,4),"WAIT_SIGNAL")
end
-- Vehicle already committed to cross extends all-red; no time-skip teleport.
do
	local f,c,w,s=trafficFixture(); s.phase="AllRedToWalk"; s.endsAt=0
	s.vehicles[1].X=0; s.vehicles[1].Speed=18
	f:advance(100); eq(s.phase,"AllRedToWalk"); eq(s.vehicles[1].X<=1.8,true)
	for i=1,30 do f:advance(100+i*0.06) end
	eq(s.phase,"Walk")
	w.badSignal=true; s.endsAt=102; f:advance(102.1); eq(s.ready,false)
end
local function prepareHit(f,w,s,t)
	w.position={X=-100,Y=3,Z=-6}
	s.phase="VehicleGreen"; s.endsAt=t+20
	s.vehicles[1].X=-106; s.vehicles[1].Speed=18
	s.players[1]={Position=U.copy(w.position),Token=w.token,Generation=1,At=t-0.06}
end
-- Actual CommerceForceDrop boundary: item moves once, wallet/XP/upgrades/total preserved.
do
	local f,c,w,s,history,queued=trafficFixture()
	local order=ok(f:order(c,"Water",1)); f:deliver(c,order.OrderId)
	local id=order.ItemIds[1]; local item=f.co.stores[c.StoreId].Items[id]
	ok(f.co:action(c,"PickCargo",{ItemId=id,ItemRevision=item.Revision}))
	local before=ok(f.p:get(c.UserId)); prepareHit(f,w,s,20); f:advance(20,false)
	eq(#history,1); local collision=history[1]
	local bad=U.copy(collision); bad.ServerPosition.X+=1; code(s:validate(c,bad),"INVALID_COLLISION")
	local result=ok(f.co:forceDrop(c,collision)); eq(result.Dropped,1); ok(f.co:forceDrop(c,collision))
	item=f.co.stores[c.StoreId].Items[id]; eq(item.State,"Recoverable"); eq(item.CarryToken,false)
	local after=ok(f.p:get(c.UserId)); eq(after.Wallet,before.Wallet); eq(after.XP,before.XP); eq(after.Store.Upgrades,before.Store.Upgrades)
	eq(#after.Store.Items,#before.Store.Items)
	f:advance(20.06); eq(#history,1,"global collision cooldown")
	w.position={X=-100,Y=3,Z=-50}; code(s:validate(c,collision),"INVALID_COLLISION","shop entry revokes proof")
	f:advance(21); code(s:validate(c,collision),"INVALID_COLLISION"); eq(count(s.proofs),0)
	f:time(46,true); eq(f.co.stores[c.StoreId].Items[id].State,"Warehouse"); f.co:tick(47); eq(count(f.co.stores[c.StoreId].Items),1)
	f:time(81,true); eq(count(f.co.collisions),0); code(f.co:forceDrop(c,collision),"INVALID_COLLISION")
end
-- Invalid movement/character swap/stationary vehicle/inside shop/respawn do not create proof.
for _,mode in ipairs({"shop","invalid","newCharacter","stationary","respawn"}) do
	local f,c,w,s,history=trafficFixture(); prepareHit(f,w,s,10)
	if mode=="shop" then w.position.Z=-50
	elseif mode=="invalid" then w.sample=false
	elseif mode=="newCharacter" then w.token="character:2"
	elseif mode=="stationary" then s.vehicles[1].X=-16; w.position.X=-16; s.players[1].Position.X=-16; s.vehicles[1].Speed=0; s.phase="Walk"
	elseif mode=="respawn" then s.vehicles[1].Hidden=true; s.vehicles[1].RespawnAt=10 end
	f:advance(10); eq(#history,0,mode)
end
-- Empty hands are a no-op; absent safe floor falls back to ledger storage, not asset deletion.
do
	local f,c,w,s,history=trafficFixture(); prepareHit(f,w,s,10); f:advance(10)
	eq(ok(f.co:forceDrop(c,history[1])).Dropped,0)
end
do
	local f,c,w,s,history=trafficFixture(); local order=ok(f:order(c,"Water",1)); f:deliver(c,order.OrderId)
	local id=order.ItemIds[1]; local item=f.co.stores[c.StoreId].Items[id]; ok(f.co:action(c,"PickCargo",{ItemId=id,ItemRevision=item.Revision}))
	w.safe=false; prepareHit(f,w,s,20); f:advance(20); eq(history[1].SafeDropCFrame,false)
	eq(ok(f.co:forceDrop(c,history[1])).SafeStorage,true); eq(f.co.stores[c.StoreId].Items[id].State,"Warehouse")
end
-- Stolen carried goods retain original owner through the real traffic authority.
do
	local f,c,w,s,history=trafficFixture(); local victim=f:add(2)
	ok(f.co:recordShiftCompletion(c)); ok(f.co:recordShiftCompletion(victim))
	local order=ok(f:order(victim,"Water",1)); f:deliver(victim,order.OrderId); f:stock(victim,order.ItemIds[1],"Slot01",true)
	local id=order.ItemIds[1]; local item=f.co.stores[victim.StoreId].Items[id]
	f:time(181); ok(f.co:action(c,"BeginTheft",{ItemId=id,ItemRevision=item.Revision})); f:time(183,true)
	eq(f.co.stores[victim.StoreId].Items[id].State,"TheftCarried")
	local a=ok(f.p:get(1)); local b=ok(f.p:get(2)); prepareHit(f,w,s,183); f:advance(183)
	ok(f.co:forceDrop(c,history[1])); item=f.co.stores[victim.StoreId].Items[id]
	eq(item.State,"Recoverable"); eq(item.OwnerUserId,2); eq(item.CarrierUserId,false)
	eq(ok(f.p:get(1)).Wallet,a.Wallet); eq(ok(f.p:get(2)).Wallet,b.Wallet)
	f:time(209,true); eq(f.co.stores[victim.StoreId].Items[id].State,"Warehouse"); eq(count(f.co.stores[c.StoreId].Items),0)
end
-- Barrier wins a queued collision; no second transient inventory survives save canonicalization.
do
	local f,c,w,s,history=trafficFixture(); local order=ok(f:order(c,"Water",1)); f:deliver(c,order.OrderId)
	local id=order.ItemIds[1]; local item=f.co.stores[c.StoreId].Items[id]; ok(f.co:action(c,"PickCargo",{ItemId=id,ItemRevision=item.Revision}))
	prepareHit(f,w,s,20); f:advance(20,false); ok(f.co:beginBarrier(c,"traffic-test"))
	code(f.co:forceDrop(c,history[1]),"PROFILE_FROZEN"); eq(f.co.stores[c.StoreId].Items[id].State,"Warehouse")
	eq(count(f.co.stores[c.StoreId].Items),1)
end
-- Real NPC state machine uses real atomic traffic grants and releases them before sale.
do
	local h=npcFixture(1); local f,c,w,s=trafficFixture(); local t=20
	h.npc.bridge.pedestrianTraffic=function()return s end
	local n=h:spawn(); local wallet=ok(h.f.p:get(1)).Wallet; local reserved=false; local waited=false
	for _=1,400 do
		t+=0.1; f:advance(t); h:step(0.1)
		if n.Phase=="WaitingSignal" then waited=true; eq(h.w.rigs[n.Id].position,1,"red waits on sidewalk") end
		if s.occupancy[n.Id] then reserved=true; eq(s.phase,"Walk","grant in walk") end
	end
	eq(waited,true); eq(reserved,true); eq(s.occupancy[n.Id],nil); eq(#h:sales(),1)
	eq(ok(h.f.p:get(1)).Wallet,wallet+7); h.npc:shutdown(); s:shutdown()
end
print("Traffic actual services / fake engine PASS "..(checks-startChecks).." assertions")
