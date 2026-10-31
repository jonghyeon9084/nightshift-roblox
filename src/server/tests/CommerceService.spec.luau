-- Deterministic, server queue simulations. No Roblox engine or live concurrency.
return function(Service, Config)
	local checks=0
	local function eq(a,b,label) checks+=1; assert(a==b,(label or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
	local function clone(v) if type(v)~="table" then return v end; local t={}; for k,x in pairs(v) do t[k]=clone(x) end; return t end
	local function fixture(config)
		local c=clone(config or Config); local time=0; local seq=0
		local world={deny=false,renderFail=false,renders={},alarms={}}
		function world:check() return {Ok=not self.deny,Code=self.deny and "TOO_FAR" or "OK",Value=false} end
		function world:renderItem(item) self.renders[item.ItemId]=clone(item); return {Ok=not self.renderFail,Code="OK",Value=false} end
		function world:setAlarm(storeId,alarm) self.alarms[storeId]=clone(alarm); return {Ok=true,Code="OK",Value=false} end
		local delivery={orders={},events={},fail=false,failComplete=false,closeCalls=0}
		function delivery:register(order)
			if self.fail then return {Ok=false,Code="DELIVERY_FAILED",Value=false} end
			self.orders[order.OrderId]=clone(order); self.orders[order.OrderId].State="Reserved"
			return {Ok=true,Code="OK",Value=false}
		end
		function delivery:event(orderId,kind,at)
			local o=self.orders[orderId]; seq+=1
			local e={EventId="event-"..seq,OrderId=orderId,StoreId=o.StoreId,RoundId=o.RoundId,Kind=kind,At=at or time}
			if kind=="Dispatched" then o.State="InTransit" elseif kind=="Arrived" then o.State="Docked"
			elseif kind=="Cancelled" then o.State="Cancelled" else o.State="Recalled" end
			return e
		end
		function delivery:cancel(orderId)
			local o=self.orders[orderId]
			if o.CancelEvent then return {Ok=true,Code="OK",Value=clone(o.CancelEvent)} end
			if o.State~="Reserved" then return {Ok=false,Code="INVALID_STATE",Value=false} end
			o.CancelEvent=self:event(orderId,"Cancelled"); return {Ok=true,Code="OK",Value=clone(o.CancelEvent)}
		end
		function delivery:complete(orderId)
			if self.failComplete then return {Ok=false,Code="DELIVERY_FAILED",Value=false} end
			self.orders[orderId].State="Completed"; return {Ok=true,Code="OK",Value=false}
		end
		function delivery:tick() local out=self.events; self.events={}; return out end
		function delivery:closeStore(storeId,roundId)
			self.closeCalls+=1; local out={}
			for orderId,o in pairs(self.orders) do
				if o.StoreId==storeId and o.RoundId==roundId then
					if o.State=="Reserved" then table.insert(out,self:cancel(orderId).Value)
					elseif o.State=="InTransit" or o.State=="Docked" then table.insert(out,self:event(orderId,"Recall")) end
				end
			end
			return out
		end
		local progression={awards={},fail=false}
		function progression:award(userId,event)
			if self.fail then return {Ok=false,Code="PROFILE_UNAVAILABLE",Value=false} end
			table.insert(self.awards,{UserId=userId,Event=clone(event)}); return {Ok=true,Code="OK",Value=false}
		end
		function progression:view() return {Level=4,Presets={{Index=1,Slots={{SlotId="Slot01",Sku="Water"}}}}} end
		local s=Service.new({Config=c,Now=function() return time end,NewId=function(prefix) seq+=1; return prefix.."-"..seq end,
			Delivery=delivery,World=world,Progression=progression})
		local contexts={}
		for i,storeId in ipairs(c.World.StoreIds) do
			eq(s:beginShift(storeId,"round-"..i,{InitialUserIds={i},TeamSize=1,Mode="Solo",Protected=false}).Code,"OK")
			contexts[i]={UserId=i,StoreId=storeId,RoundId="round-"..i,SeatGeneration=1,Loaded=true,Active=true,Mode="Solo",OnlineCount=1,ToolId="HandCarry",ProfileEpoch=1}
			s:syncContext(contexts[i])
		end
		local f={s=s,c=c,contexts=contexts,d=delivery,w=world,p=progression}
		function f:advance(t) time=t; s:tick(t) end
		function f:setTime(t) time=t end
		function f:send(user,action,payload) return s:action(contexts[user],action,payload) end
		function f:order(user,sku,quantity,revision)
			return self:send(user,"OrderStock",{Sku=sku or "Water",Quantity=quantity or 1,StockRevision=revision or s:view(contexts[user]).Wholesale.Revision})
		end
		function f:dock(orderId)
			delivery.events={delivery:event(orderId,"Dispatched"),delivery:event(orderId,"Arrived")}; s:tick(time)
			return s.orders[orderId].ItemIds
		end
		function f:pick(user,itemId)
			local item=s.items[itemId]; return self:send(user,item.State=="Truck" and "PickCargo" or (item.State=="Shelf" and "PickShelf" or "PickWarehouse"),{ItemId=itemId,ItemRevision=item.Revision})
		end
		function f:place(user,itemId,slot)
			local item=s.items[itemId]; return self:send(user,"PlaceShelf",{ItemId=itemId,ItemRevision=item.Revision,CarryToken=item.CarryToken,SlotId=slot or "Slot01"})
		end
		return f
	end
	-- Shared stock, all eight stores, finite last-unit competition at one revision.
	do
		local c=clone(Config); c.Products.Water.StockCap=1; local f=fixture(c)
		local rev=f.s:view(f.contexts[1]).Wholesale.Revision
		eq(f:order(1,"Water",1,rev).Code,"OK")
		eq(f:order(2,"Water",1,rev).Code,"STALE_STOCK")
		eq(f:order(2,"Water",1).Code,"OUT_OF_STOCK")
		for i=1,8 do eq(f.s:view(f.contexts[i]).Wholesale.Rows[1].Available,0) end
		eq(f.s.stores.Store01.OperatingCash,236); eq(f.s.stores.Store02.OperatingCash,240)
	end
	-- Failed checks/register are all-or-nothing; tampering, negative/NaN, foreign IDs.
	do
		local f=fixture(); local stock=f.s.stockRevision
		f.d.fail=true; eq(f:order(1).Code,"DELIVERY_FAILED"); eq(f.s.stockRevision,stock); eq(f.s.stock.Water,32); eq(f.s.stores.Store01.OperatingCash,240)
		f.d.fail=false; f.w.deny=true; eq(f:order(1).Code,"TOO_FAR"); f.w.deny=false
		eq(f:order(1,"Water",-1).Code,"BAD_REQUEST"); eq(f:order(1,"Water",0/0).Code,"BAD_REQUEST")
		eq(f:order(1,"Bogus").Code,"BAD_REQUEST")
		eq(f:send(1,"OrderStock",{Sku="Water",Quantity=1,StockRevision=1,Price=0}).Code,"BAD_REQUEST")
		f.s.stores.Store01.OperatingCash=5; eq(f:order(1,"Milk").Code,"INSUFFICIENT_FUNDS"); eq(f.s.stock.Milk,32)
		f.s.stores.Store01.OperatingCash=240
		local o=f:order(1).Value.OrderId
		eq(f:send(2,"CancelStockOrder",{OrderId=o}).Code,"NOT_OWNER")
		eq(f:send(1,"CancelStockOrder",{OrderId="fake"}).Code,"NOT_FOUND")
		eq(f:send(1,"CancelStockOrder",{OrderId=o}).Code,"OK"); eq(f.s.stores.Store01.OperatingCash,240)
		eq(f:send(1,"CancelStockOrder",{OrderId=o}).Code,"OK"); eq(f.s.stores.Store01.OperatingCash,240)
		local e=clone(f.d.orders[o].CancelEvent); e.Kind="Failed"; eq(f.s:_event(e).Code,"INVALID_STATE")
		e=clone(f.d.orders[o].CancelEvent); e.EventId="foreign"; e.StoreId="Store02"; eq(f.s:_event(e).Code,"INVALID_STATE")
		e=f.d:event(o,"Dispatched"); eq(f.s:_event(e).Code,"INVALID_STATE"); eq(#f.s:view(f.contexts[1]).Store.Items,0)
	end
	-- Cancel does not restore cycle allowance; restock returns cap without changing refund.
	do
		local f=fixture()
		for _=1,2 do local o=f:order(1,"Water",4).Value.OrderId; eq(f:send(1,"CancelStockOrder",{OrderId=o}).Code,"OK") end
		eq(f:order(1).Code,"ORDER_LIMIT"); f:advance(120)
		local o=f:order(1,"Water",4).Value.OrderId; f:advance(240)
		eq(f.s.stock.Water,32); eq(f:send(1,"CancelStockOrder",{OrderId=o}).Code,"OK"); eq(f.s.stock.Water,32); eq(f.s.stores.Store01.OperatingCash,240)
		f:advance(360); eq(f.s.stock.StarJelly,3); eq(f.s.stock.MidnightMilk,0)
		eq(f:order(1,"StarJelly",1).Code,"OK"); eq(f:order(1,"StarJelly",1).Code,"ORDER_LIMIT")
		f:advance(720); eq(f.s.stock.MidnightMilk,3); eq(f.s.stock.StarJelly,2)
		f:advance(12000); eq(f.s.stock.GlowBattery,3)
	end
	-- Dispatch wins cancel; recall only refunds items still in Truck, once.
	do
		local f=fixture(); local o=f:order(1,"Milk",3).Value.OrderId; local items=f:dock(o)
		eq(f:send(1,"CancelStockOrder",{OrderId=o}).Code,"INVALID_STATE")
		local dispatched={EventId="bad",OrderId=o,StoreId="Store01",RoundId="round-1",Kind="Dispatched",At=0}
		eq(f.s:_event(dispatched).Code,"INVALID_STATE")
		eq(f:pick(1,items[1]).Code,"OK"); eq(f:pick(1,items[2]).Code,"CARRY_FULL")
		eq(f:place(1,items[1]).Code,"OK"); eq(#f.p.awards,1)
		local e=f.d:event(o,"Recall",75); f.d.events={e}; f:advance(75)
		eq(f.s.stores.Store01.OperatingCash,234); eq(f.s.stock.Milk,31)
		eq(f.s.items[items[1]].State,"Shelf"); eq(f.s.items[items[2]].State,"Recalled")
		eq(f.s:_event(e).Code,"OK"); eq(f.s.stores.Store01.OperatingCash,234)
		eq(f:pick(1,items[2]).Code,"INVALID_STATE")
	end
	-- Direct placement, token/slot constraints, reward repeat, line sale idempotence.
	do
		local f=fixture(); local o=f:order(1,"Water",2).Value.OrderId; local items=f:dock(o); local item=f.s.items[items[1]]
		eq(f:pick(2,item.ItemId).Code,"NOT_OWNER"); eq(f:pick(1,item.ItemId).Code,"OK")
		eq(f:send(1,"PlaceShelf",{ItemId=item.ItemId,ItemRevision=item.Revision,CarryToken="fake",SlotId="Slot01"}).Code,"BAD_TOKEN")
		f.w.renderFail=true; eq(f:place(1,item.ItemId).Code,"OK"); eq(item.State,"Shelf"); eq(f.s.dirtyItems[item.ItemId],true)
		f.w.renderFail=false; f:advance(1); eq(f.s.dirtyItems[item.ItemId],nil)
		eq(f:pick(1,item.ItemId).Code,"OK"); eq(f:place(1,item.ItemId).Code,"OK"); eq(#f.p.awards,1)
		eq(f.s:claimForLine(f.contexts[1],item.ItemId,item.Revision,"line-1").Code,"OK")
		eq(#f.s:view(f.contexts[1]).Carry,0,"line token excluded from commerce carry")
		eq(f:pick(1,items[2]).Code,"CARRY_FULL")
		eq(f:send(2,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"INVALID_STATE")
		eq(f.s:sellLine(f.contexts[1],"line-1","sale-1").Code,"OK"); eq(item.State,"Sold")
		eq(f.s:sellLine(f.contexts[1],"line-1","sale-1").Code,"OK"); eq(f.s.stores.Store01.Sales,1)
		eq(f.s:sellLine(f.contexts[1],"line-1","sale-2").Code,"NOT_FOUND"); eq(f.s.stores.Store01.OperatingCash,239)
		eq(f.s:sellLine(f.contexts[2],"line-1","sale-1").Code,"INVALID_STATE"); eq(#f.p.awards,2)
		local v=f.s:view(f.contexts[1]); v.Wholesale.Rows[1].Available=999; eq(f.s.stock.Water,30)
		eq(f:send(1,"ApplyPreset",{Index=1}).Code,"OK"); eq(#f.s:view(f.contexts[1]).Store.Items,1)
	end
	-- Two concurrent holders, victim protection/active changes, recovery and secure timing.
	do
		local f=fixture(); local o=f:order(1,"Water",2).Value.OrderId; local items=f:dock(o); local item=f.s.items[items[1]]
		f.s.stores.Store02.Protected=true; eq(f:send(2,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"PROTECTED")
		f.s.stores.Store02.Protected=false
		eq(f:send(2,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"OK")
		f.contexts[1].Active=false; f.s:syncContext(f.contexts[1]); f:advance(2); eq(f.s.thefts[2].State,"Cancelled"); eq(item.State,"Truck")
		f.contexts[1].Active=true; f.s:syncContext(f.contexts[1])
		eq(f:send(2,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"OK")
		eq(f:send(3,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"OK"); f:advance(4)
		local thief=item.CarrierUserId; eq(item.State,"TheftCarried"); eq(item.OwnerStoreId,"Store01")
		eq(f.s.thefts[thief==2 and 3 or 2].State,"Cancelled")
		eq(f.w.alarms.Store01.Location,"Truck"); eq(f.w.alarms.Store01.SourceId,o)
		eq(f:send(thief,"SecureTheft",{ItemId=item.ItemId,ItemRevision=item.Revision,CarryToken=item.CarryToken}).Code,"INVALID_STATE")
		eq(f:send(1,"RecoverItem",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"OK"); eq(item.State,"Warehouse"); eq(item.Stolen,false)
		eq(f:send(2,"BeginTheft",{ItemId=items[2],ItemRevision=f.s.items[items[2]].Revision}).Code,"COOLDOWN")
		f:advance(64)
		local item2=f.s.items[items[2]]; eq(f:send(2,"BeginTheft",{ItemId=item2.ItemId,ItemRevision=item2.Revision}).Code,"OK"); f:advance(66)
		local token=item2.CarryToken; f:advance(91)
		eq(item2.OwnerStoreId,"Store01","deadline alone never transfers ownership")
		eq(f:send(1,"RecoverItem",{ItemId=item2.ItemId,ItemRevision=item2.Revision}).Code,"INVALID_STATE")
		eq(f:send(2,"SecureTheft",{ItemId=item2.ItemId,ItemRevision=item2.Revision,CarryToken=token}).Code,"OK")
		eq(item2.OwnerStoreId,"Store02"); eq(item2.State,"Warehouse"); eq(item2.Stolen,true)
		eq(f:pick(2,item2.ItemId).Code,"OK"); eq(f:place(2,item2.ItemId).Code,"OK"); eq(#f.p.awards,0)
		eq(f:send(3,"BeginTheft",{ItemId=item2.ItemId,ItemRevision=item2.Revision}).Code,"OK"); f:advance(93)
		eq(f:send(2,"RecoverItem",{ItemId=item2.ItemId,ItemRevision=item2.Revision}).Code,"OK")
		eq(item2.Stolen,true,"recovery must not launder previously secured stock")
		eq(f:pick(2,item2.ItemId).Code,"OK"); eq(f:place(2,item2.ItemId).Code,"OK")
		eq(f.s:claimForLine(f.contexts[2],item2.ItemId,item2.Revision,"stolen-line").Code,"OK")
		eq(f.s:sellLine(f.contexts[2],"stolen-line","stolen-sale").Code,"OK")
		eq(f.s.stores.Store02.OperatingCash,247); eq(f.s.stores.Store02.Sales,0); eq(f.s.stores.Store02.Revenue,0); eq(#f.p.awards,0)
	end
	-- Departure and shift closure revoke tokens, discard cash, do not reset by reconnect.
	do
		local f=fixture(); local o=f:order(1,"Water",2).Value.OrderId; local items=f:dock(o)
		eq(f:pick(1,items[1]).Code,"OK"); local token=f.s.items[items[1]].CarryToken
		f.s:depart(1); eq(f.s.items[items[1]].State,"Warehouse"); eq(f.s.items[items[1]].CarryToken,false)
		f.s:syncContext(f.contexts[1]); eq(f:pick(1,items[1]).Code,"OK"); eq(f.s.items[items[1]].CarryToken==token,false)
		eq(f.s:beginShift("Store01","round-1",{InitialUserIds={1},TeamSize=1,Mode="Solo",Protected=false}).Code,"OK")
		eq(f.s.stores.Store01.OperatingCash,232)
		eq(f.s:endShift("Store01","round-1").Code,"OK"); eq(f.s.stores.Store01.OperatingCash,0)
		eq(f.s.items[items[1]].State,"Expired"); eq(f.s.items[items[2]].State,"Recalled")
		eq(f.s:endShift("Store01","round-1").Code,"OK"); eq(f.d.closeCalls,1)
		eq(f.s:beginShift("Store01","round-1",{InitialUserIds={1},TeamSize=1,Mode="Solo",Protected=false}).Code,"OK"); eq(f.s.stores.Store01.OperatingCash,0)
	end
	-- Recall at input boundary wins, pending permanent reward retries use original ID.
	do
		local f=fixture(); local o=f:order(1).Value.OrderId; local item=f.s.items[f:dock(o)[1]]
		local e=f.d:event(o,"Recall",75); f.d.events={e}; f:setTime(75)
		eq(f:pick(1,item.ItemId).Code,"STALE_ITEM"); eq(item.State,"Recalled"); eq(f.s.stores.Store01.OperatingCash,240)
		local o2=f:order(1).Value.OrderId; local i2=f:dock(o2)[1]
		f.p.fail=true; eq(f:pick(1,i2).Code,"OK"); eq(f:place(1,i2).Code,"OK"); eq(#f.p.awards,0)
		f.p.fail=false; f:advance(76); eq(#f.p.awards,1); f:advance(77); eq(#f.p.awards,1)
	end
	-- Slot capacity/SKU, cart capacity and return-to-original-slot fallback.
	do
		local f=fixture(); f.contexts[1].ToolId="Handcart"; f.s:syncContext(f.contexts[1])
		local water=f:dock(f:order(1,"Water",4).Value.OrderId)
		eq(f:pick(1,water[1]).Code,"OK"); eq(f:pick(1,water[2]).Code,"OK"); eq(f:pick(1,water[3]).Code,"CARRY_FULL")
		eq(f:place(1,water[1]).Code,"OK"); eq(f:place(1,water[2]).Code,"OK")
		for i=3,4 do eq(f:pick(1,water[i]).Code,"OK"); eq(f:place(1,water[i]).Code,"OK") end
		local milk=f:dock(f:order(1,"Milk",1).Value.OrderId)[1]; eq(f:pick(1,milk).Code,"OK"); eq(f:place(1,milk).Code,"SLOT_FULL")
		eq(f:place(1,milk,"Slot02").Code,"OK")
		eq(f:pick(1,water[1]).Code,"OK"); eq(f:place(1,water[1],"Slot02").Code,"SKU_MISMATCH"); eq(f:place(1,water[1],"Slot03").Code,"OK")
		local item=f.s.items[water[1]]; eq(f.s:claimForLine(f.contexts[1],item.ItemId,item.Revision,"return-line").Code,"OK")
		eq(f.s:returnLine(f.contexts[1],"return-line").Code,"OK"); eq(item.State,"Shelf"); eq(item.SlotId,"Slot03")
		eq(f.s:returnLine(f.contexts[1],"return-line").Code,"NOT_FOUND")
	end
	-- Store item/open-order limits include reservations; support is once per shift.
	do
		local c=clone(Config); c.Wholesale.MaxItemsPerStore=3; local f=fixture(c)
		eq(f:order(1,"Water",4).Code,"ORDER_LIMIT"); eq(f:order(1,"Water",2).Code,"OK")
		eq(f:order(1,"Milk",2).Code,"ORDER_LIMIT"); eq(f:order(1,"Milk",1).Code,"OK"); eq(f:order(1,"Bread",1).Code,"ORDER_LIMIT")
		f.s.stores.Store02.OperatingCash=0; f:advance(1); eq(f.s.stores.Store02.OperatingCash,40); eq(f.s.stores.Store02.SupportUsed,true)
		f.s.stores.Store02.OperatingCash=0; f:advance(2); eq(f.s.stores.Store02.OperatingCash,0)
		eq(#f.p.awards,0)
	end
	-- Steal/claim contention and movement failure never consume or duplicate goods.
	do
		local f=fixture(); local item=f.s.items[f:dock(f:order(1).Value.OrderId)[1]]
		eq(f:pick(1,item.ItemId).Code,"OK"); eq(f:place(1,item.ItemId).Code,"OK")
		eq(f:send(2,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"OK")
		eq(f.s:claimForLine(f.contexts[1],item.ItemId,item.Revision,"race-line").Code,"OK"); f:advance(2)
		eq(f.s.thefts[2].State,"Cancelled"); eq(item.State,"Carried"); eq(f.s:returnLine(f.contexts[1],"race-line").Code,"OK")
		eq(f:send(2,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"OK"); f.w.deny=true; f:advance(4)
		eq(f.s.thefts[2].State,"Cancelled"); eq(item.State,"Shelf"); f.w.deny=false
		eq(f:send(2,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"OK"); f:advance(6)
		eq(item.State,"TheftCarried"); eq(f.w.alarms.Store01.Location,"Shelf"); f.s:depart(2)
		eq(item.State,"Warehouse"); eq(item.CarryToken,false); eq(item.OwnerStoreId,"Store01")
	end
	-- A teammate can accept a validated Tray line; no caller can cross store rounds.
	do
		local f=fixture(); local c=clone(f.contexts[1]); c.UserId=9; f.s:syncContext(c)
		local item=f.s.items[f:dock(f:order(1).Value.OrderId)[1]]
		eq(f:pick(1,item.ItemId).Code,"OK"); eq(f:place(1,item.ItemId).Code,"OK")
		eq(f.s:claimForLine(f.contexts[1],item.ItemId,item.Revision,"team-line").Code,"OK")
		eq(f.s:sellLine(f.contexts[2],"team-line","foreign-sale").Code,"NOT_FOUND")
		eq(f.s:sellLine(c,"team-line","team-sale").Code,"OK"); eq(f.p.awards[2].UserId,9)
	end
	-- Failed reservations and arrival failures settle only refundable units.
	do
		local f=fixture(); local o=f:order(1,"Bread",4).Value.OrderId
		local failed=f.d:event(o,"Failed"); eq(f.s:_event(failed).Code,"OK"); eq(f.s.stores.Store01.OperatingCash,240)
		eq(f.s:_event(failed).Code,"OK"); eq(f.s.stock.Bread,32)
		local o2=f:order(1,"Milk",4).Value.OrderId; eq(f.s:_event(f.d:event(o2,"Dispatched")).Code,"OK")
		eq(f.s:_event(f.d:event(o2,"Failed")).Code,"OK"); eq(f.s.stock.Milk,32); eq(f.s.stores.Store01.OperatingCash,240)
		for _,itemId in ipairs(f.s.orders[o2].ItemIds) do eq(f.s.items[itemId].State,"Recalled") end
	end
	print("CommerceService: "..checks.." checks passed (fake Delivery/World/Progression; serialized contention)")
	return checks
end
