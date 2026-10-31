--!nonstrict
-- Pure schema/migration. Storage, lease acquisition and restore are server duties.
local Profile = {}

function Profile.new(config)
	return {SchemaVersion=2,Revision=0,Wallet=config.Economy.InitialWallet,XP=0,Level=1,
		UnlockedTools={"HandCarry"},EquippedTool="HandCarry",Cosmetics={},Presets={},Best={},RareDiscoveries={},
		CompletedFirstShift=false,RewardCursor={Epoch=0,Sequence=0},Session=false,
		EconomyCursor={Epoch=0,Sequence=0},ActivityCursor={Epoch=0,Sequence=0},
		Store={DisplayName="",Upgrades={Warehouse=0},Items={},RecoveryDebt=0,
			Achievements={DemandCompletions=0,ContestCompletions=0,BestDiversity=0,BestPlan=0,BestLogistics=0}}}
end

-- Inject the SHIPPED v1 normalizer, not a permissive identity function.
-- It must use SchemaVersion=1, SeatsPerStore=4 and the old ModeTags, regardless
-- of current runtime config. Never use the new one-seat limit to reject old Best.
-- v1 Wallet survives unchanged; transient OperatingCash is never added.
function Profile.migrate(raw,config,contract,validateLegacy,userId)
	if type(raw)~="table" or getmetatable(raw)~=nil then return nil,"PROFILE_CORRUPT" end
	if raw.SchemaVersion~=1 and raw.SchemaVersion~=2 then return nil,"SCHEMA_UNSUPPORTED" end
	if type(validateLegacy)~="function" then return nil,"PROFILE_CORRUPT" end
	local baseKeys={SchemaVersion=true,Revision=true,Wallet=true,XP=true,Level=true,UnlockedTools=true,
		EquippedTool=true,Cosmetics=true,Presets=true,Best=true,RareDiscoveries=true,
		CompletedFirstShift=true,RewardCursor=true,Session=true}
	local keys=table.clone(baseKeys)
	if raw.SchemaVersion==2 then keys.Store=true; keys.EconomyCursor=true; keys.ActivityCursor=true end
	if not contract.record(raw,keys) then return nil,"PROFILE_CORRUPT" end
	local base={}; for k in pairs(baseKeys) do base[k]=raw[k] end; base.SchemaVersion=1
	-- Protect the original datastore value even if an adapter normalizes in place.
	local ok,normalized,code=pcall(validateLegacy,contract.copy(base))
	if not ok or not normalized then return nil,code or "PROFILE_CORRUPT" end
	local nextProfile=contract.copy(normalized); nextProfile.SchemaVersion=2
	if raw.SchemaVersion==1 then
		local fresh=Profile.new(config)
		nextProfile.Store=fresh.Store
		nextProfile.EconomyCursor={Epoch=normalized.RewardCursor.Epoch,Sequence=0}
		nextProfile.ActivityCursor={Epoch=normalized.RewardCursor.Epoch,Sequence=0}
	else
		-- Validate extension before copying so malicious cycles cannot recurse.
		local valid,why=Profile.validateExtension(raw,config,contract,userId)
		if not valid then return nil,why end
		nextProfile.Store=contract.copy(raw.Store)
		nextProfile.EconomyCursor=contract.copy(raw.EconomyCursor)
		nextProfile.ActivityCursor=contract.copy(raw.ActivityCursor)
	end
	return nextProfile,"OK"
end

function Profile.validateExtension(raw,config,c,userId)
	if type(userId)~="number" or not c.integer(math.abs(userId),9007199254740991,1) then return false,"PROFILE_CORRUPT" end
	if type(raw)~="table" or type(raw.RewardCursor)~="table" then return false,"PROFILE_CORRUPT" end
	for _,name in ipairs({"EconomyCursor","ActivityCursor"}) do
		local cursor=raw[name]
		if not c.record(cursor,{Epoch=true,Sequence=true}) or not c.integer(cursor.Epoch)
			or not c.integer(cursor.Sequence) or cursor.Epoch~=raw.RewardCursor.Epoch then return false,"PROFILE_CORRUPT" end
	end
	local s=raw.Store
	if not c.record(s,{DisplayName=true,Upgrades=true,Items=true,RecoveryDebt=true,Achievements=true})
		or type(s.DisplayName)~="string" or #s.DisplayName>config.Profile.MaxDisplayNameBytes
		or string.find(s.DisplayName,"%c") or utf8.len(s.DisplayName)==nil
		or not c.record(s.Upgrades,{Warehouse=true}) or not c.integer(s.Upgrades.Warehouse,config.Upgrades.Warehouse.MaxLevel)
		or not c.integer(s.RecoveryDebt,config.Products.Water.WholesalePrice)
		or not c.array(s.Items,config.Profile.MaxOwnedItems) then return false,"PROFILE_CORRUPT" end
	local a=s.Achievements
	if not c.record(a,{DemandCompletions=true,ContestCompletions=true,BestDiversity=true,BestPlan=true,BestLogistics=true})
		or not c.integer(a.DemandCompletions) or not c.integer(a.ContestCompletions)
		or not c.integer(a.BestDiversity,config.Contest.DiversityMax) or not c.integer(a.BestPlan,config.Contest.PlanMax)
		or not c.integer(a.BestLogistics,config.Contest.LogisticsMax) then return false,"PROFILE_CORRUPT" end
	local seen,slots,warehouse={},{},0
	for _,item in ipairs(s.Items) do
		if not c.record(item,{ItemId=true,OwnerUserId=true,Sku=true,UnitCost=true,State=true,SlotId=true})
			or not c.id(item.ItemId) or seen[item.ItemId] or item.OwnerUserId~=userId
			or type(item.Sku)~="string" or not config.Products[item.Sku]
			or not c.integer(item.UnitCost,config.Economy.MaxCurrency)
			or (item.State~="Warehouse" and item.State~="Shelf" and item.State~="SafeStorage") then return false,"PROFILE_CORRUPT" end
		seen[item.ItemId]=true
		if item.State=="Shelf" then
			if type(item.SlotId)~="string" or not table.find(config.World.ShelfSlotIds,item.SlotId) then return false,"PROFILE_CORRUPT" end
			local slot=slots[item.SlotId] or {Sku=item.Sku,Count=0}; slots[item.SlotId]=slot
			slot.Count+=1
			if slot.Sku~=item.Sku or slot.Count>config.World.ShelfSlotCapacity then return false,"PROFILE_CORRUPT" end
		else
			if item.SlotId~=false then return false,"PROFILE_CORRUPT" end
			if item.State=="Warehouse" then warehouse+=1 end
		end
	end
	if warehouse>config.Upgrades.Warehouse.Capacities[s.Upgrades.Warehouse] then return false,"PROFILE_CORRUPT" end
	return true,"OK"
end

-- Calculate a canonical SAVE VIEW, never mutate live inventory here.
-- Paid orders must already have been materialized once before calling this.
function Profile.canonicalItems(items,userId,warehouseLevel,config,c)
	if type(userId)~="number" or not c.integer(math.abs(userId),9007199254740991,1) then return nil,"PROFILE_CORRUPT" end
	if not c.array(items,config.Profile.MaxOwnedItems) or not c.integer(warehouseLevel,config.Upgrades.Warehouse.MaxLevel) then return nil,"PROFILE_CORRUPT" end
	local out,seen,slots={},{},{}
	for _,item in ipairs(items) do
		if type(item)~="table" or not c.id(item.ItemId) or seen[item.ItemId] or item.OwnerUserId~=userId
			or type(item.Sku)~="string" or not config.Products[item.Sku] or not c.integer(item.UnitCost,config.Economy.MaxCurrency)
			or not table.find(config.Enums.ItemState,item.State) then return nil,"PROFILE_CORRUPT" end
		seen[item.ItemId]=true
		if item.State~="Sold" and item.State~="Recalled" and item.State~="Expired" then
			local slot=false; local state="Warehouse"
			if item.State=="Shelf" then
				slot=item.SlotId; state="Shelf"
				if type(slot)~="string" or not table.find(config.World.ShelfSlotIds,slot) then return nil,"PROFILE_CORRUPT" end
				local row=slots[slot] or {Sku=item.Sku,Count=0}; slots[slot]=row; row.Count+=1
				if row.Sku~=item.Sku or row.Count>config.World.ShelfSlotCapacity then return nil,"PROFILE_CORRUPT" end
			end
			table.insert(out,{ItemId=item.ItemId,OwnerUserId=userId,Sku=item.Sku,UnitCost=item.UnitCost,State=state,SlotId=slot})
		end
	end
	table.sort(out,function(a,b) return a.ItemId<b.ItemId end)
	local count=0
	for _,item in ipairs(out) do
		if item.State=="Warehouse" then
			count+=1
			if count>config.Upgrades.Warehouse.Capacities[warehouseLevel] then item.State="SafeStorage" end
		end
	end
	return out,"OK"
end

return Profile
