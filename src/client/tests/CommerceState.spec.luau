--!strict
local CommerceState = require("../Modules/CommerceState")
local count=0
local function check(value: any, message: string)
	assert(value,message) count+=1
end
local function packet(sequence: number): any
	return {ProtocolVersion=1,Kind="Snapshot",Sequence=sequence,ServerTime=100,
		Self={Wallet=7,Carry={}},Wholesale={Revision=2,Cycle=1,Rows={}},Stores={},
		Store={StoreId="Store01",RoundId="r1",Revision=5},Nearby={},Rankings={}}
end
local s=CommerceState.new()
local accepted,gap=CommerceState.apply(s,{ProtocolVersion=1,Kind="Delta",Sequence=1,ServerTime=100,Self={Wallet=999}},10)
check(not accepted and gap and s.Self==false,"delta before snapshot must not expose partial state")
check(CommerceState.apply(s,packet(3),10),"snapshot")
check(s.Self.Wallet==7 and s.HasSnapshot,"authoritative wallet")
check(CommerceState.now(s,12)==102,"server sampled time")
accepted,gap=CommerceState.apply(s,{ProtocolVersion=1,Kind="Delta",Sequence=5,ServerTime=102,Self={Wallet=9}},12)
check(accepted and gap,"gap requests reconciliation")
check(s.Store.Revision==5 and s.Wholesale.Revision==2 and s.Self.Wallet==9,"omitted slices retained")
check(not CommerceState.apply(s,packet(4),13) and s.Sequence==5,"late snapshot cannot rewind state")
local old=packet(6) old.Wholesale.Revision=1
check(not CommerceState.apply(s,old,13) and s.Sequence==5,"stock revision cannot rewind")
old=packet(6) old.Store.Revision=4
check(not CommerceState.apply(s,old,13) and s.Sequence==5,"same round store cannot rewind")
old=packet(6) old.Store.RoundId="r2" old.Store.Revision=1
check(CommerceState.apply(s,old,13),"new round revision reset")
check(CommerceState.apply(s,{ProtocolVersion=1,Kind="Delta",Sequence=7,ServerTime=104,Store=false,Nearby=false},14),"false slice clear")
check(s.Store==false and s.Nearby==false,"deleted slices")
local bad=packet(8) bad.Rankings=nil
check(not CommerceState.apply(s,bad,15),"full snapshot required")
bad=packet(8) bad.Sequence=0/0
check(not CommerceState.apply(s,bad,15),"NaN sequence")
bad=packet(8) bad.ServerTime=math.huge
check(not CommerceState.apply(s,bad,15),"infinite time")
bad=packet(8) bad.ProtocolVersion=2
check(not CommerceState.apply(s,bad,15),"version mismatch")
local request=CommerceState.request({StoreId="Store08",RoundId="r8",SeatGeneration=4},"RecoverItem",{ItemId="foreign-item",ItemRevision=2},1)
check(request.StoreId=="Store08" and request.Payload.ItemId=="foreign-item","target item never overrides home membership")
check(request.RoundId=="r8" and request.SeatGeneration==4 and request.RequestId==1,"exact envelope")
local slots=CommerceState.preset({{SlotId="Slot01",Sku=false},{SlotId="Slot02",Sku="Milk",Revision=999,ItemIds={"a"}}})
check(#slots==1 and slots[1].SlotId=="Slot02" and slots[1].Sku=="Milk","preset excludes empty slots")
check(slots[1].Revision==nil and slots[1].ItemIds==nil,"preset exact nested schema")
local groups=CommerceState.shelfCandidates({
	{ItemId="z",Sku="Soda",State="Shelf",SlotId="Slot04"},
	{ItemId="a",Sku="Soda",State="Shelf",SlotId="Slot01"},
	{ItemId="b",Sku="Soda",State="Shelf",SlotId="Slot05"},
	{ItemId="c",Sku="Soda",State="Warehouse",SlotId=false},
	{ItemId="d",Sku="GlowBattery",State="Shelf",SlotId="Slot12"}},"Soda")
check(groups[1].ItemId=="a" and groups[2].ItemId=="b" and groups[3]==nil,"match server deterministic slot grouping for all SKUs")
local storage=CommerceState.storage({StoreId="Store08",Items={
	{OwnerStoreId="Store08",State="Warehouse",Sku="Milk",Quantity=1},
	{OwnerStoreId="Store08",State="Warehouse",Sku="Milk",Quantity=1},
	{OwnerStoreId="Store08",State="Truck",Sku="Bread",Quantity=1},
	{OwnerStoreId="Store08",State="Carried",Sku="Bread",Quantity=1},
	{OwnerStoreId="Store08",State="Shelf",Sku="Bread",Quantity=1},
	{OwnerStoreId="Store08",State="Sold",Sku="Bread",Quantity=1},
	{OwnerStoreId="Store01",State="TheftCarried",Sku="Bread",Quantity=1}},
	Orders={{State="Reserved",Quantity=4},{State="InTransit",Quantity=1},{State="Cancelled",Quantity=4}}},24)
check(storage.Warehouse==2 and storage.BySku.Milk==2,"warehouse SKU quantities")
check(storage.Used==9 and storage.Reserved==4 and storage.Remaining==15,"server cap includes reserved and live owned items only")
storage=CommerceState.storage({StoreId="Store08",Items={},Orders={}},24)
check(storage.Warehouse==0 and storage.Remaining==24,"empty warehouse and store")
check(CommerceState.storage(false,24).Remaining==0,"missing store is not an empty available store")
check(CommerceState.storage({StoreId="Store08",Items={},Orders={{State="Reserved",Quantity=25}}},24).Remaining==0,"capacity never negative")
print("CommerceState: "..count.." checks passed")
