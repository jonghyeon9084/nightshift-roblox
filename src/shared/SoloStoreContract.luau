--!nonstrict
-- Pure DTO validation/calculation only. No authority, remotes, clocks or storage.
local Contract = {}
Contract.Version = "2.0.0"
Contract.ClientSchemas = {
	OrderStock = { Sku="sku", Quantity="quantity", StockRevision="uint", AllocationId="optionalId" },
	CancelStockOrder = { OrderId="id" },
	PickCargo = { ItemId="id", ItemRevision="uint" },
	PickWarehouse = { ItemId="id", ItemRevision="uint" },
	PickShelf = { ItemId="id", ItemRevision="uint" },
	PlaceShelf = { ItemId="id", ItemRevision="uint", CarryToken="id", SlotId="slot" },
	DropWarehouse = { ItemId="id", ItemRevision="uint", CarryToken="id" },
	BeginTheft = { ItemId="id", ItemRevision="uint" },
	CancelTheft = { TheftId="id" }, RecoverItem = { ItemId="id", ItemRevision="uint" },
	EquipTool = { ToolId="tool" }, SavePreset = { Index="preset", Slots="slots" }, ApplyPreset = { Index="preset" },
	BuyUpgrade = { UpgradeId="upgrade", ExpectedLevel="uint", ProfileRevision="uint" },
	SetContestParticipation = { CycleId="id", Participate="boolean" },
	RequestRecoveryStock = { ProfileRevision="uint" },
}
Contract.ServerOnly = { CommitNpcSale=true, ForceDrop=true, RestoreInventory=true, RecordVerifiedSale=true,
	SetTrafficPhase=true, GrantMoney=true, SetOwner=true, CompleteDemand=true, SetContestScore=true }
Contract.Events = { "OwnerAssigned", "OwnerReleased", "InventoryCommitted", "NpcVisited", "NpcDeparted", "NpcSaleCommitted",
	"DemandPrepared", "DemandProgress", "DemandCompleted", "AllocationReleased", "ContestPrepared",
	"ContestOpportunity", "ContestScoreChanged", "ContestFinalized", "TrafficPhaseChanged",
	"CarryDropped", "TheftAlarm", "ItemRecovered", "UpgradePurchased", "ProfileStatusChanged" }

function Contract.integer(v, maximum, minimum)
	return type(v)=="number" and v==v and v%1==0 and v >= (minimum or 0) and v <= (maximum or 2147483647)
end
function Contract.id(v, max)
	return type(v)=="string" and #v>0 and #v <= (max or 96) and not string.find(v,"%c")
end
function Contract.record(v, allowed)
	if type(v)~="table" or getmetatable(v)~=nil then return false end
	for k in pairs(v) do if not allowed[k] then return false end end
	return true
end
function Contract.array(v, max)
	if type(v)~="table" or getmetatable(v)~=nil then return false end
	local n=0
	for k in pairs(v) do if not Contract.integer(k,max,1) then return false end; n+=1 end
	for i=1,n do if v[i]==nil then return false end end
	return n<=max
end
local function clone(v)
	if type(v)~="table" then return v end
	local out={}; for k,x in pairs(v) do out[k]=clone(x) end; return out
end
Contract.copy=clone

function Contract.validateAction(raw, config)
	local top={ProtocolVersion=true,RequestId=true,Action=true,StoreId=true,RoundId=true,OwnerGeneration=true,Payload=true}
	if not Contract.record(raw,top) then return nil,"BAD_REQUEST" end
	for k in pairs(top) do if raw[k]==nil then return nil,"BAD_REQUEST" end end
	if not Contract.integer(raw.ProtocolVersion) then return nil,"BAD_REQUEST" end
	if raw.ProtocolVersion~=config.ProtocolVersion then return nil,"VERSION_MISMATCH" end
	local schema=type(raw.Action)=="string" and Contract.ClientSchemas[raw.Action]
	if not schema or not Contract.integer(raw.RequestId,config.Network.MaxRequestId,1)
		or type(raw.StoreId)~="string" or not config.World.Stores[raw.StoreId]
		or not (raw.RoundId==false or Contract.id(raw.RoundId))
		or not Contract.integer(raw.OwnerGeneration,nil,1) or not Contract.record(raw.Payload,schema) then return nil,"BAD_REQUEST" end
	for k,kind in pairs(schema) do
		local v=raw.Payload[k]; local ok=false
		if kind=="uint" then ok=Contract.integer(v)
		elseif kind=="id" then ok=Contract.id(v)
		elseif kind=="optionalId" then ok=v==false or Contract.id(v)
		elseif kind=="boolean" then ok=type(v)=="boolean"
		elseif kind=="quantity" then ok=Contract.integer(v,config.Wholesale.MaxUnitsPerOrder,1)
		elseif kind=="sku" then ok=type(v)=="string" and config.Products[v]~=nil
		elseif kind=="slot" then ok=type(v)=="string" and table.find(config.World.ShelfSlotIds,v)~=nil
		elseif kind=="tool" then ok=type(v)=="string" and config.Progression.Tools[v]~=nil
		elseif kind=="upgrade" then ok=type(v)=="string" and config.Upgrades[v]~=nil
		elseif kind=="preset" then ok=Contract.integer(v,config.Progression.FreePresetSlots,1)
		elseif kind=="slots" then
			ok=Contract.array(v,#config.World.ShelfSlotIds)
			if ok then
				local seen={}
				for _,slot in ipairs(v) do
					if not Contract.record(slot,{SlotId=true,Sku=true}) or type(slot.SlotId)~="string"
						or not table.find(config.World.ShelfSlotIds,slot.SlotId) or type(slot.Sku)~="string"
						or not config.Products[slot.Sku] or seen[slot.SlotId] then ok=false; break end
					seen[slot.SlotId]=true
				end
			end
		end
		if not ok then return nil,"BAD_REQUEST" end
	end
	return clone(raw),"OK"
end

-- Plan against the EXISTING ledger; this never creates stock or mutates input.
-- All ready owners get two units of both SKUs or nobody starts this cycle.
function Contract.planDemand(stock, participants, rotationIndex, config)
	if not Contract.array(participants,config.Capacity.TargetPlayers) or #participants==0
		or not Contract.integer(rotationIndex,nil,1) or type(stock)~="table" then return nil,"BAD_REQUEST" end
	local seen={}; local pair=config.Demand.Rotation[(rotationIndex-1)%#config.Demand.Rotation+1]
	local cost=0
	for _,sku in ipairs(pair) do
		if not Contract.integer(stock[sku]) then return nil,"BAD_REQUEST" end
		if stock[sku]<#participants*config.Demand.UnitsPerSku then return nil,"SUPPLY_UNAVAILABLE" end
		cost+=config.Products[sku].WholesalePrice*config.Demand.UnitsPerSku
	end
	for _,p in ipairs(participants) do
		-- Studio negative IDs are admitted only by the server's IsStudio+Memory gate.
		if type(p)~="table" or not Contract.integer(math.abs(type(p.UserId)=="number" and p.UserId or 0),9007199254740991,1)
			or seen[p.UserId] or not Contract.integer(p.Wallet,config.Economy.MaxCurrency) then return nil,"BAD_REQUEST" end
		if p.Wallet<cost then return nil,"INSUFFICIENT_FUNDS" end
		seen[p.UserId]=true
	end
	local rows={}
	for _,sku in ipairs(pair) do
		table.insert(rows,{Sku=sku,PerOwner=config.Demand.UnitsPerSku,
			Reserved=#participants*config.Demand.UnitsPerSku,Public=stock[sku]-#participants*config.Demand.UnitsPerSku})
	end
	return {Rows=rows,CostPerOwner=cost},"OK"
end

function Contract.npcKind(sample,config)
	if type(sample)~="number" or sample~=sample or sample<0 or sample>=1 then return nil,"BAD_REQUEST" end
	return sample<config.NPC.RichProbability and "Rich" or "Normal","OK"
end

-- Monotonic transaction cursors belong to one leased profile, never to a client.
function Contract.nextCursor(cursor,epoch,sequence)
	if not Contract.record(cursor,{Epoch=true,Sequence=true}) or not Contract.integer(cursor.Epoch)
		or not Contract.integer(cursor.Sequence) or not Contract.integer(epoch,nil,1)
		or not Contract.integer(sequence,nil,1) then return nil,"BAD_REQUEST" end
	if epoch~=cursor.Epoch then return nil,"STALE_PROFILE" end
	if sequence<=cursor.Sequence then return nil,"DUPLICATE_TRANSACTION" end
	if sequence~=cursor.Sequence+1 then return nil,"STALE_REQUEST" end
	return {Epoch=epoch,Sequence=sequence},"OK"
end

-- Called ONLY with a server-committed, ordered event; trust checks remain server-side.
-- Pure scoring gives no credit for natural/rich visits or repeated opportunities/items.
function Contract.scoreSale(state,event,config)
	local nextState=clone(state)
	if event.CycleId~=state.CycleId or event.OwnerUserId~=state.OwnerUserId or event.Kind~="Normal"
		or event.Committed~=true or not Contract.integer(event.OpportunityIndex,config.Contest.OpportunityCount,1)
		or state.Opportunities[event.OpportunityIndex] or not Contract.array(event.Units,1) then return nextState,false end
	local unit=event.Units[1]
	if not unit or not Contract.id(unit.ItemId) or state.Items[unit.ItemId] or unit.PurchaseCycleId~=state.CycleId
		or not state.Targets[unit.Sku] or unit.BasicTool~=true or unit.Practice==true or unit.WasStolen==true or unit.RecoveryLoan==true
		or not table.find(config.Contest.ShelfSlots,unit.SlotId) then return nextState,false end
	nextState.Opportunities[event.OpportunityIndex]=true; nextState.Items[unit.ItemId]=true
	if not nextState.Skus[unit.Sku] then
		nextState.Skus[unit.Sku]=true
		nextState.Diversity=math.min(config.Contest.DiversityMax,nextState.Diversity+config.Contest.DiversityPerSku)
	end
	if (nextState.Sold[unit.Sku] or 0)<state.Targets[unit.Sku] then
		nextState.Sold[unit.Sku]=(nextState.Sold[unit.Sku] or 0)+1
		nextState.Plan=math.min(config.Contest.PlanMax,nextState.Plan+config.Contest.PlanPerUnit)
	end
	if unit.OwnerLogisticsComplete==true then nextState.Logistics=math.min(config.Contest.LogisticsMax,nextState.Logistics+config.Contest.LogisticsPerUnit) end
	return nextState,true
end

-- R-A counts each current-cycle paid unit, capped at its personal target.
-- Rich quantities never enter R-B scoring; do not waste R-A's reserved supply.
-- Runtime SeenTransactions/SeenItems are cleared at cycle close, never persisted.
function Contract.advanceDemand(state,event,config)
	local out=clone(state)
	if event.Committed~=true or event.OwnerUserId~=state.OwnerUserId or event.CycleId~=state.CycleId
		or not Contract.id(event.TransactionId) or state.SeenTransactions[event.TransactionId]
		or (event.Kind~="Normal" and event.Kind~="Rich") or not Contract.array(event.Units,config.NPC.RichMaxUnits) then return out,false end
	out.SeenTransactions[event.TransactionId]=true
	for _,unit in ipairs(event.Units) do
		if Contract.id(unit.ItemId) and not out.SeenItems[unit.ItemId] and unit.PurchaseCycleId==state.CycleId
			and state.Targets[unit.Sku] and unit.Practice~=true and unit.WasStolen~=true and unit.RecoveryLoan~=true then
			out.SeenItems[unit.ItemId]=true
			out.Sold[unit.Sku]=math.min(state.Targets[unit.Sku],(out.Sold[unit.Sku] or 0)+1)
		end
	end
	local complete=true
	for sku,target in pairs(state.Targets) do if (out.Sold[sku] or 0)<target then complete=false end end
	out.Completed=complete
	return out,complete and not state.Completed
end

-- A completion must enter the same profile transaction as its ActivityCursor.
-- This is a pure proposal; the server still checks lease, event origin and cycle.
function Contract.recordAchievement(profile,epoch,sequence,kind,scores,config)
	local cursor,code=Contract.nextCursor(profile.ActivityCursor,epoch,sequence)
	if not cursor then return nil,code end
	if kind~="Demand" and kind~="Contest" then return nil,"BAD_REQUEST" end
	if kind=="Contest" and (type(scores)~="table" or not Contract.integer(scores.Diversity,config.Contest.DiversityMax)
		or not Contract.integer(scores.Plan,config.Contest.PlanMax) or not Contract.integer(scores.Logistics,config.Contest.LogisticsMax)) then return nil,"BAD_REQUEST" end
	local out=clone(profile); local a=out.Store.Achievements
	out.ActivityCursor=cursor
	if kind=="Demand" then a.DemandCompletions=math.min(2147483647,a.DemandCompletions+1)
	else
		a.ContestCompletions=math.min(2147483647,a.ContestCompletions+1)
		a.BestDiversity=math.max(a.BestDiversity,scores.Diversity)
		a.BestPlan=math.max(a.BestPlan,scores.Plan)
		a.BestLogistics=math.max(a.BestLogistics,scores.Logistics)
	end
	return out,"OK"
end

function Contract.signalAt(elapsed,config)
	if type(elapsed)~="number" or elapsed~=elapsed or elapsed<0 or elapsed==math.huge then return nil,"BAD_REQUEST" end
	local t=config.Traffic; local durations={t.VehicleGreenSeconds,t.AllRedSeconds,t.WalkSeconds,t.AllRedSeconds}
	local cycle=0; for _,n in ipairs(durations) do cycle+=n end
	local offset=elapsed%cycle
	for i,n in ipairs(durations) do
		if offset<n then return {Phase=t.Phases[i],VehicleGo=i==1,PedestrianGo=i==3,Remaining=n-offset},"OK" end
		offset-=n
	end
	return nil,"INVALID_STATE"
end

-- Snapshot extension: required Self progress arrays and bounded transient customer stream.
-- Cursor is server-session monotonic (gaps allowed), scoped by the full Self identity below.
-- Snapshots repeat unexpired entries; clients consume each cursor once. No replay rewards.
Contract.CustomerEventTTL=20
Contract.CustomerEventLimit=32
Contract.CustomerEventKinds={NpcVisited=true,NpcSaleCommitted=true,NpcDeparted=true}
function Contract.customerContext(me)
 return table.concat({tostring(me.UserId),tostring(me.StoreId),tostring(me.OwnerGeneration),tostring(me.ProfileEpoch),tostring(me.RoundId)},":")
end
function Contract.validSelfProgress(me)
 if not (me.RoundId==false or Contract.id(me.RoundId)) or not Contract.id(me.EquippedTool)
  or not Contract.array(me.RareDiscoveries,64) or not Contract.array(me.UnlockedTools,16) or not Contract.array(me.Presets,8) then return false end
 for _,list in ipairs({me.RareDiscoveries,me.UnlockedTools}) do
  local seen={}; for _,id in ipairs(list) do if not Contract.id(id) or seen[id] then return false end; seen[id]=true end
 end
 if not table.find(me.UnlockedTools,me.EquippedTool) then return false end
 local indices={}
 for _,preset in ipairs(me.Presets) do
  if not Contract.record(preset,{Index=true,Slots=true}) or not Contract.integer(preset.Index,6,1)
   or indices[preset.Index] or not Contract.array(preset.Slots,16) then return false end
  indices[preset.Index]=true; local slots={}
  for _,slot in ipairs(preset.Slots) do
   if not Contract.record(slot,{SlotId=true,Sku=true}) or not Contract.id(slot.SlotId) or not Contract.id(slot.Sku) or slots[slot.SlotId] then return false end
   slots[slot.SlotId]=true
  end
 end
 return true
end
function Contract.validCustomerFeed(feed,me,now)
 if not Contract.record(feed,{Cursor=true,Entries=true}) or not Contract.integer(feed.Cursor)
  or not Contract.array(feed.Entries,Contract.CustomerEventLimit) then return false end
 local previous=0; local seen={}
 for _,e in ipairs(feed.Entries) do
  if type(e)~="table" or not Contract.CustomerEventKinds[e.Kind] or (e.CustomerKind~="Normal" and e.CustomerKind~="Rich")
   or not Contract.id(e.EventId) or not Contract.id(e.NpcId) or seen[e.EventId]
   or not Contract.integer(e.Cursor) or e.Cursor<=previous or e.Cursor>feed.Cursor
   or not me.StoreId or e.OwnerUserId~=me.UserId or e.StoreId~=me.StoreId or e.OwnerGeneration~=me.OwnerGeneration
   or e.ProfileEpoch~=me.ProfileEpoch or e.RoundId~=me.RoundId
   or not Contract.integer(e.ProfileRevision) or e.ProfileRevision>me.ProfileRevision
   or type(e.At)~="number" or e.At~=e.At or e.At>now or e.At<now-Contract.CustomerEventTTL
   or e.ExpiresAt~=e.At+Contract.CustomerEventTTL
   or not Contract.integer(e.Units,4) or not Contract.integer(e.Revenue) then return false end
  if e.Kind=="NpcSaleCommitted" then if e.Units<1 then return false end
  elseif e.Units~=0 or e.Revenue~=0 then return false end
  previous=e.Cursor; seen[e.EventId]=true
 end
 return true
end

return Contract
