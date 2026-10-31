--!nonstrict
-- v2 solo server. IO jobs run outside the single non-yielding economic queue.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local SS=game:GetService("ServerStorage")
local RunService=game:GetService("RunService")
local Http=game:GetService("HttpService")
local namespace=RS:WaitForChild("NightShift",10); assert(namespace,"NightShift missing")
local shared=namespace:WaitForChild("Shared",10); assert(shared,"Shared missing")
local config=require(shared.Config); local cc=require(shared.CommerceConfig)
assert(config.ProtocolVersion==2 and cc.ProtocolVersion==2 and cc.Capacity.SeatsPerStore==1,"v2 required")
local modules=script.Parent.Modules
local Protocol=require(modules.Protocol)
local Profiles=require(modules.ProfileService)
local Ownership=require(modules.OwnershipService)
local Commerce=require(modules.CommerceService)
local Game=require(modules.SoloGameService)
local World=require(modules.WorldAdapter)
local U=require(modules.ServerUtil)
local Bridge=require(modules.RuntimeBridge)
local function now() return workspace:GetServerTimeNow() end
local authorityAt=now()
local session=Http:GenerateGUID(false)
local function newId(prefix) return prefix..":"..Http:GenerateGUID(false) end
-- Align old world adapter geometry with the authoritative eight-store build.
config=U.copy(config)
for _,k in ipairs({"HubPosition","HubSpawn","HubStoreSelect","HubSize","RoadWidth","StoreSize","StoreIds","Stores"}) do config.World[k]=U.copy(cc.World[k]) end
local builder=require(SS.NightShift.BuildWorld)
local truck=SS.NightShift:FindFirstChild("BuildDeliveryTruck")
local world=World.new(builder.build(workspace),config,cc,{Content=require(modules.OperatorContent),TruckBuilder=truck and require(truck)})
local storage=Profiles.newMemoryStore()
if cc.Features.PersistentSave then
 assert(cc.Profile.DefaultMode=="DataStore","Explicit DataStore mode required")
 local ds=game:GetService("DataStoreService"); local data=ds:GetDataStore(cc.Profile.DataStoreName)
 storage={Mode="DataStore",GetBudget=function() return ds:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) end,
  UpdateAsync=function(_,key,transform) return data:UpdateAsync(key,transform) end}
else assert(cc.Profile.DefaultMode=="Memory","Explicit Memory mode required") end
local profiles=Profiles.new({Config=cc,Store=storage,SessionId=session,UnixNow=os.time,IsStudio=RunService:IsStudio()})
local commerce=Commerce.new({Config=cc,Profiles=profiles,Now=function() return authorityAt end,NewId=newId,World=world})
local ownership=Ownership.new(cc,profiles,function(c,p) return commerce:restoreInventory(c,p) end,world)
commerce:setOwnership(ownership)
local service=Game.new({Config=config,CommerceConfig=cc,Profiles=profiles,Commerce=commerce,Ownership=ownership,World=world,Now=function() return authorityAt end,NewId=newId})
local function remote(parent,name,class)
 local r=parent:FindFirstChild(name); if r then assert(r.ClassName==class,"Remote collision"); return r end
 r=Instance.new(class); r.Name=name; r.Parent=parent; return r
end
local remotes=remote(namespace,"Remotes","Folder")
local channels={}
for _,prefix in ipairs({"","Commerce"}) do channels[prefix]={Action=remote(remotes,prefix.."Action","RemoteEvent"),Ack=remote(remotes,prefix.."ActionResult","RemoteEvent"),
 State=remote(remotes,prefix.."State","RemoteEvent"),Snapshot=remote(remotes,prefix=="" and "GetSnapshot" or "GetCommerceSnapshot","RemoteFunction")} end
local connections,queue,jobs,working={},{},{},{}
local closing,failed,draining=false,false,false
local serial=0
local function enqueue(kind,player,data)
 serial+=1; table.insert(queue,{Kind=kind,Player=player,Data=data,At=now(),Serial=serial})
end
local function job(id,kind,player,connection)
 jobs[id]=jobs[id] or {}
 for _,old in ipairs(jobs[id]) do if old.Kind==kind and kind=="save" then return end end
 table.insert(jobs[id],{Kind=kind,Player=player,Connection=connection})
 if working[id] then return end
 working[id]=true
 task.defer(function()
  while #jobs[id]>0 do
   local j=table.remove(jobs[id],1)
   if j.Kind=="load" then
    local result=profiles:load(id)
    if closing or not j.Player or j.Player.Parent~=Players then profiles:save(id,true)
    else enqueue("ProfileReady",j.Player,{Result=result,Epoch=profiles:status(id).Epoch,Connection=j.Connection}) end
   else
    local saved=profiles:save(id,j.Kind=="release")
    if not saved.Ok then warn("NightShift profile "..j.Kind.." failed: "..tostring(id).." "..saved.Code) end
   end
  end
  working[id]=nil
 end)
end
local host={contexts=function()
 local out={}; for _,c in pairs(ownership.owners) do table.insert(out,U.copy(c)) end; return out
end,activityPlan=function(uid)
 local c=ownership:getOwnerContext(uid)
 return c and {Contest=commerce.contest:view(c),Demand=commerce.demand:view(c)} or false
end,npcInventory=function(uid)
 local c=ownership:getOwnerContext(uid); local s=c and commerce.stores[c.StoreId]; local out={}
 if s and not s.Frozen then for _,i in pairs(s.Items) do if i.State=="Shelf" then
  table.insert(out,{ItemId=i.ItemId,SlotId=i.SlotId,Sku=i.Sku,ContestHeld=i.ContestHeld==true})
 end end end
 return out
end,enqueue=function(kind,c,payload,callback) enqueue("Internal",false,{Kind=kind,Context=U.copy(c),Payload=U.copy(payload),Callback=callback}) end}
Bridge.configure(host)
local function trafficBuilder(name)
 local m=SS.NightShift:FindFirstChild(name)
 if m and m:IsA("ModuleScript") then local ok,b=pcall(require,m); if ok then return b end end
 return nil
end
local trafficWorld=require(modules.TrafficWorldAdapter).new(world.world,world,
 {Vehicle=trafficBuilder("BuildRoadVehicle"),Signals=trafficBuilder("BuildTrafficSignals")},Players)
local traffic=require(modules.TrafficService).new({Config=cc,World=trafficWorld,Bridge=Bridge,Now=now,NewId=newId})
Bridge.registerTraffic(traffic,function(t) traffic:tick(t) end,function() return traffic:snapshot() end)
Bridge.registerPedestrianTraffic(traffic)
if not traffic.ready then warn("NightShift traffic unavailable: "..tostring(traffic.reason)) end
local npcWorld=require(modules.NPCWorldAdapter).new(world.world,cc,SS.NightShift:FindFirstChild("BuildCustomerRig"))
local npc=require(modules.NPCShoppingService).new({Config=cc,Bridge=Bridge,World=npcWorld,Now=now,NewId=newId,Random=Random.new()})
Bridge.registerNPC(npc,function(t) npc:tick(t) end)
local function internal(data)
 local c,p=data.Context,data.Payload; local kind=data.Kind
 if ownership:validate(c)~="OK" then return U.result("STALE_OWNER") end
 -- The owner lease must still match; notification rounds use the CURRENT night, not spawn-time context.
 local user=service.users[c.UserId]; local current=user and service:context(user)
 if not current then return U.result("STALE_OWNER") end
 c.RoundId=current.RoundId
 if kind=="EndNpcVisit" then return commerce:endNpcVisit(c,p.NpcId)
 elseif kind=="SelectNpcItems" then return commerce:selectNpcItems(c,p.NpcId,p.Kind,p.OpportunityId)
 elseif kind=="CancelNpcSelection" then return commerce:cancelNpcSelection(c,p.NpcId,p.SelectionId)
 elseif kind=="CommitNpcSale" then return commerce:commitNpcSale(c,p)
 elseif kind=="ForceDrop" then return commerce:forceDrop(c,p)
 elseif kind=="OfferOpportunity" then return commerce.contest:offerOpportunity(c,p.Index)
 elseif kind=="ObserveOpportunity" then return commerce:observeOpportunity(c,p.OpportunityId,p.ArrivedAt,p.Outcome,p.Reason) end
 return U.result("BAD_REQUEST")
end
local function callback(fn,value)
 if not fn then return end
 local co=coroutine.create(fn); local ok,err=coroutine.resume(co,value)
 if coroutine.status(co)~="dead" then coroutine.close(co); warn("NightShift callback yielded") elseif not ok then warn("NightShift callback failed: "..tostring(err)) end
end
local function drain(t)
 if draining or failed then return end
 draining=true
 local co=coroutine.create(function()
  commerce.npcAuthority=host.npcAuthority; commerce.collisionAuthority=host.collisionAuthority
  world:sample(t)
  for _,user in pairs(service.users) do if user.player and world:outOfBounds(user.player) then
   commerce:depart(user.id); local c=service:context(user); world:move(user.player,c and c.StoreId or false,"Spawn")
  end end
  local batch=queue; queue={}
  table.sort(batch,function(a,b) return a.At<b.At or (a.At==b.At and a.Serial<b.Serial) end)
  for _,e in ipairs(batch) do
   authorityAt=e.At
   local player,data=e.Player,e.Data; local user=player and service.users[player.UserId]
   if e.Kind=="Connect" and player.Parent==Players then service:connect(player); job(player.UserId,"load",player,connections[player])
   elseif e.Kind=="ProfileReady" then
    if user and user.player==player and connections[player]==data.Connection then
     if data.Result.Ok then service:profileReady(player,data.Epoch) else user.errorCode=data.Result.Code end
    end
   elseif e.Kind=="Disconnect" then
    if user and user.player==player then
     local c=service:disconnect(player)
     if c then U.call(host.npcAuthority,"removeOwner",c.StoreId,c.OwnerGeneration) end
     job(player.UserId,"release",player)
    end
   elseif e.Kind=="CharacterGone" then
    if user and user.player==player then commerce:depart(user.id); user.loaded=false; if ownership.owners[user.id] then ownership.owners[user.id].Loaded=false end end
   elseif e.Kind=="CharacterReady" then
    if user and user.player==player and player.Character==data then local c=service:context(user); world:move(player,c and c.StoreId or false,"Spawn") end
   elseif e.Kind=="Internal" then callback(data.Callback,internal(data))
   elseif e.Kind=="Action" then
    if user and user.player==player and connections[player]==data.Connection then
     local answer=data.Channel=="Commerce" and service:commerceAction(user,data.Request) or service:action(user,data.Request)
     local wire=data.Connection[data.Channel]; local ack=service:ack(user,wire,data.Request,answer)
     Protocol.remember(wire,data.Request,ack,cc); channels[data.Channel].Ack:FireClient(player,ack)
    end
   end
  end
  authorityAt=t
  commerce:tick(t); service:tick(t)
  if host.trafficTick then host.trafficTick(t) end
  if host.npcTick then host.npcTick(t) end
 end)
 local ok,err=coroutine.resume(co)
 local yielded=coroutine.status(co)~="dead"; if yielded then coroutine.close(co) end
 draining=false
 if not ok or yielded then failed=true; service.ready=false; warn("NightShift queue halted: "..tostring(err or "yield forbidden")) end
end
for prefix,channel in pairs(channels) do
 local channelKey=prefix
 channel.Action.OnServerEvent:Connect(function(player,raw)
  local conn=connections[player]; local user=service.users[player.UserId]
  if not conn or not user then return end
  local wire=conn[channelKey]; local t=now()
  local parseable=type(raw)=="table" and Protocol.integer(raw.RequestId,cc.Network.MaxRequestId) and raw.RequestId>0
  local function reject(code)
   if parseable then channel.Ack:FireClient(player,service:ack(user,wire,raw,U.result(code))) end
  end
  if not Protocol.consume(conn[""],cc,t) then if t-conn[""].rateReplyAt>=1 then conn[""].rateReplyAt=t; reject("RATE_LIMIT") end; return end
  local request,code
  if channelKey=="Commerce" then request,code=Protocol.validateCommerce(raw,cc) else request,code=Protocol.validate(raw,config) end
  if not request then reject(code); return end
  local old=wire.cache[request.RequestId]
  if old then if Protocol.equal(request,old.request) then channel.Ack:FireClient(player,old.ack) else reject("REQUEST_ID_REUSED") end; return end
  if wire.pending[request.RequestId] then reject(Protocol.equal(request,wire.pending[request.RequestId]) and "REQUEST_IN_PROGRESS" or "REQUEST_ID_REUSED"); return end
  if request.RequestId<=wire.high then reject("STALE_REQUEST"); return end
  wire.high=request.RequestId
  if failed or closing then reject("NOT_READY"); return end
  wire.pending[request.RequestId]=request
  enqueue("Action",player,{Channel=channelKey,Connection=conn,Request=request})
 end)
 channel.Snapshot.OnServerInvoke=function(player,raw)
  local conn=connections[player]; local user=service.users[player.UserId]; local t=now()
  if not conn or not user or failed then return {Ok=false,Code="NOT_READY",Snapshot=false} end
  local wire=conn[channelKey]; local code=Protocol.validSnapshot(raw,cc)
  if code~="OK" then return {Ok=false,Code=code,Snapshot=false} end
  if t-wire.snapshotAt<cc.Network.SnapshotCooldown then return {Ok=false,Code="RATE_LIMIT",RetryAfter=cc.Network.SnapshotCooldown,Snapshot=false} end
  wire.snapshotAt=t
  local snapshot=channelKey=="Commerce" and service:commercePacket(user,wire,t) or service:packet(user,wire,t)
  if channelKey=="Commerce" and host.trafficSnapshot then snapshot.Traffic=host.trafficSnapshot() end
  return {Ok=true,Code="OK",RetryAfter=0,Snapshot=snapshot}
 end
end
local hooks={}
local function track(player)
 if closing or connections[player] then return end
 connections[player]={[""]=Protocol.newConnection(cc,now()),Commerce=Protocol.newConnection(cc,now())}
 enqueue("Connect",player)
 local list={}; hooks[player]=list
 local function added(character)
  task.spawn(function()
   local human=character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid",10)
   local root=character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart",10)
   if not human or not root or player.Character~=character or player.Parent~=Players then return end
   table.insert(list,human.Died:Connect(function() enqueue("CharacterGone",player) end))
   enqueue("CharacterReady",player,character)
  end)
 end
 table.insert(list,player.CharacterAdded:Connect(added)); table.insert(list,player.CharacterRemoving:Connect(function() enqueue("CharacterGone",player) end))
 if player.Character then added(player.Character) end
end
Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(function(player)
 enqueue("Disconnect",player); connections[player]=nil
 for _,hook in ipairs(hooks[player] or {}) do hook:Disconnect() end; hooks[player]=nil
end)
for _,player in ipairs(Players:GetPlayers()) do track(player) end
RunService.Heartbeat:Connect(function()
 local t=now(); drain(t)
 for _,id in ipairs(profiles:due()) do
  local user=service.users[id]; job(id,user and user.player and "save" or "release",user and user.player)
 end
 if failed then return end
 commerce:flushPresentation()
 for player,conn in pairs(connections) do local user=service.users[player.UserId]
  if user and user.player==player then for prefix,channel in pairs(channels) do local wire=conn[prefix]
   if t-wire.lastSend>=cc.Network.StateInterval then
    local packet=prefix=="Commerce" and service:commercePacket(user,wire,t) or service:packet(user,wire,t)
    if prefix=="Commerce" and host.trafficSnapshot then packet.Traffic=host.trafficSnapshot() end
    channel.State:FireClient(player,packet)
   end
  end end
 end
end)
game:BindToClose(function()
 closing=true; local deadline=os.clock()+cc.Profile.CloseBudgetSeconds
 npc:shutdown()
 traffic:shutdown()
 for player in pairs(connections) do enqueue("Disconnect",player) end
 drain(now()); profiles:close()
 while next(working) and os.clock()<deadline do task.wait(math.min(0.05,deadline-os.clock())) end
end)
print("NightShift v2 source runtime: 8 solo stores; Studio acceptance not asserted")
