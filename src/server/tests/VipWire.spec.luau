-- Actual NPC/economy/serializer/client chain with fake clock, movement and storage.
local initial=checks
local h=npcFixture(2,0.01); local n=h:spawn()
local wire={sequence=0}
local client=Client.new({Config=CC,Player={UserId=1},Dirty=function() end})
local function snapshot(uid,w)
 return h.f.game:commercePacket(h.f.game.users[uid or 1],w or wire,h.f.game.now())
end
local function receive() local p=snapshot(); eq(client:receive(p),true,"actual serialized packet applied"); return p end
h:untilPhase("Checkout")
local p=receive(); eq(#p.CustomerEvents.Entries,1); eq(p.CustomerEvents.Entries[1].Kind,"NpcVisited")
eq(client.notice.Text,"부자 손님 방문 · 진열대 도착")
local staleTick=h.f.game:commercePacket(h.f.game.users[1],wire,h.f.game.now()-1)
eq(staleTick.ServerTime,h.f.game.now(),"snapshot time includes queue-drained events")
eq(client:receive(staleTick),true,"event emitted after heartbeat start remains valid")
local oldNotice=client.notice; receive(); eq(client.notice,oldNotice,"duplicate cursor never re-notifies")
for _=1,100 do if n.Sold then break end; h:step() end
eq(n.Sold,true,"real scheduler committed sale")
p=receive(); local saleEvent=p.CustomerEvents.Entries[#p.CustomerEvents.Entries]
eq(saleEvent.Kind,"NpcSaleCommitted"); eq(saleEvent.CustomerKind,"Rich"); eq(saleEvent.Units,2); eq(saleEvent.Revenue,14)
eq(client.notice.Text,"부자 손님 구매 · 2개 / 매출 14")
print("ACTUAL_OFFLINE_PAYLOAD Kind="..saleEvent.Kind.." CustomerKind="..saleEvent.CustomerKind.." OwnerUserId="..saleEvent.OwnerUserId.." StoreId="..saleEvent.StoreId.." Cursor="..saleEvent.Cursor.." Units="..saleEvent.Units.." Revenue="..saleEvent.Revenue)
local last=h:sales()[1]; local cursor=h.f.co.eventCursor
ok(h.f.co:commitNpcSale(h.c,last.p)); eq(h.f.co.eventCursor,cursor,"receipt replay emits no sale")
oldNotice=client.notice; receive(); eq(client.notice,oldNotice)
local c2=h.f:add(2); local foreign=snapshot(2,{sequence=200})
eq(#foreign.CustomerEvents.Entries,0,"other owner receives no NPC events")
eq(client:receive(foreign),false,"foreign Self rejected")
local function reject(change,label)
 local q=U.copy(p); q.Sequence=1000; change(q)
 local before=client.state.Sequence
 eq(client:receive(q),false,label); eq(client.state.Sequence,before,"atomic rejection")
end
reject(function(q) q.CustomerEvents.Entries[1].OwnerUserId=2 end,"foreign owner event")
reject(function(q) q.CustomerEvents.Entries[1].StoreId="Store02" end,"foreign store event")
reject(function(q) q.CustomerEvents.Entries[1].OwnerGeneration=99 end,"generation mismatch")
reject(function(q) q.CustomerEvents.Entries[1].ProfileEpoch=99 end,"epoch mismatch")
reject(function(q) q.CustomerEvents.Entries[1].RoundId="past-night" end,"old round")
reject(function(q) q.CustomerEvents.Entries[1].Kind="Rich" end,"Kind collision rejected")
reject(function(q) q.CustomerEvents.Entries[2].Cursor=q.CustomerEvents.Entries[1].Cursor end,"duplicate event cursor")
reject(function(q) q.CustomerEvents.Entries[2].EventId=q.CustomerEvents.Entries[1].EventId end,"duplicate EventId")
reject(function(q) q.CustomerEvents.Entries[2].Units=5 end,"invalid quantity")
reject(function(q) q.Self.RareDiscoveries=nil end,"required dictionary DTO")
reject(function(q) q.Self.EquippedTool="Unknown" end,"equipped tool must be unlocked")
reject(function(q) q.Self.Presets={{Index=1,Slots={{Sku="Water"}}}} end,"preset shape")
reject(function(q) q.ServerTime+=21 end,"expired events")
reject(function(q) q.CustomerEvents=false end,"explicit false feed rejected")
reject(function(q) q.Self=42 end,"malformed Self rejected without throw")
reject(function(q) q.CustomerEvents.Cursor=1; q.CustomerEvents.Entries={} end,"old cursor rejected")
-- Expiry suppresses labels; retained watermark cannot regress after global ring eviction.
h:run(4); p=receive(); eq(p.CustomerEvents.Entries[#p.CustomerEvents.Entries].Kind,"NpcDeparted"); eq(client.notice.Text,"부자 손님 퇴장")
for _=1,260 do h.f.co:_emit("InventoryCommitted",c2,1) end
p=receive(); eq(#p.CustomerEvents.Entries,0); eq(p.CustomerEvents.Cursor>0,true)
h.f.game.nights[1]={RoundId="next-night",Phase="Running"}
p=receive(); eq(p.Self.RoundId,"next-night"); eq(client.notice,nil,"round reset clears past notification")
eq(p.CustomerEvents.Cursor,0); eq(#p.CustomerEvents.Entries,0)
-- Full server serialization includes actual persisted progress fields (no invented rewards).
local profile=ok(h.f.p:get(1)); eq(Contract.validSelfProgress(p.Self),true)
eq(p.Self.RareDiscoveries,profile.RareDiscoveries); eq(p.Self.UnlockedTools,profile.UnlockedTools)
eq(p.Self.EquippedTool,profile.EquippedTool); eq(p.Self.Presets,profile.Presets)
local released=h.f.game:disconnect(h.player); eq(released.UserId,1); eq(h.f.co.visits[n.Id],nil)
eq(#h.f.co:customerEvents(h.c).Entries,0,"departed owner cannot read past events")
local c3=h.f:add(3); eq(c3.StoreId,h.c.StoreId); eq(#snapshot(3,{sequence=0}).CustomerEvents.Entries,0,"new slot owner has no previous events")
-- Empty or failed checkout is never a purchase notification.
local empty=npcFixture(0,0.01); empty:spawn(); empty:run(10)
local emptyFeed=empty.f.co:customerEvents(empty.c)
local visit,departure=false,false
for _,e in ipairs(emptyFeed.Entries) do eq(e.Kind~="NpcSaleCommitted",true); visit=visit or e.Kind=="NpcVisited"; departure=departure or e.Kind=="NpcDeparted" end
eq(visit,true); eq(departure,true)
local failed=npcFixture(1,0.01); failed:spawn(); failed:untilPhase("Checkout")
failed.f.co.commitNpcSale=function() return U.result("CURRENCY_CAP") end
failed:run(5)
for _,e in ipairs(failed.f.co:customerEvents(failed.c).Entries) do eq(e.Kind~="NpcSaleCommitted",true) end
-- Every Self context transition clears pending notifications, even while remaining in one client.
local reset=U.copy(p); reset.Sequence=wire.sequence+1; reset.Self.OwnerGeneration+=10; reset.Store.OwnerGeneration=reset.Self.OwnerGeneration
reset.Self.ProfileEpoch+=1; reset.CustomerEvents={Cursor=0,Entries={}}
eq(client:receive(reset),true); eq(client.notice,nil); eq(client.state.CustomerCursor,0)
-- Upgrade capacity and restore maintain 32 distinct paid IDs; level 0 rejects 32 warehouse units.
local f=fixture(); local c=f:add(8)
local items={}; for i=1,32 do items[i]={ItemId="saved:"..i,OwnerUserId=8,Sku="Water",UnitCost=4,State="Warehouse",SlotId=false} end
ok(f.p:mutate(8,c.ProfileEpoch,function(raw) raw.Store.Upgrades.Warehouse=1; raw.Store.Items=items; return raw end))
local saved=ok(f.p:get(8)); eq(SoloProfile.validateExtension(saved,CC,Contract,8),true)
local bad=U.copy(saved); bad.Store.Upgrades.Warehouse=0; eq(SoloProfile.validateExtension(bad,CC,Contract,8),false)
-- Reuse lease only in this explicit restore fixture: no save/Studio claim.
ok(f.co:releaseOwner(c)); f.co.restored={}
local assigned=ok(f.owners:assignOwner({UserId=8,DisplayName="복원"},c.ProfileEpoch))
local bins={}; for _,item in pairs(f.co.stores[assigned.StoreId].Items) do eq(bins[item.WarehouseBin],nil); bins[item.WarehouseBin]=item.ItemId end
eq(count(bins),32); eq(f.co:view(assigned).Store.WarehouseCapacity,32)
print("VIP WIRE PASS "..(checks-initial).." assertions; actual services/serializer/client, FAKE adapters; Studio=false")
