--!nonstrict
-- Solo night flow; NPC receipts are the only source of sales/progress.
local U=require(script.Parent.ServerUtil)
local Game={}; Game.__index=Game
function Game.new(d)
	return setmetatable({config=d.Config,commerceConfig=d.CommerceConfig,profiles=d.Profiles,commerce=d.Commerce,
		ownership=d.Ownership,world=d.World,now=d.Now,newId=d.NewId,users={},nights={},ready=true},Game)
end
function Game:connect(player)
	local user={id=player.UserId,player=player,name=player.DisplayName,loaded=false,profileReady=false,errorCode=false,moveAt=-math.huge,signalAt=-math.huge}
	self.users[player.UserId]=user; return user
end
function Game:profileReady(player,epoch)
	local user=self.users[player.UserId]; if not user or user.player~=player then return U.result("STALE_PROFILE") end
	local assigned=self.ownership:assignOwner(player,epoch); user.errorCode=assigned.Code
	if assigned.Ok then
		user.profileReady=true; self.world:move(player,assigned.Value.StoreId,"Spawn")
	end
	return assigned
end
function Game:context(user)
	local c=self.ownership:getOwnerContext(user.id)
	if c then c.Loaded=user.loaded; c.Active=true; local night=self.nights[user.id]; c.RoundId=night and night.RoundId or false; c.Practice=night and night.Practice or false end
	return c
end
function Game:membership(user,request)
	local c=self:context(user)
	if not c or request.StoreId~=c.StoreId then return nil,"NOT_OWNER" end
	if request.OwnerGeneration~=c.OwnerGeneration then return nil,"STALE_OWNER" end
	if request.RoundId~=c.RoundId then return nil,"STALE_ROUND" end
	local code=self.ownership:validate(c); if code~="OK" then return nil,code end
	return c,"OK"
end
function Game:commerceAction(user,request)
	local c,code=self:membership(user,request); if not c then return U.result(code) end
	return self.commerce:action(c,request.Action,request.Payload)
end
function Game:action(user,request)
	local c,code=self:membership(user,request); if not c then return U.result(code) end
	local action,p=request.Action,request.Payload; local now=self.now(); local night=self.nights[user.id]
	if action=="SetLoaded" then
		user.loaded=p.Loaded; self.ownership.owners[user.id].Loaded=p.Loaded
		if not p.Loaded then self.commerce:depart(user.id) end
		return U.result("OK")
	end
	if not user.loaded then return U.result("NOT_LOADED") end
	if not self.world:alive(user.player) then return U.result("NOT_ACTIVE") end
	if action=="TravelToEntry" or action=="Reposition" then
		if now-user.moveAt<self.config.Interaction.RepositionCooldown then return U.result("COOLDOWN") end
		user.moveAt=now; self.commerce:depart(user.id)
		return U.result(self.world:move(user.player,c.StoreId,action=="Reposition" and "Spawn" or "Entry") and "OK" or "MOVE_FAILED")
	elseif action=="SetReady" or action=="SoloPractice" then
		if night then return U.result("INVALID_STATE") end
		if action=="SetReady" and not p.Ready then return U.result("OK") end
		if p.RosterVersion~=c.OwnerGeneration then return U.result("STALE_ROSTER") end
		self.nights[user.id]={RoundId=self.newId("night"),Practice=action=="SoloPractice",Phase="Running",StartedAt=false,EndsAt=false,
			StartSales=self.commerce.stores[c.StoreId].Sales,SuccessCount=0,Outage=false,OutageDone=false,BellShown=false,Anxiety=0,Result=false}
		self.ownership.owners[user.id].Practice=action=="SoloPractice"
		return U.result("OK")
	elseif action=="AcknowledgeResult" then
		if not night or night.Phase~="Result" then return U.result("INVALID_STATE") end
		self.nights[user.id]=nil; self.ownership.owners[user.id].Practice=false; return U.result("OK")
	elseif action=="InputShape" then
		local outage=night and night.Outage
		if not outage or outage.Resolved or outage.OutageId~=p.OutageId or p.Generation~=c.OwnerGeneration then return U.result("STALE_OUTAGE") end
		local near=U.call(self.world,"check",c,{StoreId=c.StoreId,Marker="Breaker"}); if not near.Ok then return near end
		if p.Shape==outage.Shapes[outage.Progress+1] then outage.Progress+=1 else outage.Progress=0; night.Anxiety=math.min(100,night.Anxiety+10) end
		if outage.Progress==3 then outage.Resolved=true; night.OutageDone=true; self.world:setOutage(c.StoreId,false) end
		return U.result("OK")
	elseif action=="Signal" then
		if now-user.signalAt<self.config.Interaction.SignalCooldown then return U.result("COOLDOWN") end
		user.signalAt=now; user.signal={Target=p.Target,Message=p.Message,ExpiresAt=now+self.config.Interaction.SignalSeconds}
		return U.result("OK")
	end
	-- Manual legacy line sales, employee roles and support paths are retired.
	return U.result("BAD_REQUEST")
end
function Game:tick(now)
	for uid,user in pairs(self.users) do
		if user.player and user.errorCode=="STORE_FULL" and not self.ownership.owners[uid] then
			local status=self.profiles:status(uid)
			if not status.Frozen then self:profileReady(user.player,status.Epoch) end
		end
	end
	for uid,n in pairs(self.nights) do
		local c=self.ownership:getOwnerContext(uid); local store=c and self.commerce.stores[c.StoreId]
		if store and n.Phase=="Running" then
			n.SuccessCount=store.Sales-n.StartSales
			if n.SuccessCount>0 and not n.StartedAt then n.StartedAt=now; n.EndsAt=now+self.config.Round.MaxSeconds end
			if n.SuccessCount>=3 then n.BellShown=true end
			if n.SuccessCount>=2 and not n.OutageDone and not n.Outage then
				n.Outage={OutageId=self.newId("outage"),Shapes={"Circle","Triangle","Square"},Progress=0,EndsAt=now+self.config.Outage.AutoRestoreSeconds,Resolved=false}
				self.world:setOutage(c.StoreId,true)
			end
			if n.Outage and not n.Outage.Resolved and now>=n.Outage.EndsAt then n.Outage.Resolved=true; n.OutageDone=true; self.world:setOutage(c.StoreId,false) end
			if n.SuccessCount>=self.config.Round.SuccessOrders and n.OutageDone then
				local recorded=self.commerce:recordShiftCompletion(c)
				if recorded.Ok then n.Phase="Result"; n.Result={Code="AdjustedClose",Reason=false,FreeRetry=true} end
			elseif n.EndsAt and now>=n.EndsAt then
				n.Phase="Result"; n.Result={Code="Incomplete",Reason="TimeLimit",FreeRetry=true}; self.world:setOutage(c.StoreId,false)
			end
		end
	end
end
function Game:disconnect(player)
	local user=self.users[player.UserId]; if not user or user.player~=player then return nil end
	local c=self:context(user); self.commerce:depart(user.id)
	if c then
		local barrier=self.commerce:beginBarrier(c,"Disconnect")
		user.errorCode=barrier.Code
		-- Even lease loss must retire live representations. Canonical profile view already
		-- reflects every paid unit; no stale writer is allowed to overwrite cloud data.
		self.commerce:releaseOwner(c); self.world:setOutage(c.StoreId,false)
		U.call(self.world,"renderOwner",c.StoreId,"",false,0)
	end
	self.nights[user.id]=nil; user.player=nil; return c
end
function Game:nextAction(user,view,p)
	local c=self:context(user); if not p then return "WaitForProfile" end
	if not c then return "WaitForStore" end
	local n=self.nights[user.id]
	if n and n.Phase=="Result" then return "ViewResults" end
	if n and n.Outage and not n.Outage.Resolved then return "RestorePower" end
	if #view.Carry>0 then return "PlaceShelf" end
	if #view.Orders>0 then return view.Orders[1].State=="Docked" and "Unload" or "WaitForDelivery" end
	local warehouse,shelf=false,false
	for _,i in ipairs(view.Items) do warehouse=warehouse or i.State=="Warehouse" or i.State=="SafeStorage"; shelf=shelf or i.State=="Shelf" end
	if warehouse then return "Warehouse" end
	if shelf then return "WaitForCustomer" end
	if p.Wallet<4 and #view.Items==0 and p.Store.RecoveryDebt==0 then return "FreeRecovery" end
	return "GoToPC"
end
function Game:commercePacket(user,wire,now)
	-- Heartbeat's timestamp predates its queue drain; never serialize newer events as future-dated.
	now=math.max(now,self.now())
	local c=self:context(user); local got=self.profiles:get(user.id); local p=got.Ok and got.Value or nil
	local view=self.commerce:view(c); local stores={}
	for _,id in ipairs(self.commerceConfig.World.StoreIds) do local s=self.commerce.stores[id]
		table.insert(stores,{StoreId=id,OwnerUserId=s and s.OwnerUserId or false,DisplayName=s and s.DisplayName or "",
			Occupied=s~=nil,Sales=s and s.Sales or 0,Revenue=s and s.Revenue or 0,Alarm=s and U.copy(s.Alarm) or false})
	end
	wire.sequence+=1; wire.lastSend=now
	view.ProtocolVersion=2; view.Kind="Snapshot"; view.Sequence=wire.sequence; view.ServerTime=now; view.Stores=stores
	view.Self={UserId=user.id,StoreId=c and c.StoreId or false,OwnerGeneration=c and c.OwnerGeneration or 0,ProfileEpoch=c and c.ProfileEpoch or 0,
		ProfileRevision=p and p.Revision or 0,Wallet=p and p.Wallet or 0,XP=p and p.XP or 0,Level=p and p.Level or 1,DisplayName=user.name,
		RoundId=c and c.RoundId or false,Upgrades=p and U.copy(p.Store.Upgrades) or {Warehouse=0},Achievements=p and U.copy(p.Store.Achievements) or {},
		NextAction=self:nextAction(user,view,p),EquippedTool=p and p.EquippedTool or "HandCarry",UnlockedTools=p and U.copy(p.UnlockedTools) or {"HandCarry"},
		Presets=p and U.copy(p.Presets) or {},RareDiscoveries=p and U.copy(p.RareDiscoveries) or {}}
	view.CustomerEvents=self.commerce:customerEvents(c)
	view.ProfileStatus=self.profiles:status(user.id); view.ProfileStatus.ErrorCode=view.ProfileStatus.ErrorCode or (user.errorCode~="OK" and user.errorCode or false)
	view.Traffic={Revision=0,Signals={}} -- Traffic integration supplies authoritative snapshots.
	return view
end
function Game:packet(user,wire,now)
	local c=self:context(user); local n=self.nights[user.id]; wire.sequence+=1; wire.lastSend=now
	local function timer(ends) return ends and {Running=true,Remaining=math.max(0,ends-now),EndsAt=ends} or false end
	local store=false
	if c then
		store={StoreId=c.StoreId,OwnerUserId=user.id,OwnerGeneration=c.OwnerGeneration,RoundId=n and n.RoundId or false,
			Revision=self.commerce.stores[c.StoreId].Revision,RosterVersion=c.OwnerGeneration,Phase=n and n.Phase or "Lobby",Round=false,Result=n and n.Result or false,Signals=user.signal and {U.copy(user.signal)} or {}}
		if n then
			local o=n.Outage; store.Round={RoundId=n.RoundId,Mode="Solo",ActiveUserIds={user.id},ActiveCount=1,SuccessCount=n.SuccessCount,
				Anxiety=n.Anxiety,ShiftTimer=timer(n.EndsAt),Preparing=not n.StartedAt,BellShown=n.BellShown,Order=false,Recovery=false,
				OutageStatus=o and (o.Resolved and "Done" or "Active") or "Pending",Outage=o and {
					OutageId=o.OutageId,Revision=o.Progress,Generation=c.OwnerGeneration,Timer=timer(o.EndsAt),SharedShapes=U.copy(o.Shapes),
					Progress=o.Progress,CanInput=not o.Resolved,InputBlockReason=o.Resolved and "NoOutage" or "None",Resolution="Solo",Roles={}} or false}
		end
	end
	return {ProtocolVersion=2,Kind="Snapshot",Sequence=wire.sequence,ServerTime=now,
		Self={UserId=user.id,DisplayName=user.name,StoreId=c and c.StoreId or false,OwnerGeneration=c and c.OwnerGeneration or 0,
			RoundId=c and c.RoundId or false,Loaded=user.loaded,Participant=c and "Active" or "Hub",Ready=false,Carry=false,Role=false},Store=store,Stores={}}
end
function Game:ack(user,wire,request,answer)
	local c=self:context(user); local p=self.profiles:get(user.id)
	return {ProtocolVersion=2,RequestId=request.RequestId,Action=type(request.Action)=="string" and request.Action or false,Ok=answer.Ok,Code=answer.Code,Value=answer.Value or false,
		Sequence=wire.sequence,OwnerGeneration=c and c.OwnerGeneration or 0,ProfileRevision=p.Ok and p.Value.Revision or 0,RetryAfter=0}
end
return Game
