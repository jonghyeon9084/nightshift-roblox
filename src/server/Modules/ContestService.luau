--!nonstrict
local Shared=game:GetService("ReplicatedStorage").NightShift.Shared
local C=require(Shared.SoloStoreContract)
local U=require(script.Parent.ServerUtil)
local Contest={}; Contest.__index=Contest
function Contest.new(config,now,newId) return setmetatable({config=config,now=now,newId=newId,cycle=false},Contest) end
function Contest:prepare(demand,owners)
	local cy={CycleId=demand.CycleId,Phase="Prepare",StartsAt=demand.StartsAt,EndsAt=demand.EndsAt,Owners={},Results=false,Finalized=false}
	for _,c in ipairs(owners) do
		cy.Owners[c.UserId]={OwnerUserId=c.UserId,ProfileEpoch=c.ProfileEpoch,OwnerGeneration=c.OwnerGeneration,DisplayName=c.DisplayName,
			CycleId=cy.CycleId,Joined=false,Eligible=true,Reason=false,Targets=U.copy(demand.Owners[c.UserId].Targets),
			Diversity=0,Plan=0,Logistics=0,Skus={},Sold={},Items={},Opportunities={},Offers={},Recorded=false}
	end
	self.cycle=cy
end
function Contest:setParticipation(c,id,enabled)
	local cy=self.cycle; local s=cy and cy.Owners[c.UserId]
	if not cy or id~=cy.CycleId or self.now()>=cy.StartsAt then return U.result("NEXT_CYCLE") end
	if not s or not s.Eligible or s.ProfileEpoch~=c.ProfileEpoch or s.OwnerGeneration~=c.OwnerGeneration then return U.result("NEXT_CYCLE") end
	s.Joined=enabled; return U.result("OK")
end
function Contest:start(id)
	if not self.cycle or self.cycle.CycleId~=id then return U.result("STALE_ACTIVITY") end
	if self.cycle.Phase=="Prepare" then self.cycle.Phase="Active" end
	return U.result("OK")
end
-- NPC scheduler requests the fixed intent before departure; OfferedAt is the actual scheduling time.
function Contest:offerOpportunity(c,index)
	local cy=self.cycle; local s=cy and cy.Owners[c.UserId]
	if not cy or not s or not s.Joined or not s.Eligible or s.ProfileEpoch~=c.ProfileEpoch or s.OwnerGeneration~=c.OwnerGeneration
		or self.now()<cy.StartsAt or self.now()>=cy.EndsAt or not C.integer(index,self.config.Contest.OpportunityCount,1) then return U.result("STALE_ACTIVITY") end
	if s.Offers[index] then return U.result("OK",s.Offers[index]) end
	local targets={}; for sku in pairs(s.Targets) do table.insert(targets,sku) end
	-- Preserve rotation order rather than alphabetic order.
	for _,pair in ipairs(self.config.Demand.Rotation) do if s.Targets[pair[1]] and s.Targets[pair[2]] then targets=pair; break end end
	local row={OpportunityId=self.newId("opportunity"),Index=index,CycleId=cy.CycleId,
		Sku=targets[index<=2 and 1 or 2],DueAt=cy.StartsAt+self.config.Contest.OpportunityOffsets[index],
		OfferedAt=self.now(),ArrivedAt=false,Outcome=false,Reason=false}
	s.Offers[index]=row; return U.result("OK",row)
end
function Contest:findOffer(c,id)
	local cy=self.cycle; local s=cy and cy.Owners[c.UserId]
	if not s or not s.Joined or not s.Eligible or s.ProfileEpoch~=c.ProfileEpoch or s.OwnerGeneration~=c.OwnerGeneration then return nil end
	for _,row in pairs(s.Offers) do if row.OpportunityId==id then return row end end
	return nil
end
function Contest:observeOpportunity(c,id,arrivedAt,outcome,reason)
	local row=self:findOffer(c,id)
	if not row or row.Outcome then return U.result("STALE_ACTIVITY") end
	if outcome~="Arrived" and outcome~="Miss" and outcome~="Blocked" then return U.result("BAD_REQUEST") end
	if type(arrivedAt)~="number" or arrivedAt~=arrivedAt or math.abs(self.now()-arrivedAt)>0.25 then return U.result("BAD_REQUEST") end
	row.ArrivedAt=arrivedAt; row.Outcome=outcome; row.Reason=reason or false
	return U.result("OK")
end
function Contest:recordVerifiedSale(event)
	local cy=self.cycle; local s=cy and cy.Owners[event.OwnerUserId]
	if not cy or not s or not s.Joined or not s.Eligible or event.ProfileEpoch~=s.ProfileEpoch or event.OwnerGeneration~=s.OwnerGeneration
		or event.At<cy.StartsAt or event.At>=cy.EndsAt then return nil,false end
	local offer=s.Offers[event.OpportunityIndex]
	if not offer or offer.OpportunityId~=event.OpportunityId or offer.Outcome~="Arrived" or not offer.ArrivedAt
		or math.abs(offer.ArrivedAt-offer.DueAt)>self.config.Contest.OpportunityToleranceSeconds then return nil,false end
	return C.scoreSale(s,event,self.config)
end
function Contest:depart(id)
	local s=self.cycle and self.cycle.Owners[id]; if s then s.Eligible=false; s.Reason="Departed" end
end
function Contest:finalize(id)
	local cy=self.cycle
	if not cy or cy.CycleId~=id or self.now()<cy.EndsAt then return U.result("STALE_ACTIVITY") end
	if cy.Finalized then return U.result("OK",cy.Results) end
	local participants={}; local valid=true
	for userId,s in pairs(cy.Owners) do if s.Joined then
		table.insert(participants,userId)
		if not s.Eligible then valid=false end
		for i=1,self.config.Contest.OpportunityCount do
			local o=s.Offers[i]
			if not o or not o.ArrivedAt or (o.Outcome~="Arrived" and o.Outcome~="Miss")
				or math.abs(o.ArrivedAt-o.DueAt)>self.config.Contest.OpportunityToleranceSeconds then valid=false end
		end
	end end
	table.sort(participants)
	local comparable=valid and #participants>=2
	local result={CycleId=id,Comparable=comparable,Reason=not valid and "NotComparable" or (#participants<2 and "PersonalOnly" or false),
		Participants=participants,Categories={"Diversity","Plan","Logistics"},Winners={Diversity={},Plan={},Logistics={}}}
	if comparable then for _,category in ipairs(result.Categories) do
		local best=-1
		for _,uid in ipairs(participants) do best=math.max(best,cy.Owners[uid][category]) end
		for _,uid in ipairs(participants) do if cy.Owners[uid][category]==best then table.insert(result.Winners[category],uid) end end
	end end
	cy.Finalized=true; cy.Phase="Finished"; cy.Results=result
	return U.result("OK",result)
end
function Contest:view(c)
	local cy=self.cycle; if not cy then return false end
	local s=cy.Owners[c.UserId]; local rows={}
	for uid,r in pairs(cy.Owners) do if r.Joined then table.insert(rows,{OwnerUserId=uid,DisplayName=r.DisplayName,
		Scores={Diversity=r.Diversity,Plan=r.Plan,Logistics=r.Logistics},Status=cy.Results and (cy.Results.Comparable and "Finished" or cy.Results.Reason) or (cy.Phase=="Prepare" and "Pending" or "Active")}) end end
	table.sort(rows,function(a,b) return a.OwnerUserId<b.OwnerUserId end)
	local nextAt=false
	if s and s.Joined then for i,offset in ipairs(self.config.Contest.OpportunityOffsets) do if not s.Offers[i] then nextAt=cy.StartsAt+offset; break end end end
	return {CycleId=cy.CycleId,Phase=cy.Phase,Joined=s and s.Joined or false,Eligible=s and s.Eligible or false,
		Comparable=cy.Results and cy.Results.Comparable or false,Reason=cy.Results and cy.Results.Reason or (s and s.Reason or "NEXT_CYCLE"),
		StartsAt=cy.StartsAt,EndsAt=cy.EndsAt,NextOpportunityAt=nextAt,
		Scores={Diversity=s and s.Diversity or 0,Plan=s and s.Plan or 0,Logistics=s and s.Logistics or 0},Rows=rows,Results=U.copy(cy.Results)}
end
return Contest
