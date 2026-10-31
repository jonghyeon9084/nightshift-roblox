-- Actual pure shared modules under standalone Luau; NOT Roblox/Studio tests.
return function(C,L,K,P,legacyNormalize)
	local n=0
	local function check(value,label) n+=1; assert(value,label) end
	local function eq(a,b,label) check(a==b,label..": "..tostring(a).." ~= "..tostring(b)) end
	local function copy(v) return K.copy(v) end
	eq(C.Capacity.TargetPlayers,8,"commerce capacity"); eq(L.Capacity.TargetPlayers,8,"legacy capacity")
	eq(C.Capacity.SeatsPerStore,1,"solo capacity"); eq(#C.World.StoreIds,8,"eight store IDs")
	eq(#L.World.StoreIds,8,"eight legacy world IDs")
	for _,id in ipairs(C.World.StoreIds) do check(L.World.Stores[id]~=nil,"world store parity") end
	check(not C.Ownership.EmployeesEnabled,"employees disabled")
	check(not table.find(C.Actions,"SecureTheft"),"no ownership laundering")
	check(not table.find(L.Actions,"JoinStore"),"no employee join")
	eq(C.Economy.InitialOperatingCash,0,"no per-shift grant"); eq(C.Progression.Rewards.Sale.Coins,0,"no double sale money")
	local request={ProtocolVersion=2,RequestId=1,Action="OrderStock",StoreId="Store01",RoundId=false,OwnerGeneration=1,
		Payload={Sku="Water",Quantity=2,StockRevision=0,AllocationId=false}}
	local value,code=K.validateAction(request,C); eq(code,"OK","valid order"); check(value~=request and value.Payload~=request.Payload,"copy boundary")
	for _,q in ipairs({0,5,-1,0.5,math.huge,0/0,"1"}) do local r=copy(request); r.Payload.Quantity=q; local _,e=K.validateAction(r,C); eq(e,"BAD_REQUEST","quantity rejected") end
	for _,name in ipairs({"ForceDrop","CommitNpcSale","SecureTheft","JoinStore","SetOwner","SetContestScore"}) do
		local r=copy(request); r.Action=name; local _,e=K.validateAction(r,C); eq(e,"BAD_REQUEST","server/old action rejected")
	end
	for _,field in ipairs({"OwnerUserId","Price","Wallet","Score","SeatGeneration"}) do
		local r=copy(request); r[field]=1; local _,e=K.validateAction(r,C); eq(e,"BAD_REQUEST","unknown top field")
	end
	local r=copy(request); r.ProtocolVersion=1; _,code=K.validateAction(r,C); eq(code,"VERSION_MISMATCH","old protocol")
	r=copy(request); r.Payload.AllocationId=nil; _,code=K.validateAction(r,C); eq(code,"BAD_REQUEST","explicit false required")
	r=copy(request); r.OwnerGeneration=0; _,code=K.validateAction(r,C); eq(code,"BAD_REQUEST","zero generation")
	r=copy(request); r.Action="BuyUpgrade"; r.Payload={UpgradeId="Warehouse",ExpectedLevel=0,ProfileRevision=1}; _,code=K.validateAction(r,C); eq(code,"OK","upgrade schema")
	r.Payload.Price=0; _,code=K.validateAction(r,C); eq(code,"BAD_REQUEST","price injection")
	r=copy(request); r.Action="SetContestParticipation"; r.Payload={CycleId="cycle-a",Participate=true}; _,code=K.validateAction(r,C); eq(code,"OK","participation schema")
	for _,name in ipairs(C.Actions) do check(K.ClientSchemas[name]~=nil,"all actions have schema "..name) end
	for name in pairs(K.ClientSchemas) do check(table.find(C.Actions,name)~=nil,"no undocumented action "..name) end
	local stock={Water=32,Bread=32,Milk=32,Snack=32}; local owners={}
	for i=1,8 do table.insert(owners,{UserId=i,Wallet=240}) end
	local plan; plan,code=K.planDemand(stock,owners,1,C); eq(code,"OK","8-owner demand")
	eq(plan.CostPerOwner,18,"first target affordable")
	for _,row in ipairs(plan.Rows) do eq(row.Reserved+row.Public,stock[row.Sku],"ledger conservation"); eq(row.PerOwner,2,"equal allotment") end
	eq(stock.Water,32,"planning no mutation")
	local nine=copy(owners); table.insert(nine,{UserId=9,Wallet=240}); _,code=K.planDemand(stock,nine,1,C); eq(code,"BAD_REQUEST","ninth participant")
	local poor=copy(owners); poor[8].Wallet=0; _,code=K.planDemand(stock,poor,1,C); eq(code,"INSUFFICIENT_FUNDS","unaffordable cycle cannot start")
	local short=copy(stock); short.Water=15; _,code=K.planDemand(short,owners,1,C); eq(code,"SUPPLY_UNAVAILABLE","no synthetic reservation")
	_,code=K.planDemand({Water=0,Bread=0},owners,1,C); eq(code,"SUPPLY_UNAVAILABLE","sold out preparation")
	plan,code=K.planDemand(stock,owners,2,C); eq(code,"OK","second cycle"); eq(plan.Rows[1].Sku,"Milk","rotation changed")
	eq(plan.CostPerOwner,20,"second target affordable")
	local duplicates=copy(owners); duplicates[8].UserId=1; _,code=K.planDemand(stock,duplicates,1,C); eq(code,"BAD_REQUEST","duplicate participant")
	eq(K.npcKind(0,C),"Rich","rich lower bound"); eq(K.npcKind(0.029999,C),"Rich","rich threshold below")
	eq(K.npcKind(0.03,C),"Normal","rich threshold exact"); eq(K.npcKind(0.999,C),"Normal","normal upper sample")
	_,code=K.npcKind(1,C); eq(code,"BAD_REQUEST","invalid rng")
	local cursor={Epoch=2,Sequence=7}; local nextCursor
	nextCursor,code=K.nextCursor(cursor,2,8); eq(code,"OK","ordered commit"); eq(cursor.Sequence,7,"cursor immutable")
	for _,sequence in ipairs({6,7}) do _,code=K.nextCursor(cursor,2,sequence); eq(code,"DUPLICATE_TRANSACTION","replay") end
	_,code=K.nextCursor(cursor,1,8); eq(code,"STALE_PROFILE","old lease")
	_,code=K.nextCursor(cursor,2,9); eq(code,"STALE_REQUEST","out-of-order event")
	local state={CycleId="cycle-a",OwnerUserId=1,Opportunities={},Items={},Skus={},Sold={},Targets={Water=2,Bread=2},Diversity=0,Plan=0,Logistics=0}
	local event={CycleId="cycle-a",OwnerUserId=1,Kind="Normal",Committed=true,OpportunityIndex=1,
		Units={{ItemId="paid-1",PurchaseCycleId="cycle-a",Sku="Water",SlotId="Slot01",BasicTool=true,Practice=false,WasStolen=false,OwnerLogisticsComplete=true}}}
	local scored,accepted=K.scoreSale(state,event,C); check(accepted,"verified sale credited")
	eq(scored.Diversity,10,"diversity"); eq(scored.Plan,10,"plan"); eq(scored.Logistics,10,"logistics")
	eq(state.Plan,0,"score input unchanged")
	local replay; replay,accepted=K.scoreSale(scored,event,C); check(not accepted,"duplicate opportunity"); eq(replay.Plan,10,"replay no growth")
	for _,fieldValue in ipairs({{"Kind","Rich"},{"Committed",false},{"CycleId","old"},{"OwnerUserId",2},{"OpportunityIndex",false}}) do
		local e=copy(event); e[fieldValue[1]]=fieldValue[2]; _,accepted=K.scoreSale(state,e,C); check(not accepted,"invalid sale source")
	end
	for _,fieldValue in ipairs({{"PurchaseCycleId","old"},{"BasicTool",false},{"Practice",true},{"WasStolen",true},{"RecoveryLoan",true},{"SlotId","Slot03"},{"Sku","StarJelly"}}) do
		local e=copy(event); e.Units[1][fieldValue[1]]=fieldValue[2]; _,accepted=K.scoreSale(state,e,C); check(not accepted,"ineligible lineage")
	end
	for i=2,4 do local e=copy(event); e.OpportunityIndex=i; e.Units[1].ItemId="paid-"..i; e.Units[1].Sku=i>2 and "Bread" or "Water"; scored=K.scoreSale(scored,e,C) end
	eq(scored.Diversity,20,"two-SKU cap"); eq(scored.Plan,40,"plan cap"); eq(scored.Logistics,30,"logistics cap")
	local goal={CycleId="cycle-a",OwnerUserId=1,Targets={Water=2,Bread=2},Sold={},Completed=false,SeenTransactions={},SeenItems={}}
	local sale=copy(event); sale.TransactionId="sale-1"; sale.Kind="Rich"
	sale.Units={copy(event.Units[1]),copy(event.Units[1])}; sale.Units[2].ItemId="paid-2"
	local advanced,completed=K.advanceDemand(goal,sale,C); eq(advanced.Sold.Water,2,"R-A rich counts actual units"); check(not completed,"partial demand")
	eq(goal.Sold.Water,nil,"demand input unchanged")
	local duplicateGoal; duplicateGoal,completed=K.advanceDemand(advanced,sale,C); eq(duplicateGoal.Sold.Water,2,"R-A transaction replay"); check(not completed,"no duplicate completion")
	sale.TransactionId="sale-2"; for i,unit in ipairs(sale.Units) do unit.ItemId="bread-"..i; unit.Sku="Bread" end
	advanced,completed=K.advanceDemand(advanced,sale,C); check(completed and advanced.Completed,"R-A completion transition")
	duplicateGoal,completed=K.advanceDemand(advanced,sale,C); check(not completed,"R-A completion once")
	local excluded=copy(event); excluded.TransactionId="loan"; excluded.Units[1].RecoveryLoan=true
	duplicateGoal=K.advanceDemand(goal,excluded,C); eq(duplicateGoal.Sold.Water,nil,"loan excluded from R-A")
	excluded=copy(event); excluded.TransactionId="fake"; excluded.Committed=false; duplicateGoal=K.advanceDemand(goal,excluded,C); eq(duplicateGoal.Sold.Water,nil,"uncommitted R-A")
	local achievement=P.new(C); achievement.ActivityCursor={Epoch=2,Sequence=0}
	achievement.EconomyCursor={Epoch=2,Sequence=0}; achievement.RewardCursor={Epoch=2,Sequence=0}
	local recorded; recorded,code=K.recordAchievement(achievement,2,1,"Demand",false,C); eq(code,"OK","achievement recorded")
	eq(recorded.Store.Achievements.DemandCompletions,1,"persistent demand count"); eq(recorded.Wallet,240,"achievement no money")
	_,code=K.recordAchievement(recorded,2,1,"Demand",false,C); eq(code,"DUPLICATE_TRANSACTION","achievement replay")
	recorded,code=K.recordAchievement(recorded,2,2,"Contest",{Diversity=20,Plan=40,Logistics=30},C); eq(code,"OK","contest persisted")
	eq(recorded.Store.Achievements.ContestCompletions,1,"persistent contest count"); eq(recorded.Store.Achievements.BestPlan,40,"persistent best")
	local reopened; reopened,code=P.migrate(recorded,C,K,legacyNormalize,1); eq(code,"OK","v2 achievements roundtrip")
	eq(reopened.Store.Achievements.DemandCompletions,1,"demand survives normalization")
	eq(reopened.Store.Achievements.BestPlan,40,"contest survives normalization")
	_,code=K.recordAchievement(recorded,2,3,"Contest",{Diversity=21,Plan=40,Logistics=30},C); eq(code,"BAD_REQUEST","invalid record cap")
	_,code=K.recordAchievement(recorded,1,3,"Demand",false,C); eq(code,"STALE_PROFILE","old epoch achievement")
	for t=0,113 do local phase=K.signalAt(t,C); check(not (phase.VehicleGo and phase.PedestrianGo),"signals mutually exclusive") end
	eq(K.signalAt(20,C).Phase,"AllRedToWalk","yellow clearance boundary"); eq(K.signalAt(23,C).Phase,"Walk","walk boundary")
	eq(K.signalAt(35,C).Phase,"AllRedToVehicle","clearance boundary"); eq(K.signalAt(38,C).Phase,"VehicleGreen","cycle boundary")
	local fresh=P.new(C); eq(fresh.Wallet,240,"new profile only initial money")
	local legacy=copy(fresh); legacy.SchemaVersion=1; legacy.Wallet=17; legacy.Store=nil; legacy.EconomyCursor=nil; legacy.ActivityCursor=nil
	legacy.Best={{Key="Coop/4/1/false/false",Sales=2,Revenue=10,TeamSize=4,ToolTier=1,Mode="Coop",HadSupport=false,HadReduction=false}}
	local migrated; migrated,code=P.migrate(legacy,C,K,legacyNormalize,1); eq(code,"OK","real v1 normalizer migration")
	eq(migrated.Wallet,17,"no legacy operating cash grant"); eq(migrated.Best[1].TeamSize,4,"archived team record preserved")
	eq(legacy.SchemaVersion,1,"raw unchanged"); eq(#migrated.Store.Items,0,"no invented old inventory")
	local twice; twice,code=P.migrate(migrated,C,K,legacyNormalize,1); eq(code,"OK","migration repeat"); eq(twice.Wallet,17,"no repeated grant")
	local corrupt=copy(legacy); corrupt.Wallet=0/0; _,code=P.migrate(corrupt,C,K,legacyNormalize,1); eq(code,"PROFILE_CORRUPT","corrupt v1 rejects")
	corrupt=copy(legacy); corrupt.SchemaVersion=3; _,code=P.migrate(corrupt,C,K,legacyNormalize,1); eq(code,"SCHEMA_UNSUPPORTED","future version")
	_,code=P.migrate(nil,C,K,legacyNormalize,1); eq(code,"PROFILE_CORRUPT","nil read is not new profile")
	local items={}
	for i=1,26 do table.insert(items,{ItemId=string.format("i%02d",i),OwnerUserId=1,Sku="Water",UnitCost=4,State=i==1 and "TheftCarried" or "Truck",SlotId=false}) end
	local canonical; canonical,code=P.canonicalItems(items,1,0,C,K); eq(code,"OK","transient canonicalization")
	eq(#canonical,26,"inventory preserved"); eq(canonical[24].State,"Warehouse","capacity boundary"); eq(canonical[25].State,"SafeStorage","overflow protected")
	eq(items[1].State,"TheftCarried","no mutation of live state")
	fresh.Store.Items=canonical; local valid; valid,code=P.validateExtension(fresh,C,K,1); check(valid,"canonical profile extension")
	canonical,code=P.canonicalItems(items,1,1,C,K); eq(code,"OK","upgraded capacity"); eq(canonical[26].State,"Warehouse","upgrade effect")
	local duplicate=copy(items); duplicate[2].ItemId=duplicate[1].ItemId; _,code=P.canonicalItems(duplicate,1,0,C,K); eq(code,"PROFILE_CORRUPT","duplicate identity")
	local foreign=copy(items); foreign[2].OwnerUserId=2; _,code=P.canonicalItems(foreign,1,0,C,K); eq(code,"PROFILE_CORRUPT","foreign owner inventory")
	local shelf={}; for i=1,5 do table.insert(shelf,{ItemId="s"..i,OwnerUserId=1,Sku="Water",UnitCost=4,State="Shelf",SlotId="Slot01"}) end
	_,code=P.canonicalItems(shelf,1,0,C,K); eq(code,"PROFILE_CORRUPT","shelf overflow")
	table.remove(shelf); canonical,code=P.canonicalItems(shelf,1,0,C,K); eq(code,"OK","four shelf items valid"); eq(canonical[1].SlotId,"Slot01","shelf slot preserved")
	fresh.Store.Items=canonical; fresh.Store.Items[1].OwnerUserId=2; valid=P.validateExtension(fresh,C,K,1); check(not valid,"foreign persisted owner rejected")
	fresh=P.new(C); fresh.Store.DisplayName=string.char(255); valid=P.validateExtension(fresh,C,K,1); check(not valid,"invalid UTF8")
	fresh=P.new(C); fresh.Store.StoreId="Store01"; valid=P.validateExtension(fresh,C,K,1); check(not valid,"persistent seat rejected")
	fresh=P.new(C); fresh.EconomyCursor.Epoch=1; valid=P.validateExtension(fresh,C,K,1); check(not valid,"cursor epoch mismatch")
	print("PASS SoloStoreContract "..n.." assertions (offline pure Luau; no Studio/cloud/queue simulation)")
end
