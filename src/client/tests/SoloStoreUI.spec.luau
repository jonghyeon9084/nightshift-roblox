-- Offline controller mocks and real pure reducer/contract execution; no Studio.
return function(M,Client,C,K,G,D,T,U)
 local count=0
 local function check(value,message) count+=1; assert(value,"check "..count..": "..message) end
 local function clone(v) if type(v)~="table" then return v end; local r={}; for k,x in pairs(v) do r[k]=clone(x) end; return r end
 local function packet(seq)
  return {ProtocolVersion=2,Sequence=seq or 1,ServerTime=100,
   Self={UserId=1,StoreId="Store01",OwnerGeneration=1,ProfileEpoch=1,ProfileRevision=1,Wallet=240,XP=0,Level=1,UnlockedTools={"HandCarry"},EquippedTool="HandCarry",Presets={},RoundId=false,RareDiscoveries={},DisplayName="한국어 긴 닉네임",Upgrades={Warehouse=0},Achievements={DemandCompletions=0,ContestCompletions=0,BestDiversity=0,BestPlan=0,BestLogistics=0},NextAction="GoToPC"},
   ProfileStatus={State="Temporary",Mode="Memory",Frozen=false,Dirty=true,SavedRevision=0,ErrorCode=false},
   Stores={{StoreId="Store01",OwnerUserId=1,DisplayName="한국어 긴 닉네임",Sales=0,Revenue=0,Alarm=false}},
   Store={StoreId="Store01",OwnerUserId=1,OwnerGeneration=1,Revision=1,WarehouseCapacity=24,SafeStorageCount=0,Orders={},Items={},Slots={{SlotId="Slot01",Sku=false,ItemIds={},Revision=1}}},
   Wholesale={Revision=1,Cycle=1,NextRestockAt=220,Rows={{Sku="Water",PublicAvailable=10,MyAllocated=2,AllocationId="alloc1",ReserveUntil=180,UnitCost=4,SalePrice=7,Rarity="Basic"}}},
   CustomerEvents={Cursor=0,Entries={}},Items={},Nearby={},Carry={},Theft=false,Demand=false,Contest=false,Traffic={Revision=1,Signals={}}}
 end
 local p=packet(); local state=M.new()
 check(M.apply(state,p,0),"v2 full contract DTO without Kind")
 check(not M.apply(state,p,1),"stale sequence")
 local q=packet(2); q.ProtocolVersion=1; check(not M.apply(state,q,1),"reject old protocol")
 q=packet(2); q.Self=false; check(not M.apply(state,q,1),"explicit false self rejected")
 q=packet(2); q.ProfileStatus=false; check(not M.apply(state,q,1),"missing profile status rejected")
 q=packet(2); q.Carry=nil; check(not M.apply(state,q,1),"missing carry rejected atomically"); check(state.Sequence==1,"failed apply unchanged")
 q=packet(2); q.Self.OwnerGeneration=0; check(not M.apply(state,q,1),"old generation")
 q=packet(2); q.Store.OwnerUserId=2; check(not M.apply(state,q,1),"foreign private store")
 q=packet(2); q.Self.ProfileRevision=0; check(not M.apply(state,q,1),"old profile revision")
 q={ProtocolVersion=2,Kind="Delta",Sequence=2,ServerTime=101,Self=clone(p.Self)}; q.Self.OwnerGeneration=2
 check(not M.apply(state,q,1),"generation delta requires full private reset")
 q=packet(3); q.Self.OwnerGeneration=2; q.Store.OwnerGeneration=2
 local accepted,gap=M.apply(state,q,1); check(accepted and gap,"new owner snapshot and sequence gap")
 check(#state.Carry==0,"new snapshot clears tokens")
 check(M.now(state,6)==105,"server time projection")
 for _,view in ipairs({{390,844},{390,300},{320,568},{800,360},{1920,1080}}) do
  local l=M.layout(view[1],view[2]); check(l.Width<=view[1]-24,"width fits "..view[1]); check(l.Height<=view[2]-24,"height fits"); check(l.BodyHeight>=44,"body visible"); check(l.Touch>=44,"touch target")
 end
 local stock=clone(p.Store)
 stock.Items={{ItemId="a",State="Truck",OrderId="o",Sku="Water"},{ItemId="b",State="Warehouse",Sku="Water"}}
 stock.Orders={{OrderId="o",State="InTransit",Quantity=2}}
 local cap=M.storage(stock,24); check(cap.Used==3 and cap.Warehouse==1 and cap.Remaining==21,"inflight capacity without duplicate IDs")
 -- Physics and network are deliberately controlled test doubles.
 local near=true
 local handlers={}; local sent={}; local latest=packet()
 local function remote(class)
  return {IsA=function(_,name) return class==name end,OnClientEvent={Connect=function(_,fn) table.insert(handlers,fn); return {Disconnect=function() end} end},
   FireServer=function(_,raw) table.insert(sent,raw) end,InvokeServer=function(_,raw) check(raw.ProtocolVersion==2,"snapshot request v2"); return {Ok=true,Snapshot=latest} end}
 end
 local remotes={}; for k,name in pairs(C.Network.Remotes) do remotes[name]=remote(k=="GetSnapshot" and "RemoteFunction" or "RemoteEvent") end
 local folder={FindFirstChild=function(_,name) return remotes[name] end}
 local env=getfenv(Client.new)
 env.task={spawn=function(fn) fn() end}
 env.Enum={KeyCode={E="E",V="V",F="F",F5="F5",One="One",Two="Two",Three="Three",Four="Four"}}
 local dirty=0
 local client=Client.new({Config=C,Player={},Dirty=function() dirty+=1 end,LegacyStore=function() return false end,Work=function() end,Rebind=function() end})
 client.near=function() return near end; client.itemNear=function() return near end
 check(client:bind(folder),"bind all real remote names")
 check(client.state.HasSnapshot,"snapshot received after subscriptions")
 check(client:active(),"temporary active owner")
 local labels,buttons={},{}
 local function render(section)
  labels={}; buttons={}; client.section=section
  client:render({Label=function(text) table.insert(labels,text) end,Button=function(text,fn,enabled,key,id) buttons[id or text]={Text=text,Call=fn,Enabled=enabled,Key=key} end})
  return table.concat(labels,"\n")
 end
 local function ack(ok,code)
  local req=sent[#sent]
  local a={ProtocolVersion=2,RequestId=req.RequestId,Action=req.Action,OwnerGeneration=1,Ok=ok,Code=code or "OK"}
  handlers[2](a)
 end
 local function validateLast(action)
  local req=sent[#sent]; local valid,why=K.validateAction(req,C)
  check(valid~=nil,"real shared validator accepts "..action.." "..tostring(why)); check(req.Action==action,"correct action")
  check(req.SeatGeneration==nil and req.OwnerGeneration==1,"owner envelope only")
  ack(true)
  client.lastInput=-math.huge
 end
 local text=render("shop")
 check(string.find(text,"임시 저장",1,true)~=nil,"temporary mode visible")
 check(buttons["act-buy-Water"].Enabled,"PC owner can buy")
 buttons["act-buy-Water"].Call(); validateLast("OrderStock")
 check(sent[#sent].Payload.AllocationId=="alloc1","owned unexpired allocation")
 check(client.state.Self.Wallet==240 and #client.state.Store.Items==0,"ack no optimistic money or items")
 render("shop"); local old=buttons["act-buy-Water"].Call; near=false; old(); check(#sent==1,"stale callback rechecks PC proximity")
 render("shop"); check(not buttons["act-buy-Water"].Enabled,"remote PC disabled")
 near=true; client.state.ProfileStatus.Frozen=true
 render("profile"); check(not buttons["act-upgrade"].Enabled,"frozen cannot upgrade")
 client.state.ProfileStatus.Frozen=false
 render("profile"); buttons["act-upgrade"].Call(); validateLast("BuyUpgrade")
 check(string.find(table.concat(labels,"\n"),"전문화 · 이번 버전 보류",1,true)~=nil,"specialization deferred")
 client.state.Self.NextAction="FreeRecovery"
 render("profile"); buttons["act-recovery"].Call(); validateLast("RequestRecoveryStock")
 check(string.find(table.concat(labels,"\n"),"아직 발견한 상품",1,true)~=nil,"empty discovery not fabricated")
 client.state.Self.Level=5
 render("profile"); buttons["act-preset-1"].Call(); validateLast("SavePreset")
 render("profile"); buttons["act-apply-1"].Call(); validateLast("ApplyPreset")
 render("profile"); buttons["act-equip-HandCarry"].Call(); validateLast("EquipTool")
 client.state.Store.Orders={{OrderId="o1",Sku="Water",Quantity=1,State="Reserved",ArriveAt=120}}
 render("shop"); buttons["act-cancel-o1"].Call(); validateLast("CancelStockOrder")
 local carry={ItemId="i1",Revision=1,Sku="Water",Quantity=1,State="Carried",OwnerUserId=1,OwnerStoreId="Store01",CarryToken="token1"}
 client.state.Carry={carry}
 render("items"); buttons["act-place-i1"].Call(); validateLast("PlaceShelf")
 render("items"); buttons["act-drop-i1"].Call(); validateLast("DropWarehouse")
 client.state.Carry={}
 for _,pair in ipairs({{"Truck","PickCargo"},{"Warehouse","PickWarehouse"},{"Shelf","PickShelf"},{"Recoverable","RecoverItem"},{"SafeStorage","RecoverItem"}}) do
  local item=clone(carry); item.State=pair[1]; client.state.Store.Items={item}
  render("items"); local id=(pair[2]=="RecoverItem" and "act-recover-" or "act-pick-").."i1"
  check(buttons[id].Enabled,"direct item enabled "..pair[1]); buttons[id].Call(); validateLast(pair[2])
 end
 local foreign=clone(carry); foreign.OwnerUserId=2; foreign.OwnerStoreId="Store02"; foreign.State="Shelf"
 client.state.Store.Items={}; client.state.Nearby={foreign}
 render("items"); buttons["act-theft-i1"].Call(); validateLast("BeginTheft")
 client.state.Theft={TheftId="t1",State="Holding",CompleteAt=104}
 render("items"); buttons["act-cancel-theft"].Call(); validateLast("CancelTheft")
 client.state.Carry={foreign}; foreign.State="TheftCarried"
 text=render("items"); check(not buttons["act-place-i1"].Enabled and not buttons["act-drop-i1"].Enabled,"foreign carry cannot place or store")
 for id in pairs(buttons) do check(not string.find(id,"secure",1,true),"no permanent theft transfer") end
 client.state.Demand={CycleId="c1",Phase="Active",StartsAt=100,EndsAt=400,ReserveUntil=220,Eligible=true,Reason=false,Targets={{Sku="Water",Required=2,Sold=1}},Completed=false,NextTargets={{Sku="Milk",Required=2}}}
 client.state.Contest={CycleId="c1",Phase="Preparing",Joined=false,Eligible=true,Comparable=false,Reason="PersonalOnly",StartsAt=100,EndsAt=400,NextOpportunityAt=190,Scores={Diversity=10,Plan=10,Logistics=10},Rows={},Results=false}
 text=render("goals"); check(string.find(text,"1/2",1,true)~=nil,"R-A actual sold progress"); check(string.find(text,"다음 목표 · 우유",1,true)~=nil,"next cycle goal")
 check(string.find(text,"종합 우승·경제 보상 없음",1,true)~=nil,"no fake reward")
 buttons["act-contest"].Call(); validateLast("SetContestParticipation")
 client.state.Contest.Phase="Active"; render("goals"); check(not buttons["act-contest"].Enabled,"active cycle participation closed")
 client.state.Contest.Phase="Finished"; client.state.Contest.Results={Comparable=false,Reason="PersonalOnly",Winners={}}
 text=render("goals"); check(string.find(text,"비교 순위 없음",1,true)~=nil,"personal only no rank")
 client.state.Contest.Rows={{OwnerUserId=1,DisplayName="가",Scores={Diversity=20,Plan=40,Logistics=30},Status="Finished"},{OwnerUserId=2,DisplayName="나",Scores={Diversity=20,Plan=40,Logistics=30},Status="Finished"}}
 client.state.Contest.Results={Comparable=true,Winners={Diversity={1,2},Plan={1,2},Logistics={1,2}}}
 text=render("goals"); check(string.find(text,"공동 1위 · 가, 나",1,true)~=nil,"ties all shown separately")
 client.state.Traffic={Signals={{CrossingId="Cross01",PedestrianGo=false,PhaseEndsAt=120}}}
 client.state.Stores[1].Alarm={ItemId="i1",RecoverUntil=125}
 text=render("items"); check(string.find(text,"보행 대기",1,true)~=nil and string.find(text,"도난 경보",1,true)~=nil,"server traffic and alarm")
 latest=packet(20); latest.Notice={EventId="ev1",Kind="RichCustomerArrived"}; client:receive(latest)
 text=render("shop"); check(string.find(text,"부자 손님 방문",1,true)==nil,"unconfirmed notice schema ignored")
 latest=packet(21); latest.Stores[1].Sales=2; latest.Stores[1].Revenue=14; client:receive(latest)
 text=render("shop"); check(string.find(text,"매출 갱신",1,true)~=nil,"server sales notice")
 latest=packet(22); latest.Notice={EventId="ev2",Kind="NpcSaleCommitted",CustomerKind="Rich",Units=2,Revenue=14}; client:receive(latest)
 check(string.find(render("shop"),"부자 손님 구매",1,true)==nil,"unconfirmed rich purchase ignored")
 client.state.Self.RareDiscoveries={"StarJelly"}; check(string.find(render("profile"),"별빛 젤리",1,true)~=nil,"server discovery extension")
 client:send("BuyUpgrade",{UpgradeId="Warehouse",ExpectedLevel=0,ProfileRevision=1}); local waiting=#sent
 client.lastInput=-math.huge; client:send("BuyUpgrade",{UpgradeId="Warehouse",ExpectedLevel=0,ProfileRevision=1}); check(#sent==waiting,"pending request double click blocked")
 ack(false,"INSUFFICIENT_FUNDS"); check(string.find(client.status,"게임머니",1,true)~=nil,"error localized")
 check(client.state.Self.Wallet==240,"failure no money mutation")
 -- Neither a late acknowledgement nor an old generation may clear current request state.
 client.lastInput=-math.huge
 client:send("BuyUpgrade",{UpgradeId="Warehouse",ExpectedLevel=0,ProfileRevision=1})
 local req=sent[#sent]
 handlers[2]({ProtocolVersion=2,RequestId=req.RequestId,Action="OrderStock",OwnerGeneration=1,Ok=true})
 check(client.pending[req.RequestId]~=nil,"wrong action acknowledgement ignored")
 handlers[2]({ProtocolVersion=2,RequestId=req.RequestId,Action=req.Action,OwnerGeneration=0,Ok=true})
 check(client.pending[req.RequestId]~=nil,"old owner acknowledgement ignored")
 handlers[2]({ProtocolVersion=2,RequestId=req.RequestId,Action=req.Action,OwnerGeneration=1,Ok=true})
 check(client.pending[req.RequestId]==nil,"matching acknowledgement clears pending")
 latest=packet(30); latest.Self.StoreId=false; latest.Store=false; client:receive(latest)
 check(not client:active(),"unassigned ninth player cannot act")
 check(string.find(render("shop"),"빈 매장 자동 배정",1,true)~=nil,"unassigned state visible")

 -- Execute the CURRENT real server DTO serializers with explicit dependency doubles.
 local at=100; local serial=0
 local function newid(prefix) serial+=1; return prefix..serial end
 local context={UserId=1,StoreId="Store01",OwnerGeneration=1,ProfileEpoch=1,RoundId=false,Loaded=true,Active=true,Wallet=240,DisplayName="실제 DTO 테스트"}
 local stock={Public={},Revision=1}; for sku in pairs(C.Products) do stock.Public[sku]=32 end
 local demand=D.new(C,function() return at end,newid,stock)
 check(demand:prepare("actual-cycle-1",{context},1).Ok,"real demand prepare")
 local contest=T.new(C,function() return at end,newid); contest:prepare(demand.cycle,{context})
 check(contest:setParticipation(context,"actual-cycle-1",true).Ok,"real contest participation")
 local canonical={Revision=1,Wallet=240,XP=0,Level=1,EquippedTool="HandCarry",UnlockedTools={"HandCarry"},Presets={},RareDiscoveries={"StarJelly"},Store={Upgrades={Warehouse=0},Achievements=clone(packet().Self.Achievements),RecoveryDebt=0}}
 local view=clone(packet()); view.Orders={}; view.Items={}; view.Carry={}; view.Store.OwnerGeneration=1
 local commerceMock={customerEvents=function() return {Cursor=0,Entries={}} end,stores={Store01={OwnerUserId=1,DisplayName=context.DisplayName,Sales=0,Revenue=0,Revision=1,Alarm=false}},view=function()
  local v=clone(view); v.Demand=demand:view(context); v.Contest=contest:view(context); return v
 end}
 local service=G.new({Config={},CommerceConfig=C,Profiles={get=function() return U.result("OK",canonical) end,status=function() return clone(packet().ProfileStatus) end},Commerce=commerceMock,
  Ownership={getOwnerContext=function() return clone(context) end},World={},Now=function() return at end,NewId=newid})
 local user={id=1,name=context.DisplayName,loaded=true,errorCode=false}; service.users[1]=user
 local wire={sequence=100}
 local actual=service:commercePacket(user,wire,at)
 check(client:receive(actual),"real SoloGameService commercePacket accepted")
 text=render("goals"); check(string.find(text,"다음 목표 · 우유",1,true)~=nil,"real Demand:view SKU array")
 check(buttons["act-contest"].Enabled,"real Prepare phase enabled")
 text=render("profile"); check(string.find(text,"별빛 젤리",1,true)~=nil,"actual emitted RareDiscoveries array")
 context.RoundId="new-night"; service.nights[1]={RoundId="new-night"}
 client:receive(service:commercePacket(user,wire,at))
 check(client:context().RoundId=="new-night","round ID from commerce stream, independent of lagging night stream")
 local req=M.request(client:context(),"BuyUpgrade",{UpgradeId="Warehouse",ExpectedLevel=0,ProfileRevision=1},500)
 local realAck=service:ack(user,wire,req,U.result("OK"))
 check(realAck.Action=="BuyUpgrade" and realAck.OwnerGeneration==1 and realAck.ProtocolVersion==2,"real Ack schema")
 demand.cycle.Owners[1].Sold.Water=1
 client:receive(service:commercePacket(user,wire,at)); check(string.find(render("goals"),"1/2",1,true)~=nil,"real demand progress DTO")
 at=500; contest.cycle.Owners[1].Joined=false
 check(contest:finalize("actual-cycle-1").Ok,"real finalize")
 client:receive(service:commercePacket(user,wire,at)); check(string.find(render("goals"),"비교 순위 없음",1,true)~=nil,"real noncomparable finalized DTO")
 check(demand:prepare("actual-cycle-2",{context},2).Ok,"second real demand cycle")
 contest:prepare(demand.cycle,{context}); client:receive(service:commercePacket(user,wire,at))
 check(string.find(render("goals"),"다음 목표 · 물",1,true)~=nil,"two-cycle rotation from real serializer")
 canonical=nil
 -- Simulate no profile via the exact serializer's failure branch.
 service.profiles.get=function() return U.result("PROFILE_UNAVAILABLE") end
 service.ownership.getOwnerContext=function() return nil end; view.Store=false; client.state=M.new()
 check(client:receive(service:commercePacket(user,wire,at)),"initial unavailable profile packet accepted"); check(pcall(function() render("profile") end),"empty achievements pre-profile state does not throw")
 check(string.find(render("profile"),"아직 발견한 상품",1,true)~=nil,"real empty discovery array")
 print("PASS "..count.." assertions; OFFLINE pure reducer + controller mocks, not Studio")
end
