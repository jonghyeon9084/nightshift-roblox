--!nocheck
-- Server-only, non-yielding facade. Profiles owns schema validation and leases.
local Service = {}
Service.__index = Service

local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}; for k, value in pairs(v) do out[k] = copy(value) end; return out
end
local function result(code, value) return { Ok = code == "OK", Code = code, Value = copy(value == nil and false or value) } end
local function integer(v) return type(v) == "number" and v == v and v >= 0 and v < math.huge and v % 1 == 0 end
local function contains(t, v) return table.find(t, v) ~= nil end

function Service.new(deps)
	return setmetatable({ config = deps.Config, profiles = deps.Profiles, consumed = {} }, Service)
end

function Service:_read(userId)
	local status = self.profiles:status(userId)
	if not status or not integer(status.Epoch) or status.Epoch == 0 then return result("PROFILE_UNAVAILABLE") end
	local p = self.profiles:get(userId)
	if not p.Ok then return p end
	return result("OK", { Profile = p.Value, Epoch = status.Epoch })
end

function Service:_normalize(p)
	local level = 1
	for i, xp in ipairs(self.config.Progression.LevelXP) do if p.XP >= xp then level = i end end
	p.Level = level; p.UnlockedTools = {}
	for tool, required in pairs(self.config.Progression.Tools) do
		if level >= required then table.insert(p.UnlockedTools, tool) end
	end
	table.sort(p.UnlockedTools, function(a,b) return self.config.Progression.Tools[a] < self.config.Progression.Tools[b] end)
	if not contains(p.UnlockedTools, p.EquippedTool) then p.EquippedTool = "HandCarry" end
end

function Service:award(userId, event)
	if type(event) ~= "table" or type(event.TransactionId) ~= "string" or #event.TransactionId == 0
		or #event.TransactionId > self.config.Network.MaxStringBytes or not integer(event.Epoch)
		or type(event.Eligible) ~= "boolean" or not self.config.Progression.Rewards[event.Kind]
		or (event.Sku ~= false and not self.config.Products[event.Sku]) then return result("BAD_REQUEST") end
	if event.Kind ~= "CoopClose" and event.Sku == false then return result("BAD_REQUEST") end
	local read = self:_read(userId); if not read.Ok then return read end
	if event.Epoch ~= read.Value.Epoch then return result("LEASE_LOST") end
	local records = self.consumed[userId]
	if not records then records = {}; self.consumed[userId] = records end
	-- Retain transaction identities across epochs for this server's lifetime.
	local prior = records[event.TransactionId]
	if prior then
		if prior.Kind ~= event.Kind or prior.Sku ~= event.Sku or prior.Eligible ~= event.Eligible or prior.Epoch ~= event.Epoch then
			return result("INVALID_STATE")
		end
		return result("OK", false)
	end
	local updated = self.profiles:mutate(userId, event.Epoch, function(original)
		local p = copy(original)
		if p.RewardCursor.Epoch > event.Epoch then return nil end
		local sequence = p.RewardCursor.Epoch == event.Epoch and p.RewardCursor.Sequence or 0
		p.RewardCursor = { Epoch = event.Epoch, Sequence = sequence + 1 }
		if event.Eligible then
			local reward = self.config.Progression.Rewards[event.Kind]
			p.Wallet = math.min(self.config.Economy.MaxCurrency, p.Wallet + reward.Coins)
			p.XP = math.min(self.config.Progression.MaxXP, p.XP + reward.XP)
			local product = self.config.Products[event.Sku]
			if product and product.Rarity == "Rare" and not contains(p.RareDiscoveries, event.Sku) then
				table.insert(p.RareDiscoveries, event.Sku)
			end
		end
		self:_normalize(p)
		return p
	end)
	if not updated.Ok then return updated end
	records[event.TransactionId] = copy(event)
	return result("OK", self:view(userId))
end

function Service:equip(userId, toolId)
	if type(toolId) ~= "string" or not self.config.Progression.Tools[toolId] then return result("BAD_REQUEST") end
	local read = self:_read(userId); if not read.Ok then return read end
	if read.Value.Profile.Level < self.config.Progression.Tools[toolId] then return result("LEVEL_LOCKED") end
	return self.profiles:mutate(userId, read.Value.Epoch, function(original)
		local p = copy(original); self:_normalize(p)
		if not contains(p.UnlockedTools, toolId) then return nil end
		p.EquippedTool = toolId; return p
	end)
end

function Service:savePreset(userId, index, slots)
	if not integer(index) or index < 1 or index > self.config.Progression.FreePresetSlots or type(slots) ~= "table"
		or #slots > #self.config.World.ShelfSlotIds then return result("PRESET_INVALID") end
	local seen = {}; local count = 0
	for key, slot in pairs(slots) do
		count += 1
		if not integer(key) or key < 1 or key > #slots or type(slot) ~= "table"
			or not contains(self.config.World.ShelfSlotIds, slot.SlotId) or not self.config.Products[slot.Sku]
			or seen[slot.SlotId] then return result("PRESET_INVALID") end
		for field in pairs(slot) do if field ~= "SlotId" and field ~= "Sku" then return result("PRESET_INVALID") end end
		seen[slot.SlotId] = true
	end
	if count ~= #slots then return result("PRESET_INVALID") end
	local read = self:_read(userId); if not read.Ok then return read end
	if read.Value.Profile.Level < self.config.Progression.Tools.LayoutPreset then return result("LEVEL_LOCKED") end
	return self.profiles:mutate(userId, read.Value.Epoch, function(original)
		local p = copy(original)
		if p.Level < self.config.Progression.Tools.LayoutPreset then return nil end
		local preset = { Index = index, Slots = copy(slots) }
		for i, old in ipairs(p.Presets) do if old.Index == index then p.Presets[i] = preset; return p end end
		table.insert(p.Presets, preset); table.sort(p.Presets, function(a,b) return a.Index < b.Index end)
		return p
	end)
end

function Service:view(userId)
	local read = self.profiles:get(userId)
	if not read.Ok then
		return { Wallet = 0, XP = 0, Level = 1, Tools = {}, EquippedTool = "HandCarry", Cosmetics = {}, RareDiscoveries = {}, Presets = {}, Best = {} }
	end
	local p = read.Value
	return copy({ Wallet = p.Wallet, XP = p.XP, Level = p.Level, Tools = p.UnlockedTools,
		EquippedTool = p.EquippedTool, Cosmetics = p.Cosmetics, RareDiscoveries = p.RareDiscoveries, Presets = p.Presets, Best = p.Best })
end

-- Main must check OfficePC/active membership for preset writes and reject equip
-- while either legacy-line carry or Commerce carry is present (facade has no World).
return Service
