-- Real Commerce + Delivery, deterministic clock/world facade. No Studio.
return function(Commerce,Delivery,C)
 local checks=0
 local function eq(a,b,label) checks+=1; assert(a==b,(label or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
 local function ok(r) eq(r.Code,"OK"); return r.Value end
 local function fixture()
  local f={time=0,seq=0,denied=false,renders={},checks={}}
  local world={}
  function world:check(c,t) table.insert(f.checks,{Context=c,Target=t}); return {Ok=not f.denied,Code=f.denied or "OK"} end
  function world:renderItem(item) f.renders[item.ItemId]=item; return {Ok=true,Code="OK"} end
  function world:setAlarm() return {Ok=true,Code="OK"} end
  local engine={}
  for _,name in ipairs({"createTruck","moveTruck","destroyTruck"}) do engine[name]=function() return {Ok=true,Code="OK"} end end
  local progression={award=function() return {Ok=true,Code="OK"} end,view=function() return {} end}
  f.d=Delivery.new({Config=C,Now=function() return f.time end,Engine=engine})
  f.s=Commerce.new({Config=C,Now=function() return f.time end,World=world,Delivery=f.d,Progression=progression,
   NewId=function(prefix) f.seq+=1; return prefix.."-"..f.seq end})
  f.contexts={}
  for n=1,2 do
   local c={UserId=n,StoreId="Store0"..n,RoundId="round"..n,SeatGeneration=1,Loaded=true,Active=true,Mode="Solo",ToolId="HandCarry",ProfileEpoch=1}
   f.contexts[n]=c; ok(f.s:beginShift(c.StoreId,c.RoundId,{InitialUserIds={n},TeamSize=1,Mode="Solo",Protected=false})); f.s:syncContext(c)
  end
  function f:act(n,action,p) return self.s:action(self.contexts[n],action,p) end
  function f:advance(delta) self.time+=delta; self.s:tick(self.time) end
  function f:order(q) return self:act(1,"OrderStock",{Sku="Water",Quantity=q,StockRevision=self.s.stockRevision}) end
  function f:dock(q)
   local order=ok(self:order(q)); self:advance(5); self:advance(12)
   eq(self.s.orders[order.OrderId].State,"Docked"); return self.s.orders[order.OrderId]
  end
  function f:pick(item,n)
   return self:act(n or 1,({Truck="PickCargo",Warehouse="PickWarehouse",Shelf="PickShelf"})[item.State],{ItemId=item.ItemId,ItemRevision=item.Revision})
  end
  function f:drop(item,slot,n)
   local p={ItemId=item.ItemId,ItemRevision=item.Revision,CarryToken=item.CarryToken}
   if slot then p.SlotId=slot end
   return self:act(n or 1,slot and "PlaceShelf" or "DropWarehouse",p)
  end
  function f:bins(expected)
   local bins,n={},0
   for _,item in pairs(self.s.items) do if item.OwnerStoreId=="Store01" and item.State=="Warehouse" then
    eq(type(item.WarehouseBin),"number"); eq(bins[item.WarehouseBin],nil,"unique bin"); bins[item.WarehouseBin]=true; n+=1
    eq(self.renders[item.ItemId].WarehouseBin,item.WarehouseBin)
   end end
   eq(n,expected); eq(self.s:_size(self.s.stores.Store01),expected + #self.s:_carry(1))
  end
  return f
 end
 do
  local f=fixture(); local initial=f.s.stock.Water
  f.denied="TOO_FAR"; eq(f:order(1).Code,"TOO_FAR"); eq(f.s.stock.Water,initial); eq(f.s.stores.Store01.OperatingCash,240)
  eq(f.checks[#f.checks].Target.Marker,"OfficePC"); eq(f.checks[#f.checks].Target.StoreId,"Store01")
  f.denied="NO_LINE_OF_SIGHT"; eq(f:order(1).Code,"NO_LINE_OF_SIGHT"); f.denied=false
  f.contexts[1].Active=false; f.s:syncContext(f.contexts[1]); eq(f:order(1).Code,"NOT_ACTIVE")
  f.contexts[1].Active=true; f.s:syncContext(f.contexts[1])
  local order=f:dock(4); local item=f.s.items[order.ItemIds[1]]
  eq(f.renders[item.ItemId].CargoIndex,1); ok(f:pick(item)); local stale={ItemId=item.ItemId,ItemRevision=item.Revision,CarryToken=item.CarryToken}
  ok(f:drop(item)); eq(item.State,"Warehouse"); eq(item.CarryToken,false)
  eq(f:act(1,"DropWarehouse",stale).Code,"STALE_ITEM")
  eq(f:act(2,"PickWarehouse",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"NOT_OWNER")
  eq(f:act(2,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"INVALID_STATE")
  f:advance(75); eq(item.State,"Warehouse"); eq(f.s.stores.Store01.OperatingCash,236)
  f:advance(3); eq(f.s.stores.Store01.OperatingCash,236); f:bins(1)
  ok(f:pick(item)); eq(f:act(1,"DropWarehouse",stale).Code,"STALE_ITEM")
  f.s:depart(1); eq(item.State,"Warehouse"); eq(item.CarryToken,false); f:bins(1)
  f.contexts[1].SeatGeneration=2; f.s:syncContext(f.contexts[1]); eq(f.s.stores.Store01.OperatingCash,236)
  ok(f:pick(item)); ok(f:drop(item,"Slot01")); eq(item.State,"Shelf"); eq(item.WarehouseBin,false)
  ok(f:pick(item)); ok(f:drop(item)); f:bins(1)
 end
 do
  local f=fixture(); local last
  -- Six real deliveries; advance wholesale cycles without changing production caps.
  for batch=1,6 do
   if batch==3 or batch==5 then f:advance(120) end
   local order=f:dock(4)
   for _,id in ipairs(order.ItemIds) do last=f.s.items[id]; ok(f:pick(last)); ok(f:drop(last)) end
   f:advance(3)
  end
  f:bins(24); eq(f:order(1).Code,"ORDER_LIMIT")
  local released=last.WarehouseBin; ok(f:pick(last)); f:bins(23)
  eq(f:order(1).Code,"ORDER_LIMIT","carried item still reserves capacity")
  ok(f:drop(last)); eq(last.WarehouseBin,released); f:bins(24)
  ok(f:pick(last)); ok(f:drop(last,"Slot01"))
  ok(f:act(2,"BeginTheft",{ItemId=last.ItemId,ItemRevision=last.Revision})); f:advance(2)
  eq(last.State,"TheftCarried"); eq(f.s:_size(f.s.stores.Store01),24); eq(f:order(1).Code,"ORDER_LIMIT")
  local stolenToken=last.CarryToken
  ok(f:act(1,"RecoverItem",{ItemId=last.ItemId,ItemRevision=last.Revision})); f:bins(24)
  eq(last.CarryToken,false); eq(f:act(2,"SecureTheft",{ItemId=last.ItemId,ItemRevision=last.Revision,CarryToken=stolenToken}).Code,"BAD_TOKEN")
  local walletBefore=f.s.stores.Store01.OperatingCash
  ok(f.s:beginShift("Store01","round1",{InitialUserIds={1},TeamSize=1,Mode="Solo",Protected=false})); eq(f.s.stores.Store01.OperatingCash,walletBefore)
  ok(f.s:endShift("Store01","round1")); eq(f.s.stores.Store01.OperatingCash,0)
  for _,item in pairs(f.s.items) do eq(item.State,"Expired"); eq(item.WarehouseBin,false) end
 end
 print("WAREHOUSE_SERVER_PASS "..checks.." checks: real logistics, 24 bins/cap, PC rejection, duplicate/foreign/theft/departure/reconnect/expiry; no Studio")
end
