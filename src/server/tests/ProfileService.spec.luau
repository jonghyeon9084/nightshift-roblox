-- Inject actual ProfileService and CommerceConfig. Pure fake-IO tests, not cloud/Studio proof.
return function(ProfileService, Config)
	local checks, cases = 0, 0
	local function expect(value, message) checks += 1; assert(value,message or "expectation failed") end
	local function eq(a,b,message) expect(a == b,(message or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
	local function deep(value)
		if type(value) ~= "table" then return value end
		local out = {}; for k,v in pairs(value) do out[k]=deep(v) end; return out
	end
	local function case(name,fn)
		fn(); cases += 1; print("PASS ProfileService " .. name)
	end
	local function fixture(mode)
		local f = {now=1000,clock=0,waits={},statuses={}}
		local store = {Mode=mode or "DataStore",records={},calls=0,writes=0,budget=100,
			failBefore=0,loseAfter=0,repeatTransform=false}
		function store:GetBudget() return self.budget end
		function store:UpdateAsync(key,transform)
			self.calls += 1
			if self.failBefore > 0 then self.failBefore -= 1; error("fake storage unavailable") end
			local nextValue = transform(deep(self.records[key]))
			if self.repeatTransform then
				local duplicate = transform(deep(self.records[key]))
				if nextValue then
					eq(duplicate.Revision,nextValue.Revision,"pure retry revision")
					eq(duplicate.RewardCursor.Epoch,nextValue.RewardCursor.Epoch,"pure retry epoch")
				end
				nextValue = duplicate
			end
			if self.beforeCommit then
				local hook=self.beforeCommit; self.beforeCommit=nil; hook()
				-- Model UpdateAsync's CAS conflict: rerun against the concurrent winner.
				nextValue=transform(deep(self.records[key]))
			end
			if nextValue == nil then return nil end
			self.records[key]=deep(nextValue); self.writes += 1
			if self.afterCommit then local hook=self.afterCommit; self.afterCommit=nil; hook() end
			if self.loseAfter > 0 then self.loseAfter -= 1; error("fake committed response lost") end
			return deep(nextValue)
		end
		function f.new(session)
			return ProfileService.new({Config=Config,Store=store,SessionId=session or "server-A",UnixNow=function() return f.now end,
				Wait=function(seconds) table.insert(f.waits,seconds); f.now += seconds; f.clock += seconds end,
				MonotonicNow=function() return f.clock end,
				OnStatus=function(id,status)
					expect(status.Session == nil and status.Id == nil,"status hides session identity")
					table.insert(f.statuses,{id=id,status=status})
				end})
		end
		f.store=store; f.service=f.new(); return f
	end
	local function load(f,id) local r=f.service:load(id or 1); expect(r.Ok,r.Code); return r.Value end
	local function wallet(service,id,value)
		return service:mutate(id,service:status(id).Epoch,function(p) p.Wallet=value; return p end)
	end
	case("nil-only creation and copied results",function()
		local f=fixture(); local p=load(f,123)
		eq(p.SchemaVersion,1); eq(p.Wallet,0); eq(p.RewardCursor.Epoch,1); eq(p.Session.Epoch,1)
		expect(f.store.records["u:123"] ~= nil); eq(f.store.records["u:1"],nil)
		eq(f.service:status(123).State,"Ready"); eq(f.service:status(123).Dirty,false)
		p.Wallet=999; eq(f.service:get(123).Value.Wallet,0)
		eq(f.service:load(123).Value.Revision,1); eq(f.store.calls,1)
		eq(f.service:load(-1).Code,"BAD_REQUEST"); eq(f.service:load(0/0).Code,"BAD_REQUEST")
	end)
	case("explicit temporary memory mode",function()
		local s=ProfileService.new({Config=Config,SessionId="memory",UnixNow=function() return 1000 end})
		expect(s:load(1).Ok); eq(s:status(1).State,"Temporary"); eq(s:status(1).Mode,"Memory")
		expect(wallet(s,1,20).Ok); expect(s:save(1,true).Ok)
		local other=ProfileService.new({Config=Config,SessionId="memory-2",UnixNow=function() return 1000 end})
		eq(other:load(1).Value.Wallet,0,"fresh process memory has no persistence")
	end)
	case("bounded load failure never creates a default",function()
		local f=fixture(); f.store.failBefore=99
		eq(f.service:load(1).Code,"PROFILE_UNAVAILABLE"); eq(f.store.calls,3); eq(f.store.writes,0)
		eq(#f.waits,2); eq(f.waits[1],1); eq(f.waits[2],2)
		eq(f.service:status(1).State,"LoadFailed"); eq(f.service:save(1,true).Code,"PROFILE_UNAVAILABLE")
		eq(f.store.calls,3); eq(f.store.records["u:1"],nil)
	end)
	case("existing load outage preserves persisted progress",function()
		local f=fixture(); load(f); expect(wallet(f.service,1,70).Ok); expect(f.service:save(1,true).Ok)
		f.store.failBefore=3; f.service=f.new("server-B")
		eq(f.service:load(1).Code,"PROFILE_UNAVAILABLE"); eq(f.store.records["u:1"].Wallet,70)
		eq(f.service:save(1,false).Code,"PROFILE_UNAVAILABLE"); eq(f.store.records["u:1"].Wallet,70)
	end)
	case("future and unknown legacy schema rejected without writes",function()
		for _,version in ipairs({0,2,999}) do
			local f=fixture(); load(f); f.store.records["u:1"].SchemaVersion=version
			local writes=f.store.writes; local s=f.new("server-B")
			eq(s:load(1).Code,"SCHEMA_UNSUPPORTED"); eq(f.store.writes,writes)
			eq(f.store.records["u:1"].SchemaVersion,version)
		end
	end)
	case("malformed persisted required values are preserved",function()
		local invalid={
			function(p) p.Wallet=-1 end, function(p) p.XP=0/0 end, function(p) p.Revision=nil end,
			function(p) p.Wallet=math.huge end, function(p) p.Session.Epoch=99 end,
			function(p) p.CompletedFirstShift="yes" end, function(p) p.OperatingCash=240 end,
			function(p) p.Cosmetics={"unapproved"} end, function(p) p.RareDiscoveries={"Water"} end,
			function(p) p.Best={[2]={}} end, function(p) p.Session=nil end,
		}
		for _,breakValue in ipairs(invalid) do
			local f=fixture(); load(f); breakValue(f.store.records["u:1"])
			local writes=f.store.writes; eq(f.new("B"):load(1).Code,"PROFILE_CORRUPT"); eq(f.store.writes,writes)
		end
	end)
	case("v1 normalization derives level and tools and deduplicates rares",function()
		local f=fixture(); load(f); expect(f.service:save(1,true).Ok)
		local stored=f.store.records["u:1"]; stored.XP=180; stored.Level=1; stored.UnlockedTools={"Fake"}
		stored.EquippedTool="Fake"; stored.RareDiscoveries={"StarJelly","StarJelly"}
		local p=f.new("B"):load(1).Value
		eq(p.Level,4); eq(#p.UnlockedTools,4); eq(p.EquippedTool,"HandCarry"); eq(#p.RareDiscoveries,1)
	end)
	case("active owner lock and exact expiry takeover",function()
		local f=fixture(); local p=load(f); local other=f.new("B")
		eq(other:load(1).Code,"SESSION_LOCKED"); eq(other:status(1).State,"Locked")
		f.now=p.Session.ExpiresAt; local winner=other:load(1)
		expect(winner.Ok); eq(winner.Value.Session.Epoch,2)
		eq(f.service:save(1,false).Code,"LEASE_LOST"); eq(f.service:mutate(1,1,function(x) return x end).Code,"LEASE_LOST")
		eq(f.store.records["u:1"].Session.Id,"B")
	end)
	case("transform reruns and ambiguous acquire keep one epoch",function()
		local f=fixture(); f.store.repeatTransform=true; f.store.loseAfter=1
		local p=load(f); eq(f.store.calls,2); eq(p.Session.Epoch,1); eq(p.Revision,1)
		eq(f.store.records["u:1"].RewardCursor.Epoch,1)
	end)
	case("CAS acquisition loser cannot steal active owner",function()
		local f=fixture(); local other=f.new("B")
		f.store.beforeCommit=function() expect(other:load(1).Ok) end
		eq(f.service:load(1).Code,"SESSION_LOCKED"); eq(f.store.records["u:1"].Session.Id,"B")
	end)
	case("mutation rollback, no aliases and forbidden yielding",function()
		local f=fixture(); local p=load(f); local epoch=p.Session.Epoch
		eq(f.service:mutate(1,epoch,function(x) x.Wallet=9; error("bad callback") end).Code,"INTERNAL_ERROR")
		eq(f.service:mutate(1,epoch,function(x) x.Wallet=9; return nil end).Code,"INVALID_STATE")
		eq(f.service:mutate(1,epoch,function(x) x.Wallet=9; coroutine.yield(); return x end).Code,"INTERNAL_ERROR")
		eq(f.service:get(1).Value.Wallet,0); eq(f.service:get(1).Value.Revision,p.Revision)
		local retained
		expect(f.service:mutate(1,epoch,function(x) retained=x; x.Wallet=7; return x end).Ok)
		retained.Wallet=999; eq(f.service:get(1).Value.Wallet,7)
		eq(f.service:mutate(1,epoch,function(x) x.Session.Id="B"; return x end).Code,"PROFILE_CORRUPT")
		eq(f.service:mutate(1,epoch,function(x) x.Revision+=1; return x end).Code,"PROFILE_CORRUPT")
		eq(f.service:mutate(1,epoch,function(x) x.Wallet=Config.Economy.MaxCurrency+1; return x end).Code,"PROFILE_CORRUPT")
	end)
	case("reentrant mutation rejected without partial commit",function()
		local f=fixture(); local p=load(f)
		expect(f.service:mutate(1,p.Session.Epoch,function(x)
			eq(wallet(f.service,1,99).Code,"REQUEST_IN_PROGRESS")
			eq(f.service:save(1,false).Code,"REQUEST_IN_PROGRESS")
			x.Wallet=4; return x
		end).Ok); eq(f.service:get(1).Value.Wallet,4)
	end)
	case("wallet XP preset record cursor restore with new epoch",function()
		local f=fixture(); local p=load(f)
		expect(f.service:mutate(1,p.Session.Epoch,function(x)
			x.Wallet=55; x.XP=180; x.EquippedTool="LayoutPreset"; x.CompletedFirstShift=true
			x.RewardCursor.Sequence=1; x.RareDiscoveries={"StarJelly"}
			x.Presets={{Index=1,Slots={{SlotId="Slot01",Sku="Water"}}}}
			x.Best={{Key="Coop/2/4/false/false",Sales=3,Revenue=21,TeamSize=2,ToolTier=4,Mode="Coop",HadSupport=false,HadReduction=false}}
			return x
		end).Ok)
		expect(f.service:save(1,true).Ok); eq(f.store.records["u:1"].Session,false)
		local restored=f.new("B"):load(1).Value
		eq(restored.Wallet,55); eq(restored.XP,180); eq(restored.Level,4); eq(restored.EquippedTool,"LayoutPreset")
		eq(restored.Presets[1].Slots[1].Sku,"Water"); eq(restored.Best[1].Revenue,21)
		eq(restored.RareDiscoveries[1],"StarJelly"); eq(restored.CompletedFirstShift,true)
		eq(restored.RewardCursor.Epoch,2); eq(restored.RewardCursor.Sequence,0)
	end)
	case("preset and ranking boundary checks",function()
		local f=fixture(); local p=load(f)
		eq(f.service:mutate(1,p.Session.Epoch,function(x) x.Presets={{Index=1,Slots={}}}; return x end).Code,"PROFILE_CORRUPT")
		for _,edit in ipairs({
			function(x) x.Presets={{Index=3,Slots={}}} end,
			function(x) x.Presets={{Index=1,Slots={{SlotId="Slot01",Sku="Water"},{SlotId="Slot01",Sku="Milk"}}}} end,
			function(x) x.Presets={{Index=1,Slots={{SlotId="Slot13",Sku="Water"}}}} end,
			function(x) x.Presets={{Index=1,Slots={{SlotId="Slot01",Sku="Unknown"}}}} end,
			function(x) x.Best={{Key="wrong",Sales=1,Revenue=1,TeamSize=1,ToolTier=1,Mode="Coop",HadSupport=false,HadReduction=false}} end,
		}) do
			eq(f.service:mutate(1,p.Session.Epoch,function(x) x.XP=300; edit(x); return x end).Code,"PROFILE_CORRUPT")
		end
	end)
	case("cursor and reward atomically committed; duplicate cursor callback cancels",function()
		local f=fixture(); local p=load(f); local epoch=p.Session.Epoch
		-- TransactionId de-duplication belongs to Progression; this tests its persistence primitive.
		local function reward(sequence)
			return f.service:mutate(1,epoch,function(x)
				if sequence <= x.RewardCursor.Sequence then return nil end
				x.RewardCursor.Sequence=sequence; x.Wallet+=2; x.XP+=5; return x
			end)
		end
		expect(reward(1).Ok); eq(reward(1).Code,"INVALID_STATE"); eq(reward(3).Code,"PROFILE_CORRUPT")
		eq(f.service:get(1).Value.Wallet,2); eq(f.service:get(1).Value.XP,5)
		expect(f.service:save(1,false).Ok); eq(f.store.records["u:1"].RewardCursor.Sequence,1)
		f.service=f.new("server-A"); load(f); eq(reward(1).Code,"INVALID_STATE")
		expect(f.service:save(1,true).Ok); f.service=f.new("B"); load(f)
		eq(reward(2).Code,"LEASE_LOST"); eq(f.service:get(1).Value.Wallet,2)
	end)
	case("one writer and load blocked during yielded save; later mutation stays dirty",function()
		local f=fixture(); load(f); expect(wallet(f.service,1,10).Ok)
		f.store.beforeCommit=function()
			eq(f.service:status(1).State,"Saving")
			eq(f.service:save(1,false).Code,"REQUEST_IN_PROGRESS")
			eq(f.service:load(1).Code,"REQUEST_IN_PROGRESS")
			expect(wallet(f.service,1,20).Ok)
		end
		expect(f.service:save(1,false).Ok)
		eq(f.store.records["u:1"].Wallet,10); eq(f.service:get(1).Value.Wallet,20)
		eq(f.service:status(1).Dirty,true)
		expect(f.service:save(1,false).Ok); eq(f.store.records["u:1"].Wallet,20); eq(f.service:status(1).Dirty,false)
	end)
	case("lease takeover during in-flight save fences old writer",function()
		local f=fixture(); local p=load(f); expect(wallet(f.service,1,100).Ok)
		f.store.beforeCommit=function()
			f.now=p.Session.ExpiresAt; expect(f.new("B"):load(1).Ok)
		end
		eq(f.service:save(1,false).Code,"LEASE_LOST")
		eq(f.store.records["u:1"].Wallet,0); eq(f.store.records["u:1"].Session.Id,"B")
	end)
	case("response-lost normal save is idempotent",function()
		local f=fixture(); load(f); expect(wallet(f.service,1,18).Ok); f.store.loseAfter=1
		expect(f.service:save(1,false).Ok); eq(f.store.records["u:1"].Wallet,18)
		eq(f.service:status(1).SavedRevision,2); eq(f.service:status(1).Dirty,false)
	end)
	case("save failure retains dirty and freezes at safety boundary",function()
		local f=fixture(); local p=load(f); expect(wallet(f.service,1,18).Ok); f.store.failBefore=99
		eq(f.service:save(1,false).Code,"SAVE_FAILED"); eq(f.service:status(1).State,"SaveFailed")
		eq(f.service:status(1).Dirty,true); eq(f.store.records["u:1"].Wallet,0)
		expect(wallet(f.service,1,19).Ok)
		f.now=p.Session.ExpiresAt-Config.Profile.FreezeBeforeExpirySeconds
		eq(f.service:status(1).Frozen,true); eq(wallet(f.service,1,20).Code,"PROFILE_UNAVAILABLE")
		f.store.failBefore=0; expect(f.service:save(1,false).Ok)
		eq(f.service:status(1).Frozen,false); expect(wallet(f.service,1,20).Ok)
	end)
	case("renew clean profiles and autosave dirty profiles every configured interval",function()
		local f=fixture(); load(f,1); load(f,2); expect(wallet(f.service,2,5).Ok)
		eq(#f.service:due(),0); f.now+=30; eq(#f.service:due(),2)
		for _,id in ipairs(f.service:due()) do expect(f.service:save(id,false).Ok) end
		eq(#f.service:due(),0); eq(f.store.records["u:1"].Session.ExpiresAt,1150)
		eq(f.store.records["u:2"].Wallet,5)
	end)
	case("due notifies freeze boundary without a new write",function()
		local f=fixture(); local p=load(f); local notifications=#f.statuses
		f.now=p.Session.ExpiresAt-Config.Profile.FreezeBeforeExpirySeconds
		f.service:due(); eq(#f.statuses,notifications+1)
		eq(f.statuses[#f.statuses].status.Frozen,true)
		f.service:due(); eq(#f.statuses,notifications+1,"no duplicate freeze notifications")
	end)
	case("budget exhaustion bounded without UpdateAsync or overwrites",function()
		local f=fixture(); load(f); expect(wallet(f.service,1,7).Ok); f.store.budget=0
		eq(f.service:save(1,false).Code,"SAVE_FAILED"); eq(f.store.calls,1); eq(#f.waits,2)
		eq(f.service:status(1).Dirty,true); eq(f.store.records["u:1"].Wallet,0)
	end)
	case("release atomic and frozen against concurrent mutation",function()
		local f=fixture(); load(f); expect(wallet(f.service,1,13).Ok)
		f.store.beforeCommit=function() eq(wallet(f.service,1,14).Code,"PROFILE_UNAVAILABLE") end
		expect(f.service:save(1,true).Ok); eq(f.store.records["u:1"].Wallet,13)
		eq(f.store.records["u:1"].Session,false); eq(f.service:status(1).State,"Released")
		local calls=f.store.calls; expect(f.service:save(1,true).Ok); eq(f.store.calls,calls)
		eq(f.service:get(1).Code,"PROFILE_UNAVAILABLE"); eq(#f.service:due(),0)
	end)
	case("release response loss cannot overwrite released record or claim confirmation",function()
		local f=fixture(); load(f); expect(wallet(f.service,1,22).Ok); f.store.loseAfter=1
		eq(f.service:save(1,true).Code,"LEASE_LOST"); eq(f.service:status(1).State,"LeaseLost")
		eq(f.store.records["u:1"].Session,false); eq(f.store.records["u:1"].Wallet,22)
		local other=f.new("B"); expect(other:load(1).Ok); expect(wallet(other,1,23).Ok); expect(other:save(1,false).Ok)
		eq(f.service:save(1,true).Code,"LEASE_LOST"); eq(f.store.records["u:1"].Wallet,23)
	end)
	case("failed release leaves lock to expire",function()
		local f=fixture(); load(f); expect(wallet(f.service,1,22).Ok); f.store.failBefore=3
		eq(f.service:save(1,true).Code,"SAVE_FAILED"); eq(f.store.records["u:1"].Session.Id,"server-A")
		eq(f.service:status(1).Dirty,true); eq(f.new("B"):load(1).Code,"SESSION_LOCKED")
	end)
	case("close saves and releases all loaded profiles",function()
		local f=fixture(); load(f,1); load(f,2); expect(wallet(f.service,2,30).Ok)
		local results=f.service:close(); expect(results[1].Ok); expect(results[2].Ok)
		eq(f.store.records["u:2"].Wallet,30); eq(f.store.records["u:1"].Session,false)
		eq(f.service:load(3).Code,"PROFILE_UNAVAILABLE"); eq(#f.service:due(),0)
	end)
	case("close global budget prevents starting later writes and retries",function()
		local f=fixture(); load(f,1); load(f,2)
		f.store.afterCommit=function() f.clock+=Config.Profile.CloseBudgetSeconds end
		local outcomes=f.service:close(); expect(outcomes[1].Ok); eq(outcomes[2].Code,"SAVE_FAILED")
		eq(f.store.records["u:1"].Session,false); eq(f.store.records["u:2"].Session.Id,"server-A")
		local calls=f.store.calls; f.service:close(); eq(f.store.calls,calls)
	end)
	case("close waits for an actual suspended writer before release",function()
		local f=fixture(); load(f); expect(wallet(f.service,1,24).Ok)
		f.store.beforeCommit=function() coroutine.yield() end
		local saveResult
		local writer=coroutine.create(function() saveResult=f.service:save(1,false) end)
		expect(coroutine.resume(writer)); eq(coroutine.status(writer),"suspended")
		local normalWait=f.service.wait
		f.service.wait=function(seconds)
			normalWait(seconds)
			if coroutine.status(writer) == "suspended" then expect(coroutine.resume(writer)) end
		end
		local outcomes=f.service:close()
		expect(saveResult.Ok); expect(outcomes[1].Ok); eq(f.store.records["u:1"].Wallet,24)
		eq(f.store.records["u:1"].Session,false); eq(f.service:status(1).State,"Released")
	end)
	case("observer errors or yields cannot break commits",function()
		local f=fixture(); f.service.onStatus=function() error("UI observer failed") end
		load(f); expect(wallet(f.service,1,5).Ok)
		f.service.onStatus=function() coroutine.yield() end
		expect(f.service:save(1,true).Ok); eq(f.store.records["u:1"].Wallet,5)
	end)
	print(string.format("PROFILE_TESTS_OK cases=%d checks=%d (fake storage; no Studio/cloud)",cases,checks))
	return {Cases=cases,Checks=checks,Mode="Fake"}
end
