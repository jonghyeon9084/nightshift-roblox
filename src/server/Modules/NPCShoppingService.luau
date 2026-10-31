--!nonstrict
-- Server-owned visible visits. No ledger writes, yields, client input or timed revenue.
local C=require(game:GetService("ReplicatedStorage").NightShift.Shared.SoloStoreContract)
local U=require(script.Parent.ServerUtil)
local NPC={}; NPC.__index=NPC
local SPEED=10
local function key(c) return c.StoreId..":"..c.OwnerGeneration..":"..c.ProfileEpoch end
local function same(a,b) return a.UserId==b.UserId and key(a)==key(b) end
function NPC.new(d)
	return setmetatable({config=d.Config,bridge=d.Bridge,world=d.World,now=d.Now,newId=d.NewId,random=d.Random,
		active={},owners={},events={},closed=false,maxActive=#d.Config.World.StoreIds*d.Config.NPC.MaxActivePerStore},NPC)
end
function NPC:_event(n,kind,code)
	table.insert(self.events,{At=self.now(),NpcId=n and n.Id or false,StoreId=n and n.Context.StoreId or false,Kind=kind,Code=code or false})
	if #self.events>128 then table.remove(self.events,1) end
end
function NPC:_count(storeId,natural)
	local count=0; for _,n in pairs(self.active) do if (not storeId or n.Context.StoreId==storeId) and (not natural or not n.Offer) then count+=1 end end; return count
end
function NPC:_submit(n,kind,payload,callback)
	self.bridge.submit(kind,n.Context,payload,function(r)
		if self.closed or self.active[n.Id]~=n then return end
		callback(r)
	end)
end
function NPC:_observe(n,outcome,reason,callback)
	if not n.Offer or n.Observed then if callback then callback(U.result("OK")) end; return end
	n.Observed=true
	self:_submit(n,"ObserveOpportunity",{OpportunityId=n.Offer.OpportunityId,ArrivedAt=self.now(),Outcome=outcome,Reason=reason or false},function(r)
		if callback then callback(r) end
	end)
end
function NPC:_cancelSelection(n)
	if n.Selection then self.bridge.submit("CancelNpcSelection",n.Context,{NpcId=n.Id,SelectionId=n.Selection.SelectionId}); n.Selection=nil end
end
function NPC:_releaseCrossing(n)
	if n.Crossing then
		-- Retain the granting adapter so a registry replacement cannot leak its occupancy.
		U.call(n.Crossing,"releaseCrossing",n.Id,n.Route.CrossingId); n.Crossing=nil
	end
end
function NPC:_remove(n,reason)
	self:_observe(n,"Blocked",reason)
	self:_cancelSelection(n)
	U.call(self.world,"destroy",n.Id)
	self:_releaseCrossing(n)
	self.bridge.submit("EndNpcVisit",n.Context,{NpcId=n.Id})
	self.active[n.Id]=nil; self:_event(n,"Removed",reason)
end
function NPC:removeOwner(storeId,generation)
	for _,n in pairs(self.active) do if n.Context.StoreId==storeId and n.Context.OwnerGeneration==generation then self:_remove(n,"OWNER_LEFT") end end
	return U.result("OK")
end
function NPC:shutdown()
	self.closed=true
	for _,n in pairs(self.active) do self:_remove(n,"SESSION_CLOSED") end
	self.owners={}
	return U.result("OK")
end
function NPC:_path(n,points,after)
	n.Points=points; n.PointIndex=1; n.After=after; n.Phase="Moving"
end
function NPC:_exit(n,reason)
	self:_cancelSelection(n); n.EndReason=reason
	local path=U.call(self.world,"exitPath",n.Route,n.Position)
	if not path.Ok then self:_remove(n,reason); return end
	self:_path(n,path.Value,"Done")
end
function NPC:_target(n)
	local items=self.bridge.npcInventory(n.Context.UserId)
	local slots,seen={},{}
	for _,i in ipairs(items) do
		if (n.Offer and i.ContestHeld and i.Sku==n.Offer.Sku) or (not n.Offer and not i.ContestHeld) then
			if not seen[i.SlotId] then seen[i.SlotId]=true; table.insert(slots,i.SlotId) end
		end
	end
	table.sort(slots)
	-- Empty shops still receive a visible look and an unsatisfied departure.
	local slot=#slots>0 and slots[math.min(#slots,math.floor(self.random:NextNumber()*#slots)+1)] or self.config.Contest.ShelfSlots[1]
	local target=U.call(self.world,"shelfTarget",n.Route,slot)
	if not target.Ok then self:_remove(n,"INVALID_SHELF_PATH"); return end
	n.SlotId=slot; n.Browse=target.Value
	local path=U.call(self.world,"browsePath",n.Route,n.Position,n.Browse)
	if not path.Ok then self:_remove(n,"INVALID_SHELF_PATH"); return end
	self:_path(n,path.Value,"Browse")
end
function NPC:_arrived(n,phase)
	n.Phase=phase; n.At=self.now()
	U.call(self.world,"label",n.Id,phase,n.SlotId)
	if phase=="WaitingSignal" then return
	elseif phase=="Approach" then self:_target(n)
	elseif phase=="Browse" then
		n.BrowseReached=true
		local travel=U.call(self.world,"checkoutSeconds",n.Route,n.Browse,SPEED)
		if not travel.Ok then self:_remove(n,"INVALID_CHECKOUT_PATH"); return end
		n.ReadyAt=math.max(n.At+0.75,n.Offer and n.Offer.DueAt-travel.Value-0.25 or 0)
	elseif phase=="Checkout" then
		n.CheckoutReached=true
		n.ReadyAt=math.max(n.At+0.25,n.Offer and n.Offer.DueAt or 0)
	elseif phase=="Done" then self:_remove(n,n.EndReason or "VISIT_ENDED") end
end
function NPC:_checkout(n)
	local path=U.call(self.world,"checkoutPath",n.Route,n.Position)
	if not path.Ok then self:_remove(n,"INVALID_CHECKOUT_PATH"); return end
	self:_path(n,path.Value,"Checkout")
end
function NPC:_select(n)
	n.Phase="Selecting"; n.Attempts+=1
	self:_submit(n,"SelectNpcItems",{NpcId=n.Id,Kind=n.Kind,OpportunityId=n.Offer and n.Offer.OpportunityId or false},function(r)
		if r.Ok then
			n.Selection=U.copy(r.Value)
			U.call(self.world,"basket",n.Id,r.Value.Items,self.bridge.npcInventory(n.Context.UserId))
		else n.NoStock=r.Code end
		self:_checkout(n)
	end)
end
function NPC:_pay(n)
	n.Phase="Paying"
	if not n.Selection then
		self:_observe(n,n.NoStock=="OUT_OF_STOCK" and "Miss" or "Blocked",n.NoStock,function() self:_exit(n,n.NoStock) end)
		return
	end
	self:_observe(n,"Arrived",false,function(observed)
		if not observed.Ok then self:_exit(n,observed.Code); return end
		n.Sale=n.Sale or {TransactionId=self.newId("npc-sale"),NpcId=n.Id,Kind=n.Kind,SelectionId=n.Selection.SelectionId,
			Items=U.copy(n.Selection.Items),OpportunityId=n.Offer and n.Offer.OpportunityId or false}
		self:_submit(n,"CommitNpcSale",n.Sale,function(r)
			if r.Ok then n.Sold=true; self:_event(n,"SaleCommitted",r.Value.Units); self:_exit(n,"SOLD")
			elseif (r.Code=="STALE_ITEM" or r.Code=="STALE_SELECTION") and n.Attempts<2 and not n.Offer then
				self:_cancelSelection(n); n.Sale=nil; n.NoStock=nil; n.CheckoutReached=false
				U.call(self.world,"basket",n.Id,{},{}); self:_target(n)
			elseif (r.Code=="NOT_READY" or r.Code=="INTERNAL_ERROR") and not n.Retried then
				-- Same immutable transaction and selection; never mint a new retry payout.
				n.Retried=true; n.Phase="Checkout"; n.ReadyAt=self.now()+0.2
			else self:_exit(n,r.Code) end
		end)
	end)
end
function NPC:validate(c,id,kind,phase,opportunity)
	local n=self.active[id]
	if self.closed or not n or not same(c,n.Context) or kind~=n.Kind or (opportunity or false)~=(n.Offer and n.Offer.OpportunityId or false)
		or n.Sold or self.now()-n.Born>90 then return U.result("INVALID_NPC") end
	local valid=phase=="Browse" and n.BrowseReached and n.Phase=="Selecting"
		or phase=="Checkout" and n.BrowseReached and n.CheckoutReached and n.Phase=="Paying"
	if not valid then return U.result("INVALID_NPC") end
	local at=U.call(self.world,"at",n.Id,phase=="Browse" and n.Browse or n.Route.Checkout,0.35)
	return at.Ok and U.result("OK",{SlotId=n.SlotId}) or U.result("INVALID_NPC")
end
function NPC:_spawn(c,offer)
	if self.closed or self:_count()>=self.maxActive or self:_count(c.StoreId)>=self.config.NPC.MaxActivePerStore then return false,"NPC_CAP" end
	local route=U.call(self.world,"route",c.StoreId)
	if not route.Ok then return false,route.Code end
	local kind=offer and "Normal" or C.npcKind(self.random:NextNumber(),self.config)
	if not kind then return false,"INVALID_RNG" end
	local n={Id=self.newId("npc"),Context=U.copy(c),Kind=kind,Route=route.Value,Offer=offer,Position=route.Value.Spawn,
		Born=self.now(),LastAt=self.now(),Attempts=0,Phase="Spawn"}
	local created=U.call(self.world,"create",n.Id,kind,n.Position)
	if not created.Ok then return false,created.Code end
	self.active[n.Id]=n; self:_event(n,"Spawn",kind)
	self:_path(n,n.Route.ToWait,"WaitingSignal")
	return true
end
function NPC:_step(n,t)
	if t-n.Born>90 then self:_remove(n,"VISIT_TIMEOUT"); return end
	local dt=math.clamp(t-n.LastAt,0,0.2); n.LastAt=t
	if n.Phase=="Moving" then
		local target=n.Points[n.PointIndex]
		local moved=U.call(self.world,"move",n.Id,n.Position,target,dt*SPEED)
		if not moved.Ok then self:_remove(n,"PATH_BLOCKED"); return end
		n.Position=moved.Value.Position
		if moved.Value.Arrived then
			n.PointIndex+=1
			if n.PointIndex>#n.Points then
				if n.After=="Crossed" then self:_releaseCrossing(n); self:_path(n,n.Route.ToEntry,"Approach")
				else self:_arrived(n,n.After) end
			end
		end
	elseif n.Phase=="WaitingSignal" then
		if not n.Route.CrossingId then self:_path(n,n.Route.ToEntry,"Approach"); return end
		local traffic=self.bridge.pedestrianTraffic()
		local grant=U.call(traffic,"requestCrossing",n.Id,n.Route.CrossingId,t,n.Route.CrossingSeconds)
		if grant.Ok then n.Crossing=traffic; self:_path(n,n.Route.Crossing,"Crossed") end
	elseif n.Phase=="Browse" and t>=n.ReadyAt then self:_select(n)
	elseif n.Phase=="Checkout" and t>=n.ReadyAt then self:_pay(n) end
end
function NPC:_schedule(c,t)
	local k=key(c); local state=self.owners[k]
	if not state then state={NextAt=t+self.config.NPC.VisitMinSeconds+self.random:NextNumber()*(self.config.NPC.VisitMaxSeconds-self.config.NPC.VisitMinSeconds)}; self.owners[k]=state end
	if state.ScheduleAt and t<state.ScheduleAt then return end
	state.ScheduleAt=t+0.25
	local plan=self.bridge.activityPlan(c.UserId); local contest=plan and plan.Contest
	if contest and contest.Joined and contest.Eligible and contest.Phase=="Active" then
		-- Per-cycle tracking is bounded to four opportunities per owner.
		if state.Cycle~=contest.CycleId then state.Cycle=contest.CycleId; state.Offered={}; state.Pending={} end
		if not state.Estimate or t>=(state.EstimateRetryAt or math.huge) then
			state.Estimate=U.call(self.world,"visitSeconds",c.StoreId,SPEED)
			state.EstimateRetryAt=state.Estimate.Ok and math.huge or t+15
		end
		local estimate=state.Estimate
		for index,offset in ipairs(self.config.Contest.OpportunityOffsets) do
			local due=contest.StartsAt+offset
			if not state.Offered[index] and t>=due-(estimate.Ok and estimate.Value or 60) then
				state.Offered[index]=true
				self.bridge.submit("OfferOpportunity",c,{Index=index},function(r)
					if self.closed or self.owners[k]~=state then return end
					if r.Ok then
						local spawned,why=self:_spawn(c,r.Value)
						if not spawned then
							if why=="NPC_CAP" then state.Pending[index]=r.Value
							else self.bridge.submit("ObserveOpportunity",c,{OpportunityId=r.Value.OpportunityId,ArrivedAt=self.now(),Outcome="Blocked",Reason=why}) end
						end
					end
				end)
				break
			end
		end
		for index,offer in pairs(state.Pending) do
			local spawned,why=self:_spawn(c,offer)
			if spawned then state.Pending[index]=nil
			elseif why~="NPC_CAP" or t>=offer.DueAt then
				state.Pending[index]=nil
				self.bridge.submit("ObserveOpportunity",c,{OpportunityId=offer.OpportunityId,ArrivedAt=t,Outcome="Blocked",Reason=why})
			end
		end
	end
	if t>=state.NextAt then
		state.NextAt=t+self.config.NPC.VisitMinSeconds+self.random:NextNumber()*(self.config.NPC.VisitMaxSeconds-self.config.NPC.VisitMinSeconds)
		-- Long approaches overlap two fixed customers; both store slots belong to that
		-- opt-in round. Existing natural visits finish, then random arrivals resume after it.
		local reserved=contest and contest.Joined and contest.Eligible and (contest.Phase=="Prepare" or contest.Phase=="Active")
		if not reserved and self:_count(c.StoreId,true)<1 then local spawned,why=self:_spawn(c,false); if not spawned then self:_event(nil,"SpawnRejected",why) end end
	end
end
function NPC:tick(t)
	if self.closed then return end
	if self.NextTick and t<self.NextTick then return end
	self.NextTick=t+0.05
	local current,live={},{}
	for _,c in ipairs(self.bridge.contexts()) do if c.Loaded then current[c.UserId]=c; live[key(c)]=true end end
	for k in pairs(self.owners) do if not live[k] then self.owners[k]=nil end end
	for _,n in pairs(self.active) do
		local c=current[n.Context.UserId]
		if not c or not same(c,n.Context) then self:_remove(n,"OWNER_UNAVAILABLE") else self:_step(n,t) end
	end
	for _,id in ipairs(self.config.World.StoreIds) do for _,c in pairs(current) do if c.StoreId==id then self:_schedule(c,t) end end end
end
return NPC
