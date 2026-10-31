-- Actual server modules together; only spatial/engine/clock adapters are fakes.
return function(Service,Protocol,L,C,Profiles,Progression,Delivery,Commerce,Ranking)
 local checks=0
 local function eq(a,b,message) checks+=1; assert(a==b,(message or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
 local function ok(v,message) checks+=1; assert(v,message or "expected true") end
 local now=0; local serial=0
 local function id(prefix) serial+=1; return prefix..":"..serial end
 local store=Profiles.newMemoryStore()
 local profiles=Profiles.new({Config=C,Store=store,SessionId="integration-session",UnixNow=function() return 1000+math.floor(now) end,Wait=function() end})
 local progression=Progression.new({Config=C,Profiles=profiles,NewId=id})
 local engine={trucks={}}
 function engine:createTruck(orderId,storeId) for _,v in pairs(self.trucks) do assert(v~=storeId,"two trucks in store") end self.trucks[orderId]=storeId; return {Ok=true} end
 function engine:moveTruck() return {Ok=true} end
 function engine:destroyTruck(orderId) self.trucks[orderId]=nil; return {Ok=true} end
 local world={stores={},checks=0}
 for _,storeId in ipairs(C.World.StoreIds) do world.stores[storeId]={available=true} end
 function world:alive(p) return p and not p.dead end
 function world:near(p,_,marker) return self:alive(p) and p.near==marker end
 function world:inside(p) return self:alive(p) end
 function world:move(p,s,m) p.location=s; p.near=m; return true end
 function world:setLayout() end
 function world:setOutage() end
 function world:check(c,target)
  self.checks+=1
  local code=self.block or "OK"; return {Ok=code=="OK",Code=code,Value=false}
 end
 function world:renderItem() return {Ok=true,Code="OK"} end
 function world:setAlarm() return {Ok=true,Code="OK"} end
 local delivery=Delivery.new({Config=C,Now=function() return now end,Engine=engine})
 local commerce=Commerce.new({Config=C,Now=function() return now end,NewId=id,Delivery=delivery,World=world,Progression=progression})
 local ranking=Ranking.new({Config=C,Profiles=profiles})
 local runtime=Service.runtimeConfig(L,C)
 eq(#runtime.World.StoreIds,8); eq(#L.World.StoreIds,4); eq(#runtime.World.MarkerOrder,#L.World.MarkerOrder); eq(runtime.Capacity.MinCoopPlayers,2)
 local service=Service.new(runtime,world,{Config=C,Commerce=commerce,Profiles=profiles,Progression=progression,Ranking=ranking})
 local requestId=0
 local function request(u,action,payload)
  requestId+=1
  return {ProtocolVersion=1,RequestId=requestId,Action=action,Payload=payload or {},StoreId=u.storeId,RoundId=u.storeId and service.stores[u.storeId].RoundId or false,SeatGeneration=u.generation}
 end
 local function legacy(u,action,payload,target)
  local r=request(u,action,payload); if target then r.StoreId=target; r.RoundId=false end
  local parsed,code=Protocol.validate(r,runtime); if not parsed then return code end
  return service:action(u,parsed,now)
 end
 local function action(u,name,payload)
  local parsed,code=Protocol.validateCommerce(request(u,name,payload),C); if not parsed then return {Ok=false,Code=code} end
  return service:commerceAction(u,parsed)
 end
 local function join(n,storeId)
  eq(profiles:load(n).Ok,true)
  local u=service:connect({UserId=n,DisplayName="Test"..n}); eq(legacy(u,"JoinStore",{},storeId),"OK"); eq(legacy(u,"SetLoaded",{Loaded=true}),"OK"); return u
 end
 local function tick(t)
  now=t
  -- Real Main runs save workers outside the mutation queue. Memory adapter does not yield here.
  for _,userId in ipairs(profiles:due()) do eq(profiles:save(userId,false).Ok,true) end
  service:tick(now)
 end
 local function view(u) return commerce:view(service:commerceContext(u)) end
 local function buy(u,sku,quantity)
  return action(u,"OrderStock",{Sku=sku,Quantity=quantity,StockRevision=view(u).Wholesale.Revision})
 end
 local a,b=join(1,"Store01"),join(2,"Store01")
 eq(legacy(a,"SetReady",{Ready=true,RosterVersion=service.stores.Store01.RosterVersion}),"OK")
 eq(legacy(b,"SetReady",{Ready=true,RosterVersion=service.stores.Store01.RosterVersion}),"OK")
 tick(3)
 local shop=service.stores.Store01
 eq(shop.Phase,"Running"); eq(shop.round.preparing,true); eq(shop.round.shift.due,false)
 eq(view(a).Store.OperatingCash,240); eq(progression:view(a.id).Wallet,0)
 -- Replay protection compares nested preset values, rejects exotic fields and copies payloads.
 local nested=request(a,"SavePreset",{Index=1,Slots={{SlotId="Slot01",Sku="Water"}}})
 local parsed=Protocol.validateCommerce(nested,C); ok(parsed); ok(Protocol.equal(parsed,nested))
 nested.Payload.Slots[1].Sku="Milk"; ok(not Protocol.equal(parsed,nested)); eq(parsed.Payload.Slots[1].Sku,"Water")
 for _,bad in ipairs({-1,math.huge,0/0}) do local r=request(a,"OrderStock",{Sku="Water",Quantity=bad,StockRevision=1}); eq(select(2,Protocol.validateCommerce(r,C)),"BAD_REQUEST") end
 local bad=request(a,"SavePreset",{Index=1,Slots={{SlotId="Slot01",Sku="Water",Extra=true}}}); eq(select(2,Protocol.validateCommerce(bad,C)),"BAD_REQUEST")
 bad=request(a,"EquipTool",{ToolId="HandCarry",Extra=1}); eq(select(2,Protocol.validateCommerce(bad,C)),"BAD_REQUEST")
 local wire=Protocol.newConnection(C,now); local wireLegacy=Protocol.newConnection(runtime,now)
 local req=Protocol.validateCommerce(request(a,"OrderStock",{Sku="Water",Quantity=1,StockRevision=view(a).Wholesale.Revision}),C)
 local purchased=service:commerceAction(a,req); eq(purchased.Code,"OK")
 local ack=service:commerceAck(a,req.RequestId,purchased.Code,purchased.Value); Protocol.remember(wire,req,ack,C)
 eq(wire.cache[req.RequestId].ack.EntityId,purchased.Value.OrderId); eq(wireLegacy.cache[req.RequestId],nil)
 eq(view(a).Store.OperatingCash,236)
 -- cancellation duplicates cannot turn operating cash into a wallet or exceed original cash.
 eq(action(a,"CancelStockOrder",{OrderId=purchased.Value.OrderId}).Code,"OK")
 eq(action(b,"CancelStockOrder",{OrderId=purchased.Value.OrderId}).Code,"OK")
 eq(view(a).Store.OperatingCash,240); eq(progression:view(a.id).Wallet,0)
 local batch=buy(a,"Water",4); eq(batch.Code,"OK")
 tick(8); tick(20)
 eq(view(a).Store.Orders[2].State,"Docked")
 local items=view(a).Store.Items; eq(#items,4)
 for _,item in ipairs(items) do
  eq(action(a,"PickCargo",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"OK")
  eq(action(b,"PickCargo",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"STALE_ITEM")
  local held=view(a).Carry[1]
  eq(action(a,"PlaceShelf",{ItemId=held.ItemId,ItemRevision=held.Revision,CarryToken=held.CarryToken,SlotId="Slot01"}).Code,"OK")
 end
 eq(progression:view(a.id).XP,8); eq(progression:view(a.id).Wallet,0)
 tick(20.1); eq(shop.round.preparing,false); ok(shop.round.shift.due>now); eq(shop.round.order.lines[1].product,"Water")
 local order=shop.round.order
 local function lineAction(u,name)
  local line=order.lines[1]; local payload={OrderId=order.id,LineId=1,LineRevision=line.revision}
  if name=="PickUp" then payload.Shelf="Shelf1"; u.player.near="Shelf1"
  elseif name=="PutDown" or name=="ReturnItem" then payload.CarryToken=line.token; u.player.near="Counter"
  else u.player.near="Counter" end
  return legacy(u,name,payload)
 end
 eq(lineAction(a,"PickUp"),"OK"); eq(lineAction(b,"PickUp"),"INVALID_STATE")
 eq(#view(a).Carry,0); ok(a.carry.CarryToken)
 eq(action(a,"EquipTool",{ToolId="HandCarry"}).Code,"CARRY_FULL")
 eq(lineAction(a,"PutDown"),"OK"); eq(service:hasLineClaim(a),true)
 local remaining=view(a).Store.Items[2]
 eq(action(a,"PickShelf",{ItemId=remaining.ItemId,ItemRevision=remaining.Revision}).Code,"CARRY_FULL")
 b.player.near="Counter"
 local acceptedRequest=request(b,"AcceptLine",{OrderId=order.id,LineId=1,LineRevision=order.lines[1].revision})
 eq(service:action(b,acceptedRequest,now),"OK")
 eq(service:action(b,acceptedRequest,now),"STALE_ORDER")
 eq(progression:view(b.id).Wallet,2); eq(progression:view(b.id).XP,5)
 eq(view(a).Stores[1].Sales,1); eq(view(a).Store.OperatingCash,231)
 eq(service:hasLineClaim(a),false)
 -- Direct repeated sale uses the same server identity and cannot pay twice.
 eq(commerce:sellLine(service:commerceContext(b),order.id..":1","sale:"..order.id..":1").Code,"OK")
 eq(progression:view(b.id).Wallet,2)
 -- Reposition returns cargo before moving. Visits themselves never change membership.
 local shelved
 for _,item in ipairs(view(a).Store.Items) do if item.State=="Shelf" then shelved=item; break end end
 eq(action(a,"PickShelf",{ItemId=shelved.ItemId,ItemRevision=shelved.Revision}).Code,"OK")
 a.player.location="Store02"; service:tick(now); eq(a.storeId,"Store01"); eq(a.player.location,"Store02")
 eq(legacy(a,"Reposition"),"OK"); eq(#view(a).Carry,0)
 -- Gate real spatial errors without committing the ledger.
 world.block="NO_LINE_OF_SIGHT"; local cash=view(a).Store.OperatingCash
 eq(buy(a,"Bread",1).Code,"NO_LINE_OF_SIGHT"); eq(view(a).Store.OperatingCash,cash); world.block=nil
 -- All eight stores reserve from the same stock revision, including competition for the last unit.
 local teams={[1]=a}
 for i=2,8 do local u=join(i+10,C.World.StoreIds[i]); teams[i]=u; eq(legacy(u,"SoloPractice",{RosterVersion=service.stores[u.storeId].RosterVersion}),"OK") end
 -- Use Milk so prior Water orders do not affect the shared last-stock test.
 for i=1,8 do eq(buy(teams[i],"Milk",i==1 and 3 or 4).Code,"OK") end
 local revision=view(a).Wholesale.Revision
 local r1=request(teams[2],"OrderStock",{Sku="Milk",Quantity=1,StockRevision=revision})
 local r2=request(teams[3],"OrderStock",{Sku="Milk",Quantity=1,StockRevision=revision})
 eq(service:commerceAction(teams[2],r1).Code,"OK"); eq(service:commerceAction(teams[3],r2).Code,"STALE_STOCK")
 eq(buy(teams[3],"Milk",1).Code,"OUT_OF_STOCK")
 -- Beginner protection persists across visits/reconnect and rejects cross-store theft.
 local victim
 for _,item in ipairs(view(a).Store.Items) do if item.State=="Shelf" then victim=item; break end end
 eq(action(teams[2],"BeginTheft",{ItemId=victim.ItemId,ItemRevision=victim.Revision}).Code,"PROTECTED")
 -- Inactive phases cancel holds and prohibit profile/economic mutation.
 shop.Phase="Recovery"; service:syncCommerce(); eq(action(a,"EquipTool",{ToolId="HandCarry"}).Code,"NOT_ACTIVE"); shop.Phase="Running"; service:syncCommerce()
 local stale=request(a,"OrderStock",{Sku="Bread",Quantity=1,StockRevision=view(a).Wholesale.Revision}); stale.SeatGeneration-=1
 eq(service:commerceAction(a,stale).Code,"STALE_SEAT")
 -- Server closing ledger, category key and repeated ranking writes.
 service:finish(shop,"Incomplete","TestStop",now)
 local rows=ranking:view(); eq(rows[1].Sales,1); eq(rows[1].Revenue,7); eq(rows[1].TeamSize,2); eq(rows[1].Mode,"Coop")
 eq(#progression:view(a.id).Best,1); eq(progression:view(a.id).Best[1].Key,"Coop/2/1/false/false")
 eq(progression:view(b.id).Wallet,2); eq(view(a).Store,false)
 local record=ranking.transactions["rank:"..rows[1].RoundId].input
 local before=profiles:get(a.id).Value.Revision
 eq(ranking:record(record).Code,"OK"); eq(profiles:get(a.id).Value.Revision,before)
 local altered=table.clone(record); altered.Revenue=999; eq(ranking:record(altered).Code,"INVALID_STATE")
 local alternate=table.clone(record); alternate.TransactionId="other"; eq(ranking:record(alternate).Code,"INVALID_STATE")
 -- Actual profile release/reload restores earned wallet, XP and category best, not operating money.
 eq(profiles:save(b.id,true).Code,"OK"); eq(profiles:load(b.id).Code,"OK"); eq(progression:view(b.id).Wallet,2); eq(#progression:view(b.id).Best,1)
 -- Private snapshot only carries the requesting user's profile and monotonic sequence.
 local c=Protocol.newConnection(C,now); local snap=service:commercePacket(b,c,now,true)
 eq(snap.Self.Wallet,2); eq(snap.Self.Session,nil); eq(snap.Self.RewardCursor,nil); eq(snap.Kind,"Snapshot"); eq(#snap.Stores,8); eq(#snap.Wholesale.Rows,11)
 eq(service:commercePacket(b,c,now+0.1,false),nil)
 local delta=service:commercePacket(b,c,now+1,false); eq(delta.Sequence,snap.Sequence+1); eq(delta.Self,nil)
 -- New completed-profile shifts exercise theft against an actual legacy claim.
 for _,u in ipairs({a,b,teams[2]}) do
  local status=profiles:status(u.id)
  eq(profiles:mutate(u.id,status.Epoch,function(p) p.CompletedFirstShift=true; return p end).Ok,true)
 end
 local attacker=teams[2]; local victimStore=service.stores.Store01; local attackerStore=service.stores.Store02
 service:finish(attackerStore,"Incomplete","Reset",now)
 service:startRound(victimStore,false,now); service:startRound(attackerStore,true,now)
 service:syncCommerce()
 eq(view(a).Stores[1].Protected,false); eq(view(attacker).Stores[2].Protected,false)
 eq(buy(a,"Bread",2).Code,"OK")
 tick(now+5); tick(now+12)
 local cargo=view(a).Store.Items
 for _,item in ipairs(cargo) do
  eq(action(a,"PickCargo",{ItemId=item.ItemId,ItemRevision=item.Revision}).Code,"OK")
  local held=view(a).Carry[1]
  eq(action(a,"PlaceShelf",{ItemId=held.ItemId,ItemRevision=held.Revision,CarryToken=held.CarryToken,SlotId="Slot01"}).Code,"OK")
 end
 tick(now+0.1)
 local target=view(a).Store.Items[1]
 eq(action(attacker,"BeginTheft",{ItemId=target.ItemId,ItemRevision=target.Revision}).Code,"OK")
 order=victimStore.round.order
 eq(lineAction(a,"PickUp"),"OK")
 tick(now+2)
 eq(view(attacker).Theft.State,"Cancelled"); eq(#view(attacker).Carry,0)
 eq(lineAction(a,"PutDown"),"OK")
 -- Disconnect while Tray owns the claim restores the physical item and clears the line.
 local departure={}; service:depart(a,"Disconnect",departure); service:selectRecoverySurvivors(departure)
 service:tick(now,true); service:settleDepartures(departure,now); service:tickCommerce(now)
 eq(order.lines[1].status,"Uncollected"); eq(order.lines[1].claimUser,false)
 eq(victimStore.Phase,"Recovery")
 local currentTarget
 for _,item in ipairs(view(b).Store.Items) do if item.State=="Shelf" then currentTarget=item; break end end
 eq(action(attacker,"BeginTheft",{ItemId=currentTarget.ItemId,ItemRevision=currentTarget.Revision}).Code,"PROTECTED")
 -- Resume the remaining participant; membership remains Store01 despite visiting Store02.
 eq(legacy(b,"FinishSolo"),"OK"); service:syncCommerce()
 eq(action(attacker,"BeginTheft",{ItemId=currentTarget.ItemId,ItemRevision=currentTarget.Revision}).Code,"OK")
 tick(now+2)
 local stolen=view(attacker).Carry[1]; ok(stolen and stolen.Stolen); eq(stolen.OwnerStoreId,"Store01")
 eq(view(b).Stores[1].Alarm.Location,"Shelf")
 eq(action(b,"RecoverItem",{ItemId=stolen.ItemId,ItemRevision=stolen.Revision}).Code,"OK")
 eq(#view(attacker).Carry,0); eq(view(attacker).Theft.State,"Recovered")
 eq(action(attacker,"SecureTheft",{ItemId=stolen.ItemId,ItemRevision=stolen.Revision,CarryToken=stolen.CarryToken}).Code,"STALE_ITEM")
 -- Adjusted completion is categorized separately and gives no cooperative close coins.
 local wallet=progression:view(b.id).Wallet
 service:finish(victimStore,"AdjustedClose",false,now)
 eq(progression:view(b.id).Wallet,wallet)
 local category
 for _,row in ipairs(ranking:view()) do if row.RoundId==victimStore.result.RoundId then category=row end end
 eq(category.Mode,"Solo"); eq(category.HadReduction,true)
 local unchanged=view(attacker).Store.OperatingCash
 commerce:beginShift(attackerStore.StoreId,attackerStore.RoundId,{InitialUserIds={attacker.id},TeamSize=1,Mode="Practice",Protected=false})
 eq(view(attacker).Store.OperatingCash,unchanged)
 ok(world.checks>0)
 print("SERVER COMMERCE INTEGRATION PASS: "..checks.." assertions; real domain modules, fake spatial/engine/clock; no Studio")
end
