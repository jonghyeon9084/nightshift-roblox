--!nonstrict
-- Only these scalar fields may cross the client -> server boundary.
local Protocol = {}
local schemas = {
	JoinStore = {}, LeaveStore = {}, TravelToEntry = {}, Reposition = {},
	SetLoaded = { Loaded = "boolean" }, SetReady = { Ready = "boolean", RosterVersion = "integer" },
	SoloPractice = { RosterVersion = "integer" }, ResumeReady = { Ready = "boolean" },
	FinishSolo = {}, RequestSolo = {}, CancelSolo = {}, AcknowledgeResult = {},
	PickUp = { OrderId = "id", LineId = "line", LineRevision = "integer", Shelf = "shelf" },
	PutDown = { OrderId = "id", LineId = "line", LineRevision = "integer", CarryToken = "id" },
	ReturnItem = { OrderId = "id", LineId = "line", LineRevision = "integer", CarryToken = "id" },
	AcceptLine = { OrderId = "id", LineId = "line", LineRevision = "integer" },
	ClaimRole = { OutageId = "id", RoleId = "role", Generation = "integer" },
	ReleaseRole = { OutageId = "id", RoleId = "role", Generation = "integer" },
	RenewRole = { OutageId = "id", RoleId = "role", Generation = "integer" },
	ShareSegment = { OutageId = "id", RoleId = "role", Generation = "integer" },
	InputShape = { OutageId = "id", Generation = "integer", Shape = "shape" },
	Signal = { Target = "marker", Message = "message" },
}
local enums = {
	shelf = { Shelf1 = true, Shelf2 = true, Shelf3 = true },
	role = { Panel1 = true, Panel2 = true, Panel3 = true, Breaker = true },
	shape = { Circle = true, Triangle = true, Square = true },
	marker = { Counter = true, Shelf1 = true, Shelf2 = true, Shelf3 = true, SignalPanel = true, Breaker = true },
	message = { Here = true, PanelHelp = true, BreakerHelp = true },
}
local top = { ProtocolVersion = true, RequestId = true, Action = true, StoreId = true, RoundId = true, SeatGeneration = true, Payload = true }
function Protocol.integer(v, max)
	return type(v) == "number" and v == v and v >= 0 and v <= (max or 2147483647) and v % 1 == 0
end
local function id(v, config)
	return type(v) == "string" and #v > 0 and #v <= config.Network.MaxStringBytes
end
function Protocol.validate(raw, config)
	if type(raw) ~= "table" then return nil, "BAD_REQUEST" end
	local count = 0
	for key in pairs(raw) do
		count += 1
		if count > 7 or not top[key] then return nil, "BAD_REQUEST" end
	end
	if count ~= 7 or not Protocol.integer(raw.RequestId, config.Network.MaxRequestId) or raw.RequestId < 1
		or not Protocol.integer(raw.ProtocolVersion) then return nil, "BAD_REQUEST" end
	if raw.ProtocolVersion ~= config.ProtocolVersion then return nil, "VERSION_MISMATCH" end
	if not id(raw.Action, config) or not schemas[raw.Action]
		or not (raw.StoreId == false or (id(raw.StoreId, config) and config.World.Stores[raw.StoreId]))
		or not (raw.RoundId == false or id(raw.RoundId, config))
		or not Protocol.integer(raw.SeatGeneration) or type(raw.Payload) ~= "table" then return nil, "BAD_REQUEST" end
	local schema, payload = schemas[raw.Action], {}
	count = 0
	for key, value in pairs(raw.Payload) do
		count += 1
		local kind = schema[key]
		if count > config.Network.MaxPayloadFields or not kind then return nil, "BAD_REQUEST" end
		local valid = false
		if kind == "boolean" then valid = type(value) == "boolean"
		elseif kind == "integer" then valid = Protocol.integer(value)
		elseif kind == "line" then valid = Protocol.integer(value, config.Order.MaxLines) and value >= 1
		elseif kind == "id" then valid = id(value, config)
		else valid = id(value, config) and enums[kind][value] == true end
		if not valid then return nil, "BAD_REQUEST" end
		payload[key] = value
	end
	for key in pairs(schema) do if payload[key] == nil then return nil, "BAD_REQUEST" end end
	local request = table.clone(raw)
	request.Payload = payload
	return request, "OK"
end
function Protocol.equal(a, b)
	for key in pairs(top) do
		if key ~= "Payload" and a[key] ~= b[key] then return false end
	end
	for key, value in pairs(a.Payload) do if b.Payload[key] ~= value then return false end end
	for key, value in pairs(b.Payload) do if a.Payload[key] ~= value then return false end end
	return true
end
function Protocol.newConnection(config, now)
	return { tokens = config.Network.ActionBurst, tokenAt = now, high = 0, cache = {}, order = {}, pending = {},
		sequence = 0, snapshotAt = -math.huge, rateReplyAt = -math.huge, rejected = 0, lastSend = -math.huge,
		selfRevision = -1, storeRevision = -1, summaryRevision = -1, storeId = false, lastTimer = -math.huge }
end
function Protocol.consume(connection, config, now)
	connection.tokens = math.min(config.Network.ActionBurst, connection.tokens + math.max(0, now - connection.tokenAt) * config.Network.ActionRate)
	connection.tokenAt = now
	if connection.tokens < 1 then connection.rejected += 1; return false end
	connection.tokens -= 1
	return true
end
function Protocol.remember(connection, request, ack, config)
	connection.pending[request.RequestId] = nil
	connection.cache[request.RequestId] = { request = request, ack = ack }
	table.insert(connection.order, request.RequestId)
	if #connection.order > config.Network.RequestCacheSize then
		connection.cache[table.remove(connection.order, 1)] = nil
	end
end
function Protocol.validSnapshot(raw, config)
	if type(raw) ~= "table" then return "BAD_REQUEST" end
	local count = 0
	for key in pairs(raw) do count += 1; if count > 1 or key ~= "ProtocolVersion" then return "BAD_REQUEST" end end
	if not Protocol.integer(raw.ProtocolVersion) then return "BAD_REQUEST" end
	return raw.ProtocolVersion == config.ProtocolVersion and "OK" or "VERSION_MISMATCH"
end
return Protocol
