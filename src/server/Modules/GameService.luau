--!nonstrict
-- Authoritative state. Every public mutator is non-yielding and is called by Main's serial queue.
local Timer = require(script.Parent.Timer)
local Service = {}
Service.__index = Service
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end
local function contains(list, item) return table.find(list, item) ~= nil end
local function remove(list, item)
	local index = table.find(list, item)
	if index then table.remove(list, index) end
end
function Service.new(config, world)
	local self = setmetatable({ config = config, world = world, users = {}, stores = {}, serial = 0, summaryRevision = 0,
		random = Random.new(), ready = false }, Service)
	for _, id in ipairs(config.World.StoreIds) do
		local map = world.stores[id]
		self.stores[id] = { StoreId = id, Revision = 0, RosterVersion = 0, Phase = map.available and "Lobby" or "Unavailable",
			Available = map.available, UnavailableReason = map.reason, seats = {}, round = false, RoundId = false,
			result = false, startTimer = false, resultTimer = false, signals = {}, lastSchedule = false, lastLayout = 0 }
		if map.available then world:setLayout(id, config.InitialLayouts[1]) end
	end
	self.ready = true
	return self
end
function Service:id(prefix)
	self.serial += 1
	return prefix .. "-" .. self.serial
end
function Service:touch(store)
	if store then store.Revision += 1 end
end
function Service:touchUser(user)
	user.revision += 1
	self:touch(user.storeId and self.stores[user.storeId] or nil)
end
function Service:setParticipant(user, participant)
	if user.participant ~= participant then user.participant = participant; user.generation += 1; self:touchUser(user) end
end
function Service:connect(player)
	local user = self.users[player.UserId]
	if not user then
		user = { id = player.UserId, name = player.DisplayName, player = player, storeId = false, seat = false,
			generation = 0, participant = "Hub", loaded = false, ready = false, resumeReady = false,
			carry = false, role = false, lastResult = false, revision = 0, moveAt = -math.huge, signalAt = -math.huge }
		self.users[user.id] = user
	end
	user.player, user.name, user.loaded = player, player.DisplayName, false
	self:touchUser(user)
	return user
end
function Service:characterReady(user)
	if not user.player or not self.world:alive(user.player) then return end
	local store = user.storeId and self.stores[user.storeId]
	if store and store.Phase == "Recovery" and user.participant == "Reserved" then
		self:setParticipant(user, "Returning")
		self.world:move(user.player, store.StoreId, "Spawn")
	elseif store then self.world:move(user.player, store.StoreId, "Spawn")
	else self.world:move(user.player, false, "Spawn") end
end
function Service:rosterChanged(store)
	store.RosterVersion += 1
	for _, user in pairs(store.seats) do user.ready = false; self:touchUser(user) end
	if store.Phase == "Starting" then store.Phase = "Lobby"; store.startTimer = false end
	self:touch(store)
end
function Service:releaseRole(user)
	if not user.role then return end
	local store = user.storeId and self.stores[user.storeId]
	local outage = store and store.round and store.round.outage
	local role = outage and outage.roles[user.role.RoleId]
	if role and role.owner == user.id then
		role.owner, role.lease = false, 0
		self.serial += 1
		role.generation = self.serial
		outage.revision += 1
	end
	user.role = false
	self:touchUser(user)
end
function Service:clearRoles(store)
	for _, user in pairs(store.seats) do self:releaseRole(user) end
end
function Service:clearCarry(user)
	if not user.carry then return end
	local store = user.storeId and self.stores[user.storeId]
	local order = store and store.round and store.round.order
	local line = order and order.lines[user.carry.LineId]
	if line and line.carrier == user.id then
		line.status, line.carrier, line.token, line.tray = "Uncollected", false, false, false
		line.revision += 1
	end
	user.carry = false
	self:touchUser(user)
end
function Service:dropSeat(user)
	local store = user.storeId and self.stores[user.storeId]
	self:clearCarry(user)
	self:releaseRole(user)
	if store then store.seats[user.seat] = nil end
	user.storeId, user.seat, user.loaded, user.ready, user.resumeReady = false, false, false, false, false
	user.participant = "Hub"
	user.generation += 1
	self:touchUser(user)
	if store then self:rosterChanged(store) end
end
function Service:counts(store)
	local occupied, online = 0, 0
	for _, user in pairs(store.seats) do occupied += 1; if user.player then online += 1 end end
	return occupied, online
end
function Service:membership(user, request)
	if request.SeatGeneration ~= user.generation then return "STALE_SEAT" end
	if not user.storeId or request.StoreId ~= user.storeId then return "NOT_MEMBER" end
	if request.RoundId ~= self.stores[user.storeId].RoundId then return "STALE_ROUND" end
	return "OK"
end
function Service:active(user, store, allowOutage)
	if user.participant ~= "Active" then return "NOT_ACTIVE" end
	if store.Phase ~= "Running" then return "INVALID_STATE" end
	if not user.loaded then return "NOT_LOADED" end
	if not self.world:alive(user.player) then return "NOT_ACTIVE" end
	if not allowOutage and store.round.outage and store.round.outage.status == "Active" then return "INVALID_STATE" end
	return "OK"
end
function Service:newOrder(store, now)
	local round = store.round
	if round.order or round.success >= self.config.Round.SuccessOrders then return end
	local first = self.config.Schedules[round.schedule].FirstProducts[round.success + 1]
	local products = { first }
	for _, product in ipairs(self.config.ProductOrder) do if product ~= first then table.insert(products, product) end end
	local order = { id = self:id("o"), stage = round.success + 1, required = round.target, accepted = 0,
		timer = Timer.new(self.config.Order.Seconds, now, true), lines = {} }
	for index = 1, round.target do
		order.lines[index] = { id = index, product = products[index], status = "Uncollected", revision = 0,
			carrier = false, token = false, tray = false, acceptedBy = false }
	end
	round.order = order
	if order.stage == 3 then round.bellShown = true end
	round.boundary, round.boundaryKind = false, "None"
	self:touch(store)
end
function Service:clearOrder(store)
	for _, user in pairs(store.seats) do self:clearCarry(user) end
	store.round.order = false
	self:touch(store)
end
function Service:startRound(store, solo, now)
	local config = self.config
	local schedules = {}
	for _, name in ipairs({ "A", "B", "C" }) do if name ~= store.lastSchedule then table.insert(schedules, name) end end
	local schedule = schedules[self.random:NextInteger(1, #schedules)]
	local layouts = {}
	for index = 1, #config.InitialLayouts do if index ~= store.lastLayout then table.insert(layouts, index) end end
	local layout = layouts[self.random:NextInteger(1, #layouts)]
	local active = {}
	store.RoundId = self:id("r")
	for seat = 1, config.Capacity.SeatsPerStore do
		local user = store.seats[seat]
		if user and user.player then
			table.insert(active, user.id)
			user.startGeneration, user.startedRound = user.generation, store.RoundId
			self:setParticipant(user, "Active")
			user.ready, user.resumeReady = false, false
		end
	end
	store.lastSchedule, store.lastLayout = schedule, layout
	store.Phase, store.startTimer, store.result, store.signals = "Running", false, false, {}
	store.round = { id = store.RoundId, schedule = schedule, mode = solo and "Solo" or "Coop", initial = copy(active), active = active,
		target = math.max(1, #active - 1), success = 0, anxiety = config.Anxiety.Initial, anxietyCause = "None",
		shift = Timer.new(config.Round.MaxSeconds, now, true), boundary = false, boundaryKind = "None",
		layout = copy(config.InitialLayouts[layout]), shuffleStatus = "Pending", outageStatus = "Pending", bellShown = false,
		order = false, outage = false, recovery = false, recoveryBudget = config.Round.RecoveryBudgetSeconds,
		soloRequest = false, soloUsed = false, hadReduction = false, hadSolo = solo, hadSupport = false }
	self.world:setOutage(store.StoreId, false)
	self.world:setLayout(store.StoreId, store.round.layout)
	self:newOrder(store, now)
	self:touch(store)
end
function Service:repartition(store)
	local round, outage = store.round, store.round.outage
	if not outage or outage.status ~= "Active" then return end
	self:clearRoles(store)
	outage.roles, outage.roleOrder, outage.shared, outage.progress = {}, {}, { false, false, false }, 0
	self.serial += 1
	outage.generation = self.serial
	outage.revision += 1
	outage.partitionCount = #round.active
	local segments = self.config.Outage.SegmentsByPlayers[#round.active]
	for index, indices in ipairs(segments) do
		local id = "Panel" .. index
		outage.roles[id] = { id = id, indices = copy(indices), owner = false, generation = outage.generation, shared = false, lease = 0, renewAt = -math.huge }
		table.insert(outage.roleOrder, id)
	end
	outage.roles.Breaker = { id = "Breaker", indices = {}, owner = false, generation = outage.generation, shared = false, lease = 0, renewAt = -math.huge }
	table.insert(outage.roleOrder, "Breaker")
	if round.mode == "Solo" then outage.shared = copy(outage.answer) end
	self:touch(store)
end
function Service:startOutage(store, now)
	local round = store.round
	if round.outageStatus ~= "Pending" then return end
	local answer = copy(self.config.Outage.Shapes)
	for index = #answer, 2, -1 do local other = self.random:NextInteger(1, index); answer[index], answer[other] = answer[other], answer[index] end
	round.outage = { id = self:id("x"), revision = 0, generation = 0, status = "Active", answer = answer,
		timer = Timer.new(self.config.Outage.AutoRestoreSeconds, now, true), penalties = 0, resolution = false, roles = {}, roleOrder = {} }
	round.outageStatus = "Active"
	if round.order then Timer.pause(round.order.timer, now) end
	Timer.pause(round.boundary, now)
	self:repartition(store)
	self.world:setOutage(store.StoreId, true)
	self:touch(store)
end
function Service:boundary(store, now)
	local round = store.round
	if not round or round.order or (round.outage and round.outage.status == "Active") then return end
	local schedule = self.config.Schedules[round.schedule]
	if round.outageStatus == "Pending" and round.success >= schedule.OutageAfterSuccess then
		self:startOutage(store, now)
		return
	end
	local shuffleDue = round.shuffleStatus == "Active" or (round.shuffleStatus == "Pending" and round.success >= schedule.ShuffleAfterSuccess
		and (not schedule.ShuffleAfterOutage or round.outageStatus == "Done"))
	if shuffleDue then round.shuffleStatus = "Active" end
	if self:checkResult(store, now) then return end
	if not round.boundary then
		round.boundaryKind = shuffleDue and "Shuffle" or "NextOrder"
		round.boundary = Timer.new(self.config.Round.BoundarySeconds, now, true)
	else
		if shuffleDue then round.boundaryKind = "Shuffle" end
		Timer.resume(round.boundary, now)
	end
	self:touch(store)
end
function Service:completeOrder(store, now)
	local round, order = store.round, store.round.order
	if not order or order.accepted < order.required then return end
	self:clearOrder(store)
	round.success += 1
	self:boundary(store, now)
end
function Service:restoreOutage(store, resolution, now)
	local round, outage = store.round, store.round.outage
	if not outage or outage.status ~= "Active" then return end
	self:clearRoles(store)
	outage.status, outage.resolution = "Done", resolution
	outage.roles, outage.roleOrder, outage.shared, outage.progress = {}, {}, { false, false, false }, 0
	outage.answer = {}
	outage.revision += 1
	Timer.pause(outage.timer, now)
	round.outageStatus = "Done"
	if resolution == "Support" then round.hadSupport = true end
	self.world:setOutage(store.StoreId, false)
	if round.order then Timer.resume(round.order.timer, now) end
	if not round.order then Timer.resume(round.boundary, now) end
	self:touch(store)
	if not self:checkResult(store, now) then self:boundary(store, now) end
end
function Service:finish(store, code, reason, now)
	local round = store.round
	if not round then return end
	local result = { StoreId = store.StoreId, RoundId = round.id, Code = code, FailureReason = reason or false,
		SuccessCount = round.success, OutageResolution = round.outage and round.outage.resolution or false,
		HadReduction = round.hadReduction, HadSolo = round.hadSolo, HadSupport = round.hadSupport, FinishedAt = now }
	self:clearOrder(store)
	self:clearRoles(store)
	self.world:setOutage(store.StoreId, false)
	for _, id in ipairs(round.initial) do local user = self.users[id]; if user then user.lastResult = copy(result); self:touchUser(user) end end
	local drop = {}
	for _, user in pairs(store.seats) do
		user.lastResult, user.ready, user.resumeReady = copy(result), false, false
		if not user.player then table.insert(drop, user) else self:setParticipant(user, "Waiting") end
	end
	for _, user in ipairs(drop) do self:dropSeat(user) end
	store.round, store.result, store.Phase, store.signals = false, result, "Result", {}
	store.resultTimer = Timer.new(self.config.Round.ResultSeconds, now, true)
	self:touch(store)
	if code == "Abandoned" then self:toLobby(store) end
end
function Service:checkResult(store, now, timeLimit)
	local round = store.round
	if not round then return true end
	if round.anxiety >= self.config.Anxiety.Maximum then self:finish(store, "Incomplete", "Anxiety", now); return true end
	if round.success >= self.config.Round.SuccessOrders and round.shuffleStatus == "Done" and round.outageStatus == "Done" then
		self:finish(store, round.hadSolo and "AdjustedClose" or (round.hadSupport and "SupportClose" or "CoopSuccess"), false, now)
		return true
	end
	if timeLimit then self:finish(store, "Incomplete", "TimeLimit", now); return true end
	return false
end
function Service:toLobby(store)
	store.round, store.RoundId, store.result, store.resultTimer, store.startTimer = false, false, false, false, false
	store.Phase, store.signals = "Lobby", {}
	for _, user in pairs(store.seats) do user.ready, user.resumeReady = false, false; self:setParticipant(user, "Waiting") end
	self:rosterChanged(store)
end
function Service:reduce(store, now)
	local round = store.round
	if not round then return end
	round.target = math.max(1, #round.active - 1)
	local order = round.order
	if order then
		order.required = math.max(order.accepted, round.target)
		local pending = {}
		local priority = { Tray = 1, Carried = 2, Uncollected = 3 }
		for _, line in ipairs(order.lines) do if priority[line.status] then table.insert(pending, line) end end
		table.sort(pending, function(a, b)
			return priority[a.status] < priority[b.status] or (priority[a.status] == priority[b.status] and a.id < b.id)
		end)
		for index = order.required - order.accepted + 1, #pending do
			local line = pending[index]
			if line.carrier then self:clearCarry(self.users[line.carrier]) end
			line.status, line.carrier, line.token, line.tray = "Cancelled", false, false, false
			line.revision += 1
		end
	end
	if round.outage and round.outage.status == "Active" and round.outage.partitionCount ~= #round.active then self:repartition(store) end
	self:touch(store)
	if order then self:completeOrder(store, now) end
end
function Service:pauseRound(round, now)
	Timer.pause(round.shift, now)
	Timer.pause(round.boundary, now)
	if round.order then Timer.pause(round.order.timer, now) end
	if round.outage then Timer.pause(round.outage.timer, now) end
end
function Service:resumeTimers(round, now)
	Timer.resume(round.shift, now)
	local dark = round.outage and round.outage.status == "Active"
	if dark then Timer.resume(round.outage.timer, now)
	else
		if round.order then Timer.resume(round.order.timer, now) end
		if not round.order then Timer.resume(round.boundary, now) end
	end
end
function Service:confirmSolo(store, survivorId, now, deferReduction)
	local round = store.round
	if not round then return end
	local survivor = self.users[survivorId]
	if not survivor or not survivor.player or survivor.storeId ~= store.StoreId then
		self:finish(store, "Abandoned", "AllLeft", now)
		return
	end
	if round.recovery then round.recoveryBudget = Timer.remaining(round.recovery.timer, now) end
	if #round.active > 1 then round.hadReduction = true end
	local drop = {}
	for _, user in pairs(store.seats) do
		if user.id ~= survivorId then
			self:clearCarry(user)
			self:releaseRole(user)
			if user.player then self:setParticipant(user, "Waiting") else table.insert(drop, user) end
		end
		user.resumeReady = false
	end
	for _, user in ipairs(drop) do self:dropSeat(user) end
	self:clearRoles(store)
	round.mode, round.hadSolo, round.active, round.recovery, round.soloRequest = "Solo", true, { survivorId }, false, false
	store.Phase = "Running"
	self:setParticipant(survivor, "Active")
	self:resumeTimers(round, now)
	self:repartition(store)
	self:touch(store)
	if not deferReduction then self:reduce(store, now) end
end
function Service:resumeCoop(store, now)
	local round = store.round
	if not round or not round.recovery or Timer.expired(round.recovery.timer, now) then return end
	local ready = {}
	for seat = 1, self.config.Capacity.SeatsPerStore do
		local user = store.seats[seat]
		if user and (user.participant == "Active" or user.participant == "Returning") and user.player then
			if not user.loaded or not user.resumeReady or not self.world:alive(user.player) then return end
			table.insert(ready, user.id)
		end
	end
	if #ready < self.config.Capacity.MinCoopPlayers then return end
	round.recoveryBudget = Timer.remaining(round.recovery.timer, now)
	local drop = {}
	for _, user in pairs(store.seats) do
		if user.participant == "Reserved" then table.insert(drop, user) end
		if contains(ready, user.id) then self:setParticipant(user, "Active") end
		user.resumeReady = false
	end
	for _, user in ipairs(drop) do self:dropSeat(user) end
	round.active, round.recovery, store.Phase = ready, false, "Running"
	self:resumeTimers(round, now)
	self:reduce(store, now)
	self:touch(store)
end
-- Called for every departure in a same-timestamp batch BEFORE tick/deadlines/reduction.
function Service:depart(user, reason, context)
	local store = user.storeId and self.stores[user.storeId]
	if reason == "Disconnect" then user.player = nil end
	user.loaded, user.ready, user.resumeReady = false, false, false
	if not store then self:touchUser(user); return end
	local round = store.round
	-- Death and CharacterRemoving/PlayerRemoving can describe the same loss.
	-- Preserve an existing reservation instead of treating the second notification as a voluntary leave.
	if user.participant == "Reserved" and reason ~= "Leave" then self:touchUser(user); return end
	if reason == "Character" and user.participant == "Waiting" then
		if store.Phase == "Lobby" or store.Phase == "Starting" then self:rosterChanged(store) end
		self:touchUser(user)
		return
	end
	local group = context[store.StoreId]
	if not group then
		group = { candidates = {}, before = round and copy(round.active) or {} }
		context[store.StoreId] = group
	end
	self:clearCarry(user)
	self:releaseRole(user)
	if round and contains(round.active, user.id) then
		remove(round.active, user.id)
		round.hadReduction, round.soloRequest = true, false
		if round.mode == "Coop" and store.Phase == "Running" and reason ~= "Leave" then
			self:setParticipant(user, "Reserved")
			table.insert(group.candidates, user)
		else self:dropSeat(user) end
	elseif round and store.Phase == "Recovery" and user.participant == "Returning" and reason ~= "Leave" then
		self:setParticipant(user, "Reserved")
	else self:dropSeat(user) end
	self:touch(store)
end
function Service:selectRecoverySurvivors(context)
	-- Complete the same-time departure batch before recovery's deadline selects its survivor.
	for id in pairs(context) do
		local store = self.stores[id]
		local round = store.round
		if round and round.recovery and not contains(round.active, round.recovery.survivor) then
			for seat = 1, self.config.Capacity.SeatsPerStore do
				local user = store.seats[seat]
				if user and user.participant == "Returning" and user.player then
					round.recovery.survivor, round.active = user.id, { user.id }
					self:setParticipant(user, "Active")
					break
				end
			end
		end
	end
end
function Service:settleDepartures(context, now)
	for id, group in pairs(context) do
		local store, round = self.stores[id], self.stores[id].round
		if round then
			if round.mode == "Solo" then
				if #round.active == 0 then self:finish(store, "Incomplete", "SoloLeft", now) end
			elseif store.Phase == "Recovery" then
				local connected = {}
				local reserved = 0
				for seat = 1, self.config.Capacity.SeatsPerStore do
					local user = store.seats[seat]
					if user and (user.participant == "Active" or user.participant == "Returning") and user.player then table.insert(connected, user) end
					if user and (user.participant == "Reserved" or user.participant == "Returning") then reserved += 1 end
				end
				if #connected == 0 then self:finish(store, "Abandoned", "AllLeft", now)
				else
					if not contains(round.active, round.recovery.survivor) then
						local replacement = connected[1]
						round.active, round.recovery.survivor = { replacement.id }, replacement.id
						self:setParticipant(replacement, "Active")
						if replacement.participant == "Active" then reserved = math.max(0, reserved - 1) end
					end
					if reserved == 0 then self:confirmSolo(store, round.recovery.survivor, now) end
				end
			elseif #round.active == 0 then self:finish(store, "Abandoned", "AllLeft", now)
			elseif #round.active == 1 and #group.before > 1 then
				if #group.candidates > 0 and round.recoveryBudget > 0 then
					store.Phase = "Recovery"
					round.recovery = { survivor = round.active[1], timer = Timer.new(round.recoveryBudget, now, true) }
					self:pauseRound(round, now)
					self:clearRoles(store)
					for _, user in pairs(store.seats) do user.resumeReady = false end
				else self:confirmSolo(store, round.active[1], now) end
			else
				for _, user in ipairs(group.candidates) do if user.storeId == id then self:dropSeat(user) end end
				if #round.active < #group.before then self:reduce(store, now) end
			end
		end
		self:touch(store)
	end
end
function Service:inputReason(user, store, now)
	local round = store.round
	local outage = round and round.outage
	if not outage or outage.status ~= "Active" then return "NoOutage" end
	if store.Phase == "Recovery" then return "Recovery" end
	if store.Phase ~= "Running" or user.participant ~= "Active" then return "NotActive" end
	if not user.loaded then return "Loading" end
	local breaker = outage.roles.Breaker
	if not breaker or breaker.owner ~= user.id then return "NotBreakerOwner" end
	if not self:roleConnected(store, breaker, now) then return "MissingOwner" end
	for _, roleId in ipairs(outage.roleOrder) do
		local role = outage.roles[roleId]
		if roleId ~= "Breaker" then
			if not self:roleConnected(store, role, now) then return "MissingOwner" end
			if not role.shared then return "Unshared" end
		end
	end
	return "None"
end
function Service:roleConnected(store, role, now)
	local user = role.owner and self.users[role.owner]
	return user ~= nil and user ~= false and user.storeId == store.StoreId and user.participant == "Active" and user.loaded
		and store.Phase == "Running" and role.lease > now
		and self.world:near(user.player, store.StoreId, role.id == "Breaker" and "Breaker" or "SignalPanel")
end
function Service:tickStore(store, now)
	for index = #store.signals, 1, -1 do
		if store.signals[index].ExpiresAt <= now then table.remove(store.signals, index); self:touch(store) end
	end
	if store.Phase == "Starting" and Timer.expired(store.startTimer, now) then self:startRound(store, false, store.startTimer.due) end
	if store.Phase == "Result" then if Timer.expired(store.resultTimer, now) then self:toLobby(store) end; return end
	local round = store.round
	if not round then return end
	-- No current input can rescue a round at its upper bound.
	if Timer.expired(round.shift, now) then self:checkResult(store, now, true); return end
	local needsReduction = false
	if round.recovery and Timer.expired(round.recovery.timer, now) then
		self:confirmSolo(store, round.recovery.survivor, round.recovery.timer.due, true)
		needsReduction = true
	end
	if not store.round or store.Phase == "Recovery" then return end
	if round.soloRequest and Timer.expired(round.soloRequest.timer, now) then
		self:confirmSolo(store, round.soloRequest.requester, round.soloRequest.timer.due, true)
		needsReduction = true
	end
	if not store.round then return end
	local outage = round.outage
	if outage and outage.status == "Active" then
		for index, threshold in ipairs(self.config.Outage.PenaltySeconds) do
			if outage.timer.due and now >= outage.timer.due - self.config.Outage.AutoRestoreSeconds + threshold and outage.penalties < index then
				outage.penalties = index
				round.anxiety = math.min(self.config.Anxiety.Maximum, round.anxiety + self.config.Outage.PenaltyAnxiety)
				round.anxietyCause = "OutageDelay"
				self:touch(store)
			end
		end
		if Timer.expired(outage.timer, now) then self:restoreOutage(store, "Support", outage.timer.due) end
		if self:checkResult(store, now) then return end
	end
	if round.order and Timer.expired(round.order.timer, now) then
		local expiredAt = round.order.timer.due
		self:clearOrder(store)
		round.anxiety = math.min(self.config.Anxiety.Maximum, round.anxiety + self.config.Order.TimeoutAnxiety)
		round.anxietyCause = "OrderTimeout"
		if self:checkResult(store, now) then return end
		-- A pending exceptional shuffle is resolved before the replacement order.
		local schedule = self.config.Schedules[round.schedule]
		if round.shuffleStatus == "Active" or (round.shuffleStatus == "Pending" and round.success >= schedule.ShuffleAfterSuccess
			and (not schedule.ShuffleAfterOutage or round.outageStatus == "Done")) then self:boundary(store, expiredAt)
		else self:newOrder(store, expiredAt) end
	end
	if needsReduction and store.round then self:reduce(store, now) end
	if not store.round then return end
	if round.boundary and Timer.expired(round.boundary, now) then
		local at = round.boundary.due
		if round.boundaryKind == "Shuffle" then
			round.layout = { round.layout[3], round.layout[1], round.layout[2] }
			round.shuffleStatus = "Done"
			self.world:setLayout(store.StoreId, round.layout)
		end
		round.boundary, round.boundaryKind = false, "None"
		if not self:checkResult(store, now) then self:newOrder(store, at) end
		self:touch(store)
	end
	if store.round and round.outage and round.outage.status == "Active" then
		for _, roleId in ipairs(round.outage.roleOrder) do
			local role = round.outage.roles[roleId]
			if role.owner and not self:roleConnected(store, role, now) then self:releaseRole(self.users[role.owner]) end
		end
	end
end
function Service:tick(now)
	for _, id in ipairs(self.config.World.StoreIds) do self:tickStore(self.stores[id], now) end
end
function Service:nextDeadline()
	local earliest = math.huge
	local function add(timer) if timer and timer.due then earliest = math.min(earliest, timer.due) end end
	for _, store in pairs(self.stores) do
		add(store.startTimer); add(store.resultTimer)
		local round = store.round
		if round then
			add(round.shift); add(round.boundary)
			if round.order then add(round.order.timer) end
			if round.recovery then add(round.recovery.timer) end
			if round.soloRequest then add(round.soloRequest.timer) end
			local outage = round.outage
			if outage and outage.status == "Active" and outage.timer.due then
				add(outage.timer)
				local threshold = self.config.Outage.PenaltySeconds[outage.penalties + 1]
				if threshold then earliest = math.min(earliest, outage.timer.due - self.config.Outage.AutoRestoreSeconds + threshold) end
			end
		end
	end
	return earliest
end
function Service:action(user, request, now)
	local action, payload = request.Action, request.Payload
	-- A late unload report from the just-finished Starting state can only revoke this user's input.
	-- It cannot restore permission, move a seat or affect another user's role.
	local startedStore = user.storeId and self.stores[user.storeId]
	if action == "SetLoaded" and payload.Loaded == false and startedStore and request.StoreId == user.storeId
		and request.RoundId == false and user.startedRound == startedStore.RoundId
		and request.SeatGeneration == user.startGeneration and user.generation == user.startGeneration + 1 then
		user.loaded, user.resumeReady = false, false
		self:releaseRole(user)
		self:touchUser(user)
		return "OK"
	end
	if request.SeatGeneration ~= user.generation then return "STALE_SEAT" end
	if action == "JoinStore" then
		if request.RoundId ~= false or not request.StoreId then return "BAD_REQUEST" end
		local target = self.stores[request.StoreId]
		if not target or not target.Available then return "STORE_UNAVAILABLE" end
		local current = user.storeId and self.stores[user.storeId]
		if current == target then return "INVALID_STATE" end
		if current and current.Phase ~= "Lobby" and current.Phase ~= "Starting" and current.Phase ~= "Result" then
			if current.Phase == "Recovery" and (user.participant == "Returning" or user.participant == "Reserved") then
				local context = {}; self:depart(user, "Leave", context); self:settleDepartures(context, now)
			else return "INVALID_STATE" end
		end
		local free
		for seat = 1, self.config.Capacity.SeatsPerStore do if not target.seats[seat] then free = seat; break end end
		if not free then return "STORE_FULL" end
		if user.storeId then self:dropSeat(user) end
		user.storeId, user.seat, user.participant = target.StoreId, free, "Waiting"
		user.generation += 1
		user.loaded, user.ready, user.resumeReady = false, false, false
		target.seats[free] = user
		self:rosterChanged(target)
		self:touchUser(user)
		return "OK", self.world:move(user.player, target.StoreId, "Entry") and "OK" or "MOVE_FAILED"
	end
	local membership = self:membership(user, request)
	if membership ~= "OK" then return membership end
	local store, round = self.stores[user.storeId], self.stores[user.storeId].round
	if action == "LeaveStore" then
		local context = {}; self:depart(user, "Leave", context); self:settleDepartures(context, now)
		return "OK", self.world:move(user.player, false, "Spawn") and "OK" or "MOVE_FAILED"
	elseif action == "TravelToEntry" or action == "Reposition" then
		if now - user.moveAt < self.config.Interaction.RepositionCooldown then return "COOLDOWN", false, self.config.Interaction.RepositionCooldown - (now - user.moveAt) end
		user.moveAt = now
		self:releaseRole(user)
		local moved = self.world:move(user.player, store.StoreId, action == "Reposition" and "Spawn" or "Entry")
		return moved and "OK" or "MOVE_FAILED", moved and "OK" or "MOVE_FAILED"
	elseif action == "SetLoaded" then
		user.loaded = payload.Loaded
		if not payload.Loaded then
			user.resumeReady = false
			self:releaseRole(user)
			if store.Phase == "Lobby" or store.Phase == "Starting" then self:rosterChanged(store) end
		end
		self:touchUser(user)
		return "OK"
	elseif action == "SetReady" or action == "SoloPractice" then
		if store.Phase ~= "Lobby" and not (action == "SetReady" and store.Phase == "Starting") then return "INVALID_STATE" end
		if payload.RosterVersion ~= store.RosterVersion then return "STALE_ROSTER" end
		if not user.loaded and (action == "SoloPractice" or payload.Ready) then return "NOT_LOADED" end
		if (action == "SoloPractice" or payload.Ready) and not self.world:alive(user.player) then return "NOT_ACTIVE" end
		if action == "SoloPractice" then
			local occupied, online = self:counts(store)
			if occupied ~= 1 or online ~= 1 then return "INVALID_STATE" end
			self:startRound(store, true, now)
		else
			if not payload.Ready then self:rosterChanged(store)
			else
				user.ready = true
				local count, allReady = 0, true
				for _, member in pairs(store.seats) do
					count += 1
					if not member.player or not member.ready or not member.loaded or not self.world:alive(member.player) then allReady = false end
				end
				if count >= self.config.Capacity.MinCoopPlayers and allReady and store.Phase == "Lobby" then
					store.Phase, store.startTimer = "Starting", Timer.new(self.config.Round.StartConfirmSeconds, now, true)
				end
				self:touchUser(user)
			end
		end
		return "OK"
	elseif action == "AcknowledgeResult" then
		if store.Phase ~= "Result" then return "INVALID_STATE" end
		self:toLobby(store)
		return "OK"
	elseif action == "ResumeReady" then
		if store.Phase ~= "Recovery" or (user.participant ~= "Active" and user.participant ~= "Returning") then return "INVALID_STATE" end
		if payload.Ready and not user.loaded then return "NOT_LOADED" end
		if payload.Ready and not self.world:alive(user.player) then return "NOT_ACTIVE" end
		user.resumeReady = payload.Ready
		self:touchUser(user)
		self:resumeCoop(store, now)
		return "OK"
	elseif action == "FinishSolo" then
		if store.Phase ~= "Recovery" or round.recovery.survivor ~= user.id then return "INVALID_STATE" end
		self:confirmSolo(store, user.id, now)
		return "OK"
	elseif action == "ReleaseRole" then
		local outage = round and round.outage
		if not outage or outage.id ~= payload.OutageId then return "STALE_OUTAGE" end
		local role = outage.roles[payload.RoleId]
		if not role or role.generation ~= payload.Generation then return "STALE_ROLE" end
		if role.owner ~= user.id then return "NOT_ACTIVE" end
		self:releaseRole(user)
		return "OK"
	end
	local code = self:active(user, store, true)
	if code ~= "OK" then return code end
	if action == "RequestSolo" or action == "CancelSolo" then
		if round.mode ~= "Coop" or #round.active ~= 2 then return "INVALID_STATE" end
		if action == "RequestSolo" then
			if round.soloRequest then return "REQUEST_IN_PROGRESS" end
			if round.soloUsed then return "ALREADY_USED" end
			round.soloUsed, round.soloRequest = true, { requester = user.id, timer = Timer.new(self.config.Round.SoloRequestSeconds, now, true) }
		else
			if not round.soloRequest or round.soloRequest.requester == user.id then return "INVALID_STATE" end
			round.soloRequest = false
		end
		self:touch(store)
		return "OK"
	elseif action == "Signal" then
		if now - user.signalAt < self.config.Interaction.SignalCooldown then return "COOLDOWN", false, self.config.Interaction.SignalCooldown - (now - user.signalAt) end
		if not self.world:near(user.player, store.StoreId, payload.Target) or not self.world:inside(user.player, store.StoreId) then return "TOO_FAR" end
		user.signalAt = now
		-- A player's latest signal replaces their previous one, bounding the slice to four entries.
		for index = #store.signals, 1, -1 do if store.signals[index].SenderUserId == user.id then table.remove(store.signals, index) end end
		table.insert(store.signals, { SignalId = self:id("s"), SenderUserId = user.id, Target = payload.Target, Message = payload.Message,
			ExpiresAt = now + self.config.Interaction.SignalSeconds })
		self:touch(store)
		return "OK"
	elseif action == "ClaimRole" or action == "RenewRole" or action == "ShareSegment" or action == "InputShape" then
		return self:roleAction(user, store, request, now)
	elseif action == "PickUp" or action == "PutDown" or action == "ReturnItem" or action == "AcceptLine" then
		return self:itemAction(user, store, request, now)
	end
	return "BAD_REQUEST"
end
function Service:itemAction(user, store, request, now)
	local payload, action, round = request.Payload, request.Action, store.round
	local order = round.order
	if not order or order.id ~= payload.OrderId then return "STALE_ORDER" end
	local line = order.lines[payload.LineId]
	if not line or line.revision ~= payload.LineRevision then return "STALE_LINE" end
	if round.outage and round.outage.status == "Active" then return "INVALID_STATE" end
	if action == "PickUp" then
		if user.carry then return "CARRY_FULL" end
		if line.status ~= "Uncollected" then return "INVALID_STATE" end
		local shelf = tonumber(string.sub(payload.Shelf, -1))
		if round.layout[shelf] ~= line.product then return "BAD_REQUEST" end
		if not self.world:near(user.player, store.StoreId, payload.Shelf) then return "TOO_FAR" end
		line.status, line.carrier, line.token = "Carried", user.id, self:id("c")
		line.revision += 1
		user.carry = { RoundId = round.id, OrderId = order.id, LineId = line.id, LineRevision = line.revision,
			ProductId = line.product, CarryToken = line.token }
		self:touchUser(user)
	elseif action == "PutDown" or action == "ReturnItem" then
		if line.status ~= "Carried" or line.carrier ~= user.id or not user.carry or line.token ~= payload.CarryToken
			or user.carry.CarryToken ~= payload.CarryToken then return "BAD_TOKEN" end
		if action == "PutDown" and not self.world:near(user.player, store.StoreId, "Counter") then return "TOO_FAR" end
		line.status, line.carrier, line.token = action == "PutDown" and "Tray" or "Uncollected", false, false
		line.tray = action == "PutDown" and line.id or false
		line.revision += 1
		user.carry = false
		self:touchUser(user)
	else
		if line.status ~= "Tray" then return "INVALID_STATE" end
		if not self.world:near(user.player, store.StoreId, "Counter") then return "TOO_FAR" end
		line.status, line.tray, line.acceptedBy = "Accepted", false, user.id
		line.revision += 1
		order.accepted += 1
		self:completeOrder(store, now)
	end
	self:touch(store)
	return "OK"
end
function Service:roleAction(user, store, request, now)
	local payload, action, outage = request.Payload, request.Action, store.round.outage
	if not outage or outage.id ~= payload.OutageId or outage.status ~= "Active" then return "STALE_OUTAGE" end
	local role = outage.roles[action == "InputShape" and "Breaker" or payload.RoleId]
	if not role or role.generation ~= payload.Generation then return "STALE_ROLE" end
	local marker = role.id == "Breaker" and "Breaker" or "SignalPanel"
	if not self.world:near(user.player, store.StoreId, marker) then return "TOO_FAR" end
	if action == "ClaimRole" then
		if role.owner then return "ROLE_TAKEN" end
		if user.role then return "INVALID_STATE" end
		self.serial += 1
		role.generation, role.owner, role.lease, role.renewAt = self.serial, user.id, now + self.config.Outage.RoleLeaseSeconds, now
		user.role = { OutageId = outage.id, RoleId = role.id, Generation = role.generation }
		self:touchUser(user)
	else
		if role.owner ~= user.id or not user.role or user.role.Generation ~= payload.Generation then return "STALE_ROLE" end
		if action == "RenewRole" then
			if now - role.renewAt < self.config.Outage.RoleRenewSeconds then return "COOLDOWN", false, self.config.Outage.RoleRenewSeconds - (now - role.renewAt) end
			role.lease, role.renewAt = now + self.config.Outage.RoleLeaseSeconds, now
		elseif action == "ShareSegment" then
			if role.id == "Breaker" then return "INVALID_STATE" end
			role.shared = true
			for _, index in ipairs(role.indices) do outage.shared[index] = outage.answer[index] end
		elseif action == "InputShape" then
			local reason = self:inputReason(user, store, now)
			if reason ~= "None" then return reason == "Unshared" and "NOT_SHARED" or "INVALID_STATE" end
			outage.progress = payload.Shape == outage.answer[outage.progress + 1] and outage.progress + 1 or 0
			if outage.progress == 3 then self:restoreOutage(store, store.round.mode == "Solo" and "Solo" or "Coop", now) end
		end
	end
	outage.revision += 1
	self:touch(store)
	return "OK"
end
function Service:summaries()
	local summaries, signature = {}, {}
	for _, id in ipairs(self.config.World.StoreIds) do
		local store, def = self.stores[id], self.config.World.Stores[id]
		local occupied, online = self:counts(store)
		table.insert(summaries, { StoreId = id, DisplayName = def.Name, SignShape = def.Shape, Phase = store.Phase,
			Available = store.Available, UnavailableReason = store.UnavailableReason, OccupiedSeats = occupied,
			OnlineCount = online, FreeSeats = self.config.Capacity.SeatsPerStore - occupied })
		table.insert(signature, id .. ":" .. store.Phase .. ":" .. occupied .. ":" .. online .. ":" .. tostring(store.Available))
	end
	local key = table.concat(signature, "|")
	if key ~= self.summaryKey then self.summaryKey = key; self.summaryRevision += 1 end
	return summaries
end
function Service:selfState(user)
	local shapes = {}
	local store = user.storeId and self.stores[user.storeId]
	local outage = store and store.round and store.round.outage
	if outage and outage.status == "Active" and user.role then
		local role = outage.roles[user.role.RoleId]
		if role and role.owner == user.id then
			for _, index in ipairs(role.indices) do table.insert(shapes, { Index = index, Shape = outage.answer[index] }) end
		end
	end
	return { UserId = user.id, StoreId = user.storeId, Seat = user.seat, SeatGeneration = user.generation,
		Participant = user.participant, Loaded = user.loaded, Carry = copy(user.carry), Role = copy(user.role),
		ReadShapes = shapes, LastResult = copy(user.lastResult) }
end
function Service:storeState(store, user, now)
	local seats = {}
	for index = 1, self.config.Capacity.SeatsPerStore do
		local member = store.seats[index]
		if member then table.insert(seats, { Seat = index, UserId = member.id, DisplayName = member.name, Participant = member.participant,
			Online = member.player ~= nil, Ready = member.ready, Loaded = member.loaded, ResumeReady = member.resumeReady }) end
	end
	local state = { StoreId = store.StoreId, RoundId = store.RoundId, Revision = store.Revision, RosterVersion = store.RosterVersion,
		Phase = store.Phase, Seats = seats, StartTimer = Timer.wire(store.startTimer, now), Round = false,
		Result = copy(store.result), ResultTimer = Timer.wire(store.resultTimer, now), Signals = copy(store.signals) }
	local r = store.round
	if not r then return state end
	local round = { RoundId = r.id, Schedule = r.schedule, Mode = r.mode, InitialUserIds = copy(r.initial), ActiveUserIds = copy(r.active),
		ActiveCount = #r.active, TargetLines = r.target, SuccessCount = r.success, Anxiety = r.anxiety, AnxietyCause = r.anxietyCause,
		ShiftTimer = Timer.wire(r.shift, now), BoundaryTimer = Timer.wire(r.boundary, now), BoundaryKind = r.boundaryKind,
		ShelfProducts = copy(r.layout), ShuffleStatus = r.shuffleStatus, OutageStatus = r.outageStatus, BellShown = r.bellShown,
		Order = false, Outage = false, Recovery = false, SoloRequest = false, SoloRequestUsed = r.soloUsed,
		HadReduction = r.hadReduction, HadSolo = r.hadSolo, HadSupport = r.hadSupport }
	if r.order then
		local order = r.order
		local lines = {}
		for _, line in ipairs(order.lines) do table.insert(lines, { LineId = line.id, ProductId = line.product, Status = line.status,
			LineRevision = line.revision, CarrierUserId = line.carrier, TrayIndex = line.tray, AcceptedByUserId = line.acceptedBy }) end
		round.Order = { OrderId = order.id, Stage = order.stage, RequiredCount = order.required, AcceptedCount = order.accepted,
			Timer = Timer.wire(order.timer, now), Lines = lines }
	end
	if r.outage then
		local outage, roles, missing, connected = r.outage, {}, {}, 0
		for _, roleId in ipairs(outage.roleOrder) do
			local role = outage.roles[roleId]
			local isConnected = self:roleConnected(store, role, now)
			table.insert(roles, { RoleId = roleId, Indices = copy(role.indices), OwnerUserId = role.owner, Generation = role.generation,
				Connected = isConnected, Shared = role.shared })
			if roleId ~= "Breaker" then
				if isConnected then connected += 1 end
				if not isConnected or not role.shared then table.insert(missing, tonumber(string.sub(roleId, -1))) end
			end
		end
		local reason = self:inputReason(user, store, now)
		round.Outage = { OutageId = outage.id, Revision = outage.revision, Timer = Timer.wire(outage.timer, now), PenaltiesApplied = outage.penalties,
			RequiredPanelCount = math.max(0, #outage.roleOrder - 1), ConnectedPanelCount = connected, RequiredBreakerCount = 1,
			Roles = roles, SharedShapes = copy(outage.shared), Progress = outage.progress, MissingSegments = missing,
			CanInput = reason == "None", InputBlockReason = reason, Resolution = outage.resolution }
	end
	if r.recovery then
		local reserved = {}
		for seat = 1, self.config.Capacity.SeatsPerStore do
			local member = store.seats[seat]
			if member and (member.participant == "Reserved" or member.participant == "Returning") then table.insert(reserved, member.id) end
		end
		round.Recovery = { Timer = Timer.wire(r.recovery.timer, now), BudgetRemaining = Timer.remaining(r.recovery.timer, now),
			SurvivorUserId = r.recovery.survivor, ReservedUserIds = reserved }
	end
	if r.soloRequest then round.SoloRequest = { RequesterUserId = r.soloRequest.requester, Timer = Timer.wire(r.soloRequest.timer, now) } end
	state.Round = round
	return state
end
function Service:packet(user, connection, now, full)
	local summaries = self:summaries()
	local store = user.storeId and self.stores[user.storeId]
	local switched = user.storeId ~= connection.storeId
	local ownChanged = connection.selfRevision ~= user.revision
	local storeChanged = switched or (store and connection.storeRevision ~= store.Revision)
	local summaryChanged = connection.summaryRevision ~= self.summaryRevision
	local timerDue = store and now - connection.lastTimer >= self.config.Network.TimerSyncInterval
	if not full and not ownChanged and not storeChanged and not summaryChanged and not timerDue then return nil end
	connection.sequence += 1
	local packet = { ProtocolVersion = self.config.ProtocolVersion, Kind = full and "Snapshot" or "Delta", Sequence = connection.sequence, ServerTime = now }
	if full or ownChanged or switched then packet.Self = self:selfState(user) end
	if full or summaryChanged then packet.Stores = summaries end
	if full or storeChanged or switched or timerDue then
		packet.Store = store and self:storeState(store, user, now) or false
		connection.lastTimer = now
	end
	connection.selfRevision, connection.storeRevision = user.revision, store and store.Revision or -1
	connection.summaryRevision, connection.storeId = self.summaryRevision, user.storeId
	connection.lastSend = now
	return packet
end
function Service:ack(user, requestId, code, moveCode, retry)
	local store = user.storeId and self.stores[user.storeId]
	return { ProtocolVersion = self.config.ProtocolVersion, RequestId = requestId, Ok = code == "OK", Code = code,
		StoreId = user.storeId, RoundId = store and store.RoundId or false, Revision = store and store.Revision or 0,
		RetryAfter = retry or 0, MoveCode = moveCode or false }
end
return Service
