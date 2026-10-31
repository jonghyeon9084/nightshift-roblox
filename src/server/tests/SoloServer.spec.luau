-- Actual modules, fake clock/storage/world/NPC evidence. Never a Studio claim.
local checks=0
local function eq(a,b,label) checks+=1; assert(U.same(a,b),(label or "equality")..": "..tostring(a).." ~= "..tostring(b)) end
local function ok(r,label) checks+=1; assert(r and r.Ok,tostring(label or "OK")..": "..tostring(r and r.Code)); return r.Value end
local function code(r,want,label) eq(r.Code,want,label) end
local function count(t) local n=0; for _ in pairs(t) do n+=1 end; return n end
local function fixture()
 local t,unix,serial=0,1000,0
 local now=function() return t end
 local id=function(prefix) serial+=1; return prefix..":"..serial end
 local config=U.copy(CC); local store=Profiles.newMemoryStore()
 local profiles=Profiles.new({Config=config,Store=store,SessionId=id("server"),UnixNow=function() return unix end,Wait=function() end,IsStudio=true})
 local world={stores={},rendered={},trucks={},stages={},reject=false,restoreFail=false}
 for _,s in ipairs(config.World.StoreIds) do world.stores[s]={available=true} end
 function world:check() return U.result(self.reject or "OK") end
 function world:stageInventory(c,items) if self.restoreFail then return U.result("RESTORE_FAILED") end; self.stages[c.UserId]=U.copy(items); return U.result("OK") end
 function world:publishInventoryStage(c) self.stages[c.UserId]=nil; return U.result("OK") end
 function world:discardInventoryStage(c) self.stages[c.UserId]=nil; return U.result("OK") end
 function world:renderItem(i) self.rendered[i.ItemId]=U.copy(i); return U.result("OK") end
 function world:createTruck(oid,sid) self.trucks[oid]=sid; return U.result("OK") end
 function world:moveTruck(oid,segment,alpha) eq(segment=="ApproachToDock" or segment=="DockToExit",true,"actual world segment contract"); return U.result("OK") end
 function world:destroyTruck(oid) self.trucks[oid]=nil; return U.result("OK") end
 function world:setAlarm() return U.result("OK") end
 function world:renderOwner() return U.result("OK") end
 function world:move() return true end
 function world:alive() return true end
 function world:setOutage(s,active) self.outage=active end
 local npcs={}
 local npc={validate=function(_,c,npcId,kind,phase,opportunity)
  local r=npcs[npcId]; return U.result(r and r.uid==c.UserId and r.kind==kind and r.phase==phase and r.opportunity==opportunity and "OK" or "INVALID_NPC")
 end}
 local traffic={validate=function(_,c,col) return U.result(col.Valid==true and "OK" or "INVALID_COLLISION") end}
 local commerce=Commerce.new({Config=config,Profiles=profiles,Now=now,NewId=id,World=world,NpcAuthority=npc,CollisionAuthority=traffic})
 local owners=Ownership.new(config,profiles,function(c,p)return commerce:restoreInventory(c,p) end,world); commerce:setOwnership(owners)
 local gameService=Game.new({Config=Config,CommerceConfig=config,Profiles=profiles,Commerce=commerce,Ownership=owners,World=world,Now=now,NewId=id})
 local f={p=profiles,co=commerce,owners=owners,w=world,config=config,id=id,npcs=npcs,game=gameService,storage=store}
 function f:time(value,tick) t=value; if tick then self.co:tick(t) end end
 function f:unix(value) unix=value end
 function f:add(uid)
  local player={UserId=uid,DisplayName="사장"..uid}; local p=ok(self.p:load(uid),"load")
  local user=self.game:connect(player); ok(self.game:profileReady(player,p.Session.Epoch),"assign")
  user.loaded=true; self.owners.owners[uid].Loaded=true
  return self.game:context(user),player
 end
 function f:order(c,sku,n,allocation)
  return self.co:action(c,"OrderStock",{Sku=sku,Quantity=n,AllocationId=allocation or false,StockRevision=self.co.stock.Revision})
 end
 function f:deliver(c,oid)
  self.co:tick(t); t+=4; self.co:tick(t); t+=12; self.co:tick(t)
  eq(self.co.stores[c.StoreId].Orders[oid].State,"Docked","delivered")
 end
 function f:stock(c,iid,slot,warehouse)
  local function item() return self.co.stores[c.StoreId].Items[iid] end
  ok(self.co:action(c,"PickCargo",{ItemId=iid,ItemRevision=item().Revision}))
  if warehouse then
   ok(self.co:action(c,"DropWarehouse",{ItemId=iid,ItemRevision=item().Revision,CarryToken=item().CarryToken}))
   ok(self.co:action(c,"PickWarehouse",{ItemId=iid,ItemRevision=item().Revision}))
  end
  ok(self.co:action(c,"PlaceShelf",{ItemId=iid,ItemRevision=item().Revision,CarryToken=item().CarryToken,SlotId=slot}))
 end
 function f:sale(c,kind,opp)
  local nid=id("npc"); npcs[nid]={uid=c.UserId,kind=kind,phase="Browse",opportunity=opp or false}
  local selection=self.co:selectNpcItems(c,nid,kind,opp or false)
  if not selection.Ok then return selection end
  npcs[nid].phase="Checkout"
  local sale={TransactionId=id("sale"),NpcId=nid,Kind=kind,SelectionId=selection.Value.SelectionId,Items=selection.Value.Items,OpportunityId=opp or false}
  return self.co:commitNpcSale(c,sale),sale
 end
 return f
end

-- Ownership, exact v2 wire and no permission escalation.
do
 local f=fixture(); local assigned={}
 for uid=1,8 do local c=f:add(uid); eq(assigned[c.StoreId],nil,"unique slot"); assigned[c.StoreId]=uid end
 local p=ok(f.p:load(9)); code(f.owners:assignOwner({UserId=9,DisplayName="9"},p.Session.Epoch),"STORE_FULL")
 eq(count(f.owners.slots),8); local c=f.owners:getOwnerContext(1)
 eq(ok(f.owners:assignOwner({UserId=1,DisplayName="1"},c.ProfileEpoch)).StoreId,c.StoreId)
 local req={ProtocolVersion=2,RequestId=1,Action="OrderStock",StoreId=c.StoreId,RoundId=false,OwnerGeneration=c.OwnerGeneration,
  Payload={Sku="Water",Quantity=1,StockRevision=1,AllocationId=false}}
 local r,why=Protocol.validateCommerce(req,CC); eq(why,"OK"); eq(r,req)
 for _,action in ipairs({"SecureTheft","ForceDrop","CommitNpcSale","JoinStore","GrantMoney"}) do local bad=U.copy(req); bad.Action=action; local _,codeValue=Protocol.validateCommerce(bad,CC); eq(codeValue,"BAD_REQUEST") end
 req.ProtocolVersion=1; local _,whyOld=Protocol.validateCommerce(req,CC); eq(whyOld,"VERSION_MISMATCH")
 local stale=U.copy(c); stale.OwnerGeneration+=1; code(f:order(stale,"Water",1),"STALE_OWNER")
 local foreign=U.copy(c); foreign.StoreId="Store02"; code(f:order(foreign,"Water",1),"NOT_OWNER")
 f.w.reject="TOO_FAR"; code(f:order(c,"Water",1),"TOO_FAR"); eq(ok(f.p:get(1)).Wallet,240)
 local wire=Protocol.newConnection(CC,0); req.ProtocolVersion=2
 for i=1,129 do req.RequestId=i; Protocol.remember(wire,U.copy(req),{Ok=true},CC); wire.high=i end
 eq(wire.cache[1],nil); eq(wire.high,129); eq(#wire.order,128)
end

-- Materialized paid goods survive in-transit leave, canonical save and a new epoch exactly once.
do
 local f=fixture(); local c,player=f:add(1)
 local order=ok(f:order(c,"Water",2)); eq(ok(f.p:get(1)).Wallet,232); eq(#ok(f.p:get(1)).Store.Items,2)
 eq(ok(f.p:get(1)).Store.Items[1].State,"Warehouse","canonical paid transit")
 f.co:tick(0); code(f.co:action(c,"CancelStockOrder",{OrderId=order.OrderId}),"INVALID_STATE")
 f.game:disconnect(player); eq(count(f.owners.slots),0); ok(f.p:save(1,true))
 local c2=f:add(1); eq(c2.OwnerGeneration>c.OwnerGeneration,true); eq(c2.ProfileEpoch>c.ProfileEpoch,true)
 eq(count(f.co.stores[c2.StoreId].Items),2); eq(ok(f.p:get(1)).Wallet,232)
 for _,iid in ipairs(order.ItemIds) do eq(f.co.stores[c2.StoreId].Items[iid].State,"Warehouse") end
 eq(count(f.co.stores[c2.StoreId].Orders),0)
 code(f.co:restoreInventory(c2,ok(f.p:get(1))),"RESTORE_FAILED")
 code(f:order(c,"Water",1),"STALE_OWNER")
end

-- Cancel/refund only before departure, public stock last-unit race, validation failure rollback.
do
 local f=fixture(); local c=f:add(1); local b=f:add(2)
 f.co.stock.Public.Water=1
 local revision=f.co.stock.Revision; local order=ok(f:order(c,"Water",1))
 code(f.co:action(b,"OrderStock",{Sku="Water",Quantity=1,AllocationId=false,StockRevision=revision}),"STALE_STOCK")
 code(f:order(b,"Water",1),"OUT_OF_STOCK")
 ok(f.co:action(c,"CancelStockOrder",{OrderId=order.OrderId})); eq(ok(f.p:get(1)).Wallet,240); eq(f.co.stock.Public.Water,1)
 code(f.co:action(c,"CancelStockOrder",{OrderId=order.OrderId}),"INVALID_STATE")
 local before=ok(f.p:get(1)); local countBefore=count(f.co.stores[c.StoreId].Items)
 code(f.co:_commit(c,function(p,s) p.Wallet=-1; s.Items.bad={ItemId="bad"}; return p,"OK" end),"PROFILE_CORRUPT")
 eq(ok(f.p:get(1)),before); eq(count(f.co.stores[c.StoreId].Items),countBefore)
end

-- Real service logistics, atomic NPC sale, cursor/replay, selection contention and currency cap.
do
 local f=fixture(); local c=f:add(1); local order=ok(f:order(c,"Water",2)); f:deliver(c,order.OrderId)
 f:stock(c,order.ItemIds[1],"Slot01",true); f:stock(c,order.ItemIds[2],"Slot01",false)
 local i=f.co.stores[c.StoreId].Items[order.ItemIds[1]]; eq(i.OwnerLogisticsComplete,true)
 local result,sale=f:sale(c,"Rich"); ok(result); eq(result.Value.Units,2); eq(result.Value.Revenue,14)
 eq(ok(f.p:get(1)).Wallet,246); eq(ok(f.p:get(1)).XP,10); eq(count(f.co.stores[c.StoreId].Items),0)
 local revision=ok(f.p:get(1)).Revision; ok(f.co:commitNpcSale(c,sale)); eq(ok(f.p:get(1)).Revision,revision)
 sale.Kind="Normal"; code(f.co:commitNpcSale(c,sale),"REQUEST_ID_REUSED")
 local o2=ok(f:order(c,"Milk",1)); f:deliver(c,o2.OrderId); f:stock(c,o2.ItemIds[1],"Slot02",false)
 local n1=f.id("npc"); f.npcs[n1]={uid=1,kind="Normal",phase="Browse",opportunity=false}
 local sel=ok(f.co:selectNpcItems(c,n1,"Normal",false))
 local n2=f.id("npc"); f.npcs[n2]={uid=1,kind="Normal",phase="Browse",opportunity=false}
 code(f.co:selectNpcItems(c,n2,"Normal",false),"OUT_OF_STOCK")
 ok(f.p:mutate(1,c.ProfileEpoch,function(p)p.Wallet=CC.Economy.MaxCurrency; return p end))
 f.npcs[n1].phase="Checkout"
 local capped={TransactionId=f.id("sale"),NpcId=n1,Kind="Normal",SelectionId=sel.SelectionId,Items=sel.Items,OpportunityId=false}
 code(f.co:commitNpcSale(c,capped),"CURRENCY_CAP"); eq(count(f.co.stores[c.StoreId].Items),1)
 local item=f.co.stores[c.StoreId].Items[o2.ItemIds[1]]
 ok(f.co:action(c,"PickShelf",{ItemId=item.ItemId,ItemRevision=item.Revision}))
 code(f.co:commitNpcSale(c,capped),"STALE_ITEM")
end

-- Persistent upgrade CAS and recovery loan: no support cash, no double loan, no free refund.
do
 local f=fixture(); local c,player=f:add(1); local p=ok(f.p:get(1))
 local payload={UpgradeId="Warehouse",ExpectedLevel=0,ProfileRevision=p.Revision}
 ok(f.co:action(c,"BuyUpgrade",payload)); eq(ok(f.p:get(1)).Wallet,120); eq(ok(f.p:get(1)).Store.Upgrades.Warehouse,1)
 code(f.co:action(c,"BuyUpgrade",payload),"STALE_PROFILE")
 f.game:disconnect(player); ok(f.p:save(1,true)); c=f:add(1)
 eq(ok(f.p:get(1)).Store.Upgrades.Warehouse,1); eq(f.co:view(c).Store.WarehouseCapacity,32)
 ok(f.p:mutate(1,c.ProfileEpoch,function(value)value.Wallet=0; return value end))
 local loan=ok(f.co:action(c,"RequestRecoveryStock",{ProfileRevision=ok(f.p:get(1)).Revision}))
 eq(ok(f.p:get(1)).Wallet,0); eq(ok(f.p:get(1)).Store.RecoveryDebt,4)
 code(f.co:action(c,"RequestRecoveryStock",{ProfileRevision=ok(f.p:get(1)).Revision}),"INVALID_STATE")
 code(f.co:action(c,"CancelStockOrder",{OrderId=loan.OrderId}),"INVALID_STATE")
 f:deliver(c,loan.OrderId); f:stock(c,loan.ItemIds[1],"Slot01",false)
 local sale=ok(f:sale(c,"Normal")); eq(sale.DebtPaid,4); eq(sale.WalletDelta,3); eq(ok(f.p:get(1)).Store.RecoveryDebt,0)
end

-- Failed restore never claims a slot; corrupt/failed loads never write defaults.
do
 local f=fixture(); f.w.restoreFail=true; local p=ok(f.p:load(1))
 code(f.owners:assignOwner({UserId=1,DisplayName="A"},p.Session.Epoch),"RESTORE_FAILED")
 eq(count(f.owners.slots),0); eq(count(f.co.stores),0); eq(count(f.w.stages),0)
 local calls=0
 local broken={Mode="Memory",GetBudget=function()return 1 end,UpdateAsync=function() calls+=1; error("offline fake failure") end}
 local bad=Profiles.new({Config=CC,Store=broken,SessionId="bad",UnixNow=function()return 1000 end,Wait=function()end})
 code(bad:load(1),"PROFILE_UNAVAILABLE"); eq(calls,3); code(bad:save(1,true),"PROFILE_UNAVAILABLE")
 local raw={SchemaVersion=99}; local writes=0
 local corrupt={Mode="Memory",GetBudget=function()return 1 end,UpdateAsync=function(_,key,transform)local nextValue=transform(raw); if nextValue then writes+=1; raw=nextValue end; return nextValue end}
 local service=Profiles.new({Config=CC,Store=corrupt,SessionId="corrupt",UnixNow=function()return 1000 end,Wait=function()end})
 code(service:load(1),"SCHEMA_UNSUPPORTED"); eq(writes,0)
end

-- Legacy migration retains money/team history, lease exclusion and negative Studio isolation.
do
 local f=fixture(); local legacy=SoloProfile.new(CC); legacy.SchemaVersion=1; legacy.Store=nil; legacy.EconomyCursor=nil; legacy.ActivityCursor=nil; legacy.Wallet=17
 legacy.Best={{Key="Coop/4/1/false/false",Sales=2,Revenue=14,TeamSize=4,ToolTier=1,Mode="Coop",HadSupport=false,HadReduction=false}}
 f.storage:UpdateAsync("u:1",function()return legacy end)
 local c=f:add(1); local p=ok(f.p:get(1)); eq(p.Wallet,17); eq(p.Best[1].TeamSize,4); eq(p.SchemaVersion,2)
 eq(p.EconomyCursor.Epoch,c.ProfileEpoch); eq(p.ActivityCursor.Epoch,c.ProfileEpoch)
 local other=Profiles.new({Config=CC,Store=f.storage,SessionId="other",UnixNow=function()return 1000 end,Wait=function()end})
 code(other:load(1),"SESSION_LOCKED")
 ok(f.p:load(-1)); code(other:load(-1),"BAD_REQUEST")
 f:unix(1106); eq(f.p:status(1).Frozen,true); code(f:order(c,"Water",1),"PROFILE_FROZEN")
 f:unix(1121); code(f.p:save(1,false),"LEASE_LOST")
end

-- Save failure retains dirty data and an exit barrier; in-flight autosave preserves newer revision.
do
 local f=fixture(); local c=f:add(1); ok(f:order(c,"Water",1))
 local original=f.storage.UpdateAsync
 f.storage.UpdateAsync=function()error("injected save failure")end
 code(f.p:save(1,false),"SAVE_FAILED"); eq(f.p:status(1).State,"SaveFailed"); eq(f.p:status(1).Dirty,true); eq(ok(f.p:get(1)).Wallet,236)
 f.storage.UpdateAsync=original; ok(f.p:save(1,false)); eq(f.p:status(1).Dirty,false)
 local captured=ok(f.p:get(1)).Revision
 f.storage.UpdateAsync=function(self,key,fn) coroutine.yield("IO"); return original(self,key,fn) end
 local writer=coroutine.create(function() return f.p:save(1,false) end); local resumed,why=coroutine.resume(writer); eq(resumed,true); eq(why,"IO")
 ok(f:order(c,"Water",1)); eq(ok(f.p:get(1)).Wallet,232)
 local finished,result=coroutine.resume(writer); eq(finished,true); ok(result); eq(f.p:status(1).SavedRevision,captured); eq(f.p:status(1).Dirty,true)
 f.storage.UpdateAsync=original
 ok(f.co:beginBarrier(c,"test")); code(f:order(c,"Water",1),"PROFILE_FROZEN"); ok(f.p:save(1,true))
end

-- R-A/R-B: real ledger reservation, paid units, fixed opportunities, actual sale integration, once-only achievements.
do
 local f=fixture(); local a=f:add(1); local b=f:add(2)
 f.co:tick(0); local cy=f.co.demand.cycle; eq(cy.Phase,"Prepare"); eq(f.co.stock.Public.Water,28); eq(f.co.stock.Public.Bread,28)
 for _,c in ipairs({a,b}) do ok(f.co:action(c,"SetContestParticipation",{CycleId=cy.CycleId,Participate=true})) end
 local function allocation(c,sku)
  for id,v in pairs(f.co.demand.allocations) do if v.UserId==c.UserId and v.Sku==sku then return id end end
 end
 code(f:order(b,"Water",1,allocation(a,"Water")),"NOT_OWNER")
 local orders={}
 for _,c in ipairs({a,b}) do
  orders[c.UserId]={ok(f:order(c,"Water",2,allocation(c,"Water"))),ok(f:order(c,"Bread",2,allocation(c,"Bread")))}
 end
 f:time(1,true); f:time(13,true); f:time(14,true)
 for _,c in ipairs({a,b}) do for _,iid in ipairs(orders[c.UserId][1].ItemIds) do f:stock(c,iid,"Slot01",true) end end
 f:time(15,true); f:time(18,true); f:time(30,true)
 for _,c in ipairs({a,b}) do for _,iid in ipairs(orders[c.UserId][2].ItemIds) do f:stock(c,iid,"Slot02",true) end end
 f:time(30,true); code(f.co:action(a,"SetContestParticipation",{CycleId=cy.CycleId,Participate=false}),"NEXT_CYCLE")
 code(f:sale(a,"Rich"),"OUT_OF_STOCK","held contest stock")
 for index,offset in ipairs(CC.Contest.OpportunityOffsets) do
  f:time(cy.StartsAt+offset,false)
  for _,c in ipairs({a,b}) do
   local offer=ok(f.co.contest:offerOpportunity(c,index)); eq(ok(f.co.contest:offerOpportunity(c,index)).OpportunityId,offer.OpportunityId)
   local nid=f.id("npc"); f.npcs[nid]={uid=c.UserId,kind="Normal",phase="Browse",opportunity=offer.OpportunityId}
   local sel=ok(f.co:selectNpcItems(c,nid,"Normal",offer.OpportunityId))
   ok(f.co.contest:observeOpportunity(c,offer.OpportunityId,cy.StartsAt+offset,"Arrived",false))
   f.npcs[nid].phase="Checkout"
   local sale={TransactionId=f.id("sale"),NpcId=nid,Kind="Normal",SelectionId=sel.SelectionId,Items=sel.Items,OpportunityId=offer.OpportunityId}
   ok(f.co:commitNpcSale(c,sale)); ok(f.co:commitNpcSale(c,sale))
  end
 end
 for _,c in ipairs({a,b}) do
  eq(ok(f.p:get(c.UserId)).Store.Achievements.DemandCompletions,1)
  local score=f.co.contest.cycle.Owners[c.UserId]; eq(score.Diversity,20); eq(score.Plan,40); eq(score.Logistics,30)
 end
 f:time(cy.EndsAt,true)
 eq(f.co.contest.cycle.Results.Comparable,true); eq(#f.co.contest.cycle.Results.Winners.Plan,2)
 for _,c in ipairs({a,b}) do eq(ok(f.p:get(c.UserId)).Store.Achievements.ContestCompletions,1) end
 f.co:tick(cy.EndsAt+1); eq(ok(f.p:get(1)).Store.Achievements.ContestCompletions,1)
 f:time(cy.EndsAt+15,true); eq(f.co.demand.cycle.Rotation,2); eq(f.co.demand.cycle.Owners[1].Targets.Milk,2)
end

-- Unused allocations return once; late join cannot obtain a second allocation.
do
 local f=fixture(); local c,player=f:add(1); f.co:tick(0)
 eq(f.co.stock.Public.Water,30); f.co.demand:releaseAllocations(150); eq(f.co.stock.Public.Water,32)
 f.co.demand:releaseAllocations(151); eq(f.co.stock.Public.Water,32)
 f.game:disconnect(player); ok(f.p:save(1,true)); local nextC=f:add(1)
 code(f.co:action(nextC,"SetContestParticipation",{CycleId=f.co.demand.cycle.CycleId,Participate=true}),"NEXT_CYCLE")
 local cycle=f.co.contest.cycle; f:time(cycle.EndsAt)
 eq(ok(f.co.contest:finalize(cycle.CycleId)).Comparable,false)
end

-- Temporary theft preserves original ownership; traffic drop replay and return preserve wallet/stock.
do
 local f=fixture(); local a=f:add(1); local b=f:add(2)
 ok(f.co:recordShiftCompletion(a)); ok(f.co:recordShiftCompletion(b))
 local o=ok(f:order(a,"Water",1)); f:deliver(a,o.OrderId); f:stock(a,o.ItemIds[1],"Slot01",true)
 local item=f.co.stores[a.StoreId].Items[o.ItemIds[1]]
 code(f.co:action(b,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision}),"PROTECTED")
 f:time(181); ok(f.co:action(b,"BeginTheft",{ItemId=item.ItemId,ItemRevision=item.Revision})); f:time(183,true)
 item=f.co.stores[a.StoreId].Items[item.ItemId]; eq(item.State,"TheftCarried"); eq(item.OwnerUserId,1); eq(item.CarrierUserId,2)
 code(f.co:action(b,"DropWarehouse",{ItemId=item.ItemId,ItemRevision=item.Revision,CarryToken=item.CarryToken}),"NOT_OWNER")
 local beforeA=ok(f.p:get(1)).Wallet; local beforeB=ok(f.p:get(2)).Wallet
 local collision={CollisionId="collision:1",VehicleId="v1",ObservedAt=183,Speed=10,SafeDropCFrame="fake-safe-floor",Valid=true}
 ok(f.co:forceDrop(b,collision)); ok(f.co:forceDrop(b,collision))
 item=f.co.stores[a.StoreId].Items[item.ItemId]; eq(item.State,"Recoverable"); eq(item.CarrierUserId,false)
 eq(ok(f.p:get(1)).Wallet,beforeA); eq(ok(f.p:get(2)).Wallet,beforeB); eq(#ok(f.p:get(1)).Store.Items,1); eq(#ok(f.p:get(2)).Store.Items,0)
 collision.SafeDropCFrame="other"; code(f.co:forceDrop(b,collision),"REQUEST_ID_REUSED")
 code(f.co:forceDrop(b,{CollisionId="invalid",Valid=false}),"INVALID_COLLISION")
 f:time(209,true); eq(f.co.stores[a.StoreId].Items[item.ItemId].State,"Warehouse")
 f.co:tick(210); eq(count(f.co.stores[a.StoreId].Items),1)
 eq(ok(f.co:forceDrop(b,{CollisionId="empty",VehicleId="v1",ObservedAt=209,Speed=10,Valid=true,SafeDropCFrame=false})).Dropped,0)
end

-- Solo night reads verified sales, restores power without employees, and completes for free.
do
 local f=fixture(); local c=f:add(1); local user=f.game.users[1]
 local request={StoreId=c.StoreId,OwnerGeneration=c.OwnerGeneration,RoundId=false,Action="SetReady",Payload={Ready=true,RosterVersion=c.OwnerGeneration}}
 ok(f.game:action(user,request)); local night=f.game.nights[1]; eq(night.StartedAt,false)
 local order=ok(f:order(c,"Water",4)); f:deliver(c,order.OrderId)
 for _,iid in ipairs(order.ItemIds) do f:stock(c,iid,"Slot01",false) end
 ok(f:sale(c,"Rich")); f.game:tick(20); eq(night.BellShown,true); eq(f.w.outage,true)
 local o=night.Outage
 for _,shape in ipairs(o.Shapes) do ok(f.game:action(user,{StoreId=c.StoreId,OwnerGeneration=c.OwnerGeneration,RoundId=night.RoundId,Action="InputShape",Payload={OutageId=o.OutageId,Generation=c.OwnerGeneration,Shape=shape}})) end
 eq(f.w.outage,false)
 local order2=ok(f:order(c,"Milk",1)); f:deliver(c,order2.OrderId); f:stock(c,order2.ItemIds[1],"Slot02",false); ok(f:sale(c,"Normal")); f.game:tick(40)
 eq(night.Phase,"Result"); eq(ok(f.p:get(1)).CompletedFirstShift,true)
 local wire=Protocol.newConnection(CC,40); local packet=f.game:commercePacket(user,wire,40)
 eq(packet.ProtocolVersion,2); eq(packet.Self.DisplayName,"사장1"); eq(packet.ProfileStatus.Mode,"Memory"); eq(packet.Self.NextAction,"ViewResults")
 eq(packet.Self.Session,nil); eq(packet.Store.Items[1],nil)
end
-- Failed hidden-stage publication and yielding mutation leave no owner or partial live ledger.
do
 local f=fixture(); local p=ok(f.p:load(1))
 f.w.publishInventoryStage=function()return U.result("RESTORE_FAILED")end
 code(f.owners:assignOwner({UserId=1,DisplayName="A"},p.Session.Epoch),"RESTORE_FAILED")
 eq(count(f.co.stores),0); eq(count(f.owners.slots),0); eq(count(f.w.stages),0)
 local before=ok(f.p:get(1))
 code(f.p:mutate(1,p.Session.Epoch,function(value)value.Wallet=1; coroutine.yield(); return value end),"INTERNAL_ERROR")
 eq(ok(f.p:get(1)),before)
 code(U.call({check=function()coroutine.yield()end},"check"),"INTERNAL_ERROR")
end

-- Eight-owner allocation conservation; duplicate prepare and shortages do not mint supply.
do
 local f=fixture(); local contexts={}
 for uid=1,8 do local c=f:add(uid); table.insert(contexts,c) end
 f.co:tick(0); local cycle=f.co.demand.cycle
 for _,sku in ipairs({"Water","Bread"}) do
  local reserved=0; for _,a in pairs(f.co.demand.allocations) do if a.Sku==sku then reserved+=a.Remaining end end
  eq(reserved,16); eq(f.co.stock.Public[sku]+reserved,32)
 end
 code(f.co.demand:prepare("duplicate",{{UserId=1,Wallet=240}},1),"STALE_ACTIVITY")
 eq(f.co.stock.Public.Water,16)
 f.co.demand:releaseAllocations(150); eq(f.co.stock.Public.Water,32)
 local stock={Public={Water=1,Bread=32},Revision=1}
 local demand=Demand.new(CC,function()return 0 end,f.id,stock)
 code(demand:prepare("short",{{UserId=1,Wallet=240}},1),"SUPPLY_UNAVAILABLE")
 eq(stock.Public.Water,1); eq(count(demand.allocations),0)
end

-- Opportunity loss cannot manufacture winners/records. Personal-only valid misses are explicit.
do
 local f=fixture(); local c=f:add(1); f.co:tick(0); local cy=f.co.demand.cycle
 ok(f.co:action(c,"SetContestParticipation",{CycleId=cy.CycleId,Participate=true}))
 for index,offset in ipairs(CC.Contest.OpportunityOffsets) do
  local at=cy.StartsAt+offset; f:time(at)
  local offer=ok(f.co.contest:offerOpportunity(c,index))
  ok(f.co:observeOpportunity(c,offer.OpportunityId,at,"Miss","OUT_OF_STOCK"))
 end
 f:time(cy.EndsAt,true)
 eq(f.co.contest.cycle.Results.Reason,"PersonalOnly"); eq(f.co.contest.cycle.Results.Comparable,false)
 eq(ok(f.p:get(1)).Store.Achievements.ContestCompletions,1)
 local g=fixture(); local a=g:add(1); local b=g:add(2); g.co:tick(0); local second=g.co.demand.cycle
 for _,owner in ipairs({a,b}) do ok(g.co:action(owner,"SetContestParticipation",{CycleId=second.CycleId,Participate=true})) end
 g:time(second.EndsAt,true)
 eq(g.co.contest.cycle.Results.Reason,"NotComparable"); eq(#g.co.contest.cycle.Results.Winners.Plan,0)
 eq(ok(g.p:get(1)).Store.Achievements.ContestCompletions,0); eq(ok(g.p:get(2)).Store.Achievements.ContestCompletions,0)
end

-- Completing one contest sale cannot unlock a second future unit for a natural/rich visit.
do
 local f=fixture(); local c=f:add(1); f.co:tick(0); local cy=f.co.demand.cycle
 ok(f.co:action(c,"SetContestParticipation",{CycleId=cy.CycleId,Participate=true}))
 local allocation
 for id,a in pairs(f.co.demand.allocations) do if a.Sku=="Water" then allocation=id end end
 local order=ok(f:order(c,"Water",2,allocation)); f:deliver(c,order.OrderId)
 for _,iid in ipairs(order.ItemIds) do f:stock(c,iid,"Slot01",true) end
 local at=cy.StartsAt+90; f:time(at)
 local offer=ok(f.co.contest:offerOpportunity(c,1))
 local nid=f.id("npc"); f.npcs[nid]={uid=1,kind="Normal",phase="Browse",opportunity=offer.OpportunityId}
 local selected=ok(f.co:selectNpcItems(c,nid,"Normal",offer.OpportunityId))
 ok(f.co:observeOpportunity(c,offer.OpportunityId,at,"Arrived",false)); f.npcs[nid].phase="Checkout"
 ok(f.co:commitNpcSale(c,{TransactionId=f.id("sale"),NpcId=nid,Kind="Normal",SelectionId=selected.SelectionId,Items=selected.Items,OpportunityId=offer.OpportunityId}))
 f:time(at+6,true); code(f:sale(c,"Rich"),"OUT_OF_STOCK")
 local at2=cy.StartsAt+140; f:time(at2)
 local offer2=ok(f.co.contest:offerOpportunity(c,2)); ok(f.co:observeOpportunity(c,offer2.OpportunityId,at2,"Miss","NOT_PREPARED"))
 ok(f:sale(c,"Normal")); eq(f.co.contest.cycle.Owners[1].Plan,10)
end

-- Wire rejects old SeatGeneration envelopes explicitly; wait-listed ninth owner takes a vacated slot.
do
 local request={ProtocolVersion=1,RequestId=1,Action="JoinStore",StoreId="Store01",RoundId=false,SeatGeneration=0,Payload={}}
 local _,why=Protocol.validateCommerce(request,CC); eq(why,"VERSION_MISMATCH")
 local _,legacy=Protocol.validate(request,Config); eq(legacy,"VERSION_MISMATCH")
 local f=fixture(); local players={}
 for uid=1,8 do local _,player=f:add(uid); players[uid]=player end
 local player={UserId=9,DisplayName="대기9"}; local profile=ok(f.p:load(9)); f.game:connect(player)
 code(f.game:profileReady(player,profile.Session.Epoch),"STORE_FULL")
 f.game:disconnect(players[1]); f.game:tick(1)
 eq(f.owners:getOwnerContext(9).StoreId,"Store01"); eq(count(f.owners.slots),8)
end

-- Core collision timing/speed/cooldown validation remains enforced even with a permissive fake adapter.
do
 local f=fixture(); local c=f:add(1)
 code(f.co:forceDrop(c,{CollisionId="slow",VehicleId="v",ObservedAt=0,Speed=0,Valid=true}),"INVALID_COLLISION")
 code(f.co:forceDrop(c,{CollisionId="old",VehicleId="v",ObservedAt=-1,Speed=10,Valid=true}),"INVALID_COLLISION")
 ok(f.co:forceDrop(c,{CollisionId="hit",VehicleId="v",ObservedAt=0,Speed=10,Valid=true}))
 code(f.co:forceDrop(c,{CollisionId="twice",VehicleId="v",ObservedAt=0,Speed=10,Valid=true}),"COOLDOWN")
end
print("SOLO SERVER PASS: "..checks.." assertions; actual Luau services, FAKE world/storage/NPC/traffic; Studio=false cloud=false")
