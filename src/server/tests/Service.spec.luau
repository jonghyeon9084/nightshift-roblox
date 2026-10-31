-- Pure table-state regression tests. No Roblox world, networking, Studio, or game execution.
-- Run through Verify-Server.ps1, which supplies the actual modules and a deterministic test adapter.
return function(Service, Protocol, Config)
	local checks = 0
	local function expect(value, message) checks += 1; assert(value, message or "expectation failed") end
	local function eq(a, b, message) expect(a == b, (message or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
	local function fixture(count, scheduleIndex, layoutIndex)
		local world = { stores = {} }
		for _, id in ipairs(Config.World.StoreIds) do world.stores[id] = { available = true, reason = false } end
		function world:setLayout(id, layout) self.stores[id].layout = table.clone(layout) end
		function world:setOutage(id, active) self.stores[id].dark = active end
		function world:alive(player) return player and not player.dead end
		function world:near(player, _, marker) return self:alive(player) and player.near == marker end
		function world:inside(player) return self:alive(player) end
		function world:move(player, id, marker) player.location = { id, marker }; return not player.moveFailed end
		local service = Service.new(Config, world)
		local randomCalls = 0
		service.random = { NextInteger = function(_, low, _)
			randomCalls += 1
			if randomCalls == 1 then return scheduleIndex or low end
			if randomCalls == 2 then return layoutIndex or low end
			return low
		end }
		local users, time, requestId = {}, 0, 0
		local function send(user, action, payload, target, overrides)
			requestId += 1
			local store = user.storeId and service.stores[user.storeId]
			local request = { ProtocolVersion = 1, RequestId = requestId, Action = action, StoreId = target or user.storeId,
				RoundId = target and false or (store and store.RoundId or false), SeatGeneration = user.generation, Payload = payload or {} }
			for key, value in pairs(overrides or {}) do request[key] = value end
			local parsed, code = Protocol.validate(request, Config)
			if not parsed then return code end
			return service:action(user, parsed, time)
		end
		local function advance(target)
			local due = service:nextDeadline()
			while due <= target do service:tick(due); local nextDue = service:nextDeadline(); expect(nextDue > due, "deadline advance"); due = nextDue end
			time = target; service:tick(target)
		end
		for id = 1, count do
			local user = service:connect({ UserId = id, DisplayName = "Test" .. id })
			users[id] = user
			eq(send(user, "JoinStore", {}, "Store01"), "OK")
			eq(send(user, "SetLoaded", { Loaded = true }), "OK")
		end
		local store = service.stores.Store01
		if count == 1 then eq(send(users[1], "SoloPractice", { RosterVersion = store.RosterVersion }), "OK")
		else
			for _, user in ipairs(users) do eq(send(user, "SetReady", { Ready = true, RosterVersion = store.RosterVersion }), "OK") end
			advance(3)
		end
		local function item(user, action, lineId)
			local order = store.round.order
			local line = order.lines[lineId]
			local payload = { OrderId = order.id, LineId = lineId, LineRevision = line.revision }
			if action == "PickUp" then
				payload.Shelf = "Shelf" .. table.find(store.round.layout, line.product); user.player.near = payload.Shelf
			elseif action == "PutDown" or action == "ReturnItem" then payload.CarryToken = line.token; user.player.near = "Counter"
			else user.player.near = "Counter" end
			return send(user, action, payload)
		end
		local function leave(list, reason)
			local context = {}
			for _, user in ipairs(list) do service:depart(user, reason or "Leave", context) end
			service:selectRecoverySurvivors(context); service:tick(time); service:settleDepartures(context, time)
		end
		return service, users, store, send, advance, item, leave
	end
	-- Integration regression: vacant roles use false, not nil; packet projection
	-- must work before anyone claims an outage role (not just after solving it).
	for count=1,4 do
		local service, users, store = fixture(count)
		service:startOutage(store, 3)
		local connection = Protocol.newConnection(Config, 3)
		local packet = service:packet(users[1], connection, 3, true)
		eq(packet.Store.Round.Outage.ConnectedPanelCount, 0)
		for _, role in ipairs(packet.Store.Round.Outage.Roles) do
			eq(role.OwnerUserId, false)
			eq(role.Connected, false)
		end
		local delta = service:packet(users[1], connection, 4, false)
		eq(delta.Kind, "Delta")
		eq(delta.Store.Round.Outage.Progress, 0)
	end
	-- S1-A: departing carry restored before selection; survivor tokens/generations survive.
	do
		local _, u, s, _, _, item, leave = fixture(4)
		for index = 1, 3 do eq(item(u[index], "PickUp", index), "OK") end
		local token, generation = u[2].carry.CarryToken, u[2].generation
		leave({ u[1] })
		eq(s.round.order.lines[1].status, "Cancelled"); eq(s.round.order.required, 2)
		eq(u[2].carry.CarryToken, token); eq(u[2].generation, generation)
		eq(item(u[2], "ReturnItem", 2), "OK"); eq(s.round.order.lines[2].status, "Uncollected")
	end
	-- S1-G versus S1-H: equal-time departure precedes general return; earlier return changes selection.
	for _, earlierReturn in ipairs({ false, true }) do
		local _, u, s, _, _, item, leave = fixture(4)
		eq(item(u[2], "PickUp", 2), "OK"); eq(item(u[3], "PickUp", 3), "OK"); eq(item(u[3], "PutDown", 3), "OK")
		if earlierReturn then eq(item(u[2], "ReturnItem", 2), "OK") end
		leave({ u[1] })
		if earlierReturn then eq(s.round.order.lines[2].status, "Cancelled"); eq(s.round.order.lines[1].status, "Uncollected")
		else eq(s.round.order.lines[1].status, "Cancelled"); eq(item(u[2], "ReturnItem", 2), "OK"); eq(s.round.order.lines[2].status, "Uncollected") end
	end
	-- Duplicate pickup / old token and revision cannot duplicate carry or tray.
	do
		local _, u, s, send, _, item = fixture(2)
		local o = s.round.order
		local stale = { OrderId = o.id, LineId = 1, LineRevision = 0, Shelf = "Shelf" .. table.find(s.round.layout, o.lines[1].product) }
		eq(item(u[1], "PickUp", 1), "OK"); u[2].player.near = stale.Shelf
		eq(send(u[2], "PickUp", stale), "STALE_LINE")
		local previous = { OrderId = o.id, LineId = 1, LineRevision = u[1].carry.LineRevision, CarryToken = u[1].carry.CarryToken }
		eq(item(u[1], "ReturnItem", 1), "OK"); eq(item(u[1], "PickUp", 1), "OK")
		eq(send(u[1], "PutDown", previous), "STALE_LINE")
		eq(item(u[1], "PutDown", 1), "OK"); eq(item(u[2], "AcceptLine", 1), "OK"); eq(s.round.success, 1)
	end
	-- Partial accepted lines preserve progress when reducing; no duplicate order success.
	do
		local _, u, s, _, _, item, leave = fixture(4)
		for index = 1, 2 do eq(item(u[index], "PickUp", index), "OK"); eq(item(u[index], "PutDown", index), "OK"); eq(item(u[4], "AcceptLine", index), "OK") end
		leave({ u[3] }); eq(s.round.success, 1); eq(s.round.order, false)
	end
	-- Recovery, duplicate death/disconnect notifications, preserved order, and bounded budget.
	do
		local service, u, s, send, advance, item, leave = fixture(2)
		eq(item(u[2], "PickUp", 1), "OK")
		local orderId = s.round.order.id
		leave({ u[2] }, "Character"); eq(s.Phase, "Recovery"); eq(s.round.order.lines[1].status, "Uncollected")
		leave({ u[2] }, "Disconnect"); eq(u[2].participant, "Reserved"); eq(s.Phase, "Recovery")
		advance(8)
		service:connect({ UserId = 2, DisplayName = "Returned" }); service:characterReady(u[2])
		eq(send(u[2], "SetLoaded", { Loaded = true }), "OK")
		eq(send(u[1], "ResumeReady", { Ready = true }), "OK"); eq(send(u[2], "ResumeReady", { Ready = true }), "OK")
		eq(s.Phase, "Running"); eq(s.round.order.id, orderId); eq(s.round.recoveryBudget, 15)
		leave({ u[2] }, "Disconnect"); advance(23)
		eq(s.round.mode, "Solo"); eq(s.round.recoveryBudget, 0); eq(s.round.order.id, orderId)
	end
	-- Returning player takes survivor role at the same recovery deadline.
	do
		local service, u, s, _, _, _, leave = fixture(2)
		leave({ u[2] }, "Character"); service:characterReady(u[2]); eq(u[2].participant, "Returning")
		local context = {}; service:depart(u[1], "Leave", context); service:selectRecoverySurvivors(context)
		service:tick(23); service:settleDepartures(context, 23)
		eq(s.round.mode, "Solo"); eq(s.round.active[1], 2)
	end
	-- Four-person roles, private answer slices, generation fencing, shared input and timeout support.
	do
		local service, u, s, send, advance = fixture(4)
		service:startOutage(s, 3)
		local x = s.round.outage
		for index, roleId in ipairs(x.roleOrder) do
			u[index].player.near = roleId == "Breaker" and "Breaker" or "SignalPanel"
			eq(send(u[index], "ClaimRole", { OutageId = x.id, RoleId = roleId, Generation = x.roles[roleId].generation }), "OK")
			if roleId ~= "Breaker" then eq(#service:selfState(u[index]).ReadShapes, 1) end
		end
		eq(service:inputReason(u[4], s, 3), "Unshared")
		for index = 1, 3 do eq(send(u[index], "ShareSegment", { OutageId = x.id, RoleId = "Panel" .. index, Generation = u[index].role.Generation }), "OK") end
		eq(service:inputReason(u[4], s, 3), "None")
		local answer = table.clone(x.answer)
		for _, shape in ipairs(answer) do eq(send(u[4], "InputShape", { OutageId = x.id, Generation = u[4].role.Generation, Shape = shape }), "OK") end
		eq(x.resolution, "Coop"); eq(s.round.outageStatus, "Done")
		expect(not service.world.stores.Store01.dark); expect(not service.world.stores.Store02.dark)
		advance(4)
	end
	do
		local service, _, s, _, advance = fixture(2)
		service:startOutage(s, 3); advance(48)
		eq(s.round.outage.resolution, "Support"); eq(s.round.anxiety, 30); expect(s.round.hadSupport)
	end
	-- Full free loop: solo mode, five orders, both scheduled events, result -> fresh lobby.
	do
		local _, u, s, send, advance, item = fixture(1)
		local now = 0
		while s.Phase ~= "Result" do
			if s.round.order then
				eq(item(u[1], "PickUp", 1), "OK"); eq(item(u[1], "PutDown", 1), "OK"); eq(item(u[1], "AcceptLine", 1), "OK")
			elseif s.round.outage and s.round.outage.status == "Active" then
				local x = s.round.outage; u[1].player.near = "Breaker"
				eq(send(u[1], "ClaimRole", { OutageId = x.id, RoleId = "Breaker", Generation = x.roles.Breaker.generation }), "OK")
				for _, shape in ipairs(table.clone(x.answer)) do eq(send(u[1], "InputShape", { OutageId = x.id, Generation = u[1].role.Generation, Shape = shape }), "OK") end
			else now += 3; advance(now) end
			expect(now < 300, "finite solo loop")
		end
		eq(s.result.Code, "AdjustedClose"); eq(s.result.SuccessCount, 5)
		eq(send(u[1], "AcknowledgeResult"), "OK"); eq(s.Phase, "Lobby"); eq(s.RoundId, false); expect(u[1].lastResult ~= false)
	end
	-- Protocol allowlists and team/round fences.
	do
		local service, u, s, send = fixture(2)
		eq(send(u[1], "Signal", { Target = "Counter", Message = "Here", teamID = "Store02" }), "BAD_REQUEST")
		eq(send(u[1], "Signal", { Target = "Counter", Message = "Here" }, nil, { StoreId = "Store02" }), "NOT_MEMBER")
		eq(send(u[1], "SetLoaded", { Loaded = true }, nil, { RoundId = "old" }), "STALE_ROUND")
		eq(send(u[1], "SetLoaded", { Loaded = false }, nil, { RoundId = false, SeatGeneration = u[1].startGeneration }), "OK")
		eq(u[1].loaded, false)
		local connection = Protocol.newConnection(Config, 0)
		for _ = 1, 20 do expect(Protocol.consume(connection, Config, 0)) end
		expect(not Protocol.consume(connection, Config, 0)); expect(Protocol.consume(connection, Config, 0.1))
		local packet = service:packet(u[1], connection, 3, true)
		eq(packet.Store.StoreId, "Store01"); eq(#packet.Stores, 4); eq(packet.ProtocolVersion, 1)
		local serialized = service:storeState(s, u[1], 3)
		eq(serialized.Round.Order.Lines[1].CarryToken, nil)
	end
	-- 72 complete state loops: 1/2/3/4 participants x A/B/C x six initial layouts.
	for count = 1, 4 do
		for scheduleIndex = 1, 3 do
			for layoutIndex = 1, 6 do
				local _, u, s, send, advance, item = fixture(count, scheduleIndex, layoutIndex)
				local now, guard = count == 1 and 0 or 3, 0
				local firstRound = s.RoundId
				while s.Phase ~= "Result" do
					guard += 1; expect(guard < 30, "finite scheduled loop")
					local round = s.round
					if round.order then
						local order = round.order
						for lineId = 1, order.required do
							eq(item(u[lineId], "PickUp", lineId), "OK"); eq(item(u[lineId], "PutDown", lineId), "OK")
							eq(item(u[count], "AcceptLine", lineId), "OK")
						end
					elseif round.outage and round.outage.status == "Active" then
						local x = round.outage
						for index, roleId in ipairs(x.roleOrder) do
							u[index].player.near = roleId == "Breaker" and "Breaker" or "SignalPanel"
							eq(send(u[index], "ClaimRole", { OutageId = x.id, RoleId = roleId, Generation = x.roles[roleId].generation }), "OK")
							if roleId ~= "Breaker" then eq(send(u[index], "ShareSegment", { OutageId = x.id, RoleId = roleId, Generation = u[index].role.Generation }), "OK") end
						end
						for _, shape in ipairs(table.clone(x.answer)) do eq(send(u[count], "InputShape", { OutageId = x.id, Generation = u[count].role.Generation, Shape = shape }), "OK") end
					else now += 3; advance(now) end
				end
				eq(s.result.Code, count == 1 and "AdjustedClose" or "CoopSuccess"); eq(s.result.SuccessCount, 5)
				advance(now + Config.Round.ResultSeconds)
				eq(s.Phase, "Lobby"); eq(s.RoundId, false)
				if count == 1 then eq(send(u[1], "SoloPractice", { RosterVersion = s.RosterVersion }), "OK")
				else
					for _, user in ipairs(u) do eq(send(user, "SetReady", { Ready = true, RosterVersion = s.RosterVersion }), "OK") end
					advance(now + Config.Round.ResultSeconds + Config.Round.StartConfirmSeconds)
				end
				expect(s.RoundId ~= firstRound); expect(s.round.schedule ~= ({ "A", "B", "C" })[scheduleIndex]); expect(s.lastLayout ~= layoutIndex)
			end
		end
	end
	-- Equal-time order timeout must precede reduction completion.
	do
		local service, u, s, _, _, item = fixture(4)
		for lineId = 1, 2 do eq(item(u[lineId], "PickUp", lineId), "OK"); eq(item(u[lineId], "PutDown", lineId), "OK"); eq(item(u[4], "AcceptLine", lineId), "OK") end
		local expiredId = s.round.order.id
		local context = {}; service:depart(u[3], "Leave", context); service:tick(48); service:settleDepartures(context, 48)
		eq(s.round.success, 0); eq(s.round.anxiety, 15); expect(s.round.order.id ~= expiredId); eq(s.round.order.required, 2)
	end
	-- Explicit online solo conversion reclaims demoted carry and keeps the same order.
	do
		local _, u, s, send, advance, item = fixture(2)
		eq(item(u[2], "PickUp", 1), "OK"); local orderId = s.round.order.id
		eq(send(u[1], "RequestSolo"), "OK"); eq(send(u[2], "RequestSolo"), "REQUEST_IN_PROGRESS")
		advance(13); eq(s.round.mode, "Solo"); eq(u[2].participant, "Waiting"); eq(u[2].carry, false)
		eq(s.round.order.id, orderId); eq(s.round.order.lines[1].status, "Uncollected"); expect(s.round.hadReduction)
		eq(send(u[2], "CancelSolo"), "NOT_ACTIVE"); eq(item(u[1], "PickUp", 1), "OK")
	end
	-- Exception injection: outage pauses an existing order and a queued shuffle waits for that order.
	do
		local service, u, s, send, advance, item = fixture(2)
		local orderId = s.round.order.id
		s.round.shuffleStatus = "Active"
		s.round.boundaryKind = "Shuffle"
		s.round.boundary = { left = 3, due = 6 }
		service:startOutage(s, 3)
		service:restoreOutage(s, "Support", 3)
		advance(10)
		eq(s.round.order.id, orderId); eq(s.round.shuffleStatus, "Active"); eq(s.round.boundary.due, false)
		eq(item(u[1], "PickUp", 1), "OK"); eq(item(u[1], "PutDown", 1), "OK"); eq(item(u[2], "AcceptLine", 1), "OK")
		advance(13); eq(s.round.shuffleStatus, "Done"); expect(s.round.order.id ~= orderId)
		eq(send(u[1], "ReturnItem", { OrderId = orderId, LineId = 1, LineRevision = 1, CarryToken = "old" }), "STALE_ORDER")
	end
	-- Bounded cache and malformed scalar payloads.
	do
		local connection = Protocol.newConnection(Config, 0)
		local base = { ProtocolVersion = 1, RequestId = 1, Action = "SetLoaded", StoreId = "Store01", RoundId = false, SeatGeneration = 0, Payload = { Loaded = true } }
		for id = 1, 130 do local request = table.clone(base); request.RequestId = id; Protocol.remember(connection, request, { Code = "OK" }, Config) end
		eq(#connection.order, 128); eq(connection.cache[1], nil); expect(connection.cache[130] ~= nil)
		local bad = table.clone(base); bad.Payload = { Loaded = {} }; eq(select(2, Protocol.validate(bad, Config)), "BAD_REQUEST")
		bad = table.clone(base); bad.RequestId = 0 / 0; eq(select(2, Protocol.validate(bad, Config)), "BAD_REQUEST")
		bad = table.clone(base); bad.RoundId = string.rep("x", 97); eq(select(2, Protocol.validate(bad, Config)), "BAD_REQUEST")
		bad = table.clone(base); bad.teamID = "Store02"; eq(select(2, Protocol.validate(bad, Config)), "BAD_REQUEST")
		expect(Protocol.equal(base, table.clone(base))); bad = table.clone(base); bad.Payload = { Loaded = false }; expect(not Protocol.equal(base, bad))
	end
	print("PURE STATE SIMULATION PASS: " .. checks .. " assertions; 72 full schedule/layout/team loops; Roblox/Studio/network/geometry not executed")
end
