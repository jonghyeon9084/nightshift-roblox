--!strict
-- Bounded acknowledgement/reconciliation; a round change is a new report context.
local LoadReporter = {}
function LoadReporter.new()
	return { key = "", attempts = 0, nextAt = 0, pendingId = false, sentAt = 0 }
end
function LoadReporter.reset(state: any)
	state.key = ""
	state.pendingId = false
end
function LoadReporter.poll(state: any, me: any, store: any, desired: boolean, now: number): boolean
	if not me or not me.StoreId or not store or me.StoreId ~= store.StoreId then
		LoadReporter.reset(state)
		return false
	end
	local key = table.concat({me.StoreId, tostring(store.RoundId), tostring(me.SeatGeneration), tostring(desired)}, ":")
	if key ~= state.key then
		state.key, state.attempts, state.nextAt, state.pendingId = key, 0, 0, false
	end
	if me.Loaded == desired then return false end
	if state.pendingId then
		if now - state.sentAt < 10 then return false end
		state.pendingId = false
		state.nextAt = now + 2
	end
	return state.attempts < 2 and now >= state.nextAt
end
function LoadReporter.sent(state: any, id: number, now: number)
	state.pendingId, state.sentAt = id, now
	state.attempts += 1
	state.nextAt = now + 2
end
function LoadReporter.ack(state: any, id: number, now: number)
	if state.pendingId ~= id then return end
	state.pendingId = false
	state.nextAt = now + 2
end
return LoadReporter
