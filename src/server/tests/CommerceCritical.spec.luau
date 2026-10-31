return function(Profile,Progression,Delivery,Commerce,Config,GameService)
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}; for k,x in pairs(v) do out[k] = copy(x) end; return out
end
local function eq(a,b,label) assert(a == b, (label or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
local function ok(r) assert(r.Ok, r.Code); return r.Value end
local function profileFixture()
    local f = { now=1000 }
    local store = {Mode="Memory", records={}, loseAfter=0, calls=0}
    function store:GetBudget() return 100 end
    function store:UpdateAsync(key, fn)
        self.calls += 1
        local nextValue = fn(copy(self.records[key]))
        if nextValue == nil then return nil end
        self.records[key] = copy(nextValue)
        if self.loseAfter > 0 then self.loseAfter -= 1; error("injected committed response loss") end
        return copy(nextValue)
    end
    function f:newProfile(session)
        return Profile.new({Config=Config, Store=store, SessionId=session or "audit-A",
            UnixNow=function() return self.now end, Wait=function() end})
    end
    f.store=store; f.p=f:newProfile(); ok(f.p:load(1))
    return f
end
local function commerceFixture(longId, failSaleOnce)
    local f = profileFixture(); f.time=0; local sequence=0
    f.progression=Progression.new({Config=Config,Profiles=f.p})
    local facade={}
    function facade:award(userId,event)
        if failSaleOnce and event.Kind=="Sale" then
            failSaleOnce=false; return {Ok=false,Code="PROFILE_UNAVAILABLE",Value=false}
        end
        return f.progression:award(userId,event)
    end
    function facade:view(userId) return f.progression:view(userId) end
    local world={}
    function world:check() return {Ok=true,Code="OK"} end
    function world:renderItem() return {Ok=true,Code="OK"} end
    function world:setAlarm() return {Ok=true,Code="OK"} end
    local engine={}
    function engine:createTruck() return {Ok=true,Code="OK"} end
    function engine:moveTruck() return {Ok=true,Code="OK"} end
    function engine:destroyTruck() return {Ok=true,Code="OK"} end
    f.d=Delivery.new({Config=Config,Now=function() return f.time end,Engine=engine})
    f.s=Commerce.new({Config=Config,Now=function() return f.time end,World=world,Delivery=f.d,Progression=facade,
        NewId=function(prefix)
            sequence+=1
            if longId and prefix=="order" then return string.rep("a",longId-1)..tostring(sequence) end
            return prefix.."-"..sequence
        end})
    f.c={UserId=1,StoreId="Store01",RoundId="round-1",SeatGeneration=1,Loaded=true,Active=true,
        Mode="Solo",OnlineCount=1,ToolId="HandCarry",ProfileEpoch=f.p:status(1).Epoch}
    ok(f.s:beginShift("Store01","round-1",{InitialUserIds={1},TeamSize=1,Mode="Solo",Protected=false}))
    f.s:syncContext(f.c)
    function f:act(action,payload) return self.s:action(self.c,action,payload) end
    function f:advance(time) self.time=time; self.s:tick(time) end
    function f:order()
        return ok(self:act("OrderStock",{Sku="Water",Quantity=1,StockRevision=self.s.stockRevision})).OrderId
    end
    function f:stockShelf()
        local orderId=self:order(); self:advance(5); self:advance(17)
        local item=self.s.items[self.s.orders[orderId].ItemIds[1]]
        ok(self:act("PickCargo",{ItemId=item.ItemId,ItemRevision=item.Revision}))
        ok(self:act("PlaceShelf",{ItemId=item.ItemId,ItemRevision=item.Revision,CarryToken=item.CarryToken,SlotId="Slot01"}))
        return item
    end
    return f
end


for _,mode in ipairs({"expiry","release-loss","locked"}) do
 local f=profileFixture(); ok(f.p:mutate(1,1,function(p) p.Wallet=22; return p end)); ok(f.p:save(1,false))
 if mode=="release-loss" then f.store.loseAfter=1; eq(f.p:save(1,true).Code,"LEASE_LOST")
 else f.now=1120 end
 if mode=="locked" then local other=f:newProfile("other"); ok(other:load(1)); eq(f.p:load(1).Code,"SESSION_LOCKED")
 else local p=ok(f.p:load(1)); eq(p.Wallet,22); eq(p.Session.Epoch,2)
  eq(f.p:mutate(1,1,function(p) p.Wallet=999; return p end).Code,"LEASE_LOST") end
end
for _,length in ipairs({76,77,96}) do
 local f=commerceFixture(length,false); local orderId=f:order(); eq(#orderId,length)
 f:advance(5); f:advance(17); eq(f.s.orders[orderId].State,"Docked")
 ok(f.s:endShift("Store01","round-1")); ok(f.s:endShift("Store01","round-1"))
end
for _,departure in ipairs({"depart","endShift","none"}) do
 local f=commerceFixture(nil,true); local item=f:stockShelf()
 ok(f.s:claimForLine(f.c,item.ItemId,item.Revision,"line-1")); ok(f.s:sellLine(f.c,"line-1","sale-1"))
 eq(f.p:get(1).Value.Wallet,0)
 if departure=="depart" then f.s:depart(1) elseif departure=="endShift" then ok(f.s:endShift("Store01","round-1")) end
 f:advance(18); eq(next(f.s.pendingRewards),nil); eq(f.p:get(1).Value.Wallet,2); eq(f.p:get(1).Value.XP,7)
 ok(f.s:flushRewards(1)); ok(f.p:save(1,true)); local reloaded=ok(f.p:load(1)); eq(reloaded.Wallet,2)
 eq(f.progression:award(1,{TransactionId="sale-1",Epoch=1,Kind="Sale",Sku="Water",Eligible=true}).Code,"LEASE_LOST")
end
-- A genuine epoch loss remains explicit and never reissues the sale under a fresh epoch.
do
 local f=commerceFixture(nil,true); local item=f:stockShelf()
 ok(f.s:claimForLine(f.c,item.ItemId,item.Revision,"line-1")); ok(f.s:sellLine(f.c,"line-1","sale-1"))
 ok(f.p:save(1,true)); ok(f.p:load(1)); f.s:depart(1); f:advance(18)
 eq(f.p:get(1).Value.Wallet,0); eq(f.s:flushRewards(1).Ok,false)
 local _,pending=next(f.s.pendingRewards); eq(pending.Terminal,true); eq(pending.Event.Epoch,1)
end
-- CR-03: a stock-limited order cannot grow when four members reduce to three.
do
 local svc=setmetatable({config={}}, {__index=GameService})
 function svc:touch() end
 function svc:completeOrder(store) self.completed=store.round.order.accepted==store.round.order.required end
 local store={round={active={1,2,3},order={accepted=0,required=1,lines={{id=1,status="Uncollected",revision=1}}}}}
 svc:reduce(store,0); eq(store.round.order.required,1)
 store.round.order.accepted=1; svc:reduce(store,1); eq(svc.completed,true)
end
print("CRITICAL_REGRESSIONS_PASS: lease reacquire/lock/old epoch; 76/77/96 delivery; depart/endShift reward flush/reload/epoch fencing; reduced order")

end
