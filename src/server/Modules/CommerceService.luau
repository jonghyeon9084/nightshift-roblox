--!nocheck
-- One server-local ledger. Main invokes this facade from its non-yielding queue.
-- Delivery owns schedules/trucks only; this module owns all item/money mutations.
local Service = {}
Service.__index = Service
local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}; for k, value in pairs(v) do out[k] = copy(value) end; return out
end
local function result(code, value) return { Ok = code == "OK", Code = code, Value = copy(value == nil and false or value) } end
local function integer(v) return type(v) == "number" and v == v and v >= 0 and v < math.huge and v % 1 == 0 end
local function id(v) return type(v) == "string" and #v > 0 and #v <= 96 end
local function same(a,b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k,v in pairs(a) do if not same(v,b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
local function call(object, method, ...)
	local ok, value = pcall(object[method], object, ...)
	if not ok or type(value) ~= "table" then return result("INTERNAL_ERROR") end
	return value
end
local terminal = { Sold = true, Recalled = true, Expired = true }
local orderTerminal = { Completed = true, Recalled = true, Cancelled = true }
local fields = {
	OrderStock = { Sku="id", Quantity="int", StockRevision="int" }, CancelStockOrder = { OrderId="id" },
	PickCargo = { ItemId="id", ItemRevision="int" }, PickWarehouse = { ItemId="id", ItemRevision="int" },
	PickShelf = { ItemId="id", ItemRevision="int" }, PlaceShelf = { ItemId="id", ItemRevision="int", CarryToken="id", SlotId="id" },
	DropWarehouse = { ItemId="id", ItemRevision="int", CarryToken="id" }, BeginTheft = { ItemId="id", ItemRevision="int" },
	CancelTheft = { TheftId="id" }, RecoverItem = { ItemId="id", ItemRevision="int" },
	SecureTheft = { ItemId="id", ItemRevision="int", CarryToken="id" }, ApplyPreset = { Index="int" },
}

function Service.new(deps)
	local self = setmetatable({ config=deps.Config, now=deps.Now, newId=deps.NewId, delivery=deps.Delivery,
		world=deps.World, progression=deps.Progression, stores={}, rounds={}, orders={}, items={}, contexts={},
		thefts={}, events={}, transactions={}, pendingRewards={}, dirtyItems={}, dirtyAlarms={},
		stock={}, stockRevision=1, cycle=0, nextRestock=deps.Now()+deps.Config.Wholesale.RestockSeconds }, Service)
	for sku,p in pairs(self.config.Products) do self.stock[sku] = p.Rarity == "Basic" and p.StockCap or 0 end
	return self
end

function Service:beginShift(storeId, roundId, shift)
	if not self.config.World.Stores[storeId] or not id(roundId) or type(shift) ~= "table"
		or type(shift.InitialUserIds) ~= "table" or not integer(shift.TeamSize) or shift.TeamSize < 1
		or shift.TeamSize > self.config.Capacity.SeatsPerStore or type(shift.Protected) ~= "boolean"
		or not table.find(self.config.Ranking.ModeTags, shift.Mode) then return result("BAD_REQUEST") end
	local roster={}; local rosterCount=0
	for key,userId in pairs(shift.InitialUserIds) do
		if not integer(key) or key<1 or key>shift.TeamSize or not integer(userId) or userId<1 or roster[userId] then return result("BAD_REQUEST") end
		roster[userId]=true; rosterCount+=1
	end
	if rosterCount~=shift.TeamSize then return result("BAD_REQUEST") end
	local prior = self.rounds[roundId]
	if prior then return prior.StoreId == storeId and result("OK", prior.Begin) or result("INVALID_STATE") end
	if self.stores[storeId] and self.stores[storeId].Active then return result("INVALID_STATE") end
	local s = { StoreId=storeId, RoundId=roundId, Revision=1, OperatingCash=self.config.Economy.InitialOperatingCash,
		Sales=0, Revenue=0, Active=true, Protected=shift.Protected, Shift=copy(shift), Slots={}, SupportUsed=false,
		Cycle=self.cycle, CycleUnits=0, CycleRare=0, OnlineCount=0, OnlineActiveCount=0, Alarm=false, LastTheft=-math.huge }
	for _,slotId in ipairs(self.config.World.ShelfSlotIds) do s.Slots[slotId] = { SlotId=slotId, Sku=false, ItemIds={}, Revision=1 } end
	s.Begin = { StoreId=storeId, RoundId=roundId }
	self.stores[storeId]=s; self.rounds[roundId]=s
	return result("OK", s.Begin)
end

function Service:_counts()
	for _,s in pairs(self.stores) do s.OnlineCount=0; s.OnlineActiveCount=0 end
	for _,c in pairs(self.contexts) do
		local s = self.stores[c.StoreId]
		if s and s.Active and c.RoundId == s.RoundId then
			s.OnlineCount += 1
			if c.Active and c.Loaded then s.OnlineActiveCount += 1 end
		end
	end
end

function Service:syncContext(context)
	local old = self.contexts[context.UserId]
	if old and (old.StoreId ~= context.StoreId or old.RoundId ~= context.RoundId or old.SeatGeneration ~= context.SeatGeneration
		or old.ProfileEpoch ~= context.ProfileEpoch) then self:depart(context.UserId) end
	self.contexts[context.UserId] = copy(context); self:_counts()
	if not context.Active or not context.Loaded then
		local t = self.thefts[context.UserId]; if t and t.State == "Holding" then t.State = "Cancelled" end
	end
end

function Service:_auth(c)
	if type(c) ~= "table" then return result("BAD_REQUEST") end
	local latest = self.contexts[c.UserId]
	if not latest or not c.StoreId or latest.StoreId ~= c.StoreId then return result("NOT_MEMBER") end
	if latest.SeatGeneration ~= c.SeatGeneration then return result("STALE_SEAT") end
	if latest.RoundId ~= c.RoundId then return result("STALE_ROUND") end
	if latest.ProfileEpoch ~= c.ProfileEpoch then return result("PROFILE_UNAVAILABLE") end
	if not latest.Loaded or not c.Loaded then return result("NOT_LOADED") end
	if not latest.Active or not c.Active then return result("NOT_ACTIVE") end
	local s = self.stores[c.StoreId]
	if not s or not s.Active then return result("NOT_ACTIVE") end
	if s.RoundId ~= c.RoundId then return result("STALE_ROUND") end
	return result("OK")
end

function Service:_check(c,target) return call(self.world,"check",copy(c),copy(target)) end
function Service:_render(item)
	self.dirtyItems[item.ItemId] = true
	if call(self.world,"renderItem",self:_public(item)).Ok then self.dirtyItems[item.ItemId] = nil end
end
function Service:_alarm(s)
	self.dirtyAlarms[s.StoreId] = true
	if call(self.world,"setAlarm",s.StoreId,copy(s.Alarm)).Ok then self.dirtyAlarms[s.StoreId] = nil end
end
function Service:_public(item)
	return copy({ ItemId=item.ItemId, Sku=item.Sku, Quantity=1, UnitCost=item.UnitCost, SalePrice=item.SalePrice,
		OwnerStoreId=item.OwnerStoreId, State=item.State, Revision=item.Revision, OrderId=item.OrderId,
		SlotId=item.SlotId, CarrierUserId=item.CarrierUserId, Stolen=item.Stolen, RecoverUntil=item.RecoverUntil })
end
function Service:_carry(userId)
	local out={}; for _,item in pairs(self.items) do if item.CarrierUserId == userId and not terminal[item.State] then table.insert(out,item) end end
	table.sort(out,function(a,b) return a.ItemId < b.ItemId end); return out
end
function Service:_size(s)
	local n=0
	for _,item in pairs(self.items) do if item.OwnerStoreId == s.StoreId and item.RoundId == s.RoundId and not terminal[item.State] then n+=1 end end
	for _,o in pairs(self.orders) do if o.StoreId == s.StoreId and o.RoundId == s.RoundId and o.State == "Reserved" then n+=o.Quantity end end
	return n
end
function Service:_unlink(item)
	if item.SlotId then
		local s=self.rounds[item.RoundId]; local slot=s and s.Slots[item.SlotId]
		if slot then
			local i=table.find(slot.ItemIds,item.ItemId); if i then table.remove(slot.ItemIds,i) end
			if #slot.ItemIds == 0 then slot.Sku=false end; slot.Revision+=1
		end
	end
	item.SlotId=false
end
function Service:_move(item,state,userId,token,slotId)
	self:_unlink(item)
	item.State=state; item.CarrierUserId=userId or false; item.CarryToken=token or false; item.SlotId=slotId or false
	item.Revision+=1
	local s=self.rounds[item.RoundId]
	if slotId then local slot=s.Slots[slotId]; table.insert(slot.ItemIds,item.ItemId); slot.Sku=item.Sku; slot.Revision+=1 end
	if s then s.Revision+=1 end
	self:_render(item)
end
function Service:_stockReturn(sku,quantity)
	if quantity <= 0 then return end
	self.stock[sku]=math.min(self.config.Products[sku].StockCap,self.stock[sku]+quantity); self.stockRevision+=1
end

function Service:_order(c,p)
	local s=self.stores[c.StoreId]; local product=self.config.Products[p.Sku]
	if not product or p.Quantity < 1 or p.Quantity > self.config.Wholesale.MaxUnitsPerOrder then return result("BAD_REQUEST") end
	if p.StockRevision ~= self.stockRevision then return result("STALE_STOCK") end
	if self.stock[p.Sku] < p.Quantity then return result("OUT_OF_STOCK") end
	local open=0; for _,o in pairs(self.orders) do if o.RoundId == s.RoundId and not orderTerminal[o.State] then open+=1 end end
	local units=s.Cycle==self.cycle and s.CycleUnits or 0; local rare=s.Cycle==self.cycle and s.CycleRare or 0
	if open >= self.config.Wholesale.MaxOpenOrdersPerStore or units+p.Quantity > self.config.Wholesale.MaxUnitsPerStorePerCycle
		or self:_size(s)+p.Quantity > self.config.Wholesale.MaxItemsPerStore
		or (product.Rarity=="Rare" and rare+p.Quantity > self.config.Wholesale.MaxRareUnitsPerStorePerCycle) then return result("ORDER_LIMIT") end
	local cost=product.WholesalePrice*p.Quantity
	if s.OperatingCash < cost then return result("INSUFFICIENT_FUNDS") end
	local check=self:_check(c,{StoreId=s.StoreId,Marker="OfficePC"}); if not check.Ok then return check end
	-- Prepare every identifier before register. No callbacks/throwing expressions after it succeeds.
	local orderId=self.newId("order")
	local o={OrderId=orderId,StoreId=s.StoreId,RoundId=s.RoundId,Sku=p.Sku,Quantity=p.Quantity,UnitCost=product.WholesalePrice,
		ReservedAt=self.now(),State="Reserved",ArriveAt=false,RecallAt=false,ItemIds={},Settled=false}
	for _=1,p.Quantity do table.insert(o.ItemIds,self.newId("item")) end
	local registered=call(self.delivery,"register",{OrderId=orderId,StoreId=s.StoreId,RoundId=s.RoundId,Sku=p.Sku,
		Quantity=p.Quantity,UnitCost=product.WholesalePrice,ReservedAt=o.ReservedAt})
	if not registered.Ok then return result("DELIVERY_FAILED") end
	self.orders[orderId]=o; self.stock[p.Sku]-=p.Quantity; self.stockRevision+=1
	s.OperatingCash-=cost; s.Cycle=self.cycle; s.CycleUnits=units+p.Quantity
	s.CycleRare=rare+(product.Rarity=="Rare" and p.Quantity or 0); s.Revision+=1
	return result("OK",{OrderId=orderId})
end

function Service:_event(e)
	if type(e) ~= "table" or not id(e.EventId) or not id(e.OrderId) or type(e.At) ~= "number" or e.At ~= e.At
		or e.At < 0 or e.At == math.huge then return result("INVALID_STATE") end
	local previous=self.events[e.EventId]
	if previous then return same(previous,e) and result("OK") or result("INVALID_STATE") end
	local o=self.orders[e.OrderId]
	if not o or o.StoreId ~= e.StoreId or o.RoundId ~= e.RoundId then return result("INVALID_STATE") end
	local s=self.rounds[o.RoundId]
	if e.Kind=="Dispatched" then
		if o.State~="Reserved" then return result("INVALID_STATE") end
		local made={}
		for _,itemId in ipairs(o.ItemIds) do
			table.insert(made,{ItemId=itemId,Sku=o.Sku,Quantity=1,UnitCost=o.UnitCost,SalePrice=self.config.Products[o.Sku].SalePrice,
				OwnerStoreId=o.StoreId,RoundId=o.RoundId,State="Truck",Revision=1,OrderId=o.OrderId,SlotId=false,
				CarrierUserId=false,CarryToken=false,Stolen=false,EverSecured=false,RecoverUntil=false,LineId=false,OriginalSlot=false,Delivered=false})
		end
		o.State="InTransit"; o.ArriveAt=e.At+self.config.Delivery.TravelSeconds
		for _,item in ipairs(made) do self.items[item.ItemId]=item end
		self.events[e.EventId]=copy(e); s.Revision+=1
		for _,item in ipairs(made) do self:_render(item) end
		return result("OK")
	elseif e.Kind=="Arrived" then
		if o.State~="InTransit" then return result("INVALID_STATE") end
		o.State="Docked"; o.RecallAt=e.At+self.config.Delivery.DockSeconds
	elseif e.Kind=="Cancelled" or e.Kind=="Failed" or e.Kind=="Recall" then
		if o.Settled then self.events[e.EventId]=copy(e); return result("OK") end
		if e.Kind=="Cancelled" and o.State~="Reserved" then return result("INVALID_STATE") end
		if e.Kind=="Recall" and o.State~="InTransit" and o.State~="Docked" then return result("INVALID_STATE") end
		if orderTerminal[o.State] then return result("INVALID_STATE") end
		local returned=0; local retiring={}
		if o.State=="Reserved" then returned=o.Quantity
		else
			for _,itemId in ipairs(o.ItemIds) do local item=self.items[itemId]
				if item and item.State=="Truck" then returned+=1; table.insert(retiring,item) end
			end
		end
		-- Settlement marker and monetary ledger are committed before presentation callbacks.
		o.Settled=true; o.State=e.Kind=="Cancelled" and "Cancelled" or "Recalled"
		s.OperatingCash=math.min(self.config.Economy.MaxCurrency,s.OperatingCash+returned*o.UnitCost)
		self:_stockReturn(o.Sku,returned); self.events[e.EventId]=copy(e)
		for _,item in ipairs(retiring) do self:_move(item,"Recalled") end
	else return result("INVALID_STATE") end
	self.events[e.EventId]=copy(e); s.Revision+=1
	return result("OK")
end

function Service:_complete(orderId)
	local o=self.orders[orderId]; if not o or o.State~="Docked" then return end
	for _,itemId in ipairs(o.ItemIds) do if self.items[itemId] and self.items[itemId].State=="Truck" then return end end
	if call(self.delivery,"complete",orderId).Ok then o.State="Completed"; self.rounds[o.RoundId].Revision+=1 end
end

function Service:_queueReward(c,transactionId,kind,sku,eligible)
	if not eligible then return end
	local key=tostring(c.UserId)..":"..transactionId
	if self.pendingRewards[key] then return end
	self.pendingRewards[key]={UserId=c.UserId,RoundId=c.RoundId,Event={TransactionId=transactionId,Epoch=c.ProfileEpoch,Kind=kind,Sku=sku,Eligible=true}}
	self:_reward(key)
end
function Service:_reward(key)
	local pending=self.pendingRewards[key]; if not pending then return end
	local c=self.contexts[pending.UserId]
	if not c or c.ProfileEpoch~=pending.Event.Epoch or c.RoundId~=pending.RoundId then self.pendingRewards[key]=nil; return end
	local r=call(self.progression,"award",pending.UserId,copy(pending.Event))
	if r.Ok then self.pendingRewards[key]=nil end
end

function Service:_item(p)
	local item=self.items[p.ItemId]
	if not item then return nil,result("NOT_FOUND") end
	if item.Revision~=p.ItemRevision then return nil,result("STALE_ITEM") end
	return item,nil
end

function Service:_pick(c,action,p)
	local item,err=self:_item(p); if err then return err end
	if item.OwnerStoreId~=c.StoreId or item.RoundId~=c.RoundId then return result("NOT_OWNER") end
	local expected=action=="PickCargo" and "Truck" or (action=="PickShelf" and "Shelf" or "Warehouse")
	if item.State~=expected or item.LineId then return result("INVALID_STATE") end
	local carry=self:_carry(c.UserId); local limit=self.contexts[c.UserId].ToolId=="Handcart" and self.config.Interaction.MaxCarryWithCart or 1
	local theft=self.thefts[c.UserId]
	if #carry>=limit or (theft and theft.State=="Holding") then return result("CARRY_FULL") end
	for _,held in ipairs(carry) do if held.LineId or held.State~="Carried" then return result("CARRY_FULL") end end
	local target={StoreId=c.StoreId,Marker="WarehouseDrop"}
	if expected=="Truck" then
		if self.orders[item.OrderId].State~="Docked" then return result("INVALID_STATE") end
		target={OrderId=item.OrderId,Cargo=true}
	elseif expected=="Shelf" then target={StoreId=c.StoreId,SlotId=item.SlotId} end
	local checked=self:_check(c,target); if not checked.Ok then return checked end
	local token=self.newId("carry"); item.OriginalSlot=item.SlotId
	self:_move(item,"Carried",c.UserId,token)
	self:_complete(item.OrderId)
	return result("OK",{ItemId=item.ItemId})
end

function Service:_place(c,action,p)
	local item,err=self:_item(p); if err then return err end
	if item.OwnerStoreId~=c.StoreId or item.RoundId~=c.RoundId then return result("NOT_OWNER") end
	if item.State~="Carried" or item.LineId then return result("INVALID_STATE") end
	if item.CarrierUserId~=c.UserId or item.CarryToken~=p.CarryToken then return result("BAD_TOKEN") end
	local slotId=action=="PlaceShelf" and p.SlotId or false
	if slotId then
		local slot=self.stores[c.StoreId].Slots[slotId]; if not slot then return result("NOT_FOUND") end
		if #slot.ItemIds>=self.config.World.ShelfSlotCapacity then return result("SLOT_FULL") end
		if slot.Sku and slot.Sku~=item.Sku then return result("SKU_MISMATCH") end
	end
	local check=self:_check(c,slotId and {StoreId=c.StoreId,SlotId=slotId} or {StoreId=c.StoreId,Marker="WarehouseDrop"})
	if not check.Ok then return check end
	self:_move(item,slotId and "Shelf" or "Warehouse",nil,nil,slotId)
	if slotId and not item.Delivered then
		item.Delivered=true
		self:_queueReward(c,"delivery:"..item.ItemId,"Delivery",item.Sku,not item.Stolen)
	end
	return result("OK",{ItemId=item.ItemId})
end

function Service:_theftValid(c,item,revision)
	local auth=self:_auth(c); if not auth.Ok then return auth end
	if item.Revision~=revision then return result("STALE_ITEM") end
	if item.OwnerStoreId==c.StoreId then return result("NOT_OWNER") end
	if item.State~="Truck" and item.State~="Shelf" then return result("INVALID_STATE") end
	if item.LineId then return result("INVALID_STATE") end
	if item.State=="Truck" and self.orders[item.OrderId].State~="Docked" then return result("INVALID_STATE") end
	local attacker=self.stores[c.StoreId]; local victim=self.stores[item.OwnerStoreId]
	if not victim or not victim.Active or victim.RoundId~=item.RoundId or attacker.Protected or victim.Protected
		or attacker.OnlineActiveCount==0 or victim.OnlineActiveCount==0 then return result("PROTECTED") end
	if self.now()<victim.LastTheft+self.config.Theft.VictimCooldownSeconds then return result("COOLDOWN") end
	if #self:_carry(c.UserId)>0 then return result("CARRY_FULL") end
	return self:_check(c,item.State=="Truck" and {OrderId=item.OrderId,Cargo=true} or {StoreId=item.OwnerStoreId,SlotId=item.SlotId})
end

function Service:_beginTheft(c,p)
	local item,err=self:_item(p); if err then return err end
	local t=self.thefts[c.UserId]
	if t and (t.State=="Holding" or t.State=="Escaping") then return result("INVALID_STATE") end
	local check=self:_theftValid(c,item,p.ItemRevision); if not check.Ok then return check end
	t={TheftId=self.newId("theft"),ItemId=item.ItemId,State="Holding",CompleteAt=self.now()+self.config.Theft.HoldSeconds,
		RecoverUntil=false,ItemRevision=item.Revision,Context=copy(c)}
	self.thefts[c.UserId]=t; return result("OK",{TheftId=t.TheftId})
end

function Service:_returnStolen(item)
	local carrier=item.CarrierUserId; local t=self.thefts[carrier]
	if t and t.ItemId==item.ItemId then t.State="Recovered" end
	-- A previously secured stolen item must never be laundered into eligible stock
	-- by stealing it a second time and letting the current owner recover it.
	item.Stolen=item.EverSecured or false; item.RecoverUntil=false
	local victim=self.stores[item.OwnerStoreId]
	self:_move(item,victim and victim.Active and victim.RoundId==item.RoundId and "Warehouse" or "Expired")
end

function Service:_recover(c,p)
	local item,err=self:_item(p); if err then return err end
	if item.OwnerStoreId~=c.StoreId or item.RoundId~=c.RoundId then return result("NOT_OWNER") end
	if (item.State~="TheftCarried" and item.State~="Recoverable") or not item.RecoverUntil or self.now()>=item.RecoverUntil then return result("INVALID_STATE") end
	local check=self:_check(c,{ItemId=item.ItemId}); if not check.Ok then return check end
	self:_returnStolen(item); return result("OK")
end

function Service:_secure(c,p)
	local item,err=self:_item(p); if err then return err end
	if item.State~="TheftCarried" or item.CarrierUserId~=c.UserId or item.CarryToken~=p.CarryToken then return result("BAD_TOKEN") end
	if self.now()<item.RecoverUntil then return result("INVALID_STATE") end
	local s=self.stores[c.StoreId]
	if self:_size(s)>=self.config.Wholesale.MaxItemsPerStore then return result("ORDER_LIMIT") end
	local check=self:_check(c,{StoreId=c.StoreId,Marker="TheftReturn"}); if not check.Ok then return check end
	local victim=self.rounds[item.RoundId]; victim.Revision+=1
	item.OwnerStoreId=c.StoreId; item.RoundId=c.RoundId; item.RecoverUntil=false; item.EverSecured=true
	local t=self.thefts[c.UserId]; if t then t.State="Secured" end
	self:_move(item,"Warehouse"); return result("OK")
end

function Service:action(c,action,p)
	local schema=fields[action]
	if not schema or type(p)~="table" then return result("BAD_REQUEST") end
	for k,v in pairs(p) do if not schema[k] or not (schema[k]=="id" and id(v) or schema[k]=="int" and integer(v)) then return result("BAD_REQUEST") end end
	for k in pairs(schema) do if p[k]==nil then return result("BAD_REQUEST") end end
	-- Due recalls win over inputs at the exact deadline.
	self:tick(self.now())
	local auth=self:_auth(c); if not auth.Ok then return auth end
	if action=="OrderStock" then return self:_order(c,p) end
	if action=="CancelStockOrder" then
		local o=self.orders[p.OrderId]; if not o then return result("NOT_FOUND") end
		if o.StoreId~=c.StoreId or o.RoundId~=c.RoundId then return result("NOT_OWNER") end
		if o.State~="Reserved" and o.State~="Cancelled" then return result("INVALID_STATE") end
		local check=self:_check(c,{StoreId=c.StoreId,Marker="OfficePC"}); if not check.Ok then return check end
		local cancelled=call(self.delivery,"cancel",o.OrderId); if not cancelled.Ok then return cancelled end
		return self:_event(cancelled.Value)
	end
	if action=="PickCargo" or action=="PickWarehouse" or action=="PickShelf" then return self:_pick(c,action,p) end
	if action=="PlaceShelf" or action=="DropWarehouse" then return self:_place(c,action,p) end
	if action=="BeginTheft" then return self:_beginTheft(c,p) end
	if action=="RecoverItem" then return self:_recover(c,p) end
	if action=="SecureTheft" then return self:_secure(c,p) end
	if action=="CancelTheft" then
		local t=self.thefts[c.UserId]
		if not t or t.TheftId~=p.TheftId then return result("NOT_FOUND") end
		if t.State~="Holding" then return result("INVALID_STATE") end
		t.State="Cancelled"; return result("OK")
	end
	if action=="ApplyPreset" then
		local check=self:_check(c,{StoreId=c.StoreId,Marker="OfficePC"}); if not check.Ok then return check end
		local view=self.progression:view(c.UserId)
		if view.Level<self.config.Progression.Tools.LayoutPreset then return result("LEVEL_LOCKED") end
		for _,preset in ipairs(view.Presets) do if preset.Index==p.Index then return result("OK",preset) end end
		return result("PRESET_INVALID")
	end
	return result("BAD_REQUEST")
end

function Service:claimForLine(c,itemId,revision,lineId)
	if not id(itemId) or not id(lineId) or not integer(revision) then return result("BAD_REQUEST") end
	self:tick(self.now()); local auth=self:_auth(c); if not auth.Ok then return auth end
	local item,err=self:_item({ItemId=itemId,ItemRevision=revision}); if err then return err end
	if item.OwnerStoreId~=c.StoreId or item.RoundId~=c.RoundId then return result("NOT_OWNER") end
	if item.State~="Shelf" or item.LineId then return result("INVALID_STATE") end
	local theft=self.thefts[c.UserId]
	if #self:_carry(c.UserId)>0 or (theft and theft.State=="Holding") then return result("CARRY_FULL") end
	for _,other in pairs(self.items) do if other.RoundId==c.RoundId and other.LineId==lineId then return result("INVALID_STATE") end end
	local check=self:_check(c,{StoreId=c.StoreId,SlotId=item.SlotId}); if not check.Ok then return check end
	local token=self.newId("line"); item.OriginalSlot=item.SlotId; item.LineId=lineId
	self:_move(item,"Carried",c.UserId,token)
	local value=self:_public(item); value.CarryToken=token; return result("OK",value)
end

function Service:_returnCarried(item)
	local s=self.rounds[item.RoundId]; local slot=s and item.OriginalSlot and s.Slots[item.OriginalSlot]
	local target=slot and #slot.ItemIds<self.config.World.ShelfSlotCapacity and (not slot.Sku or slot.Sku==item.Sku) and slot.SlotId or false
	item.LineId=false
	self:_move(item,s and s.Active and (target and "Shelf" or "Warehouse") or "Expired",nil,nil,s and s.Active and target or nil)
end
function Service:returnLine(c,lineId)
	local auth=self:_auth(c); if not auth.Ok then return auth end
	for _,item in pairs(self.items) do
		if item.RoundId==c.RoundId and item.LineId==lineId and item.CarrierUserId==c.UserId then
			self:_returnCarried(item); return result("OK")
		end
	end
	return result("NOT_FOUND")
end

function Service:sellLine(c,lineId,transactionId)
	if not id(lineId) or not id(transactionId) then return result("BAD_REQUEST") end
	self:tick(self.now()); local auth=self:_auth(c); if not auth.Ok then return auth end
	local prior=self.transactions[transactionId]
	if prior then
		if prior.UserId~=c.UserId or prior.RoundId~=c.RoundId or prior.LineId~=lineId then return result("INVALID_STATE") end
		return result("OK",prior.Value)
	end
	local item
	for _,candidate in pairs(self.items) do
		-- Main has already validated the Tray line. Any teammate at the counter
		-- may accept it; acceptance need not be by the original carrier.
		if candidate.RoundId==c.RoundId and candidate.LineId==lineId then item=candidate; break end
	end
	if not item or item.State~="Carried" then return result("NOT_FOUND") end
	if item.OwnerStoreId~=c.StoreId then return result("NOT_OWNER") end
	local check=self:_check(c,{StoreId=c.StoreId,Marker="Counter"}); if not check.Ok then return check end
	local s=self.stores[c.StoreId]; local value={ItemId=item.ItemId,SalePrice=item.SalePrice,Eligible=not item.Stolen}
	self.transactions[transactionId]={UserId=c.UserId,RoundId=c.RoundId,LineId=lineId,Value=copy(value)}
	s.OperatingCash=math.min(self.config.Economy.MaxCurrency,s.OperatingCash+item.SalePrice)
	if not item.Stolen then s.Sales+=1; s.Revenue=math.min(self.config.Economy.MaxCurrency,s.Revenue+item.SalePrice) end
	item.LineId=false; self:_move(item,"Sold")
	self:_queueReward(c,transactionId,"Sale",item.Sku,not item.Stolen)
	return result("OK",value)
end

function Service:depart(userId)
	for _,item in ipairs(self:_carry(userId)) do
		if item.State=="TheftCarried" then self:_returnStolen(item) else self:_returnCarried(item) end
	end
	local t=self.thefts[userId]; if t and t.State=="Holding" then t.State="Cancelled" end
	self.contexts[userId]=nil; self:_counts()
end

function Service:tick(now)
	if type(now)~="number" or now~=now or now==math.huge then return end
	-- Delivery callbacks never mutate money. Consume events before any holding completion.
	local ok,events=pcall(self.delivery.tick,self.delivery,now)
	if ok and type(events)=="table" then for _,event in ipairs(events) do self:_event(event) end end
	for _,o in pairs(self.orders) do self:_complete(o.OrderId) end
	if now>=self.nextRestock then
		local elapsed=math.floor((now-self.nextRestock)/self.config.Wholesale.RestockSeconds)+1
		local old=self.cycle; self.cycle+=elapsed; self.nextRestock+=elapsed*self.config.Wholesale.RestockSeconds
		for sku,p in pairs(self.config.Products) do if p.Rarity=="Basic" then self.stock[sku]=p.StockCap end end
		local cadence=self.config.Wholesale.RareEveryRestocks; local rotation=self.config.Wholesale.RareRotation
		local first=math.floor(old/cadence)+1; local last=math.floor(self.cycle/cadence)
		-- At most one visit per rare SKU is needed, even after a long scheduler pause.
		for n=math.max(first,last-#rotation+1),last do local sku=rotation[(n-1)%#rotation+1]; self.stock[sku]=self.config.Products[sku].StockCap end
		self.stockRevision+=elapsed
	end
	for userId,t in pairs(self.thefts) do
		if t.State=="Holding" then
			local c=self.contexts[userId]; local item=self.items[t.ItemId]
			local check=c and item and self:_theftValid(c,item,t.ItemRevision)
			if not check or not check.Ok or c.SeatGeneration~=t.Context.SeatGeneration or c.ProfileEpoch~=t.Context.ProfileEpoch
				or c.StoreId~=t.Context.StoreId or c.RoundId~=t.Context.RoundId then t.State="Cancelled"
			elseif now>=t.CompleteAt then
				local token=self.newId("theftcarry"); local alarmId=self.newId("alarm"); local victim=self.stores[item.OwnerStoreId]
				victim.Alarm={AlarmId=alarmId,Sku=item.Sku,Location=item.State,SourceId=item.State=="Truck" and item.OrderId or item.SlotId,
					ExpiresAt=now+self.config.Theft.AlarmSeconds}; victim.LastTheft=now
				item.Stolen=true; item.RecoverUntil=now+self.config.Theft.RecoverSeconds
				t.State="Escaping"; t.RecoverUntil=item.RecoverUntil
				self:_move(item,"TheftCarried",userId,token); self:_alarm(victim); self:_complete(item.OrderId)
			end
		end
	end
	local cheapest=math.huge
	for _,p in pairs(self.config.Products) do if p.Rarity=="Basic" then cheapest=math.min(cheapest,p.WholesalePrice) end end
	for _,s in pairs(self.stores) do
		if s.Alarm and now>=s.Alarm.ExpiresAt then s.Alarm=false; s.Revision+=1; self:_alarm(s) end
		if s.Active and not s.SupportUsed and s.OperatingCash<cheapest and self:_size(s)==0 then
			s.SupportUsed=true; s.OperatingCash+=self.config.Economy.RestockSupportCash; s.Revision+=1
		end
	end
	for itemId in pairs(self.dirtyItems) do self:_render(self.items[itemId]) end
	for storeId in pairs(self.dirtyAlarms) do self:_alarm(self.stores[storeId]) end
	for key in pairs(self.pendingRewards) do self:_reward(key) end
end

function Service:endShift(storeId,roundId)
	local s=self.rounds[roundId]
	if not s or s.StoreId~=storeId then return result("STALE_ROUND") end
	if s.End then return result("OK",s.End) end
	local ok,events=pcall(self.delivery.closeStore,self.delivery,storeId,roundId)
	if not ok or type(events)~="table" then return result("DELIVERY_FAILED") end
	for _,event in ipairs(events) do local settled=self:_event(event); if not settled.Ok then return settled end end
	for _,o in pairs(self.orders) do if o.RoundId==roundId and not orderTerminal[o.State] then return result("DELIVERY_FAILED") end end
	-- Return goods stolen by this team before closing; expire goods owned by it.
	for userId,c in pairs(self.contexts) do if c.RoundId==roundId then self:depart(userId) end end
	s.Active=false
	for _,item in pairs(self.items) do if item.RoundId==roundId and not terminal[item.State] then
		local t=self.thefts[item.CarrierUserId]; if t then t.State="Recovered" end
		item.LineId=false; self:_move(item,"Expired")
	end end
	s.End={StoreId=storeId,RoundId=roundId,Sales=s.Sales,Revenue=s.Revenue,HadSupport=s.SupportUsed,TeamSize=s.Shift.TeamSize,Mode=s.Shift.Mode}
	s.OperatingCash=0; s.Alarm=false; s.Revision+=1; self:_alarm(s)
	return result("OK",s.End)
end

function Service:view(c)
	local wholesale={Revision=self.stockRevision,Cycle=self.cycle,NextRestockAt=self.nextRestock,Rows={}}
	for _,sku in ipairs(self.config.ProductOrder) do local p=self.config.Products[sku]
		table.insert(wholesale.Rows,{Sku=sku,Available=self.stock[sku],UnitCost=p.WholesalePrice,SalePrice=p.SalePrice,Rarity=p.Rarity})
	end
	local summaries={}
	for _,storeId in ipairs(self.config.World.StoreIds) do local s=self.stores[storeId]
		table.insert(summaries,{StoreId=storeId,RoundId=s and s.RoundId or false,Sales=s and s.Sales or 0,Revenue=s and s.Revenue or 0,
			OnlineCount=s and s.OnlineCount or 0,Protected=not s or s.Protected,Alarm=s and copy(s.Alarm) or false})
	end
	local store=false; local s=c and self.stores[c.StoreId]
	local latest=c and self.contexts[c.UserId]
	local member=latest and latest.StoreId==c.StoreId and latest.RoundId==c.RoundId and latest.SeatGeneration==c.SeatGeneration
	if s and s.Active and s.RoundId==c.RoundId and member then
		store={StoreId=s.StoreId,RoundId=s.RoundId,Revision=s.Revision,OperatingCash=s.OperatingCash,SupportUsed=s.SupportUsed,Orders={},Items={},Slots={}}
		for _,o in pairs(self.orders) do if o.RoundId==s.RoundId then table.insert(store.Orders,{OrderId=o.OrderId,Sku=o.Sku,Quantity=o.Quantity,
			UnitCost=o.UnitCost,State=o.State,ArriveAt=o.ArriveAt,RecallAt=o.RecallAt}) end end
		for _,item in pairs(self.items) do if item.RoundId==s.RoundId and not terminal[item.State] then table.insert(store.Items,self:_public(item)) end end
		for _,slotId in ipairs(self.config.World.ShelfSlotIds) do table.insert(store.Slots,copy(s.Slots[slotId])) end
		table.sort(store.Orders,function(a,b) return a.OrderId<b.OrderId end); table.sort(store.Items,function(a,b) return a.ItemId<b.ItemId end)
	end
	local carry={}; local theft=false
	if member then
		for _,item in ipairs(self:_carry(c.UserId)) do if not item.LineId then local v=self:_public(item); v.CarryToken=item.CarryToken; table.insert(carry,v) end end
		local t=self.thefts[c.UserId]
		if t then theft={TheftId=t.TheftId,ItemId=t.ItemId,State=t.State,CompleteAt=t.CompleteAt,RecoverUntil=t.RecoverUntil} end
	end
	-- Only the World facade has positions. Conservative check returns interaction-near
	-- items (a subset of NearbyDistance); Main may broaden using server positions.
	local nearby={}
	if member then for _,item in pairs(self.items) do
		if not terminal[item.State] and #nearby<self.config.Network.MaxSnapshotItems and self:_check(c,{ItemId=item.ItemId}).Ok then
			table.insert(nearby,self:_public(item))
		end
	end end
	return copy({Wholesale=wholesale,Stores=summaries,Store=store,Nearby=nearby,Carry=carry,Theft=theft})
end

return Service
