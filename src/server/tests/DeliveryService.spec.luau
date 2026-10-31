--!strict
-- Run with the local Luau CLI; no Roblox engine, cloud, or other worker module.
local Delivery = require("../Modules/DeliveryService")
local Config = require("../../shared/CommerceConfig")

local function eq(actual: any, expected: any)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function fixture(): any
	local f: any = { Time = 0, Calls = {}, Trucks = {}, Fail = {}, Throws = {} }
	local engine: any = {}
	local function call(method: string, orderId: string, arg: any?, alpha: number?): any
		table.insert(f.Calls, { method, orderId, arg, alpha })
		if f.Throws[method] then error("injected engine error") end
		if f.Fail[method] then return { Ok = false, Code = "DELIVERY_FAILED", Value = false } end
		return { Ok = true, Code = "OK", Value = false }
	end
	function engine:createTruck(orderId: string, storeId: string): any
		-- Simulates partial physical creation even when an acknowledgement fails.
		f.Trucks[orderId] = storeId
		return call("create", orderId, storeId)
	end
	function engine:moveTruck(orderId: string, segment: string, alpha: number): any
		assert(f.Trucks[orderId], "cannot move missing truck")
		assert(alpha >= 0 and alpha <= 1, "unclamped movement")
		return call("move", orderId, segment, alpha)
	end
	function engine:destroyTruck(orderId: string): any
		local response = call("destroy", orderId)
		if response.Ok then f.Trucks[orderId] = nil end
		return response
	end
	f.Service = Delivery.new({ Config = Config, Now = function() return f.Time end, Engine = engine })
	function f:tick(time: number): any
		self.Time = time
		return self.Service:tick(time)
	end
	function f:order(orderId: string, storeId: string?, roundId: string?): any
		return { OrderId = orderId, StoreId = storeId or "Store01", RoundId = roundId or "r1",
			Sku = "Water", Quantity = 2, UnitCost = 4, ReservedAt = 0 }
	end
	function f:register(orderId: string, storeId: string?, roundId: string?): any
		local response = self.Service:register(self:order(orderId, storeId, roundId))
		assert(response.Ok, response.Code)
		return response
	end
	return f
end

local tests: { { any } } = {}
local function test(name: string, run: () -> ()) table.insert(tests, { name, run }) end

test("registration is schedule only and duplicate body is idempotent", function()
	local f = fixture()
	local order = f:order("a")
	eq(f.Service:register(order).Ok, true)
	order.Quantity = 4
	eq(f.Service:register(order).Code, "INVALID_STATE")
	eq(f.Service:register(f:order("a")).Ok, true)
	eq(#f.Service:view("Store01"), 1)
	eq(#f.Calls, 0)
end)

test("untrusted malformed schedule cannot enter queue", function()
	local f = fixture()
	for _, field in ipairs({ "Quantity", "UnitCost", "ReservedAt" }) do
		for _, value in ipairs({ -1, math.huge, 0 / 0 }) do
			local order = f:order("a"); order[field] = value
			eq(f.Service:register(order).Code, "BAD_REQUEST")
		end
	end
	for _, change in ipairs({ { "Quantity", 0 }, { "Quantity", 5 }, { "Quantity", 1.5 },
		{ "StoreId", "foreign" }, { "Sku", "foreign" }, { "OrderId", "" }, { "extra", true } }) do
		local order = f:order("a"); order[change[1]] = change[2]
		eq(f.Service:register(order).Code, "BAD_REQUEST")
	end
	eq(#f.Service:view("Store01"), 0)
end)

test("fake clock dispatch arrival recall and exit have exact boundaries", function()
	local f = fixture(); f:register("a")
	eq(#f:tick(4.999), 0)
	local dispatched = f:tick(5)
	eq(#dispatched, 1); eq(dispatched[1].Kind, "Dispatched"); eq(dispatched[1].At, 5)
	eq(f.Service:view("Store01")[1].ArriveAt, 17)
	eq(#f:tick(16.999), 0)
	local arrived = f:tick(17)
	eq(#arrived, 1); eq(arrived[1].Kind, "Arrived"); eq(arrived[1].At, 17)
	eq(f.Service:view("Store01")[1].RecallAt, 92)
	eq(#f:tick(91.999), 0)
	local recalled = f:tick(92)
	eq(#recalled, 1); eq(recalled[1].Kind, "Recall")
	eq(f.Service:view("Store01")[1].State, "Recalled")
	eq(#f:tick(95), 0); eq(f.Trucks.a, nil)
	eq(#f:tick(100), 0)
end)

test("same tick never reissues transition event", function()
	local f = fixture(); f:register("a")
	eq(#f:tick(5), 1); eq(#f:tick(5), 0)
	eq(#f:tick(17), 1); eq(#f:tick(17), 0)
	eq(#f:tick(92), 1); eq(#f:tick(92), 0)
end)

test("one store one physical truck and FIFO queued reservation remains cancellable", function()
	local f = fixture(); f:register("a"); f:register("b"); f:register("c")
	eq(#f:tick(5), 1)
	eq(f.Service:view("Store01")[2].State, "Reserved")
	eq(f.Service:cancel("c").Ok, true)
	f:tick(17)
	eq(f.Service:complete("a").Ok, true)
	eq(#f:tick(19.999), 0)
	local events = f:tick(20)
	eq(#events, 1); eq(events[1].OrderId, "b"); eq(events[1].Kind, "Dispatched")
	eq(f.Trucks.a, nil); eq(f.Trucks.b, "Store01"); eq(f.Trucks.c, nil)
end)

test("eight store lanes dispatch independently", function()
	local f = fixture()
	for index, store in ipairs(Config.World.StoreIds) do f:register("o" .. index, store) end
	eq(#f:tick(5), 8)
	eq(#f:tick(17), 8)
end)

test("cancel response is copied stable event and never appears as late tick event", function()
	local f = fixture(); f:register("a")
	local response = f.Service:cancel("a")
	eq(response.Value.Kind, "Cancelled")
	local eventId = response.Value.EventId
	response.Value.EventId = "tampered"; response.Value.At = 999
	local again = f.Service:cancel("a")
	eq(again.Value.EventId, eventId); eq(again.Value.At, 0)
	eq(#f:tick(1000), 0); eq(#f.Calls, 0)
	eq(f.Service:complete("a").Code, "INVALID_STATE")
	eq(f.Service:cancel("missing").Code, "NOT_FOUND")
end)

test("cancel loses once dispatch committed", function()
	local f = fixture(); f:register("a"); f:tick(5)
	eq(f.Service:cancel("a").Code, "INVALID_STATE")
	eq(f.Service:view("Store01")[1].State, "InTransit")
end)

test("completion is docked only idempotent and exits without refund event", function()
	local f = fixture(); f:register("a")
	eq(f.Service:complete("a").Code, "INVALID_STATE")
	f:tick(5); eq(f.Service:complete("a").Code, "INVALID_STATE")
	f:tick(17); eq(f.Service:complete("a").Ok, true)
	f.Time = 18; eq(f.Service:complete("a").Ok, true)
	eq(#f:tick(20), 0); eq(f.Trucks.a, nil)
	eq(#f:tick(100), 0); eq(f.Service:view("Store01")[1].State, "Completed")
end)

test("recall boundary rejects late completion before tick and tick emits recall", function()
	local f = fixture(); f:register("a"); f:tick(5); f:tick(17)
	f.Time = 92
	eq(f.Service:complete("a").Code, "INVALID_STATE")
	eq(f:tick(92)[1].Kind, "Recall")
	eq(f.Service:complete("a").Code, "INVALID_STATE")
end)

test("close returns same original body and scopes by store and round", function()
	local f = fixture(); f:register("a"); f:register("b"); f:register("c", "Store02")
	f:register("d", "Store01", "r2"); f:tick(5)
	local events = f.Service:closeStore("Store01", "r1")
	eq(#events, 2); eq(events[1].Kind, "Recall"); eq(events[2].Kind, "Cancelled")
	local eventId = events[1].EventId
	events[1].EventId = "tampered"; table.remove(events)
	f.Time = 6
	local repeatEvents = f.Service:closeStore("Store01", "r1")
	eq(#repeatEvents, 2); eq(repeatEvents[1].EventId, eventId); eq(repeatEvents[1].At, 5)
	eq(f.Service:register(f:order("late")).Code, "INVALID_STATE")
	local tickEvents = f:tick(6)
	eq(#tickEvents, 1); eq(tickEvents[1].OrderId, "d")
	eq(f.Service:view("Store02")[1].State, "InTransit")
end)

test("close while docked exits and repeated close after tick preserves event", function()
	local f = fixture(); f:register("a"); f:tick(5); f:tick(17)
	local e = f.Service:closeStore("Store01", "r1")[1]
	eq(e.Kind, "Recall")
	eq(#f:tick(20), 0); eq(f.Trucks.a, nil)
	eq(f.Service:closeStore("Store01", "r1")[1].EventId, e.EventId)
end)

test("closing after natural recall or cancellation emits nothing new", function()
	local f = fixture(); f:register("a"); f:register("b")
	f.Service:cancel("b"); f:tick(5); f:tick(17); f:tick(92)
	eq(#f.Service:closeStore("Store01", "r1"), 0)
end)

test("create failure is one Failed event with no phantom dispatch", function()
	local f = fixture(); f:register("a"); f.Fail.create = true
	local events = f:tick(5)
	eq(#events, 1); eq(events[1].Kind, "Failed")
	eq(f.Trucks.a, nil); eq(#f:tick(100), 0)
	eq(f.Service:view("Store01")[1].State, "Recalled")
end)

test("movement throw becomes one Failed event before arrival", function()
	local f = fixture(); f:register("a"); f:tick(5)
	f.Throws.move = true
	local events = f:tick(17)
	eq(#events, 1); eq(events[1].Kind, "Failed")
	eq(f.Trucks.a, nil); eq(#f:tick(92), 0)
end)

test("failed cleanup blocks next truck until acknowledged", function()
	local f = fixture(); f:register("a"); f:register("b")
	f.Fail.create = true; f.Fail.destroy = true
	eq(#f:tick(5), 1)
	f.Fail.create = nil
	eq(#f:tick(6), 0); eq(f.Trucks.b, nil)
	f.Fail.destroy = nil
	local events = f:tick(7)
	eq(#events, 1); eq(events[1].OrderId, "b"); eq(f.Trucks.a, nil)
end)

test("completed exit failure never becomes a refund event", function()
	local f = fixture(); f:register("a"); f:register("b"); f:tick(5); f:tick(17)
	f.Service:complete("a"); f.Fail.move = true; f.Fail.destroy = true
	eq(#f:tick(18), 0); eq(f.Trucks.b, nil)
	f.Fail.move = nil; f.Fail.destroy = nil
	local events = f:tick(19)
	eq(#events, 1); eq(events[1].OrderId, "b"); eq(events[1].Kind, "Dispatched")
	eq(f.Service:view("Store01")[1].State, "Completed")
end)

test("failed destruction at exit retries without repeating settlement", function()
	local f = fixture(); f:register("a"); f:register("b"); f:tick(5); f:tick(17)
	eq(f:tick(92)[1].Kind, "Recall")
	f.Fail.destroy = true
	eq(#f:tick(95), 0); eq(f.Trucks.b, nil)
	f.Fail.destroy = nil
	eq(f:tick(96)[1].OrderId, "b")
end)

test("large tick jump gives full dwell after actual dock confirmation", function()
	local f = fixture(); f:register("a")
	eq(f:tick(100)[1].Kind, "Dispatched")
	local events = f:tick(1000)
	eq(#events, 1); eq(events[1].Kind, "Arrived"); eq(events[1].At, 1000)
	eq(f.Service:view("Store01")[1].RecallAt, 1075)
end)

test("view mutation cannot edit schedule or leak commercial fields", function()
	local f = fixture(); local response = f:register("a")
	response.Value.State = "Completed"
	local views = f.Service:view("Store01")
	eq(views[1].State, "Reserved"); eq(views[1].Quantity, nil); eq(views[1].UnitCost, nil)
	views[1].State = "Completed"; views[1].OrderId = "tampered"
	eq(f.Service:view("Store01")[1].OrderId, "a")
	eq(f:tick(5)[1].Kind, "Dispatched")
end)

test("backward invalid clock fails before mutation", function()
	local f = fixture(); f:register("a"); f:tick(5)
	for _, time in ipairs({ 4, math.huge, 0 / 0 }) do
		local ok = pcall(function() f.Service:tick(time) end)
		eq(ok, false)
	end
	eq(f.Service:view("Store01")[1].State, "InTransit")
end)

for _, entry in ipairs(tests) do
	local ok, failure = pcall(entry[2])
	assert(ok, entry[1] .. ": " .. tostring(failure))
	print("PASS " .. entry[1])
end
print("DeliveryService: " .. #tests .. "/" .. #tests .. " passed (fake clock/engine, no Studio)")
