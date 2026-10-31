--!nonstrict
local Shared=game:GetService("ReplicatedStorage").NightShift.Shared
local C=require(Shared.SoloStoreContract)
local U=require(script.Parent.ServerUtil)
local Demand={}; Demand.__index=Demand
function Demand.new(config,now,newId,stock)
	return setmetatable({config=config,now=now,newId=newId,stock=stock,cycle=false,allocations={}},Demand)
end
function Demand:prepare(cycleId,owners,rotation)
	if self.cycle and self.now()<self.cycle.EndsAt then return U.result("STALE_ACTIVITY") end
	self:releaseAllocations(self.now())
	local plan,why=C.planDemand(self.stock.Public,owners,rotation,self.config)
	if not plan then
		local targets={}; for _,sku in ipairs(self.config.Demand.Rotation[(rotation-1)%#self.config.Demand.Rotation+1]) do table.insert(targets,{Sku=sku,Required=2,Sold=0}) end
		self.waiting={CycleId=cycleId,Phase="Waiting",StartsAt=false,EndsAt=false,ReserveUntil=false,Eligible=false,Reason=why,Targets=targets,Completed=false,NextTargets={}}
		return U.result(why)
	end
	self.waiting=false
	self.allocations={}
	local now=self.now(); local starts=now+self.config.Demand.PrepareSeconds
	local cycle={CycleId=cycleId,Phase="Prepare",StartsAt=starts,EndsAt=starts+self.config.Demand.ActiveSeconds,
		ReserveUntil=starts+self.config.Demand.ReserveSeconds,Owners={},Rotation=rotation}
	for _,p in ipairs(owners) do
		local state={OwnerUserId=p.UserId,ProfileEpoch=p.ProfileEpoch,OwnerGeneration=p.OwnerGeneration,
			CycleId=cycleId,Targets={},Sold={},SeenTransactions={},SeenItems={},Completed=false,Eligible=true,Reason=false}
		cycle.Owners[p.UserId]=state
		for _,r in ipairs(plan.Rows) do
			state.Targets[r.Sku]=r.PerOwner; state.Sold[r.Sku]=0
			local id=self.newId("allocation")
			self.allocations[id]={AllocationId=id,UserId=p.UserId,ProfileEpoch=p.ProfileEpoch,OwnerGeneration=p.OwnerGeneration,
				CycleId=cycleId,Sku=r.Sku,Remaining=r.PerOwner,ReserveUntil=cycle.ReserveUntil}
		end
	end
	for _,r in ipairs(plan.Rows) do self.stock.Public[r.Sku]=r.Public end
	self.stock.Revision+=1; self.cycle=cycle
	return U.result("OK",cycle)
end
-- Pure plan; caller commits Remaining together with its order/profile transaction.
function Demand:orderAllocation(c,id,sku,n)
	local a=self.allocations[id]
	if not a or a.UserId~=c.UserId or a.ProfileEpoch~=c.ProfileEpoch or a.OwnerGeneration~=c.OwnerGeneration then return U.result("NOT_OWNER") end
	if not self.cycle or a.CycleId~=self.cycle.CycleId or self.now()>=a.ReserveUntil then return U.result("STALE_ACTIVITY") end
	if a.Sku~=sku or a.Remaining<n then return U.result("OUT_OF_STOCK") end
	return U.result("OK",a)
end
function Demand:releaseAllocations(now,userId)
	local changed=false
	for _,a in pairs(self.allocations) do
		if a.Remaining>0 and (now>=a.ReserveUntil or a.UserId==userId) then
			self.stock.Public[a.Sku]+=a.Remaining; a.Remaining=0; changed=true
		end
	end
	if changed then self.stock.Revision+=1 end
	if userId and self.cycle and self.cycle.Owners[userId] then
		self.cycle.Owners[userId].Eligible=false; self.cycle.Owners[userId].Reason="Departed"
	end
end
function Demand:refund(id,sku,n)
	local a=self.allocations[id]
	if a and self.cycle and a.CycleId==self.cycle.CycleId and self.now()<a.ReserveUntil and self.cycle.Owners[a.UserId].Eligible then a.Remaining+=n
	else self.stock.Public[sku]+=n end
	self.stock.Revision+=1
end
function Demand:recordVerifiedSale(event)
	local cy=self.cycle; local s=cy and cy.Owners[event.OwnerUserId]
	if not s or not s.Eligible or event.ProfileEpoch~=s.ProfileEpoch or event.OwnerGeneration~=s.OwnerGeneration
		or event.At<cy.StartsAt or event.At>=cy.EndsAt then return nil,false end
	return C.advanceDemand(s,event,self.config)
end
function Demand:view(c)
	local cy=self.cycle
	if self.waiting and (not cy or self.now()>=cy.EndsAt+15) then return U.copy(self.waiting) end
	if not cy then return false end
	local s=cy.Owners[c.UserId]; local targets={}
	local pair=self.config.Demand.Rotation[(cy.Rotation-1)%#self.config.Demand.Rotation+1]
	for _,sku in ipairs(pair) do table.insert(targets,{Sku=sku,Required=2,Sold=s and s.Sold[sku] or 0}) end
	return {CycleId=cy.CycleId,Phase=cy.Phase,StartsAt=cy.StartsAt,EndsAt=cy.EndsAt,ReserveUntil=cy.ReserveUntil,
		Eligible=s~=nil and s.Eligible and s.ProfileEpoch==c.ProfileEpoch,
		Reason=s and s.ProfileEpoch==c.ProfileEpoch and s.Reason or "NEXT_CYCLE",
		Targets=targets,Completed=s and s.Completed or false,NextTargets=U.copy(self.config.Demand.Rotation[cy.Rotation%#self.config.Demand.Rotation+1])}
end
return Demand
