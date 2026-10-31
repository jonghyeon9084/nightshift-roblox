-- Appended after SoloServer.spec: reuse actual economic fixture, fake only geometry/traffic/time.
local startChecks=checks
local function npcFixture(units,sample)
	local f=fixture(); local c,player=f:add(1)
	if units>0 then local order=ok(f:order(c,"Water",units)); f:deliver(c,order.OrderId)
		for _,id in ipairs(order.ItemIds) do f:stock(c,id,"Slot01",true) end
	end
	local t=20; f:time(t)
	local w={rigs={},green=true,blocked=false,missing=false,occupancy={},moves=0}
	function w:route(id)
		if self.missing then return U.result("MISSING_NPC_ROUTE") end
		return U.result("OK",{StoreId=id,Spawn=0,ToWait={1},CrossingId="Cross01",Crossing={2,3},CrossingSeconds=1,ToEntry={4},Checkout=8})
	end
	function w:shelfTarget(_,slot) return U.result("OK",slot=="Slot01" and 5 or 6) end
	function w:browsePath(_,position,target) return U.result("OK",{4,target}) end
	function w:checkoutPath() return U.result("OK",{7,8}) end
	function w:exitPath() return U.result("OK",{9,10}) end
	function w:checkoutSeconds() return U.result("OK",0.6) end
	function w:visitSeconds() return U.result("OK",60) end
	function w:create(id,kind,p) self.rigs[id]={position=p,kind=kind}; return U.result("OK") end
	function w:destroy(id) self.rigs[id]=nil; return U.result("OK") end
	function w:label() return U.result("OK") end
	function w:basket(id,items) self.rigs[id].basket=#items; return U.result("OK") end
	function w:move(id,from,target,maxDistance)
		if self.blocked then return U.result("PATH_BLOCKED") end
		local rig=self.rigs[id]; if not rig or rig.position~=from then return U.result("INVALID_NPC") end
		local d=target-from; local p=math.abs(d)<=maxDistance and target or from+(d>0 and 1 or -1)*maxDistance
		rig.position=p; self.moves+=1; return U.result("OK",{Position=p,Arrived=p==target})
	end
	function w:at(id,p) return self.rigs[id] and self.rigs[id].position==p and U.result("OK") or U.result("INVALID_NPC") end
	local traffic={}
	function traffic:requestCrossing(id,crossing)
		if not w.green then return U.result("WAIT_SIGNAL") end
		w.occupancy[id]=crossing; return U.result("OK")
	end
	function traffic:releaseCrossing(id) w.occupancy[id]=nil; return U.result("OK") end
	local queue,history={},{}
	local bridge={}
	function bridge.contexts() local list={}; for _,v in pairs(f.owners.owners) do table.insert(list,U.copy(v)) end; return list end
	function bridge.npcInventory(uid)
		local result={}; local ctx=f.owners:getOwnerContext(uid); local s=ctx and f.co.stores[ctx.StoreId]
		if s then for _,i in pairs(s.Items) do if i.State=="Shelf" then table.insert(result,U.copy(i)) end end end; return result
	end
	function bridge.activityPlan(uid) local ctx=f.owners:getOwnerContext(uid); return ctx and {Contest=f.co.contest:view(ctx)} end
	function bridge.pedestrianTraffic() if w.noTraffic then return nil end; return traffic end
	function bridge.submit(kind,context,payload,callback) table.insert(queue,{kind=kind,c=U.copy(context),p=U.copy(payload),cb=callback,at=t}) end
	local rng={NextNumber=function()return sample or 0.5 end}
	local npc=NPC.new({Config=f.config,Bridge=bridge,World=w,Now=function()return t end,NewId=f.id,Random=rng})
	f.co.npcAuthority=npc
	local h={f=f,c=c,player=player,npc=npc,w=w,history=history,queue=queue}
	function h:drain()
		local batch=queue; queue={}
		for _,e in ipairs(batch) do
			f:time(e.at); local r
			if e.kind=="EndNpcVisit" then r=f.co:endNpcVisit(e.c,e.p.NpcId)
			elseif e.kind=="SelectNpcItems" then r=f.co:selectNpcItems(e.c,e.p.NpcId,e.p.Kind,e.p.OpportunityId)
			elseif e.kind=="CommitNpcSale" then r=f.co:commitNpcSale(e.c,e.p)
			elseif e.kind=="CancelNpcSelection" then r=f.co:cancelNpcSelection(e.c,e.p.NpcId,e.p.SelectionId)
			elseif e.kind=="OfferOpportunity" then r=f.co.contest:offerOpportunity(e.c,e.p.Index)
			elseif e.kind=="ObserveOpportunity" then r=f.co:observeOpportunity(e.c,e.p.OpportunityId,e.p.ArrivedAt,e.p.Outcome,e.p.Reason)
			else error("unknown command") end
			table.insert(history,{kind=e.kind,p=U.copy(e.p),r=U.copy(r),at=t})
			if self.loseAck and e.kind=="CommitNpcSale" and r.Ok then self.loseAck=false; r=U.result("INTERNAL_ERROR") end
			if e.cb then e.cb(r) end
		end
		f:time(t)
	end
	function h:step(dt) t+=dt or 0.1; self:drain(); if self.tickCommerce then f.co:tick(t) end; npc:tick(t) end
	function h:setTime(value) t=value; f:time(t) end
	function h:run(seconds) for _=1,math.ceil(seconds/0.1) do self:step() end end
	function h:untilPhase(phase)
		for _=1,150 do for _,n in pairs(npc.active) do if n.Phase==phase then return n end end; self:step() end
		error("phase not reached: "..phase)
	end
	function h:spawn(offer) local success,why=npc:_spawn(c,offer); eq(success,true,why); local n; for _,v in pairs(npc.active) do n=v end; return n end
	function h:sales() local list={}; for _,e in ipairs(history) do if e.kind=="CommitNpcSale" and e.r.Ok then table.insert(list,e) end end; return list end
	return h
end

-- Visible fake rig must traverse signal/aisle/browse/checkout; no time-only payout.
do
	local h=npcFixture(2); local n=h:spawn(); local wallet=ok(h.f.p:get(1)).Wallet
	code(h.npc:validate(h.c,n.Id,"Normal","Checkout",false),"INVALID_NPC")
	h.w.green=false; h:run(5); eq(ok(h.f.p:get(1)).Wallet,wallet); eq(n.Phase,"WaitingSignal"); eq(h.w.rigs[n.Id].position,1)
	h.w.green=true; h:untilPhase("Browse"); eq(ok(h.f.p:get(1)).Wallet,wallet); eq(n.SlotId,"Slot01")
	h:run(5); eq(#h:sales(),1); eq(h:sales()[1].r.Value.Units,1); eq(ok(h.f.p:get(1)).Wallet,wallet+7)
	eq(count(h.npc.active),0); eq(count(h.w.rigs),0); eq(count(h.w.occupancy),0); eq(h.w.moves>5,true)
end
-- Three-percent boundary and bulk limited to actual four shelf units.
for _,sample in ipairs({0,0.029999,0.03,0.999}) do
	local h=npcFixture(4,sample); local n=h:spawn(); local rich=sample<0.03
	eq(n.Kind,rich and "Rich" or "Normal"); local wallet=ok(h.f.p:get(1)).Wallet
	h:run(6); eq(#h:sales(),1); eq(h:sales()[1].r.Value.Units,rich and 4 or 1)
	eq(ok(h.f.p:get(1)).Wallet,wallet+(rich and 28 or 7)); eq(count(h.f.co.stores[h.c.StoreId].Items),rich and 0 or 3)
	local cy=h.f.co.contest.cycle; if cy then eq(cy.Owners[1].Plan,0); eq(cy.Owners[1].Diversity,0) end
end
do
	local h=npcFixture(1,0.01); h:spawn(); h:run(6); eq(h:sales()[1].r.Value.Units,1,"bulk cannot invent stock")
	local empty=npcFixture(0); empty:spawn(); local before=ok(empty.f.p:get(1)); empty:run(6)
	eq(#empty:sales(),0); eq(ok(empty.f.p:get(1)),before); eq(count(empty.npc.active),0)
end
-- Another shelf is not visible just because the NPC reached an arbitrary Browse marker.
do
	local h=npcFixture(1); local n=h:spawn(); h:untilPhase("Selecting"); n.SlotId="Slot02"
	h:run(6); eq(#h:sales(),0); eq(count(h.f.co.stores[h.c.StoreId].Items),1)
end
-- Lost acknowledgement retries the SAME transaction; core returns a receipt with no second gain.
do
	local h=npcFixture(1); h.loseAck=true; h:spawn(); local wallet=ok(h.f.p:get(1)).Wallet
	h:run(6); local sales=h:sales(); eq(#sales,2); eq(sales[1].p,sales[2].p)
	eq(ok(h.f.p:get(1)).Wallet,wallet+7); eq(count(h.f.co.stores[h.c.StoreId].Items),0)
	local committed=0; for _,e in ipairs(h.f.co.events) do if e.CustomerKind=="Normal" and e.Kind=="NpcSaleCommitted" then committed+=1 end end
	eq(committed,1,"only one economic event")
end
-- Last-item race, cancellation, expiry and independent inventory revision change.
do
	local h=npcFixture(1); h:spawn(); h:spawn(); h:run(6); eq(#h:sales(),1); eq(count(h.f.co.stores[h.c.StoreId].Items),0)
	local h=npcFixture(2); local n=h:spawn(); h:untilPhase("Checkout"); local selected=n.Selection.Items[1].ItemId
	local i=h.f.co.stores[h.c.StoreId].Items[selected]; local wallet=ok(h.f.p:get(1)).Wallet
	ok(h.f.co:action(h.c,"PickShelf",{ItemId=selected,ItemRevision=i.Revision}))
	h:run(8); eq(#h:sales(),1); eq(h:sales()[1].p.Items[1].ItemId~=selected,true); eq(ok(h.f.p:get(1)).Wallet,wallet+7)
	eq(h.f.co.stores[h.c.StoreId].Items[selected].State,"Carried")
	local h=npcFixture(1); local n=h:spawn(); h:untilPhase("Checkout"); n.ReadyAt+=11
	h:run(17); eq(#h:sales(),1,"expired selection re-browses once"); eq(count(h.f.co.stores[h.c.StoreId].Items),0)
end
-- Actual theft service finishes its hold between selection and checkout; no stolen payout.
do
	local h=npcFixture(2); local thief=h.f:add(2); h.f.config.Theft.NewOwnerProtectionSeconds=0
	ok(h.f.co:recordShiftCompletion(h.c)); ok(h.f.co:recordShiftCompletion(thief))
	local n=h:spawn(); h:untilPhase("Checkout"); n.ReadyAt+=3
	local selected=n.Selection.Items[1].ItemId; local item=h.f.co.stores[h.c.StoreId].Items[selected]
	local before=ok(h.f.p:get(1)).Wallet; local thiefBefore=ok(h.f.p:get(2)).Wallet
	ok(h.f.co:action(thief,"BeginTheft",{ItemId=selected,ItemRevision=item.Revision}))
	h.tickCommerce=true; h:run(8)
	eq(h.f.co.stores[h.c.StoreId].Items[selected].State,"TheftCarried")
	eq(h.f.co.stores[h.c.StoreId].Items[selected].OwnerUserId,1)
	eq(#h:sales(),1); eq(h:sales()[1].p.Items[1].ItemId~=selected,true)
	eq(ok(h.f.p:get(1)).Wallet,before+7); eq(ok(h.f.p:get(2)).Wallet,thiefBefore)
end
-- Owner leave/reassignment, frozen profile and shutdown cannot pay from stale callbacks.
do
	local h=npcFixture(1); h:spawn(); h:untilPhase("Selecting"); local before=ok(h.f.p:get(1)).Wallet
	h.f.game:disconnect(h.player); h.npc:removeOwner(h.c.StoreId,h.c.OwnerGeneration); h:run(2)
	eq(#h:sales(),0); eq(ok(h.f.p:get(1)).Wallet,before); eq(count(h.w.rigs),0); eq(count(h.w.occupancy),0)
	local h=npcFixture(1); h:spawn(); h:untilPhase("Checkout"); local before=ok(h.f.p:get(1)).Wallet
	ok(h.f.co:beginBarrier(h.c,"fake test shutdown")); h:run(4); eq(#h:sales(),0); eq(ok(h.f.p:get(1)).Wallet,before)
	local h=npcFixture(1); h:spawn(); h:untilPhase("Selecting"); local before=ok(h.f.p:get(1)).Wallet
	h.npc:shutdown(); h:run(2); eq(#h:sales(),0); eq(ok(h.f.p:get(1)).Wallet,before); eq(count(h.npc.active),0)
end
-- Missing traffic fails closed, green is only checked on entry, occupancy is released on abort.
do
	local h=npcFixture(1); h.w.noTraffic=true; local n=h:spawn(); h:run(6); eq(n.Phase,"WaitingSignal"); eq(#h:sales(),0)
	h.w.noTraffic=false; h:step(); eq(count(h.w.occupancy),1); h.w.green=false; h:run(6); eq(#h:sales(),1); eq(count(h.w.occupancy),0)
	local h=npcFixture(1); h:spawn(); h:untilPhase("WaitingSignal"); h:step(); eq(count(h.w.occupancy),1)
	h.w.blocked=true; h:run(1); eq(count(h.w.occupancy),0); eq(count(h.npc.active),0); eq(#h:sales(),0)
	local h=npcFixture(1); h.w.noTraffic=true; local n=h:spawn(); h:run(91); eq(h.npc.active[n.Id],nil); eq(#h:sales(),0)
end
-- Cap and cooldown: max two/store, sixteen/server; missing world never creates virtual income.
do
	local h=npcFixture(0); h:spawn(); h:spawn(); local success,why=h.npc:_spawn(h.c,false); eq(success,false); eq(why,"NPC_CAP")
	for uid=2,8 do local c=h.f:add(uid); eq(h.npc:_spawn(c,false),true); eq(h.npc:_spawn(c,false),true) end
	eq(count(h.npc.active),16); h.npc:shutdown(); eq(count(h.w.rigs),0)
	local h=npcFixture(0); h:run(18); eq(count(h.npc.active),0); h:run(1); eq(count(h.npc.active),1)
	local h=npcFixture(1); h.w.missing=true; h:run(60); eq(#h:sales(),0); eq(count(h.w.rigs),0); eq(#h.npc.events<=128,true)
end
-- Real contest scheduler: arrival follows actual checkout, not a fabricated due-time receipt.
do
	local h=npcFixture(0); h.f:time(20,true); local cy=h.f.co.demand.cycle
	ok(h.f.co:action(h.c,"SetContestParticipation",{CycleId=cy.CycleId,Participate=true}))
	ok(h.f.co.contest:start(cy.CycleId))
	h:run(122) -- first due = 20+30+90 = 140; empty stock produces a visible Miss.
	local offer=h.f.co.contest.cycle.Owners[1].Offers[1]
	eq(offer~=nil,true); eq(offer.Outcome,"Miss"); eq(math.abs(offer.ArrivedAt-offer.DueAt)<1,true)
	eq(#h:sales(),0); eq(h.f.co.contest.cycle.Owners[1].Plan,0)
	local observed=0; for _,e in ipairs(h.history) do if e.kind=="ObserveOpportunity" and e.p.OpportunityId==offer.OpportunityId then observed+=1 end end
	eq(observed,1,"one opportunity observation")
end
-- Four visible ordinary visits use the same atomic API for sales, demand and capped contest scores.
do
	local h=npcFixture(0); h.f:time(20,true); local cy=h.f.co.demand.cycle
	ok(h.f.co:action(h.c,"SetContestParticipation",{CycleId=cy.CycleId,Participate=true}))
	for index,sku in ipairs({"Water","Bread"}) do
		local order=ok(h.f:order(h.c,sku,2)); h.f:deliver(h.c,order.OrderId)
		for _,id in ipairs(order.ItemIds) do h.f:stock(h.c,id,index==1 and "Slot01" or "Slot02",true) end
	end
	h:setTime(52); ok(h.f.co.contest:start(cy.CycleId)); h:run(241)
	eq(#h:sales(),4); local state=h.f.co.contest.cycle.Owners[1]
	eq(state.Diversity,20); eq(state.Plan,40); eq(state.Logistics,30)
	eq(ok(h.f.p:get(1)).Store.Achievements.DemandCompletions,1)
	for i=1,4 do local offer=state.Offers[i]; eq(offer.Outcome,"Arrived"); eq(math.abs(offer.ArrivedAt-offer.DueAt)<=1,true) end
	for _,sale in ipairs(h:sales()) do eq(sale.r.Value.Units,1); eq(sale.p.Kind,"Normal") end
	eq(count(h.f.co.stores[h.c.StoreId].Items),0)
end
print("NPC SHOPPING PASS: "..(checks-startChecks).." assertions; actual scheduler/commerce, FAKE movement/traffic/storage; Studio=false")
