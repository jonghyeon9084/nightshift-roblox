--!nonstrict
-- Pure transport/render fakes. This does not execute Roblox UI or Studio.
local Enum={KeyCode={V="V",F5="F5",E="E",F="F",T="T",One="One",Two="Two",Three="Three"}}
local workspace={}
local CommerceClient = require("../Modules/CommerceClient")
local C = require("../../shared/CommerceConfig")
local callbacks,buttons,labels,sent,events={},{},{},{},{}
local function event()
	local e={}
	function e:Connect(fn) self.fn=fn return {Disconnect=function() end} end
	return e
end
local function remote(class)
	local r={OnClientEvent=event()}
	function r:IsA(wanted) return wanted==class end
	function r:FireServer(request) table.insert(sent,request) end
	return r
end
local me={StoreId="Store08",SeatGeneration=3,Loaded=true,Participant="Active"}
local legacy={StoreId="Store08",RoundId="round",Phase="Running",Round={OutageStatus="None"}}
local client=CommerceClient.new({Config=C,LegacySelf=function() return me end,LegacyStore=function() return legacy end,
	Dirty=function() end,Work=function() end,Rebind=function() end})
client.near=function() return true end
client.itemNear=function() return true end
local packet={ProtocolVersion=1,Kind="Snapshot",Sequence=1,ServerTime=100,
	Self={Wallet=10,XP=300,Level=5,ProfileState="Temporary",SaveMode="Memory",Dirty=true,SavedRevision=0,
		Carry={},Tools={"HandCarry","Handcart","StockScanner","LayoutPreset","ToolStyle"},EquippedTool="HandCarry",
		Presets={{Index=1,Slots={{SlotId="Slot01",Sku="Milk"}}}},Best={},Theft=false,Voice="Unavailable"},
	Wholesale={Revision=8,Cycle=3,NextRestockAt=220,Rows={}},Stores={},
	Store={StoreId="Store08",RoundId="round",Revision=1,OperatingCash=240,Orders={},Items={},Slots={}},Nearby={},Rankings={}}
for _,sku in ipairs(C.ProductOrder) do
	local p=C.Products[sku]
	table.insert(packet.Wholesale.Rows,{Sku=sku,Available=3,UnitCost=p.WholesalePrice,SalePrice=p.SalePrice,Rarity=p.Rarity})
end
client:receive(packet)
local ui={Label=function(text) table.insert(labels,text) end,Button=function(text,fn,enabled,key,id)
	if id then callbacks[id]=fn buttons[id]={Enabled=enabled,Text=text,Key=key} end
end}
client.bound=true client.remotes.Action=remote("RemoteEvent")
client:render(ui)
assert(buttons["buy-GlowBattery"].Enabled and buttons["buy-Water"].Enabled,"11 actual catalog entries")
assert(string.find(buttons["buy-GlowBattery"].Text,"희귀"),"rare label")
callbacks["buy-Water"]()
assert(#sent==1 and sent[1].Payload.StockRevision==8 and sent[1].Payload.Quantity==1,"stock request uses actual revision")
assert(sent[1].StoreId=="Store08" and sent[1].RoundId=="round" and sent[1].SeatGeneration==3,"legacy authority context")
assert(client.state.Wholesale.Rows[1].Available==3 and client.state.Store.OperatingCash==240,"send never optimistically spends")
client.section="profile" client:render(ui)
client.lastInput=-math.huge callbacks["save-preset-1"]()
assert(sent[2].Action=="SavePreset" and #sent[2].Payload.Slots==0,"preset exact DTO")
assert(buttons["equip-Handcart"].Enabled,"free tool unlock")
legacy.Phase="Recovery" client:render(ui)
assert(not buttons["equip-Handcart"].Enabled,"recovery blocks input")
legacy.Phase="Running" legacy.Round.OutageStatus="Active" client:render(ui)
assert(not buttons["save-preset-1"].Enabled,"outage blocks commerce")
legacy.Round.OutageStatus="None"
client.state.Self.ProfileState="LoadFailed" client:render(ui)
assert(not buttons["equip-HandCarry"].Enabled,"failed profile cannot equip")
client.state.Self.ProfileState="Temporary"
local ackRemote=remote("RemoteEvent")
client.bound=false client.snapshot=function() events.snapshot=true end
local folder={FindFirstChild=function(_,name)
	if name=="CommerceActionResult" then return ackRemote end
	if name=="GetCommerceSnapshot" then return remote("RemoteFunction") end
	return remote("RemoteEvent")
end}
assert(client:bind(folder) and events.snapshot,"bind subscribes and snapshots")
ackRemote.OnClientEvent.fn({ProtocolVersion=1,RequestId=1,Ok=true,Code="OK"})
assert(client.state.Self.Wallet==10 and client.state.Wholesale.Rows[1].Available==3,"ack does not mutate money/stock")
assert(client.pending[1]==nil,"ack resolves only pending request")
assert(client.rareNotice and string.find(client.rareNotice,"공용"),"shared cycle rare notice")
print("CommerceClient: 15 transport/render checks passed (fakes; no Roblox execution)")

-- Review regression: secured stolen provenance must not block normal logistics.
local regressionCount=0
local function check(value,message)
	assert(value,message) regressionCount+=1
end
local function renderItem(item,carried,profileState)
	callbacks,buttons,labels={},{},{}
	local own=table.clone(client.state.Self)
	own.Carry=carried and {item} or {}
	own.ProfileState=profileState or "Temporary"
	local store=table.clone(client.state.Store)
	store.Items={item} store.Revision+=1
	store.Slots={{SlotId="Slot01",Sku=item.State=="Shelf" and item.Sku or false,ItemIds=item.State=="Shelf" and {item.ItemId} or {}}}
	client:receive({ProtocolVersion=1,Kind="Delta",Sequence=client.state.Sequence+1,ServerTime=100,
		Self=own,Store=store,Nearby={}})
	client.section="items" client:render(ui)
end
local function invoke(id)
	check(buttons[id] and buttons[id].Enabled,"expected enabled button: "..id)
	client.lastInput=-math.huge callbacks[id]()
	return sent[#sent]
end
local secured={ItemId="secured",Sku="Milk",OwnerStoreId="Store08",State="Warehouse",Revision=12,
	Stolen=true,RecoverUntil=false,SlotId=false,OrderId=false,CarrierUserId=false}
renderItem(secured,false)
local request=invoke("pick-secured")
check(request.Action=="PickWarehouse" and request.Payload.ItemId=="secured" and request.Payload.ItemRevision==12,"secured warehouse pickup DTO")
check(client.state.Store.Items[1].State=="Warehouse" and client.state.Store.Items[1].Stolen,"pickup request awaits server and preserves provenance")
check(not buttons["recover-secured"] and not buttons["secure-secured"],"secured goods must not show recovery/secure actions")
local carried=table.clone(secured)
carried.State="Carried" carried.Revision=13 carried.CarryToken="server-token" carried.CarrierUserId=42
renderItem(carried,true)
request=invoke("place-secured")
check(request.Action=="PlaceShelf" and request.Payload.SlotId=="Slot01" and request.Payload.CarryToken=="server-token" and request.Payload.ItemRevision==13,"secured placement keeps server token/revision")
check(client.state.Self.Carry[1].State=="Carried" and client.state.Self.Carry[1].Stolen,"placement cannot locally clear stolen provenance")
request=invoke("drop-secured")
check(request.Action=="DropWarehouse" and request.Payload.CarryToken=="server-token","secured goods can be returned to warehouse")
check(not buttons["secure-secured"],"owned secured carry must not be offered SecureTheft")
local shelf=table.clone(secured)
shelf.State="Shelf" shelf.SlotId="Slot01" shelf.Revision=14
renderItem(shelf,false)
check(client:shelfCandidates("Milk")[1].ItemId=="secured","secured shelf item reaches legacy customer-sale candidate path")
check(string.find(client:shelfLabels()[1],"우유"),"secured shelf item visible on sales shelf")
request=invoke("pick-secured")
check(request.Action=="PickShelf" and request.Payload.ItemRevision==14,"secured shelf pickup remains possible")
check(client.state.Self.Wallet==10 and client.state.Store.Items[1].Stolen,"UI neither grants rewards nor removes exclusion provenance")
local escaping=table.clone(carried)
escaping.OwnerStoreId="Store01" escaping.State="TheftCarried" escaping.RecoverUntil=1000
renderItem(escaping,true)
check(not buttons["place-secured"].Enabled and not buttons["drop-secured"].Enabled,"recovery window forbids normal placement/drop")
check(buttons["secure-secured"] and not buttons["secure-secured"].Enabled,"cannot secure before recovery deadline")
check(not buttons["pick-secured"],"foreign carried goods cannot use normal pickup")
escaping=table.clone(escaping) escaping.RecoverUntil=1
renderItem(escaping,true)
check(not buttons["place-secured"].Enabled and not buttons["drop-secured"].Enabled,"expired deadline alone does not transfer ownership")
request=invoke("secure-secured")
check(request.Action=="SecureTheft" and request.Payload.CarryToken=="server-token","post-deadline secure request uses private token")
check(client.state.Self.Carry[1].OwnerStoreId=="Store01","secure request waits for authoritative owner update")
local victimItem=table.clone(escaping)
victimItem.OwnerStoreId="Store08" victimItem.State="Recoverable" victimItem.RecoverUntil=1000
renderItem(victimItem,false)
request=invoke("recover-secured")
check(request.Action=="RecoverItem" and request.Payload.ItemRevision==13,"victim can recover during deadline")
check(not buttons["pick-secured"],"recoverable goods cannot use ordinary pickup")
victimItem=table.clone(victimItem) victimItem.RecoverUntil=1
renderItem(victimItem,false)
check(not buttons["recover-secured"].Enabled,"victim recovery ends at deadline")
renderItem(secured,false,"SaveFailed")
check(client:active() and buttons["pick-secured"].Enabled,"SaveFailed does not freeze a potentially valid lease")
client.section="profile" client:render(ui)
check(buttons["equip-Handcart"].Enabled,"SaveFailed permits server-authorized free-tool requests")
check(string.find(table.concat(labels,"\n"),C.Text.SaveFailed,1,true),"SaveFailed still displays persistence warning")
for _,profileState in ipairs({"Loading","LoadFailed","Locked","LeaseLost","Released"}) do
	renderItem(secured,false,profileState)
	check(not client:active() and not buttons["pick-secured"].Enabled,"unavailable profile still gated: "..profileState)
end
renderItem(secured,false,"SaveFailed")
legacy.Phase="Recovery" client:render(ui)
check(not buttons["pick-secured"].Enabled,"SaveFailed cannot bypass round recovery")
legacy.Phase="Running" legacy.Round.OutageStatus="Active" client:render(ui)
check(not buttons["pick-secured"].Enabled,"SaveFailed cannot bypass outage")
legacy.Round.OutageStatus="None"
print("CommerceClient review regressions: "..regressionCount.." checks passed (fakes; no actual sale/server/Studio)")

-- Engine-reproduced bug: a distant shelf must not take E away from nearby cargo.
client.section="items"; client.state.Self.ProfileState="Temporary"; client.state.Self.Carry={}
local far=table.clone(secured); far.ItemId="far"; far.State="Shelf"
local near=table.clone(secured); near.ItemId="near"; near.State="Truck"
client.state.Store.Items={far,near}; client.state.Nearby={}
client.itemNear=function(_,item) return item.ItemId=="near" end
client:render(ui)
assert(not buttons["pick-far"].Enabled and buttons["pick-near"].Enabled and buttons["pick-near"].Key=="E")
client.state.Self.EquippedTool="Handcart"; client.state.Self.Carry={secured}; client:render(ui)
assert(buttons["pick-near"].Enabled,"cart retains its second cargo slot")
print("CommerceClient distance/cart regression: 2 checks passed with fake spatial query")

-- Warehouse worker: stale callbacks and direct tab access must not bypass OfficePC.
local warehouseChecks=0
local function warehouseCheck(value,message) assert(value,message) warehouseChecks+=1 end
local closeToPC=true
client.near=function() return closeToPC end
client.section="shop"; client.state.Self.Carry={}; client.state.Store.Items={}
client.state.Store.Orders={{OrderId="reserved",Sku="Milk",Quantity=1,State="Reserved",ArriveAt=false,RecallAt=false}}
callbacks,buttons,labels={},{},{}
client:render(ui)
local oldBuy,oldCancel=callbacks["buy-Water"],callbacks["cancel-reserved"]
warehouseCheck(buttons["buy-Water"].Enabled and buttons["cancel-reserved"].Enabled,"own PC permits order and cancellation")
closeToPC=false
local before=#sent
client.lastInput=-math.huge oldBuy()
client.lastInput=-math.huge oldCancel()
warehouseCheck(#sent==before,"leaving PC blocks stale order and cancel callbacks before next render")
callbacks,buttons,labels={},{},{}
client:render(ui)
warehouseCheck(not buttons["buy-Water"] and not buttons["cancel-reserved"] and not buttons.quantity,"distant HUD/tab view contains no ordering controls")
warehouseCheck(string.find(table.concat(labels,"\n"),"조회 전용",1,true),"distant view clearly directs player to office PC")
client.section="items"; client.state.Store.Orders={}
callbacks,buttons,labels={},{},{}
client:render(ui)
warehouseCheck(string.find(table.concat(labels,"\n"),"창고가 비어",1,true),"empty warehouse instruction")
warehouseCheck(string.find(table.concat(labels,"\n"),"추가 보관 가능 24개",1,true),"empty store has full server cap")
callbacks["commerce-tab-shop"]()
callbacks,buttons,labels={},{},{}
client:render(ui)
warehouseCheck(not buttons["buy-Water"],"keyboard/touch tab navigation cannot expose distant order controls")
closeToPC=true
local available=client.state.Wholesale.Rows[1].Available
client.state.Wholesale.Rows[1].Available=0
callbacks,buttons,labels={},{},{}
client:render(ui)
warehouseCheck(not buttons["buy-Water"].Enabled,"empty wholesale stock disables order")
client.state.Wholesale.Rows[1].Available=available
client.pending[999]={Action="OrderStock",At=os.clock()}
ackRemote.OnClientEvent.fn({ProtocolVersion=1,RequestId=999,Ok=false,Code="TOO_FAR"})
warehouseCheck(string.find(client.status,"가까이",1,true) and client.state.Store.OperatingCash==240,"server distance refusal stays readable without spending")
legacy.Phase="Recovery"
client.lastInput=-math.huge client:send("OrderStock",{Sku="Water",Quantity=1,StockRevision=8})
warehouseCheck(#sent==before,"inactive phase blocks dispatch even while near PC")
legacy.Phase="Running"
print("CommerceClient warehouse UI: "..warehouseChecks.." checks passed (fake state/transport; no Studio)")

-- Execute the production near() function against a fake named world tree.
-- Earlier UI tests stubbed near(); these cover own-store lookup and the boundary itself.
local evidenceChecks=0
local function evidence(value,name) assert(value,name) evidenceChecks+=1 end
local function position(x)
	return setmetatable({X=x},{__sub=function(a,b) return {Magnitude=math.abs(a.X-b.X)} end})
end
local function node(children)
	return {FindFirstChild=function(_,name) return children[name] end}
end
local root={Position=position(100)}
local ownPC={Position=position(0),IsA=function(_,class) return class=="BasePart" end}
local foreignPC={Position=position(100),IsA=function(_,class) return class=="BasePart" end}
local ownChildren={OfficePC=ownPC}
local stores=node({Store08=node(ownChildren),Store01=node({OfficePC=foreignPC})})
local world=node({Stores=stores})
workspace.FindFirstChild=function(_,name) return name=="NightShiftWorld" and world or nil end
client.deps.Player={Character=node({HumanoidRootPart=root})}
client.near=nil -- Use the actual CommerceClient.near implementation.
evidence(client:near("Store01","OfficePC") and not client:near("Store08","OfficePC"),"OwnPC.NamedStoreLookup: foreign PC nearby does not count as own PC")
before=#sent
client.lastInput=-math.huge client:send("OrderStock",{Sku="Water",Quantity=1,StockRevision=8})
client.lastInput=-math.huge client:send("CancelStockOrder",{OrderId="reserved"})
evidence(#sent==before,"OwnPC.ForeignPCDispatch: both order and cancel blocked at foreign PC")
callbacks,buttons,labels={},{},{}; client.section="shop"; client:render(ui)
evidence(not buttons["buy-Water"] and not buttons["cancel-reserved"],"OwnPC.ForeignPCView: foreign PC leaves HUD in query-only mode")
root.Position=position(C.Interaction.Distance)
evidence(client:near("Store08","OfficePC"),"OwnPC.DistanceInclusive: configured boundary is allowed")
root.Position=position(C.Interaction.Distance+0.01)
evidence(not client:near("Store08","OfficePC"),"OwnPC.DistanceOutside: outside configured boundary is blocked")
root.Position=position(0)
evidence(client:near("Store08","OfficePC"),"OwnPC.AtOwnPC: own marker permits proximity")
ownChildren.OfficePC=nil
evidence(not client:near("Store08","OfficePC"),"OwnPC.MissingMarker: no marker fails closed")
ownChildren.OfficePC=ownPC
client.deps.Player.Character=nil
evidence(not client:near("Store08","OfficePC"),"OwnPC.NoCharacter: respawn fails closed")
client.deps.Player.Character=node({HumanoidRootPart=root})
evidence(not client:near(false,"OfficePC"),"OwnPC.NoMembership: no store fails closed")

local item={ItemId="ack-item",Sku="Milk",Quantity=1,OwnerStoreId="Store08",State="Warehouse",Revision=1}
client.state.Store.Items={item}
local cash=client.state.Store.OperatingCash
local stock=client.state.Wholesale.Rows[1].Available
client.lastInput=-math.huge client:send("PickWarehouse",{ItemId=item.ItemId,ItemRevision=item.Revision})
evidence(client.state.Store.Items[1]==item and item.State=="Warehouse" and item.Quantity==1,"Authority.Pending: request leaves quantity and warehouse state unchanged")
ackRemote.OnClientEvent.fn({ProtocolVersion=1,RequestId=client.requestId,Ok=true,Code="OK"})
evidence(client.state.Store.Items[1]==item and item.Quantity==1 and item.State=="Warehouse","Authority.SuccessAck: success alone does not move or decrement goods")
evidence(client.state.Store.OperatingCash==cash and client.state.Wholesale.Rows[1].Available==stock,"Authority.SuccessAckMoney: ack does not spend or restock")
local nextStore=table.clone(client.state.Store)
nextStore.Items={}; nextStore.Revision+=1
client:receive({ProtocolVersion=1,Kind="Delta",Sequence=client.state.Sequence+1,ServerTime=101,Store=nextStore})
evidence(#client.state.Store.Items==0,"Authority.StatePacket: only server state packet replaces warehouse inventory")
print("CommerceClient moderator evidence: "..evidenceChecks.." checks passed (production near/reducer with fake world/transport; no Studio)")

-- Integrator regression: UI must use the same marker as the server, even when
-- the rendered unit is on the opposite edge of a bin/rack/cargo bay.
client.itemNear=nil
ownChildren.WarehouseDrop=ownPC
ownChildren.ShelfSlots=node({Slot01=ownPC})
local cargo=ownPC
local worldWithCargo=node({Stores=stores,CommerceRuntime=node({Trucks=node({order=node({Cargo=cargo})}),Items=node({})})})
workspace.FindFirstChild=function(_,name) return name=="NightShiftWorld" and worldWithCargo or nil end
for _,distance in ipairs({9.99,10,10.01}) do
 root.Position=position(distance)
 for _,state in ipairs({"Warehouse","Shelf","Truck"}) do
  assert(client:itemNear({OwnerStoreId="Store08",State=state,SlotId="Slot01",OrderId="order",ItemId="absent"})==(distance<=10),state.." server marker boundary")
 end
end
client.section="items"; root.Position=position(0)
client.state.Self.Carry={{ItemId="drop-check",Sku="Milk",OwnerStoreId="Store08",State="Carried",Revision=1,CarryToken="token"}}
client.near=function(_,_,marker) return marker=="WarehouseDrop" end
callbacks,buttons,labels={},{},{}; client:render(ui)
assert(buttons["drop-drop-check"].Enabled and buttons["drop-drop-check"].Key==Enum.KeyCode.E,"warehouse drop gets primary E")
print("Integrator warehouse regression: 9 marker boundaries and warehouse E passed; fake spatial/UI")
