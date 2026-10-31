--!strict
-- Schedule/engine ownership only. Commerce owns items, money, theft and permissions.
-- All methods and injected engine methods must run without yielding in Main's queue.
local DeliveryService = {}
DeliveryService.__index = DeliveryService

export type DeliveryEvent = {
	EventId: string, OrderId: string, StoreId: string, RoundId: string,
	Kind: string, At: number,
}
export type DeliveryView = {
	OrderId: string, StoreId: string, RoundId: string, State: string,
	ArriveAt: number | boolean, RecallAt: number | boolean,
}

local function copy(value: any): any
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in pairs(value) do result[key] = copy(child) end
	return result
end

local function result(ok: boolean, code: string, value: any?): any
	return { Ok = ok, Code = code, Value = if value == nil then false else copy(value) }
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function id(value: any, limit: number): boolean
	return type(value) == "string" and #value > 0 and #value <= limit
end

local function viewOf(record: any): DeliveryView
	return {
		OrderId = record.Order.OrderId, StoreId = record.Order.StoreId,
		RoundId = record.Order.RoundId, State = record.State,
		ArriveAt = record.ArriveAt, RecallAt = record.RecallAt,
	}
end

function DeliveryService.new(deps: any): any
	assert(type(deps) == "table" and type(deps.Now) == "function", "Now required")
	assert(type(deps.Engine) == "table", "LogisticsEngine required")
	for _, name in ipairs({ "createTruck", "moveTruck", "destroyTruck" }) do
		assert(type(deps.Engine[name]) == "function", name .. " required")
	end
	local config = copy(deps.Config)
	assert(type(config) == "table" and config.Delivery.MaxTrucksPerStore == 1, "one truck per store required")
	for _, seconds in ipairs({ config.Wholesale.ReservationSeconds, config.Delivery.TravelSeconds,
		config.Delivery.DockSeconds, config.Delivery.ExitSeconds }) do
		assert(finite(seconds) and seconds > 0, "positive delivery duration required")
	end
	return setmetatable({
		Config = config, Now = deps.Now, Engine = deps.Engine,
		Orders = {}, Queue = {}, Occupied = {}, Closed = {}, LastTick = -math.huge,
	}, DeliveryService)
end

local function eventFor(record: any, kind: string, now: number): DeliveryEvent
	-- Order IDs are globally unique server IDs. Each kind occurs at most once.
	local prior = record.Events[kind]
	if prior then return prior end
	local event: DeliveryEvent = {
		EventId = record.Order.OrderId .. ":Delivery:" .. kind,
		OrderId = record.Order.OrderId, StoreId = record.Order.StoreId,
		RoundId = record.Order.RoundId, Kind = kind, At = now,
	}
	record.Events[kind] = event
	return event
end

local function engine(self: any, method: string, ...: any): boolean
	local ok, response = pcall(self.Engine[method], self.Engine, ...)
	return ok and type(response) == "table" and response.Ok == true
end

local function destroy(self: any, record: any): boolean
	if not record.HasTruck then return true end
	if not engine(self, "destroyTruck", record.Order.OrderId) then return false end
	record.HasTruck = false
	if self.Occupied[record.Order.StoreId] == record.Order.OrderId then
		self.Occupied[record.Order.StoreId] = nil
	end
	return true
end

local function fail(self: any, record: any, now: number, events: any)
	record.State = "Recalled" -- Failed is an event, not an OrderState enum.
	record.CleanupOnly = true
	table.insert(events, copy(eventFor(record, "Failed", now)))
	-- A failed create may have partially created a physical truck. Never reuse
	-- the store lane until idempotent destruction is acknowledged.
	destroy(self, record)
end

function DeliveryService.register(self: any, order: any): any
	local c = self.Config
	if type(order) ~= "table" then return result(false, "BAD_REQUEST") end
	local allowed = { OrderId = true, StoreId = true, RoundId = true, Sku = true,
		Quantity = true, UnitCost = true, ReservedAt = true }
	for key in pairs(order) do
		if not allowed[key] then return result(false, "BAD_REQUEST") end
	end
	local limit = c.Network.MaxStringBytes
	if not id(order.OrderId, limit) or not id(order.StoreId, limit) or not id(order.RoundId, limit)
		or not id(order.Sku, limit) or not c.World.Stores[order.StoreId] or not c.Products[order.Sku]
		or not finite(order.Quantity) or order.Quantity % 1 ~= 0 or order.Quantity < 1
		or order.Quantity > c.Wholesale.MaxUnitsPerOrder
		or not finite(order.UnitCost) or order.UnitCost % 1 ~= 0 or order.UnitCost < 0
		or order.UnitCost > c.Economy.MaxCurrency
		or not finite(order.ReservedAt) or order.ReservedAt < 0 then
		return result(false, "BAD_REQUEST")
	end
	local prior = self.Orders[order.OrderId]
	if prior then
		for key in pairs(allowed) do
			if prior.Order[key] ~= order[key] then return result(false, "INVALID_STATE") end
		end
		return result(true, "OK", viewOf(prior))
	end
	if self.Closed[order.StoreId] and self.Closed[order.StoreId][order.RoundId] then
		return result(false, "INVALID_STATE")
	end
	local record = {
		Order = copy(order), State = "Reserved", ArriveAt = false, RecallAt = false,
		DispatchAt = false, ExitAt = false, HasTruck = false, CleanupOnly = false, Events = {},
	}
	self.Orders[order.OrderId] = record
	table.insert(self.Queue, order.OrderId)
	return result(true, "OK", viewOf(record))
end

function DeliveryService.cancel(self: any, orderId: any): any
	local record = self.Orders[orderId]
	if not record then return result(false, "NOT_FOUND") end
	if record.State == "Cancelled" then return result(true, "OK", record.Events.Cancelled) end
	if record.State ~= "Reserved" then return result(false, "INVALID_STATE") end
	record.State = "Cancelled"
	return result(true, "OK", eventFor(record, "Cancelled", self.Now()))
end

function DeliveryService.complete(self: any, orderId: any): any
	local record = self.Orders[orderId]
	if not record then return result(false, "NOT_FOUND") end
	if record.State == "Completed" then return result(true, "OK", viewOf(record)) end
	local now = self.Now()
	if record.State ~= "Docked" or now >= record.RecallAt then
		return result(false, "INVALID_STATE")
	end
	record.State = "Completed"
	record.ExitAt = now
	return result(true, "OK", viewOf(record))
end

function DeliveryService.closeStore(self: any, storeId: string, roundId: string): {DeliveryEvent}
	local closed = self.Closed[storeId]
	if closed and closed[roundId] then return copy(closed[roundId]) end
	local events = {}
	local now = self.Now()
	for _, orderId in ipairs(self.Queue) do
		local record = self.Orders[orderId]
		if record.Order.StoreId == storeId and record.Order.RoundId == roundId then
			if record.State == "Reserved" then
				record.State = "Cancelled"
				table.insert(events, copy(eventFor(record, "Cancelled", now)))
			elseif record.State == "InTransit" or record.State == "Docked" then
				record.State = "Recalled"
				-- A truck still approaching has no dock pose; destroy rather than
				-- teleport it to the dock to animate an exit.
				if not record.RecallAt then record.CleanupOnly = true end
				record.ExitAt = now
				table.insert(events, copy(eventFor(record, "Recall", now)))
			end
		end
	end
	if not closed then closed = {}; self.Closed[storeId] = closed end
	closed[roundId] = copy(events)
	return copy(events)
end

function DeliveryService.tick(self: any, now: number): {DeliveryEvent}
	assert(finite(now) and now >= 0 and now >= self.LastTick, "monotonic server time required")
	self.LastTick = now
	local events = {}
	local c = self.Config
	-- First retire old trucks, so a following reservation cannot overlap even
	-- when its registration order differs from its predecessor's end time.
	for _, orderId in ipairs(self.Queue) do
		local r = self.Orders[orderId]
		if r.State == "Docked" and now >= r.RecallAt then
			r.State = "Recalled"; r.ExitAt = now
			table.insert(events, copy(eventFor(r, "Recall", now)))
		end
		if r.HasTruck and (r.State == "Completed" or r.State == "Recalled") then
			if r.CleanupOnly then
				destroy(self, r)
			else
				local alpha = math.clamp((now - r.ExitAt) / c.Delivery.ExitSeconds, 0, 1)
				if not engine(self, "moveTruck", orderId, "DockToExit", alpha) then
					-- A terminal truck cannot generate a second refund event.
					r.CleanupOnly = true
					destroy(self, r)
				elseif alpha >= 1 then
					destroy(self, r)
				end
			end
		end
	end
	for _, orderId in ipairs(self.Queue) do
		local r = self.Orders[orderId]
		local storeId = r.Order.StoreId
		if r.State == "Reserved" and now >= r.Order.ReservedAt + c.Wholesale.ReservationSeconds
			and not self.Occupied[storeId] then
			self.Occupied[storeId] = orderId
			r.HasTruck = true
			if engine(self, "createTruck", orderId, storeId) then
				r.State = "InTransit"; r.DispatchAt = now
				r.ArriveAt = now + c.Delivery.TravelSeconds
				table.insert(events, copy(eventFor(r, "Dispatched", now)))
			else
				fail(self, r, now, events)
			end
		end
		if r.State == "InTransit" then
			local alpha = math.clamp((now - r.DispatchAt) / c.Delivery.TravelSeconds, 0, 1)
			if not engine(self, "moveTruck", orderId, "ApproachToDock", alpha) then
				fail(self, r, now, events)
			elseif alpha >= 1 then
				r.State = "Docked"; r.RecallAt = now + c.Delivery.DockSeconds
				table.insert(events, copy(eventFor(r, "Arrived", now)))
			end
		end
	end
	return events
end

function DeliveryService.view(self: any, storeId: string): {DeliveryView}
	local views = {}
	for _, orderId in ipairs(self.Queue) do
		local r = self.Orders[orderId]
		if r.Order.StoreId == storeId then table.insert(views, viewOf(r)) end
	end
	return views
end

return DeliveryService
