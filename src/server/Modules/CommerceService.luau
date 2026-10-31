--!nonstrict
-- Sole economic writer. All methods run in Main's non-yielding queue.
local Shared=game:GetService("ReplicatedStorage").NightShift.Shared
local C=require(Shared.SoloStoreContract)
local P=require(Shared.SoloStoreProfile)
local U=require(script.Parent.ServerUtil)
local Demand=require(script.Parent.DemandGoalService)
local Contest=require(script.Parent.ContestService)
local Service={}; Service.__index=Service
local terminal={Sold=true,Recalled=true,Expired=true}
local function list(items) local out={}; for _,i in pairs(items) do table.insert(out,i) end; return out end
local function move(item,state,carrier,token,slot)
	item.State=state; item.Revision+=1; item.CarrierUserId=carrier or false; item.CarryToken=token or false
	item.SlotId=slot or false; item.DropCFrame=false; item.RecoverUntil=false
end
function Service.new(d)
	local self=setmetatable({config=d.Config,profiles=d.Profiles,now=d.Now,newId=d.NewId,world=d.World,
		stores={},owners={},restored={},selections={},receipts={},collisions={},collisionPairs={},thefts={},events={},eventCursor=0,customerCursors={},visits={},renders={},exiting={},
		stock={Public={},Revision=1,Cycle=1,NextRestockAt=d.Now()+d.Config.Wholesale.RestockSeconds},rotation=0,
		npcAuthority=d.NpcAuthority,collisionAuthority=d.CollisionAuthority},Service)
	for _,sku in ipairs(d.Config.ProductOrder) do self.stock.Public[sku]=d.Config.Products[sku].Rarity=="Basic" and d.Config.Products[sku].StockCap or 0 end
	self.demand=Demand.new(d.Config,d.Now,d.NewId,self.stock); self.contest=Contest.new(d.Config,d.Now,d.NewId)
	return self
end
function Service:setOwnership(ownership) self.ownership=ownership end
function Service:_auth(c,interactive)
	local code=self.ownership:validate(c); if code~="OK" then return code end
	local s=self.stores[c.StoreId]
	if not s or s.OwnerUserId~=c.UserId then return "NOT_OWNER" end
	if s.Frozen then return "PROFILE_FROZEN" end
	if interactive and not c.Loaded then return "NOT_LOADED" end
	if interactive and not c.Active then return "NOT_ACTIVE" end
	return "OK"
end
function Service:_check(c,target) return U.call(self.world,"check",c,target) end
function Service:_emit(kind,c,revision,extra)
	self.eventCursor+=1
	local event=U.copy(extra or {})
	-- Economic scoring uses Kind=Normal/Rich internally; wire Kind is ALWAYS the event name.
	event.CustomerKind=event.CustomerKind or ((event.Kind=="Rich" or event.Kind=="Normal") and event.Kind or nil)
	event.EventId=self.newId("event"); event.EventType=kind; event.Kind=kind; event.Cursor=self.eventCursor
	event.OwnerUserId=c.UserId; event.StoreId=c.StoreId; event.OwnerGeneration=c.OwnerGeneration
	event.ProfileEpoch=c.ProfileEpoch; event.ProfileRevision=revision; event.RoundId=c.RoundId or false; event.At=self.now()
	if C.CustomerEventKinds[kind] then
  self.customerCursors[c.StoreId]={Key=C.customerContext({UserId=c.UserId,StoreId=c.StoreId,OwnerGeneration=c.OwnerGeneration,ProfileEpoch=c.ProfileEpoch,RoundId=c.RoundId or false}),Cursor=event.Cursor}
 end
	table.insert(self.events,event); if #self.events>256 then table.remove(self.events,1) end
	return event
end
-- Bounded, owner-scoped transient notifications. No item IDs, tokens or private ledger on wire.
function Service:customerEvents(c)
 local feed={Cursor=0,Entries={}}
 if not c then return feed end
 local high=self.customerCursors[c.StoreId]
 local key=C.customerContext({UserId=c.UserId,StoreId=c.StoreId,OwnerGeneration=c.OwnerGeneration,ProfileEpoch=c.ProfileEpoch,RoundId=c.RoundId or false})
 if high and high.Key==key then feed.Cursor=high.Cursor end
 if self:_auth(c,false)~="OK" then return feed end
 for _,e in ipairs(self.events) do
  if C.CustomerEventKinds[e.Kind] and e.OwnerUserId==c.UserId and e.StoreId==c.StoreId
   and e.OwnerGeneration==c.OwnerGeneration and e.ProfileEpoch==c.ProfileEpoch and e.RoundId==(c.RoundId or false) then
   feed.Cursor=math.max(feed.Cursor,e.Cursor)
   if self.now()-e.At<=C.CustomerEventTTL then
    table.insert(feed.Entries,{EventId=e.EventId,Cursor=e.Cursor,Kind=e.Kind,CustomerKind=e.CustomerKind,
     OwnerUserId=e.OwnerUserId,StoreId=e.StoreId,OwnerGeneration=e.OwnerGeneration,ProfileEpoch=e.ProfileEpoch,
     RoundId=e.RoundId,ProfileRevision=e.ProfileRevision,At=e.At,ExpiresAt=e.At+C.CustomerEventTTL,
     NpcId=e.NpcId,Units=type(e.Units)=="table" and #e.Units or 0,Revenue=e.Revenue or 0})
   end
  end
 end
 while #feed.Entries>C.CustomerEventLimit do table.remove(feed.Entries,1) end
 return feed
end
function Service:endNpcVisit(c,npcId)
 local v=self.visits[npcId]
 if not v then return U.result("OK") end
 if self:_auth(c,false)~="OK" or v.UserId~=c.UserId or v.OwnerGeneration~=c.OwnerGeneration or v.ProfileEpoch~=c.ProfileEpoch then return U.result("STALE_OWNER") end
 self.visits[npcId]=nil
 local p=self:_profile(c)
 if p then self:_emit("NpcDeparted",c,p.Revision,{NpcId=npcId,CustomerKind=v.Kind}) end
 return U.result("OK")
end
function Service:restoreInventory(c,profile)
	local key=tostring(c.UserId)..":"..c.ProfileEpoch
	if self.restored[key] then return U.result("RESTORE_FAILED") end
	if self.stores[c.StoreId] then return U.result("STORE_FULL") end
	local valid,code=P.validateExtension(profile,self.config,C,c.UserId); if not valid then return U.result(code) end
	local stage={StoreId=c.StoreId,OwnerUserId=c.UserId,OwnerGeneration=c.OwnerGeneration,ProfileEpoch=c.ProfileEpoch,
		DisplayName=c.DisplayName,Revision=1,Items={},Orders={},Sales=0,Revenue=0,JoinedAt=self.now(),
		TheftAt=-math.huge,Alarm=false,Frozen=false,OrderCycle=self.stock.Cycle,Ordered=0,RareOrdered=0}
	local bin=0
	for _,raw in ipairs(profile.Store.Items) do
		for _,other in pairs(self.stores) do if other.Items[raw.ItemId] then return U.result("RESTORE_FAILED") end end
		local item=U.copy(raw); item.OwnerStoreId=c.StoreId; item.Revision=1; item.Quantity=1
		item.CarrierUserId=false; item.CarryToken=false; item.PurchaseCycleId=false; item.WasStolen=false
		item.BasicTool=false; item.OwnerLogisticsComplete=false; item.RecoveryLoan=false; item.Practice=false
		item.RecoverUntil=false; item.OrderId=false; item.CargoIndex=false
		if item.State=="Warehouse" then bin+=1; item.WarehouseBin=bin end
		stage.Items[item.ItemId]=item
	end
	-- World validates and creates hidden presentation staging before any live map is published.
	local staged=U.call(self.world,"stageInventory",c,list(stage.Items))
	if not staged.Ok then U.call(self.world,"discardInventoryStage",c); return U.result("RESTORE_FAILED") end
	local saved=self.profiles:mutate(c.UserId,c.ProfileEpoch,function(p) p.Store.DisplayName=c.DisplayName; return p end)
	if not saved.Ok then U.call(self.world,"discardInventoryStage",c); return saved end
	local published=U.call(self.world,"publishInventoryStage",c)
	if not published.Ok then U.call(self.world,"discardInventoryStage",c); return U.result("RESTORE_FAILED") end
	self.stores[c.StoreId]=stage; self.owners[c.UserId]=c.StoreId; self.restored[key]=true
	self:_emit("OwnerAssigned",c,saved.Value.Revision)
	return U.result("OK")
end
-- Copy-on-write proposal: profile failure cannot consume stock, change a live item or award activity.
function Service:_commit(c,fn)
	local code=self:_auth(c,false); if code~="OK" then return U.result(code) end
	local old=self.stores[c.StoreId]; local stage=U.copy(old); local payload=false; local failure="INVALID_STATE"
	local saved=self.profiles:mutate(c.UserId,c.ProfileEpoch,function(p)
		local nextP,why,value=fn(p,stage); failure=why or "INVALID_STATE"; payload=value
		if not nextP then return nil end
		local items,err=P.canonicalItems(list(stage.Items),c.UserId,nextP.Store.Upgrades.Warehouse,self.config,C)
		if not items then failure=err; return nil end
		nextP.Store.Items=items
		nextP.EconomyCursor.Sequence+=1
		return nextP
	end)
	if not saved.Ok then return U.result(saved.Code=="INVALID_STATE" and failure or saved.Code) end
	stage.Revision+=1; self.stores[c.StoreId]=stage
	for id,item in pairs(old.Items) do if not stage.Items[id] then local removed=U.copy(item); move(removed,"Sold"); self.renders[id]=removed end end
	for id,item in pairs(stage.Items) do self.renders[id]=U.copy(item) end
	self:_emit("InventoryCommitted",c,saved.Value.Revision,{Sequence=saved.Value.EconomyCursor.Sequence})
	return U.result("OK",payload),saved.Value
end
function Service:_profile(c) local p=self.profiles:get(c.UserId); return p.Ok and p.Value or nil end
function Service:_capacity(p) return self.config.Upgrades.Warehouse.Capacities[p.Store.Upgrades.Warehouse] end
function Service:_returnItem(s,item,p)
	local used={}; for _,i in pairs(s.Items) do if i.ItemId~=item.ItemId and i.State=="Warehouse" then used[i.WarehouseBin or 1]=true end end
	local bin=1; while used[bin] do bin+=1 end
	move(item,bin<=self:_capacity(p) and "Warehouse" or "SafeStorage"); item.WarehouseBin=bin
end
function Service:_carry(uid)
	local out={}; for _,s in pairs(self.stores) do for _,i in pairs(s.Items) do if i.CarrierUserId==uid then table.insert(out,i) end end end; return out
end
function Service:_find(id)
	for _,s in pairs(self.stores) do if s.Items[id] then return s.Items[id],s end end; return nil
end
function Service:_order(c,p,recovery)
	local near=self:_check(c,{StoreId=c.StoreId,Marker="OfficePC"}); if not near.Ok then return near end
	local profile=self:_profile(c); if not profile then return U.result("PROFILE_UNAVAILABLE") end
	local s=self.stores[c.StoreId]; local sku=recovery and "Water" or p.Sku; local quantity=recovery and 1 or p.Quantity
	if recovery then
		if p.ProfileRevision~=profile.Revision then return U.result("STALE_PROFILE") end
		if profile.Wallet>=self.config.Products.Water.WholesalePrice or next(s.Items) or profile.Store.RecoveryDebt~=0 then return U.result("INVALID_STATE") end
	else if p.StockRevision~=self.stock.Revision then return U.result("STALE_STOCK") end end
	if #list(s.Items)+quantity>self:_capacity(profile) then return U.result("SLOT_FULL") end
	local open=0; for _,o in pairs(s.Orders) do if o.State=="Reserved" or o.State=="InTransit" or o.State=="Docked" then open+=1 end end
	if open>=self.config.Wholesale.MaxOpenOrdersPerStore then return U.result("ORDER_LIMIT") end
	local ordered=s.OrderCycle==self.stock.Cycle and s.Ordered or 0
	local rare=s.OrderCycle==self.stock.Cycle and s.RareOrdered or 0
	local product=self.config.Products[sku]; local cost=recovery and 0 or product.WholesalePrice*quantity
	if ordered+quantity>self.config.Wholesale.MaxUnitsPerStorePerCycle or (product.Rarity=="Rare" and rare+quantity>self.config.Wholesale.MaxRareUnitsPerStorePerCycle) then return U.result("ORDER_LIMIT") end
	if profile.Wallet<cost then return U.result("INSUFFICIENT_FUNDS") end
	local allocation=false
	if not recovery and p.AllocationId then
		local plan=self.demand:orderAllocation(c,p.AllocationId,sku,quantity); if not plan.Ok then return plan end; allocation=plan.Value
	elseif self.stock.Public[sku]<quantity then return U.result("OUT_OF_STOCK") end
	local cy=self.demand.cycle; local ds=cy and cy.Owners[c.UserId]
	local purchaseCycle=not recovery and ds and ds.Eligible and ds.ProfileEpoch==c.ProfileEpoch and self.now()<cy.EndsAt and ds.Targets[sku] and cy.CycleId or false
	local contest=self.contest.cycle and self.contest.cycle.Owners[c.UserId]
	if contest and contest.Joined and purchaseCycle then
		local count=0; for _,i in pairs(s.Items) do if i.ContestHeld then count+=1 end end
		-- Includes previously sold units in this cycle, preventing extra contest purchases.
		count=math.max(count,s.ContestOrdered or 0)
		if count+quantity>self.config.Contest.OrderUnits then return U.result("ORDER_LIMIT") end
	end
	local orderId=self.newId("order"); local ids={}; for _=1,quantity do table.insert(ids,self.newId("item")) end
	local answer=self:_commit(c,function(nextP,nextS)
		nextP.Wallet-=cost; if recovery then nextP.Store.RecoveryDebt=product.WholesalePrice end
		nextS.OrderCycle=self.stock.Cycle; nextS.Ordered=ordered+quantity; nextS.RareOrdered=rare+(product.Rarity=="Rare" and quantity or 0)
		local held=contest and contest.Joined and purchaseCycle~=false or false
		if held then nextS.ContestOrdered=(nextS.ContestOrdered or 0)+quantity end
		local order={OrderId=orderId,Serial=nextS.Revision,Sku=sku,Quantity=quantity,State="Reserved",ReservedAt=self.now(),ArriveAt=false,RecallAt=false,
			UnitCost=recovery and 0 or product.WholesalePrice,AllocationId=allocation and allocation.AllocationId or false,ItemIds=ids,RecoveryLoan=recovery==true}
		nextS.Orders[orderId]=order
		for index,id in ipairs(ids) do nextS.Items[id]={ItemId=id,OwnerUserId=c.UserId,OwnerStoreId=c.StoreId,Sku=sku,Quantity=1,
			UnitCost=order.UnitCost,State="Truck",Revision=1,SlotId=false,CarrierUserId=false,CarryToken=false,OrderId=orderId,CargoIndex=index,
			PurchaseCycleId=purchaseCycle,WasStolen=false,BasicTool=true,Unloaded=false,Warehoused=false,OwnerLogisticsComplete=false,
			Practice=c.Practice==true,RecoveryLoan=recovery==true,ContestHeld=held,RecoverUntil=false} end
		return nextP,"OK",{OrderId=orderId,ItemIds=ids}
	end)
	if answer.Ok then
		if allocation then self.demand.allocations[allocation.AllocationId].Remaining-=quantity else self.stock.Public[sku]-=quantity end
		self.stock.Revision+=1
	end
	return answer
end
function Service:_cancel(c,p)
	local order=self.stores[c.StoreId].Orders[p.OrderId]
	if not order or order.State~="Reserved" or order.RecoveryLoan then return U.result("INVALID_STATE") end
	local answer=self:_commit(c,function(profile,s)
		local refund=order.UnitCost*order.Quantity
		if profile.Wallet+refund>self.config.Economy.MaxCurrency then return nil,"CURRENCY_CAP" end
		profile.Wallet+=refund; s.Orders[p.OrderId].State="Cancelled"
		for _,id in ipairs(order.ItemIds) do s.Items[id]=nil end
		return profile,"OK"
	end)
	if answer.Ok then self.demand:refund(order.AllocationId,order.Sku,order.Quantity) end
	return answer
end
function Service:_itemAction(c,action,p)
	local item=self:_find(p.ItemId)
	if not item then return U.result("NOT_FOUND") end
	if item.Revision~=p.ItemRevision then return U.result("STALE_ITEM") end
	if item.OwnerUserId~=c.UserId then return U.result("NOT_OWNER") end
	local s=self.stores[c.StoreId]
	local pick=action=="PickCargo" or action=="PickWarehouse" or action=="PickShelf"
	local target={StoreId=c.StoreId,ItemId=item.ItemId}
	if pick then
		local state=action=="PickCargo" and "Truck" or (action=="PickShelf" and "Shelf" or "Warehouse")
		if item.State~=state and not (action=="PickWarehouse" and item.State=="SafeStorage") then return U.result("INVALID_STATE") end
		if state=="Truck" and (not s.Orders[item.OrderId] or s.Orders[item.OrderId].State~="Docked") then return U.result("INVALID_STATE") end
		if item.State=="SafeStorage" then target={StoreId=c.StoreId,Marker="WarehouseDrop"} end
		local profile=self:_profile(c); local limit=profile.EquippedTool=="Handcart" and self.config.Interaction.MaxCarryWithCart or self.config.Interaction.MaxCarry
		for _,held in ipairs(self:_carry(c.UserId)) do if held.OwnerUserId~=c.UserId then return U.result("CARRY_FULL") end end
		if #self:_carry(c.UserId)>=limit then return U.result("CARRY_FULL") end
	elseif action=="RecoverItem" then
		if item.State~="Recoverable" and item.State~="TheftCarried" then return U.result("INVALID_STATE") end
	else
		if item.State~="Carried" or item.CarrierUserId~=c.UserId or item.CarryToken~=p.CarryToken then return U.result("BAD_TOKEN") end
		target={StoreId=c.StoreId,Marker=action=="DropWarehouse" and "WarehouseDrop" or nil,SlotId=p.SlotId}
	end
	local near=self:_check(c,target); if not near.Ok then return near end
	return self:_commit(c,function(profile,nextS)
		local i=nextS.Items[p.ItemId]
		if pick then
			local previous=i.State; move(i,"Carried",c.UserId,self.newId("carry"))
			i.BasicTool=i.BasicTool and profile.EquippedTool=="HandCarry"
			if previous=="Truck" then i.Unloaded=true end
		elseif action=="PlaceShelf" then
			local count=0
			for _,other in pairs(nextS.Items) do if other.State=="Shelf" and other.SlotId==p.SlotId then
				if other.Sku~=i.Sku then return nil,"SKU_MISMATCH" end; count+=1
			end end
			if count>=self.config.World.ShelfSlotCapacity then return nil,"SLOT_FULL" end
			move(i,"Shelf",nil,nil,p.SlotId); i.BasicTool=i.BasicTool and profile.EquippedTool=="HandCarry"
			i.OwnerLogisticsComplete=i.Unloaded==true and i.Warehoused==true
		else
			if action=="DropWarehouse" then
				local n=0; for _,other in pairs(nextS.Items) do if other.State=="Warehouse" then n+=1 end end
				if n>=self:_capacity(profile) then return nil,"SLOT_FULL" end
				i.Warehoused=i.Unloaded==true; i.BasicTool=i.BasicTool and profile.EquippedTool=="HandCarry"
			end
			self:_returnItem(nextS,i,profile)
		end
		return profile,"OK",{ItemId=i.ItemId,Revision=i.Revision}
	end)
end
function Service:_theft(c,p)
	local item,s=self:_find(p.ItemId); if not item then return U.result("NOT_FOUND") end
	if item.Revision~=p.ItemRevision then return U.result("STALE_ITEM") end
	if item.OwnerUserId==c.UserId or (item.State~="Shelf" and item.State~="Truck") or item.RecoveryLoan then return U.result("INVALID_STATE") end
	if item.State=="Truck" and (not s.Orders[item.OrderId] or s.Orders[item.OrderId].State~="Docked") then return U.result("INVALID_STATE") end
	local own=self.stores[c.StoreId]; local p1=self:_profile(c); local p2=self.profiles:get(item.OwnerUserId)
	if not p2.Ok or not p1.CompletedFirstShift or not p2.Value.CompletedFirstShift or self.now()-s.JoinedAt<self.config.Theft.NewOwnerProtectionSeconds
		or self.now()-own.JoinedAt<self.config.Theft.NewOwnerProtectionSeconds then return U.result("PROTECTED") end
	if self.now()-s.TheftAt<self.config.Theft.VictimCooldownSeconds then return U.result("COOLDOWN") end
	if #self:_carry(c.UserId)>0 or self.thefts[c.UserId] then return U.result("CARRY_FULL") end
	local near=self:_check(c,{StoreId=s.StoreId,ItemId=item.ItemId}); if not near.Ok then return near end
	local id=self.newId("theft")
	self.thefts[c.UserId]={TheftId=id,ItemId=item.ItemId,Revision=item.Revision,Context=U.copy(c),State="Holding",CompleteAt=self.now()+self.config.Theft.HoldSeconds}
	return U.result("OK",{TheftId=id})
end
function Service:action(c,action,p)
	local code=self:_auth(c,true); if code~="OK" then return U.result(code) end
	if action=="OrderStock" then return self:_order(c,p,false)
	elseif action=="RequestRecoveryStock" then return self:_order(c,p,true)
	elseif action=="CancelStockOrder" then return self:_cancel(c,p)
	elseif action=="BeginTheft" then return self:_theft(c,p)
	elseif action=="CancelTheft" then
		local t=self.thefts[c.UserId]; if not t or t.TheftId~=p.TheftId then return U.result("NOT_OWNER") end
		self.thefts[c.UserId]=nil; return U.result("OK")
	elseif action=="SetContestParticipation" then
		local cy=self.contest.cycle; local current=cy and cy.Owners[c.UserId]
		local purchased={}
		if p.Participate and cy and current and not current.Joined then
			for _,item in pairs(self.stores[c.StoreId].Items) do if item.PurchaseCycleId==p.CycleId and current.Targets[item.Sku] then table.insert(purchased,item) end end
			if #purchased>self.config.Contest.OrderUnits then return U.result("ORDER_LIMIT") end
		end
		local answer=self.contest:setParticipation(c,p.CycleId,p.Participate)
		if answer.Ok then
			for _,item in pairs(self.stores[c.StoreId].Items) do if item.PurchaseCycleId==p.CycleId then item.ContestHeld=p.Participate end end
			if p.Participate then self.stores[c.StoreId].ContestOrdered=math.max(self.stores[c.StoreId].ContestOrdered or 0,#purchased) end
		end
		return answer
	elseif action=="BuyUpgrade" then
		local near=self:_check(c,{StoreId=c.StoreId,Marker="OfficePC"}); if not near.Ok then return near end
		local answer,changed=self:_commit(c,function(profile)
			if p.ProfileRevision~=profile.Revision then return nil,"STALE_PROFILE" end
			local level=profile.Store.Upgrades.Warehouse; local upgrade=self.config.Upgrades.Warehouse
			if p.ExpectedLevel~=level then return nil,"STALE_UPGRADE" end
			if level>=upgrade.MaxLevel then return nil,"UPGRADE_MAX" end
			local price=upgrade.Prices[level+1]; if profile.Wallet<price then return nil,"INSUFFICIENT_FUNDS" end
			profile.Wallet-=price; profile.Store.Upgrades.Warehouse=level+1; return profile,"OK",{Level=level+1}
		end)
		if answer.Ok then self:_emit("UpgradePurchased",c,changed.Revision,{UpgradeId="Warehouse",Level=changed.Store.Upgrades.Warehouse}) end
		return answer
	elseif action=="EquipTool" or action=="SavePreset" or action=="ApplyPreset" then
		return self:_commit(c,function(profile)
			if action=="EquipTool" then
				if not table.find(profile.UnlockedTools,p.ToolId) then return nil,"LEVEL_LOCKED" end
				if #self:_carry(c.UserId)>0 then return nil,"INVALID_STATE" end
				profile.EquippedTool=p.ToolId
			else
				if profile.Level<self.config.Progression.Tools.LayoutPreset then return nil,"LEVEL_LOCKED" end
				if action=="SavePreset" then
					for index,old in ipairs(profile.Presets) do if old.Index==p.Index then table.remove(profile.Presets,index); break end end
					table.insert(profile.Presets,{Index=p.Index,Slots=U.copy(p.Slots)})
				else
					local found; for _,preset in ipairs(profile.Presets) do if preset.Index==p.Index then found=preset end end
					if not found then return nil,"PRESET_INVALID" end
					return profile,"OK",{Slots=found.Slots} -- layout guidance only; never create/move goods
				end
			end
			return profile,"OK"
		end)
	elseif table.find({"PickCargo","PickWarehouse","PickShelf","PlaceShelf","DropWarehouse","RecoverItem"},action) then return self:_itemAction(c,action,p) end
	return U.result("BAD_REQUEST")
end

-- NPC registry adapter must validate the server-owned NPC ID/path/checkout state.
-- No client-controlled flag can bypass this adapter, and a missing adapter refuses sales.
function Service:selectNpcItems(c,npcId,kind,opportunityId)
	local code=self:_auth(c,false); if code~="OK" then return U.result(code) end
	if kind~="Normal" and kind~="Rich" then return U.result("INVALID_NPC") end
	local verified=U.call(self.npcAuthority,"validate",c,npcId,kind,"Browse",opportunityId)
	if not verified.Ok then return U.result("INVALID_NPC") end
	if not self.visits[npcId] then
		self.visits[npcId]={UserId=c.UserId,OwnerGeneration=c.OwnerGeneration,ProfileEpoch=c.ProfileEpoch,Kind=kind}
		self:_emit("NpcVisited",c,self:_profile(c).Revision,{NpcId=npcId,CustomerKind=kind})
	end
	local offer=opportunityId and self.contest:findOffer(c,opportunityId)
	if opportunityId and (not offer or kind~="Normal" or offer.Outcome) then return U.result("STALE_ACTIVITY") end
	local selected={}; local sorted=list(self.stores[c.StoreId].Items); table.sort(sorted,function(a,b)return a.ItemId<b.ItemId end)
	for _,i in ipairs(sorted) do
		local reserved=false
		for _,sel in pairs(self.selections) do if not sel.Used and self.now()<sel.ExpiresAt then
			for _,unit in ipairs(sel.Items) do if unit.ItemId==i.ItemId then reserved=true end end
		end end
		if i.State=="Shelf" and (not verified.Value or not verified.Value.SlotId or i.SlotId==verified.Value.SlotId) and not reserved and ((offer and i.ContestHeld and i.PurchaseCycleId==offer.CycleId and i.Sku==offer.Sku
			and table.find(self.config.Contest.ShelfSlots,i.SlotId) and i.BasicTool and not i.WasStolen and not i.RecoveryLoan)
			or (not offer and not i.ContestHeld)) then
			table.insert(selected,{ItemId=i.ItemId,ExpectedRevision=i.Revision})
			if #selected>=(kind=="Rich" and self.config.NPC.RichMaxUnits or 1) then break end
		end
	end
	if #selected==0 then return U.result("OUT_OF_STOCK") end
	local id=self.newId("selection")
	local selection={SelectionId=id,UserId=c.UserId,StoreId=c.StoreId,OwnerGeneration=c.OwnerGeneration,ProfileEpoch=c.ProfileEpoch,
		NpcId=npcId,Kind=kind,OpportunityId=opportunityId or false,Items=selected,ExpiresAt=self.now()+self.config.NPC.SelectionLeaseSeconds,Used=false}
	self.selections[id]=selection
	return U.result("OK",selection)
end
function Service:cancelNpcSelection(c,npcId,selectionId)
	local sel=self.selections[selectionId]
	if not sel or sel.NpcId~=npcId or sel.UserId~=c.UserId or sel.ProfileEpoch~=c.ProfileEpoch or sel.OwnerGeneration~=c.OwnerGeneration then return U.result("STALE_SELECTION") end
	if not sel.Used then self.selections[selectionId]=nil end
	return U.result("OK")
end
function Service:commitNpcSale(c,sale)
	local code=self:_auth(c,false); if code~="OK" then return U.result(code) end
	if type(sale)~="table" or not C.id(sale.TransactionId) then return U.result("BAD_REQUEST") end
	local previous=self.receipts[sale.TransactionId]
	if previous then return previous.UserId==c.UserId and previous.Epoch==c.ProfileEpoch and U.same(previous.Sale,sale) and U.copy(previous.Result) or U.result("REQUEST_ID_REUSED") end
	local sel=self.selections[sale.SelectionId]
	if not sel or sel.Used or sel.UserId~=c.UserId or sel.StoreId~=c.StoreId or sel.OwnerGeneration~=c.OwnerGeneration or sel.ProfileEpoch~=c.ProfileEpoch
		or sel.NpcId~=sale.NpcId or sel.Kind~=sale.Kind or sel.OpportunityId~=sale.OpportunityId or not U.same(sel.Items,sale.Items) or self.now()>=sel.ExpiresAt then return U.result("STALE_SELECTION") end
	if not U.call(self.npcAuthority,"validate",c,sale.NpcId,sale.Kind,"Checkout",sale.OpportunityId).Ok then return U.result("INVALID_NPC") end
	local offer=sale.OpportunityId and self.contest:findOffer(c,sale.OpportunityId)
	if sale.OpportunityId and (not offer or offer.Outcome~="Arrived") then return U.result("STALE_ACTIVITY") end
	local event,ds,cs,completed,scored
	local answer,profile=self:_commit(c,function(p,s)
		local units={}; local revenue=0
		for _,unit in ipairs(sale.Items) do
			local i=s.Items[unit.ItemId]
			if not i or i.State~="Shelf" or i.Revision~=unit.ExpectedRevision then return nil,"STALE_ITEM" end
			local price=self.config.Products[i.Sku].SalePrice; revenue+=price
			table.insert(units,{ItemId=i.ItemId,Sku=i.Sku,Quantity=1,UnitPrice=price,PurchaseCycleId=i.PurchaseCycleId,
				SlotId=i.SlotId,BasicTool=i.BasicTool,OwnerLogisticsComplete=i.OwnerLogisticsComplete,Practice=i.Practice or c.Practice==true,WasStolen=i.WasStolen,RecoveryLoan=i.RecoveryLoan})
		end
		local debt=math.min(revenue,p.Store.RecoveryDebt); local delta=revenue-debt
		if p.Wallet+delta>self.config.Economy.MaxCurrency then return nil,"CURRENCY_CAP" end
		p.Wallet+=delta; p.Store.RecoveryDebt-=debt; p.XP=math.min(self.config.Progression.MaxXP,p.XP+#units*self.config.Progression.Rewards.Sale.XP)
		for _,unit in ipairs(units) do
			s.Items[unit.ItemId]=nil
			if self.config.Products[unit.Sku].Rarity=="Rare" and not table.find(p.RareDiscoveries,unit.Sku) then table.insert(p.RareDiscoveries,unit.Sku) end
		end
		s.Sales+=#units; s.Revenue+=revenue
		event={TransactionId=sale.TransactionId,NpcId=sale.NpcId,Kind=sale.Kind,OwnerUserId=c.UserId,StoreId=c.StoreId,
			OwnerGeneration=c.OwnerGeneration,ProfileEpoch=c.ProfileEpoch,Sequence=p.EconomyCursor.Sequence+1,At=self.now(),Committed=true,
			CycleId=self.demand.cycle and self.demand.cycle.CycleId or false,OpportunityId=sale.OpportunityId,
			OpportunityIndex=offer and offer.Index or false,Units=units,Revenue=revenue,DebtPaid=debt,WalletDelta=delta}
		ds,completed=self.demand:recordVerifiedSale(event); cs,scored=self.contest:recordVerifiedSale(event)
		if completed then p=C.recordAchievement(p,c.ProfileEpoch,p.ActivityCursor.Sequence+1,"Demand",nil,self.config) end
		return p,"OK",{TransactionId=sale.TransactionId,Units=#units,Revenue=revenue,DebtPaid=debt,WalletDelta=delta}
	end)
	if not answer.Ok then return answer end
	sel.Used=true
	if offer then offer.Released=true end
	if ds then self.demand.cycle.Owners[c.UserId]=ds end
	if cs then
		self.contest.cycle.Owners[c.UserId]=cs
		if offer then cs.Offers[offer.Index].Released=true end
	end
	self.receipts[sale.TransactionId]={UserId=c.UserId,Epoch=c.ProfileEpoch,Sale=U.copy(sale),Result=U.copy(answer)}
	self:_emit("NpcSaleCommitted",c,profile.Revision,event)
	if ds then self:_emit(completed and "DemandCompleted" or "DemandProgress",c,profile.Revision,{CycleId=ds.CycleId,Sold=ds.Sold}) end
	if scored then self:_emit("ContestScoreChanged",c,profile.Revision,{CycleId=cs.CycleId,Scores={Diversity=cs.Diversity,Plan=cs.Plan,Logistics=cs.Logistics}}) end
	return answer
end

function Service:forceDrop(c,collision)
	local code=self:_auth(c,false); if code~="OK" then return U.result(code) end
	if type(collision)~="table" or not C.id(collision.CollisionId) then return U.result("INVALID_COLLISION") end
	local old=self.collisions[collision.CollisionId]
	if old then return old.UserId==c.UserId and old.Generation==c.OwnerGeneration and U.same(old.Collision,collision) and U.copy(old.Result) or U.result("REQUEST_ID_REUSED") end
	if not C.id(collision.VehicleId) or type(collision.ObservedAt)~="number" or collision.ObservedAt~=collision.ObservedAt
		or math.abs(self.now()-collision.ObservedAt)>0.25 or type(collision.Speed)~="number" or collision.Speed~=collision.Speed
		or collision.Speed<self.config.Traffic.MinCollisionSpeed or collision.Speed==math.huge then return U.result("INVALID_COLLISION") end
	local pair=collision.VehicleId..":"..c.UserId
	if self.collisionPairs[pair] and self.now()-self.collisionPairs[pair]<self.config.Traffic.CollisionCooldownSeconds then return U.result("COOLDOWN") end
	if not U.call(self.collisionAuthority,"validate",c,collision).Ok then return U.result("INVALID_COLLISION") end
	local items=self:_carry(c.UserId); local contexts={}
	for _,i in ipairs(items) do local owner=self.ownership:getOwnerContext(i.OwnerUserId)
		if not owner or self:_auth(owner,false)~="OK" then return U.result("PROFILE_FROZEN") end; contexts[i.OwnerUserId]=owner
	end
	-- A carrier cannot mix stolen and owned goods; max two own cart units use one commit.
	local count=0; for _ in pairs(contexts) do count+=1 end
	if count>1 then return U.result("INVALID_STATE") end
	local response=U.result("OK",{Dropped=0,SafeStorage=false})
	for _,owner in pairs(contexts) do
		local changed
		response,changed=self:_commit(owner,function(p,s)
			for _,item in ipairs(items) do local i=s.Items[item.ItemId]
				if i.CarrierUserId~=c.UserId or (i.State~="Carried" and i.State~="TheftCarried") then return nil,"STALE_ITEM" end
				if collision.SafeDropCFrame then
					move(i,"Recoverable"); i.DropCFrame=collision.SafeDropCFrame; i.RecoverUntil=self.now()+self.config.Traffic.DropLifetimeSeconds
				else self:_returnItem(s,i,p) end
			end
			return p,"OK",{Dropped=#items,SafeStorage=not collision.SafeDropCFrame}
		end)
		if response.Ok then self:_emit("CarryDropped",owner,changed.Revision,{CarrierUserId=c.UserId,CollisionId=collision.CollisionId,Dropped=#items,SafeStorage=not collision.SafeDropCFrame}) end
	end
	if response.Ok then self.collisions[collision.CollisionId]={UserId=c.UserId,Generation=c.OwnerGeneration,At=self.now(),Collision=U.copy(collision),Result=U.copy(response)}; self.collisionPairs[pair]=self.now() end
	return response
end
function Service:depart(userId)
	self.thefts[userId]=nil
	for _,s in pairs(self.stores) do
		local affected=false; for _,i in pairs(s.Items) do if i.CarrierUserId==userId then affected=true end end
		if affected then local c=self.ownership:getOwnerContext(s.OwnerUserId)
			if c then self:_commit(c,function(p,nextS)
				for _,i in pairs(nextS.Items) do if i.CarrierUserId==userId then self:_returnItem(nextS,i,p) end end
				return p,"OK"
			end) end
		end
	end
end
function Service:beginBarrier(c,reason)
	local code=self:_auth(c,false); if code~="OK" then return U.result(code) end
	local answer=self:_commit(c,function(p,s)
		local canonical=P.canonicalItems(list(s.Items),c.UserId,p.Store.Upgrades.Warehouse,self.config,C)
		if not canonical then return nil,"PROFILE_CORRUPT" end
		for _,item in ipairs(canonical) do local i=s.Items[item.ItemId]; move(i,item.State,nil,nil,item.SlotId) end
		local bin=0; for _,i in pairs(s.Items) do if i.State=="Warehouse" then bin+=1; i.WarehouseBin=bin end end
		for _,o in pairs(s.Orders) do if o.State~="Cancelled" then o.State="Completed" end end
		return p,"OK"
	end)
	if not answer.Ok then return answer end
	self.demand:releaseAllocations(self.now(),c.UserId); self.contest:depart(c.UserId)
	self.stores[c.StoreId].Frozen=true
	for id,sel in pairs(self.selections) do if sel.UserId==c.UserId then self.selections[id]=nil end end
	for id,t in pairs(self.thefts) do local i=self:_find(t.ItemId); if id==c.UserId or (i and i.OwnerUserId==c.UserId) then self.thefts[id]=nil end end
	return self.profiles:beginBarrier(c.UserId,reason)
end
function Service:releaseOwner(c)
 local s=self.stores[c.StoreId]
 if not s or s.OwnerGeneration~=c.OwnerGeneration or s.OwnerUserId~=c.UserId or s.ProfileEpoch~=c.ProfileEpoch then return U.result("STALE_OWNER") end
 self.customerCursors[c.StoreId]=nil
 for id,v in pairs(self.visits) do if v.UserId==c.UserId then self.visits[id]=nil end end
 for i=#self.events,1,-1 do if self.events[i].OwnerUserId==c.UserId then table.remove(self.events,i) end end
	self.demand:releaseAllocations(self.now(),c.UserId); self.contest:depart(c.UserId)
	for id,sel in pairs(self.selections) do if sel.UserId==c.UserId then self.selections[id]=nil end end
	for id,i in pairs(s.Items) do local gone=U.copy(i); move(gone,"Sold"); self.renders[id]=gone end
	for id in pairs(s.Orders) do U.call(self.world,"destroyTruck",id); self.exiting[id]=nil end
	self.stores[c.StoreId]=nil; self.owners[c.UserId]=nil
	for id,r in pairs(self.receipts) do if r.UserId==c.UserId then self.receipts[id]=nil end end
	for id,r in pairs(self.collisions) do if r.UserId==c.UserId then self.collisions[id]=nil end end
	return self.ownership:releaseOwner(c.UserId,c.OwnerGeneration)
end
function Service:_releaseOpportunityStock(c,offer)
	if offer.Released then return end
	local s=self.stores[c.StoreId]; if not s then return end
	local items=list(s.Items); table.sort(items,function(a,b)return a.ItemId<b.ItemId end)
	for _,i in ipairs(items) do if i.ContestHeld and i.PurchaseCycleId==offer.CycleId and i.Sku==offer.Sku then i.ContestHeld=false; break end end
	offer.Released=true
end
function Service:observeOpportunity(c,id,at,outcome,reason)
	local answer=self.contest:observeOpportunity(c,id,at,outcome,reason)
	if answer.Ok and outcome~="Arrived" then self:_releaseOpportunityStock(c,self.contest:findOffer(c,id)) end
	return answer
end
function Service:recordShiftCompletion(c)
	return self:_commit(c,function(p) p.CompletedFirstShift=true; return p,"OK" end)
end
function Service:_deliver(c,now)
	local s=self.stores[c.StoreId]
	local ordered={}; for id in pairs(s.Orders) do table.insert(ordered,id) end
	table.sort(ordered,function(a,b) return s.Orders[a].Serial<s.Orders[b].Serial end)
	for _,id in ipairs(ordered) do
		s=self.stores[c.StoreId]; local o=s.Orders[id]
		if o.State=="Reserved" then
			local active=false; for _,other in pairs(s.Orders) do if other.State=="InTransit" or other.State=="Docked" then active=true end end
			for _,exit in pairs(self.exiting) do if exit.StoreId==c.StoreId then active=true end end
			if not active then
				local created=U.call(self.world,"createTruck",id,c.StoreId)
				if created.Ok then o.State="InTransit"; o.DispatchAt=now; o.ArriveAt=now+self.config.Delivery.TravelSeconds
				else self:_settleOrder(c,id,"DELIVERY_FAILED") end
			end
		elseif o.State=="InTransit" then
			local moved=U.call(self.world,"moveTruck",id,"ApproachToDock",math.clamp((now-o.DispatchAt)/self.config.Delivery.TravelSeconds,0,1))
			if not moved.Ok then self:_settleOrder(c,id,"DELIVERY_FAILED")
			elseif now>=o.ArriveAt then o.State="Docked"; o.RecallAt=now+self.config.Delivery.DockSeconds end
		elseif o.State=="Docked" then
			local remaining=false; for _,itemId in ipairs(o.ItemIds) do local i=s.Items[itemId]; if i and i.State=="Truck" then remaining=true end end
			if not remaining or now>=o.RecallAt then self:_settleOrder(c,id,false) end
		end
	end
end
function Service:_settleOrder(c,id,reason)
	local answer=self:_commit(c,function(p,s)
		local o=s.Orders[id]; if not o or o.State=="Completed" or o.State=="Cancelled" then return nil,"INVALID_STATE" end
		for _,itemId in ipairs(o.ItemIds) do local i=s.Items[itemId]; if i and i.State=="Truck" then self:_returnItem(s,i,p) end end
		o.State="Completed"; o.ErrorCode=reason; return p,"OK"
	end)
	if answer.Ok then
		if reason then U.call(self.world,"destroyTruck",id)
		else self.exiting[id]={StoreId=c.StoreId,At=self.now()} end
		if reason then local contest=self.contest.cycle and self.contest.cycle.Owners[c.UserId]; if contest then contest.Eligible=false; contest.Reason=reason end end
	end
	return answer
end
function Service:tick(now)
	-- Recent retries retain their response; expired proofs cannot authorize an old ID again.
	for id,r in pairs(self.collisions) do if r.At and now-r.At>60 then self.collisions[id]=nil end end
	for pair,at in pairs(self.collisionPairs) do if now-at>self.config.Traffic.CollisionCooldownSeconds then self.collisionPairs[pair]=nil end end
	self.demand:releaseAllocations(now)
	for id,exit in pairs(self.exiting) do
		local alpha=math.clamp((now-exit.At)/self.config.Delivery.ExitSeconds,0,1)
		local moved=U.call(self.world,"moveTruck",id,"DockToExit",alpha)
		if alpha>=1 or not moved.Ok then U.call(self.world,"destroyTruck",id); self.exiting[id]=nil end
	end
	if now>=self.stock.NextRestockAt then
		self.stock.Cycle+=1; self.stock.NextRestockAt=now+self.config.Wholesale.RestockSeconds
		for sku,product in pairs(self.config.Products) do
			local reserved=0; for _,a in pairs(self.demand.allocations) do if a.Sku==sku then reserved+=a.Remaining end end
			if product.Rarity=="Basic" then self.stock.Public[sku]=math.max(self.stock.Public[sku],product.StockCap-reserved) end
		end
		if self.stock.Cycle%self.config.Wholesale.RareEveryRestocks==0 then
			local rotation=self.config.Wholesale.RareRotation; local sku=rotation[(math.floor(self.stock.Cycle/self.config.Wholesale.RareEveryRestocks)-1)%#rotation+1]
			self.stock.Public[sku]=self.config.Products[sku].StockCap
		end
		self.stock.Revision+=1
	end
	for _,c in pairs(self.ownership.owners) do if self:_auth(c,false)=="OK" then self:_deliver(c,now) end end
	for uid,t in pairs(self.thefts) do if now>=t.CompleteAt then
		self.thefts[uid]=nil; local i,s=self:_find(t.ItemId); local c=t.Context
		if i and i.Revision==t.Revision and (i.State=="Shelf" or i.State=="Truck") and self:_auth(c,true)=="OK" and #self:_carry(uid)==0
			and now-s.TheftAt>=self.config.Theft.VictimCooldownSeconds and self:_check(c,{StoreId=s.StoreId,ItemId=i.ItemId}).Ok then
			local owner=self.ownership:getOwnerContext(i.OwnerUserId)
			if owner then self:_commit(owner,function(p,nextS)
				local item=nextS.Items[i.ItemId]; move(item,"TheftCarried",uid,self.newId("carry")); item.WasStolen=true
				item.RecoverUntil=now+self.config.Theft.RecoverSeconds; nextS.TheftAt=now
				nextS.Alarm={ItemId=i.ItemId,RecoverUntil=item.RecoverUntil,EndsAt=now+self.config.Theft.AlarmSeconds}
				return p,"OK"
			end) end
		end
	end end
	for _,c in pairs(self.ownership.owners) do if self:_auth(c,false)=="OK" then
		local s=self.stores[c.StoreId]; local expired=false
		for _,i in pairs(s.Items) do if i.RecoverUntil and now>=i.RecoverUntil then expired=true end end
		if expired then self:_commit(c,function(p,nextS)
			for _,i in pairs(nextS.Items) do if i.RecoverUntil and now>=i.RecoverUntil then self:_returnItem(nextS,i,p) end end
			return p,"OK"
		end) end
		if s.Alarm and now>=s.Alarm.EndsAt then s.Alarm=false end
	end end
	local cy=self.demand.cycle
	if self.contest.cycle then for uid,s in pairs(self.contest.cycle.Owners) do
		local c=self.ownership:getOwnerContext(uid)
		if c and c.ProfileEpoch==s.ProfileEpoch then for _,offer in pairs(s.Offers) do
			if not offer.Released and now>offer.DueAt+self.config.Contest.OpportunityToleranceSeconds then self:_releaseOpportunityStock(c,offer) end
		end end
	end end
	if cy and now>=cy.StartsAt and cy.Phase=="Prepare" then cy.Phase="Active"; self.contest:start(cy.CycleId) end
	if cy and now>=cy.EndsAt then
		cy.Phase="Finished"; local finalized=self.contest:finalize(cy.CycleId)
		if finalized.Ok then
			for uid,s in pairs(self.contest.cycle.Owners) do if s.Joined and not s.Recorded then
				local c=self.ownership:getOwnerContext(uid)
				if finalized.Value.Reason=="NotComparable" or not c or c.ProfileEpoch~=s.ProfileEpoch then s.Recorded=true
				else
					local done=self:_commit(c,function(p) return C.recordAchievement(p,c.ProfileEpoch,p.ActivityCursor.Sequence+1,"Contest",s,self.config) end)
					if done.Ok then s.Recorded=true end
				end
			end end
		end
		for _,s in pairs(self.stores) do for _,i in pairs(s.Items) do i.ContestHeld=false end end
	end
	-- Allow a result interval, then attempt the next fixed roster/rotation.
	local pendingRecord=false
	if self.contest.cycle and self.contest.cycle.Finalized then
		for _,s in pairs(self.contest.cycle.Owners) do if s.Joined and not s.Recorded then pendingRecord=true end end
	end
	if not cy or (now>=cy.EndsAt+15 and not pendingRecord) then
		local owners={}
		for _,id in ipairs(self.config.World.StoreIds) do local s=self.stores[id]
			if s then local c=self.ownership:getOwnerContext(s.OwnerUserId)
				if c and c.Loaded and self:_auth(c,false)=="OK" then local p=self:_profile(c); local row=U.copy(c); row.Wallet=p.Wallet; table.insert(owners,row) end
			end
		end
		if #owners>0 and (not self.prepareRetryAt or now>=self.prepareRetryAt) then
			self.prepareRetryAt=now+5
			local prepared=self.demand:prepare(self.newId("cycle"),owners,self.rotation+1)
			if prepared.Ok then
				self.rotation+=1; self.contest:prepare(self.demand.cycle,owners)
				for _,s in pairs(self.stores) do s.ContestOrdered=0 end
			end
		end
	end
	for id,sel in pairs(self.selections) do if now>sel.ExpiresAt+30 then self.selections[id]=nil end end
end
function Service:flushPresentation()
	for id,item in pairs(self.renders) do if U.call(self.world,"renderItem",item).Ok then self.renders[id]=nil end end
	for id,s in pairs(self.stores) do
		U.call(self.world,"setAlarm",id,s.Alarm); U.call(self.world,"renderOwner",id,s.DisplayName,s.OwnerUserId,s.OwnerGeneration)
		local p=self.profiles:get(s.OwnerUserId); if p.Ok then U.call(self.world,"setWarehouseCapacity",id,self:_capacity(p.Value)) end
	end
end
function Service:_public(item,own)
	local out={}
	for _,k in ipairs({"ItemId","Sku","Quantity","OwnerUserId","OwnerStoreId","State","Revision","SlotId","CarrierUserId","RecoverUntil","OrderId"}) do out[k]=item[k] or false end
	if own then out.UnitCost=item.UnitCost end
	return out
end
function Service:view(c)
	local s=c and self.stores[c.StoreId]; local profile=c and self:_profile(c)
	local items,carry,orders,slots,nearby={},{},{},{},{}
	local safe=0
	if s then
		for _,id in ipairs(self.config.World.ShelfSlotIds) do slots[id]={SlotId=id,Sku=false,ItemIds={},Revision=s.Revision} end
		for _,i in pairs(s.Items) do
			table.insert(items,self:_public(i,true)); if i.State=="SafeStorage" then safe+=1 end
			if i.State=="Shelf" then slots[i.SlotId].Sku=i.Sku; table.insert(slots[i.SlotId].ItemIds,i.ItemId) end
		end
		for _,o in pairs(s.Orders) do if o.State~="Completed" and o.State~="Cancelled" then table.insert(orders,{OrderId=o.OrderId,Sku=o.Sku,Quantity=o.Quantity,State=o.State,ArriveAt=o.ArriveAt,RecallAt=o.RecallAt}) end end
	end
	if c then for _,i in ipairs(self:_carry(c.UserId)) do local row=self:_public(i,false); row.CarryToken=i.CarryToken; table.insert(carry,row) end end
	for _,store in pairs(self.stores) do for _,i in pairs(store.Items) do if i.State=="Shelf" or i.State=="Truck" or i.State=="Recoverable" or i.State=="TheftCarried" then table.insert(nearby,self:_public(i,false)) end end end
	local slotRows={}; for _,id in ipairs(self.config.World.ShelfSlotIds) do if slots[id] then table.insert(slotRows,slots[id]) end end
	local rows={}; for _,sku in ipairs(self.config.ProductOrder) do
		local allocated=0; local allocationId=false; local untilAt=false
		for id,a in pairs(self.demand.allocations) do if c and a.UserId==c.UserId and a.ProfileEpoch==c.ProfileEpoch and a.Remaining>0 and self.now()<a.ReserveUntil then
			if a.Sku==sku then allocated+=a.Remaining; allocationId=id; untilAt=a.ReserveUntil end
		end end
		local product=self.config.Products[sku]; table.insert(rows,{Sku=sku,PublicAvailable=self.stock.Public[sku],MyAllocated=allocated,AllocationId=allocationId,ReserveUntil=untilAt,UnitCost=product.WholesalePrice,SalePrice=product.SalePrice,Rarity=product.Rarity})
	end
	local theft=c and self.thefts[c.UserId]
	return {Store=s and {StoreId=s.StoreId,OwnerUserId=s.OwnerUserId,OwnerGeneration=s.OwnerGeneration,Revision=s.Revision,
		WarehouseCapacity=profile and self:_capacity(profile) or 24,SafeStorageCount=safe,Orders=orders,Items=items,Slots=slotRows} or false,
		Wholesale={Revision=self.stock.Revision,Cycle=self.stock.Cycle,NextRestockAt=self.stock.NextRestockAt,Rows=rows},
		Items=items,Nearby=nearby,Carry=carry,Orders=orders,Slots=slotRows,
		Theft=theft and {TheftId=theft.TheftId,ItemId=theft.ItemId,State=theft.State,CompleteAt=theft.CompleteAt,RecoverUntil=false} or false,
		Demand=c and self.demand:view(c) or false,Contest=c and self.contest:view(c) or false}
end
return Service
