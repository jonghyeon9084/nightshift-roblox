--!nonstrict
-- Pure v2 projection. No local economy or success prediction.
local Contract = require(game:GetService("ReplicatedStorage").NightShift.Shared.SoloStoreContract)
local Model = {}
local slices = {"Self","ProfileStatus","Stores","Store","Wholesale","Items","Nearby","Carry","Theft","Demand","Contest","Traffic","CustomerEvents"}
local function finite(v)
 return type(v)=="number" and v==v and math.abs(v)<math.huge
end
function Model.new()
 return {Sequence=0,HasSnapshot=false,ServerTime=0,ReceivedAt=0,Self=false,ProfileStatus=false,
  Stores={},Store=false,Wholesale=false,Items={},Nearby={},Carry={},Theft=false,Demand=false,Contest=false,Traffic=false}
end
function Model.apply(state,packet,receivedAt)
 if type(packet)~="table" or packet.ProtocolVersion~=2 then return false,false,"VERSION_MISMATCH" end
 if not finite(packet.Sequence) or packet.Sequence%1~=0 or packet.Sequence<=state.Sequence or not finite(packet.ServerTime) then return false,false,"STALE_PACKET" end
 local kind=packet.Kind or "Snapshot"
 if kind~="Snapshot" and kind~="Delta" then return false,true,"BAD_PACKET" end
 for _,key in ipairs(slices) do
  local v=packet[key]
  if kind=="Snapshot" and v==nil then return false,true,"BAD_PACKET" end
  if v~=nil and v~=false and type(v)~="table" then return false,true,"BAD_PACKET" end
 end
 if kind=="Delta" and not state.HasSnapshot then return false,true,"NEED_SNAPSHOT" end
 local me=packet.Self
 if me==nil then me=state.Self end
 local store=packet.Store
 if store==nil then store=state.Store end
 if type(me)~="table" or not finite(me.OwnerGeneration) or not finite(me.ProfileRevision) then return false,true,"BAD_PACKET" end
 if not finite(me.ProfileEpoch) or not finite(me.Wallet) or not finite(me.XP) or not finite(me.Level)
  or type(me.DisplayName)~="string" or type(me.Upgrades)~="table" or type(me.Achievements)~="table"
  or (me.StoreId~=false and type(me.StoreId)~="string") then return false,true,"BAD_PACKET" end
 local status=packet.ProfileStatus
 if status==nil then status=state.ProfileStatus end
 if type(status)~="table" or type(status.State)~="string" or type(status.Frozen)~="boolean" then return false,true,"BAD_PACKET" end
 if store and (type(store.Items)~="table" or type(store.Orders)~="table" or type(store.Slots)~="table") then return false,true,"BAD_PACKET" end
 if state.Self and me.OwnerGeneration<state.Self.OwnerGeneration then return false,true,"STALE_OWNER" end
 if state.Self and me.ProfileEpoch==state.Self.ProfileEpoch and me.ProfileRevision<state.Self.ProfileRevision then return false,true,"STALE_PROFILE" end
 if store and (store.StoreId~=me.StoreId or store.OwnerUserId~=me.UserId or store.OwnerGeneration~=me.OwnerGeneration) then return false,true,"STORE_MISMATCH" end
 for _,key in ipairs({"Store","Wholesale"}) do
  local v=packet[key]
  if v and (not finite(v.Revision) or v.Revision<0 or v.Revision%1~=0) then return false,true,"BAD_PACKET" end
  local old=state[key]
  local same=key=="Wholesale" or (old and v and old.StoreId==v.StoreId and old.OwnerGeneration==v.OwnerGeneration)
  if v and old and same and v.Revision<old.Revision then return false,true,"STALE_REVISION" end
 end
 -- A generation switch must arrive with its full private slices, never retain old carry tokens.
 if state.Self and (me.OwnerGeneration~=state.Self.OwnerGeneration or me.ProfileEpoch~=state.Self.ProfileEpoch) and kind~="Snapshot" then return false,true,"NEED_SNAPSHOT" end
 if not Contract.validSelfProgress(me) then return false,true,"BAD_PROGRESS" end
 if packet.CustomerEvents==false then return false,true,"BAD_CUSTOMER_EVENTS" end
 local feed=packet.CustomerEvents or state.CustomerEvents
 if not Contract.validCustomerFeed(feed,me,packet.ServerTime) then return false,true,"BAD_CUSTOMER_EVENTS" end
 local sameContext=state.Self and Contract.customerContext(state.Self)==Contract.customerContext(me)
 if sameContext and feed.Cursor<(state.CustomerCursor or 0) then return false,true,"STALE_CUSTOMER_EVENTS" end
 local cursor=sameContext and (state.CustomerCursor or 0) or 0
 local fresh={}; for _,e in ipairs(feed.Entries) do if e.Cursor>cursor then table.insert(fresh,e) end end
 state.NewCustomerEvents=fresh; state.CustomerCursor=feed.Cursor
 local gap=state.Sequence>0 and packet.Sequence>state.Sequence+1
 for _,key in ipairs(slices) do if packet[key]~=nil then state[key]=packet[key] end end
 state.Sequence,state.ServerTime,state.ReceivedAt=packet.Sequence,packet.ServerTime,receivedAt
 if kind=="Snapshot" then state.HasSnapshot=true end
 return true,gap,nil
end
function Model.now(s,t) return s.ServerTime+math.max(0,t-s.ReceivedAt) end
function Model.request(c,action,payload,id)
 return {ProtocolVersion=2,RequestId=id,Action=action,StoreId=c.StoreId,RoundId=c.RoundId or false,OwnerGeneration=c.OwnerGeneration,Payload=payload}
end
function Model.storage(store,limit)
 local s={Warehouse=0,Reserved=0,Used=0,Remaining=0,BySku={}}
 if not store then return s end
 local seen={}
 for _,item in ipairs(store.Items or {}) do
  if not seen[item.ItemId] and item.State~="Sold" and item.State~="Recalled" and item.State~="Expired" then
   seen[item.ItemId]=true; s.Used+=1
   if item.State=="Warehouse" then s.Warehouse+=1; s.BySku[item.Sku]=(s.BySku[item.Sku] or 0)+1 end
  end
 end
 -- In-transit orders may already have item IDs. Count only units not represented in Items.
 for _,order in ipairs(store.Orders or {}) do
  if order.State=="Reserved" or order.State=="InTransit" then
   local represented=0
   for _,item in ipairs(store.Items or {}) do if item.OrderId==order.OrderId and seen[item.ItemId] then represented+=1 end end
   s.Reserved+=math.max(0,order.Quantity-represented)
  end
 end
 s.Used+=s.Reserved; s.Remaining=math.max(0,(store.WarehouseCapacity or limit)-s.Used)
 return s
end
function Model.preset(slots)
 local result={}
 for _,slot in ipairs(slots) do if slot.Sku then table.insert(result,{SlotId=slot.SlotId,Sku=slot.Sku}) end end
 return result
end
function Model.layout(width,height)
 local margin=12
 local w=math.max(1,math.min(440,width-margin*2))
 local h=math.max(1,math.min(760,height-margin*2))
 return {Width=w,Height=h,Header=56,Nav=48,BodyTop=116,BodyHeight=math.max(1,h-128),Touch=48}
end
return Model
