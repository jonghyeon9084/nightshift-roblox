--!nonstrict
-- Injected storage only: this module never enables cloud access or binds Roblox events.
-- Main drives due()/save(), PlayerRemoving save(id,true), and BindToClose close().
local ProfileService = {}
ProfileService.__index = ProfileService
local MAX_INT = 9007199254740991

local function integer(value, maximum, minimum)
	return type(value) == "number" and value == value and value >= (minimum or 0)
		and value <= (maximum or MAX_INT) and value % 1 == 0
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in pairs(value) do result[key] = copy(child) end
	return result
end

local function result(ok, code, value)
	return { Ok = ok, Code = code, Value = value ~= nil and copy(value) or false }
end

local function keys(value, allowed)
	if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
	for key in pairs(value) do if not allowed[key] then return false end end
	return true
end

local function array(value, limit)
	if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
	local count = 0
	for key in pairs(value) do
		if not integer(key, limit, 1) then return false end
		count += 1
	end
	if count > limit then return false end
	for index = 1, count do if value[index] == nil then return false end end
	return true
end

local PROFILE_KEYS = { SchemaVersion=true, Revision=true, Wallet=true, XP=true, Level=true,
	UnlockedTools=true, EquippedTool=true, Cosmetics=true, Presets=true, Best=true,
	RareDiscoveries=true, CompletedFirstShift=true, RewardCursor=true, Session=true }

local function normalize(raw, config)
	if type(raw) ~= "table" then return nil, "PROFILE_CORRUPT" end
	if raw.SchemaVersion ~= config.SchemaVersion then return nil, "SCHEMA_UNSUPPORTED" end
	if not keys(raw, PROFILE_KEYS) or not integer(raw.Revision) or not integer(raw.Wallet, config.Economy.MaxCurrency)
		or not integer(raw.XP, config.Progression.MaxXP) or not integer(raw.Level, MAX_INT, 1)
		or type(raw.CompletedFirstShift) ~= "boolean" or type(raw.EquippedTool) ~= "string"
		or not array(raw.UnlockedTools, 32) then return nil, "PROFILE_CORRUPT" end
	for _, tool in ipairs(raw.UnlockedTools) do if type(tool) ~= "string" then return nil, "PROFILE_CORRUPT" end end
	local cursor = raw.RewardCursor
	if not keys(cursor, {Epoch=true,Sequence=true}) or not integer(cursor.Epoch) or not integer(cursor.Sequence) then
		return nil, "PROFILE_CORRUPT"
	end
	if raw.Session ~= false then
		local session = raw.Session
		if not keys(session, {Id=true,Epoch=true,ExpiresAt=true}) or type(session.Id) ~= "string"
			or #session.Id == 0 or #session.Id > 200 or not integer(session.Epoch, MAX_INT, 1)
			or not integer(session.ExpiresAt) or session.Epoch ~= cursor.Epoch then return nil, "PROFILE_CORRUPT" end
	end
	local p = { SchemaVersion=config.SchemaVersion, Revision=raw.Revision, Wallet=raw.Wallet, XP=raw.XP,
		Level=1, UnlockedTools={}, EquippedTool=raw.EquippedTool, Cosmetics={}, Presets={}, Best={},
		RareDiscoveries={}, CompletedFirstShift=raw.CompletedFirstShift, RewardCursor=copy(cursor), Session=copy(raw.Session) }
	for level, threshold in ipairs(config.Progression.LevelXP) do if p.XP >= threshold then p.Level = level end end
	for tool, level in pairs(config.Progression.Tools) do if level <= p.Level then table.insert(p.UnlockedTools, tool) end end
	table.sort(p.UnlockedTools, function(a,b)
		local al, bl = config.Progression.Tools[a], config.Progression.Tools[b]
		return al < bl or (al == bl and a < b)
	end)
	if not table.find(p.UnlockedTools, p.EquippedTool) then p.EquippedTool = "HandCarry" end
	if not array(raw.Cosmetics, config.Profile.MaxCosmetics) or not array(raw.RareDiscoveries, #config.ProductOrder) then
		return nil, "PROFILE_CORRUPT"
	end
	-- No cosmetic IDs are authorized in C v1. An explicit future catalog is required.
	local seen = {}
	for _, id in ipairs(raw.Cosmetics) do
		if type(id) ~= "string" or not (config.Profile.AllowedCosmetics or {})[id] then return nil, "PROFILE_CORRUPT" end
		if not seen[id] then seen[id] = true; table.insert(p.Cosmetics, id) end
	end
	seen = {}
	for _, sku in ipairs(raw.RareDiscoveries) do
		if type(sku) ~= "string" or not config.Products[sku] or config.Products[sku].Rarity ~= "Rare" then
			return nil, "PROFILE_CORRUPT"
		end
		if not seen[sku] then seen[sku] = true; table.insert(p.RareDiscoveries, sku) end
	end
	if not array(raw.Presets, config.Progression.FreePresetSlots) then return nil, "PROFILE_CORRUPT" end
	seen = {}
	for _, preset in ipairs(raw.Presets) do
		if not keys(preset, {Index=true,Slots=true}) or not integer(preset.Index, config.Progression.FreePresetSlots, 1)
			or seen[preset.Index] or p.Level < config.Progression.Tools.LayoutPreset
			or not array(preset.Slots, #config.World.ShelfSlotIds) then return nil, "PROFILE_CORRUPT" end
		seen[preset.Index] = true
		local slots, slotSeen = {}, {}
		for _, slot in ipairs(preset.Slots) do
			if not keys(slot, {SlotId=true,Sku=true}) or type(slot.SlotId) ~= "string" or type(slot.Sku) ~= "string"
				or not table.find(config.World.ShelfSlotIds,slot.SlotId) or not config.Products[slot.Sku]
				or slotSeen[slot.SlotId] then return nil, "PROFILE_CORRUPT" end
			slotSeen[slot.SlotId] = true
			table.insert(slots, {SlotId=slot.SlotId,Sku=slot.Sku})
		end
		table.insert(p.Presets, {Index=preset.Index,Slots=slots})
	end
	if not array(raw.Best, config.Ranking.MaxBestRecords) then return nil, "PROFILE_CORRUPT" end
	seen = {}
	for _, record in ipairs(raw.Best) do
		if not keys(record, {Key=true,Sales=true,Revenue=true,TeamSize=true,ToolTier=true,Mode=true,HadSupport=true,HadReduction=true})
			or not integer(record.Sales, config.Economy.MaxCurrency) or not integer(record.Revenue, config.Economy.MaxCurrency)
			or not integer(record.TeamSize, config.Capacity.SeatsPerStore, 1)
			or not integer(record.ToolTier, #config.Progression.LevelXP, 1)
			or not table.find(config.Ranking.ModeTags, record.Mode) or type(record.HadSupport) ~= "boolean"
			or type(record.HadReduction) ~= "boolean" then return nil, "PROFILE_CORRUPT" end
		local expected = table.concat({record.Mode, tostring(record.TeamSize), tostring(record.ToolTier),
			tostring(record.HadSupport), tostring(record.HadReduction)}, "/")
		if record.Key ~= expected or seen[expected] then return nil, "PROFILE_CORRUPT" end
		seen[expected] = true; table.insert(p.Best, copy(record))
	end
	return p, "OK"
end

local function defaults(config)
	return { SchemaVersion=config.SchemaVersion, Revision=0, Wallet=config.Economy.InitialWallet, XP=0, Level=1,
		UnlockedTools={"HandCarry"}, EquippedTool="HandCarry", Cosmetics={}, Presets={}, Best={}, RareDiscoveries={},
		CompletedFirstShift=false, RewardCursor={Epoch=0,Sequence=0}, Session=false }
end

local Shared = game:GetService("ReplicatedStorage").NightShift.Shared
local SoloProfile = require(Shared.SoloStoreProfile)
local Contract = require(Shared.SoloStoreContract)
ProfileService.normalizeLegacy = normalize
local function normalizeV2(raw, config, userId)
	local legacy = copy(config)
	legacy.SchemaVersion = 1
	legacy.Capacity.SeatsPerStore = 4
	legacy.Ranking.ModeTags = {"Coop", "Solo", "Practice", "Support"}
	return SoloProfile.migrate(raw, config, Contract, function(value) return normalize(value, legacy) end, userId)
end

-- Memory is explicit, process-local and never falls back to DataStore.
function ProfileService.newMemoryStore()
	local records = {}
	return { Mode="Memory", GetBudget=function() return math.huge end,
		UpdateAsync=function(_, key, transform)
			local nextValue = transform(copy(records[key]))
			if nextValue == nil then return nil end
			records[key] = copy(nextValue)
			return copy(nextValue)
		end }
end

function ProfileService.new(deps)
	assert(type(deps) == "table" and type(deps.Config) == "table", "Config required")
	assert(type(deps.SessionId) == "string" and #deps.SessionId > 0 and #deps.SessionId <= 200, "Unique server SessionId required")
	assert(type(deps.UnixNow) == "function", "UnixNow required")
	local store = deps.Store
	if not store then
		assert(deps.Config.Profile.DefaultMode == "Memory", "Cloud mode requires an explicit adapter")
		store = ProfileService.newMemoryStore()
	end
	assert(type(store.UpdateAsync) == "function" and type(store.GetBudget) == "function", "StorageAdapter required")
	local mode = store.Mode or deps.Config.Profile.DefaultMode
	assert(mode == "Memory" or mode == "DataStore", "Unknown storage mode")
	return setmetatable({ config=deps.Config, store=store, mode=mode, now=deps.UnixNow, sessionId=deps.SessionId,
		studioMemoryUsers=deps.IsStudio==true and mode=="Memory",
		onStatus=deps.OnStatus, entries={}, closing=false, deadline=false,
		-- Optional deterministic retry/close hooks; Roblox task.wait/os.clock are the defaults.
		wait=deps.Wait or function(seconds) task.wait(seconds) end,
		clock=deps.MonotonicNow or os.clock }, ProfileService)
end

function ProfileService:_notify(id)
	local status = self:status(id)
	local entry = self.entries[id]
	if entry then entry.notifiedFrozen = status.Frozen end
	if self.onStatus then
		-- Observer failure/yield cannot interrupt a commit or hold its writer lock.
		local thread = coroutine.create(self.onStatus)
		coroutine.resume(thread, id, status)
		if coroutine.status(thread) ~= "dead" then coroutine.close(thread) end
	end
end

function ProfileService:_refresh(entry)
	if entry and entry.profile and entry.state ~= "Released" and entry.state ~= "LeaseLost" then
		if self.now() >= entry.leaseUntil then entry.state = "LeaseLost" end
	end
end

function ProfileService:status(id)
	local e = self.entries[id]
	self:_refresh(e)
	return { State=e and e.state or "LoadFailed", Mode=self.mode,
		Dirty=e ~= nil and e.profile ~= nil and e.profile.Revision > e.savedRevision,
		SavedRevision=e and e.savedRevision or 0, Epoch=e and e.epoch or 0,
		-- Extension for Main's new-participation gate; do not expose Session.Id.
		Frozen=self.closing or not e or not e.profile or e.state == "LeaseLost" or e.state == "Released"
			or e.barrier == true or e.releasing == true or self.now() >= e.leaseUntil - self.config.Profile.FreezeBeforeExpirySeconds,
		ErrorCode=e and e.errorCode or false }
end

function ProfileService:_update(key, transform)
	local code = "SAVE_FAILED"
	for attempt=1,self.config.Profile.MaxAttempts do
		if self.deadline and self.clock() >= self.deadline then break end
		local budgetOk, budget = pcall(function() return self.store:GetBudget() end)
		if budgetOk and type(budget) == "number" and budget >= 1 then
			-- Diagnostics are attempt-local only. Transform never mutates service/profile state.
			local decision = "OK"
			local ok, value = pcall(function()
				return self.store:UpdateAsync(key, function(old)
					local nextValue, why = transform(old, self.now())
					decision = why
					return nextValue
				end)
			end)
			if ok then
				if value == nil then return nil, decision ~= "OK" and decision or "SAVE_FAILED" end
				return value, "OK"
			end
		end
		if attempt < self.config.Profile.MaxAttempts then
			local delay = self.config.Profile.RetrySeconds[attempt] or 0
			if self.deadline and self.clock() + delay >= self.deadline then break end
			local waited = pcall(self.wait, delay)
			if not waited then break end
		end
	end
	return nil, code
end

function ProfileService:load(id)
	-- Studio's real local test players use negative UserIds. Keep those IDs
	-- distinct, memory-only, and impossible to accept in a DataStore adapter.
	local studioUser=self.studioMemoryUsers and integer(id,-1,-MAX_INT)
	if not integer(id, MAX_INT, 1) and not studioUser then return result(false,"BAD_REQUEST") end
	if self.closing then return result(false,"PROFILE_UNAVAILABLE") end
	local oldEntry = self.entries[id]
	if oldEntry then
		if oldEntry.busy or oldEntry.mutating then return result(false,"REQUEST_IN_PROGRESS") end
		self:_refresh(oldEntry)
		if oldEntry.profile and oldEntry.state ~= "Released" and oldEntry.state ~= "LeaseLost" then return self:get(id) end
	end
	local e = {state="Loading",busy=true,profile=nil,savedRevision=0,epoch=0,leaseUntil=0,nextSave=0}
	self.entries[id] = e; self:_notify(id)
	local value, code = self:_update(self.config.Profile.KeyPrefix .. tostring(id), function(raw, now)
		local p, why
		if raw == nil then p = SoloProfile.new(self.config) else p, why = normalizeV2(raw,self.config,id) end
		if not p then return nil, why end
		local session = p.Session
		if session and session.ExpiresAt > now and session.Id ~= self.sessionId then return nil,"SESSION_LOCKED" end
		-- A disconnected, lost writer must reload persisted data under a new epoch.
		-- A retried UpdateAsync may already have committed that newer epoch.
		local staleEpoch = oldEntry and oldEntry.state == "LeaseLost" and oldEntry.epoch
		local reacquire = session and session.ExpiresAt > now and session.Id == self.sessionId
			and (not staleEpoch or session.Epoch > staleEpoch)
		if not reacquire then
			local epoch = math.max(p.RewardCursor.Epoch, session and session.Epoch or 0) + 1
			if not integer(epoch) or not integer(p.Revision + 1) then return nil,"PROFILE_CORRUPT" end
			p.Revision += 1
			p.RewardCursor = {Epoch=epoch,Sequence=0}
			p.EconomyCursor = {Epoch=epoch,Sequence=0}
			p.ActivityCursor = {Epoch=epoch,Sequence=0}
			p.Session = {Id=self.sessionId,Epoch=epoch,ExpiresAt=now+self.config.Profile.LeaseSeconds}
		else
			p.Session.ExpiresAt = now + self.config.Profile.LeaseSeconds
		end
		return p,"OK"
	end)
	e.busy = false
	if value then
		local verified, why = normalizeV2(value,self.config,id)
		if not verified then value=nil; code=why
		elseif not verified.Session or verified.Session.Id ~= self.sessionId or verified.Session.ExpiresAt <= self.now() then
			value=nil; code="LEASE_LOST"
		else value=verified end
	end
	if not value then
		e.errorCode=code
		e.state = code == "SESSION_LOCKED" and "Locked" or "LoadFailed"
		self:_notify(id)
		return result(false,code == "SAVE_FAILED" and "PROFILE_UNAVAILABLE" or code)
	end
	e.profile=value; e.savedRevision=value.Revision; e.epoch=value.Session.Epoch; e.leaseUntil=value.Session.ExpiresAt
	e.nextSave=self.now()+math.min(self.config.Profile.AutosaveSeconds,self.config.Profile.RenewSeconds)
	e.state=self.mode == "Memory" and "Temporary" or "Ready"; self:_notify(id)
	return result(true,"OK",value)
end

function ProfileService:get(id)
	local e = self.entries[id]
	self:_refresh(e)
	if not e or not e.profile or e.state == "Released" then return result(false,"PROFILE_UNAVAILABLE") end
	if e.state == "LeaseLost" then return result(false,"LEASE_LOST") end
	return result(true,"OK",e.profile)
end

function ProfileService:mutate(id, epoch, fn)
	local e = self.entries[id]
	local status = self:status(id)
	if not e or not e.profile then return result(false,"PROFILE_UNAVAILABLE") end
	if e.state == "LeaseLost" or epoch ~= e.epoch then return result(false,"LEASE_LOST") end
	if status.Frozen then return result(false,"PROFILE_UNAVAILABLE") end
	if type(fn) ~= "function" then return result(false,"BAD_REQUEST") end
	if e.mutating then return result(false,"REQUEST_IN_PROGRESS") end
	e.mutating = true
	local previous = e.profile
	local thread = coroutine.create(fn)
	local ok, candidate = coroutine.resume(thread, copy(previous))
	local yielded = coroutine.status(thread) ~= "dead"
	if yielded then coroutine.close(thread) end
	e.mutating = false
	if not ok or yielded then return result(false,"INTERNAL_ERROR") end
	if candidate == nil then return result(false,"INVALID_STATE") end
	local p, code = normalizeV2(candidate,self.config,id)
	if not p then return result(false,code) end
	-- These fields are owned by Profiles. Reward cursor advances atomically, one at a time.
	if p.Revision ~= previous.Revision or not p.Session or p.Session.Id ~= self.sessionId
		or p.Session.Epoch ~= e.epoch or p.Session.ExpiresAt ~= previous.Session.ExpiresAt
		or p.RewardCursor.Epoch ~= e.epoch or p.RewardCursor.Sequence < previous.RewardCursor.Sequence
		or p.RewardCursor.Sequence > previous.RewardCursor.Sequence + 1 then return result(false,"PROFILE_CORRUPT") end
	for _,name in ipairs({"EconomyCursor","ActivityCursor"}) do
		if p[name].Epoch~=e.epoch or p[name].Sequence<previous[name].Sequence
			or p[name].Sequence>previous[name].Sequence+1 then return result(false,"PROFILE_CORRUPT") end
	end
	if self:status(id).Frozen or e.profile ~= previous then return result(false,"PROFILE_UNAVAILABLE") end
	if not integer(previous.Revision+1) then return result(false,"PROFILE_CORRUPT") end
	p.Revision=previous.Revision+1; e.profile=p; self:_notify(id)
	return result(true,"OK",p)
end

function ProfileService:save(id, release)
	if type(release) ~= "boolean" then return result(false,"BAD_REQUEST") end
	local e = self.entries[id]
	self:_refresh(e)
	if not e or not e.profile then return result(false,"PROFILE_UNAVAILABLE") end
	if e.busy or e.mutating then return result(false,"REQUEST_IN_PROGRESS") end
	if e.state == "Released" then return release and result(true,"OK") or result(false,"PROFILE_UNAVAILABLE") end
	if e.state == "LeaseLost" then return result(false,"LEASE_LOST") end
	local snapshot = copy(e.profile)
	e.busy=true; e.releasing=release; e.state="Saving"; self:_notify(id)
	local value, code = self:_update(self.config.Profile.KeyPrefix .. tostring(id), function(raw, now)
		if raw == nil then return nil,"LEASE_LOST" end
		local persisted, why = normalizeV2(raw,self.config,id)
		if not persisted then return nil,why end
		local session = persisted.Session
		if not session or session.Id ~= self.sessionId or session.Epoch ~= e.epoch or session.ExpiresAt <= now then
			return nil,"LEASE_LOST"
		end
		if persisted.Revision > snapshot.Revision then return nil,"LEASE_LOST" end
		local nextValue = copy(snapshot)
		if release then nextValue.Session = false
		else nextValue.Session = {Id=self.sessionId,Epoch=e.epoch,ExpiresAt=now+self.config.Profile.LeaseSeconds} end
		return nextValue,"OK"
	end)
	e.busy=false; e.releasing=false
	if value then
		local verified, why = normalizeV2(value,self.config,id)
		if not verified then value=nil; code=why
		elseif verified.Revision ~= snapshot.Revision or (release and verified.Session ~= false)
			or (not release and (not verified.Session or verified.Session.Id ~= self.sessionId or verified.Session.Epoch ~= e.epoch)) then
			value=nil; code="LEASE_LOST"
		else value=verified end
	end
	if value then
		e.savedRevision = math.max(e.savedRevision,snapshot.Revision)
		if release then e.state="Released"; e.profile.Session=false
		else
			e.leaseUntil=value.Session.ExpiresAt
			-- Never replace the newer in-memory wallet/cursor with the writer snapshot.
			e.profile.Session=copy(value.Session)
			e.state=self.mode == "Memory" and "Temporary" or "Ready"
			self:_refresh(e)
		end
	else
		e.state=code == "LEASE_LOST" and "LeaseLost" or "SaveFailed"
		self:_refresh(e)
	end
	e.errorCode=not value and code or false
	e.nextSave=self.now()+math.min(self.config.Profile.AutosaveSeconds,self.config.Profile.RenewSeconds)
	self:_notify(id)
	if not value then return result(false,code) end
	if e.state == "LeaseLost" then return result(false,"LEASE_LOST") end
	return result(true,"OK",snapshot.Revision)
end

-- Main enters this only after inventory settlement in the serial economic queue.
-- A departure barrier is never reopened after a failed save.
function ProfileService:beginBarrier(id, reason)
	local e=self.entries[id]
	if not e or not e.profile then return result(false,"PROFILE_UNAVAILABLE") end
	if self:status(id).Frozen and not e.barrier then return result(false,"PROFILE_FROZEN") end
	e.barrier=true; e.barrierReason=reason; self:_notify(id)
	return result(true,"OK",e.profile.Revision)
end

function ProfileService:due()
	local ids = {}
	if self.closing then return ids end
	for id,e in pairs(self.entries) do
		local previous = e.state
		self:_refresh(e)
		if previous ~= e.state or e.notifiedFrozen ~= self:status(id).Frozen then self:_notify(id) end
		if e.profile and not e.busy and e.state ~= "Released" and e.state ~= "LeaseLost" and self.now() >= e.nextSave then
			table.insert(ids,id)
		end
	end
	table.sort(ids)
	return ids
end

-- Optional integration helper. Budget limits starting/retrying IO, not an already-yielding
-- adapter call. Main may launch per-user final saves concurrently within BindToClose.
function ProfileService:close()
	self.closing=true
	self.deadline=self.deadline or self.clock()+self.config.Profile.CloseBudgetSeconds
	local ids, outcomes = {}, {}
	for id,e in pairs(self.entries) do if e.profile and e.state ~= "Released" then table.insert(ids,id) end end
	table.sort(ids)
	for _,id in ipairs(ids) do
		-- Give an already running autosave a bounded chance to finish before release.
		local e = self.entries[id]
		for _=1,self.config.Profile.CloseBudgetSeconds do
			if not e.busy or self.clock() >= self.deadline then break end
			local remaining = self.deadline-self.clock()
			if not pcall(self.wait,math.min(1,remaining)) then break end
		end
		if self.clock() >= self.deadline then outcomes[id]=result(false,"SAVE_FAILED")
		else outcomes[id]=self:save(id,true) end
	end
	return outcomes
end

return ProfileService
