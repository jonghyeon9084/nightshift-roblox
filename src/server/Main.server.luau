--!nonstrict
-- Deploy as ServerScriptService.NightShift.Main (Script).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local function clock() return workspace:GetServerTimeNow() end
local bootstrapDeadline = os.clock() + 10
local function bounded(parent, name, class)
	local child = parent:FindFirstChild(name)
	if not child then child = parent:WaitForChild(name, math.max(0.001, bootstrapDeadline - os.clock())) end
	assert(child and child.ClassName == class, "NightShift bootstrap: " .. parent:GetFullName() .. "." .. name .. " must be " .. class)
	return child
end
local namespace = bounded(ReplicatedStorage, "NightShift", "Folder")
local config = require(bounded(bounded(namespace, "Shared", "Folder"), "Config", "ModuleScript"))
assert(config.ProtocolVersion == 1, "NightShift protocol mismatch")
bootstrapDeadline = os.clock() + config.Network.BootstrapTimeout
local builder = require(bounded(bounded(ServerStorage, "NightShift", "Folder"), "BuildWorld", "ModuleScript"))
assert(type(builder) == "table" and type(builder.build) == "function", "BuildWorld.build(parent) is required")
local modules = bounded(script.Parent, "Modules", "Folder")
local Protocol = require(bounded(modules, "Protocol", "ModuleScript"))
local WorldAdapter = require(bounded(modules, "WorldAdapter", "ModuleScript"))
local GameService = require(bounded(modules, "GameService", "ModuleScript"))
-- Exactly one world build invocation for this server script/session.
local world = builder.build(workspace)
local function remote(parent, name, class)
	local found
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then assert(not found and child.ClassName == class, "NightShift remote name/type collision: " .. name); found = child end
	end
	if not found then found = Instance.new(class); found.Name = name; found.Parent = parent end
	return found
end
local remotes = remote(namespace, "Remotes", "Folder")
local Action = remote(remotes, "Action", "RemoteEvent")
local ActionResult = remote(remotes, "ActionResult", "RemoteEvent")
local State = remote(remotes, "State", "RemoteEvent")
local GetSnapshot = remote(remotes, "GetSnapshot", "RemoteFunction")
local service, connections = nil, {}
local queue, reception = {}, 0
local draining = false
local failed = false
local function enqueue(kind, player, data, receivedAt)
	reception += 1
	table.insert(queue, { kind = kind, player = player, data = data, at = receivedAt or clock(), sequence = reception })
end
local function sendAck(player, connection, request, code, moveCode, retry)
	local user = service.users[player.UserId]
	if not user then return end
	local ack = service:ack(user, request.RequestId, code, moveCode, retry)
	Protocol.remember(connection, request, ack, config)
	if player.Parent == Players then ActionResult:FireClient(player, ack) end
end
local function advanceBefore(at)
	-- Deadlines earlier than a received event must run at their own time, never at a later heartbeat time.
	local due = service:nextDeadline()
	while due < at do
		service:tick(due)
		local nextDue = service:nextDeadline()
		assert(nextDue > due, "NightShift deadline did not advance")
		due = nextDue
	end
end
local function drain(now)
	if draining or failed or not service then return end
	draining = true
	local ok, issue = xpcall(function()
		local batch = queue
		queue = {}
		table.sort(batch, function(a, b) return a.at < b.at or (a.at == b.at and a.sequence < b.sequence) end)
		local index = 1
		while index <= #batch do
			local at = batch[index].at
			advanceBefore(at)
			local last = index
			while last < #batch and batch[last + 1].at == at do last += 1 end
			local context, leaving = {}, {}
			-- All same-time disconnects, character loss and validated explicit leaves precede timers/ordinary actions.
			for cursor = index, last do
				local event = batch[cursor]
				local user = service.users[event.player.UserId]
				if user then
					if event.kind == "Disconnect" or event.kind == "CharacterGone" then
						if user.player == event.player then service:depart(user, event.kind == "Disconnect" and "Disconnect" or "Character", context) end
					elseif event.kind == "Action" and event.data.request.Action == "LeaveStore"
						and user.player == event.player and service:membership(user, event.data.request) == "OK" then
						service:depart(user, "Leave", context)
						leaving[event.sequence] = true
					end
				end
			end
			service:selectRecoverySurvivors(context)
			service:tick(at)
			service:settleDepartures(context, at)
			for cursor = index, last do
				local event = batch[cursor]
				local user = service.users[event.player.UserId]
				if event.kind == "Connect" then
					if event.player.Parent == Players then service:connect(event.player) end
				elseif event.kind == "CharacterReady" then
					if user and user.player == event.player and event.player.Character == event.data then service:characterReady(user) end
				elseif event.kind == "Action" then
					local request, connection = event.data.request, event.data.connection
					if user and user.player == event.player and connections[event.player] == connection then
						local code, moveCode, retry
						if leaving[event.sequence] then
							code, moveCode = "OK", service.world:move(event.player, false, "Spawn") and "OK" or "MOVE_FAILED"
						else code, moveCode, retry = service:action(user, request, at) end
						sendAck(event.player, connection, request, code, moveCode, retry)
					end
				end
			end
			index = last + 1
		end
		advanceBefore(now)
		service:tick(now)
	end, debug.traceback)
	draining = false
	if not ok then
		-- Stop accepting mutation after an unexpected invariant violation; do not continue a partially mutated game.
		failed = true
		service.ready = false
		warn("NightShift server stopped: " .. tostring(issue))
	end
end
GetSnapshot.OnServerInvoke = function(player, raw)
	local now, connection = clock(), connections[player]
	local empty = { Ok = false, Code = "NOT_READY", RetryAfter = config.Network.SnapshotCooldown, Snapshot = false }
	if not connection or not service or not service.ready or failed then return empty end
	if now - connection.snapshotAt < config.Network.SnapshotCooldown then
		empty.Code, empty.RetryAfter = "RATE_LIMIT", config.Network.SnapshotCooldown - (now - connection.snapshotAt)
		return empty
	end
	connection.snapshotAt = now
	local code = Protocol.validSnapshot(raw, config)
	if code ~= "OK" then empty.Code = code; return empty end
	local user = service.users[player.UserId]
	if not user or user.player ~= player then return empty end
	return { Ok = true, Code = "OK", RetryAfter = 0, Snapshot = service:packet(user, connection, now, true) }
end
Action.OnServerEvent:Connect(function(player, raw)
	local now, connection = clock(), connections[player]
	if not connection or not service then return end
	local parseableId = type(raw) == "table" and Protocol.integer(raw.RequestId, config.Network.MaxRequestId) and raw.RequestId >= 1
	if not Protocol.consume(connection, config, now) then
		-- At most one rejection acknowledgement per second, including malformed floods.
		if parseableId and now - connection.rateReplyAt >= 1 then
			connection.rateReplyAt = now
			local user = service.users[player.UserId]
			if user then ActionResult:FireClient(player, service:ack(user, raw.RequestId, "RATE_LIMIT", false, 1)) end
		end
		return
	end
	local request, code = Protocol.validate(raw, config)
	local user = service.users[player.UserId]
	if not request then
		connection.rejected += 1
		if parseableId and user then ActionResult:FireClient(player, service:ack(user, raw.RequestId, code)) end
		return
	end
	if not user then return end
	local cached = connection.cache[request.RequestId]
	if cached then
		ActionResult:FireClient(player, Protocol.equal(request, cached.request) and cached.ack or service:ack(user, request.RequestId, "REQUEST_ID_REUSED"))
		return
	end
	local pending = connection.pending[request.RequestId]
	if pending then
		ActionResult:FireClient(player, service:ack(user, request.RequestId, Protocol.equal(request, pending) and "REQUEST_IN_PROGRESS" or "REQUEST_ID_REUSED"))
		return
	end
	if request.RequestId <= connection.high then ActionResult:FireClient(player, service:ack(user, request.RequestId, "STALE_REQUEST")); return end
	connection.high = request.RequestId
	if failed or not service.ready then sendAck(player, connection, request, "NOT_READY", false, config.Loading.RetryDelay); return end
	connection.pending[request.RequestId] = request
	enqueue("Action", player, { request = request, connection = connection }, now)
end)
service = GameService.new(config, WorldAdapter.new(world, config))
local characterLost = setmetatable({}, { __mode = "k" })
local playerHooks = {}
local function trackPlayer(player)
	if connections[player] then return end
	connections[player] = Protocol.newConnection(config, clock())
	enqueue("Connect", player)
	local hooks = {}
	playerHooks[player] = hooks
	local function lost(character)
		if characterLost[character] then return end
		characterLost[character] = true
		enqueue("CharacterGone", player, character)
	end
	local function characterAdded(character)
		-- Waiting for Roblox character creation is outside the authoritative mutation queue and is bounded.
		task.spawn(function()
			local human = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", config.Network.BootstrapTimeout)
			local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", config.Network.BootstrapTimeout)
			if player.Parent ~= Players or player.Character ~= character or not human or not human:IsA("Humanoid") or not root then return end
			if hooks.death then hooks.death:Disconnect() end
			hooks.death = human.Died:Connect(function() lost(character) end)
			if human.Health <= 0 then lost(character) else enqueue("CharacterReady", player, character) end
		end)
	end
	hooks.added = player.CharacterAdded:Connect(characterAdded)
	hooks.removing = player.CharacterRemoving:Connect(lost)
	if player.Character then characterAdded(player.Character) end
end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(function(player)
	enqueue("Disconnect", player)
	connections[player] = nil
	local hooks = playerHooks[player]
	if hooks then for _, hook in pairs(hooks) do hook:Disconnect() end end
	playerHooks[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do trackPlayer(player) end
RunService.Heartbeat:Connect(function()
	local now = clock()
	drain(now)
	if failed then return end
	for player, connection in pairs(connections) do
		if now - connection.lastSend >= config.Network.StateInterval then
			local user = service.users[player.UserId]
			if user and user.player == player then
				local packet = service:packet(user, connection, now, connection.sequence == 0)
				if packet then State:FireClient(player, packet) end
			end
		end
	end
end)
-- Server capacity is configured by the integrator in Studio/place settings; never publish or alter it here.
print("NightShift server ready: four independent stores; target capacity " .. config.Capacity.TargetPlayers .. "; no play-test claim")
