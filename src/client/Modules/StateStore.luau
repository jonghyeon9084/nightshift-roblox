--!strict
-- Pure wire-state reducer. Slices carry their own packet time so partial
-- deltas never restart a timer that belongs to an unchanged Store slice.
local StateStore = {}

function StateStore.new(version: number)
	return { Version = version, Sequence = 0, Self = false, Stores = {}, Store = false,
		StoreTime = 0, HasSnapshot = false, Revisions = {} }
end

function StateStore.apply(state: any, packet: any): (boolean, boolean, string?)
	if type(packet) ~= "table" or packet.ProtocolVersion ~= state.Version then
		return false, false, "VERSION_MISMATCH"
	end
	if type(packet.Sequence) ~= "number" or packet.Sequence % 1 ~= 0
		or packet.Sequence <= state.Sequence or type(packet.ServerTime) ~= "number" then
		return false, false, "STALE_PACKET"
	end
	if packet.Kind ~= "Snapshot" and packet.Kind ~= "Delta" then return false, false, "BAD_PACKET" end
	if packet.Kind == "Snapshot" and (type(packet.Self) ~= "table"
		or type(packet.Stores) ~= "table" or packet.Store == nil) then
		return false, false, "BAD_PACKET"
	end
	local gap = (state.Sequence > 0 and packet.Sequence > state.Sequence + 1)
		or (not state.HasSnapshot and packet.Kind == "Delta")
	local nextSelf = if packet.Self ~= nil then packet.Self else state.Self
	local nextStore = if packet.Store ~= nil then packet.Store else state.Store
	if nextStore ~= false then
		if type(nextStore) ~= "table" or type(nextStore.Revision) ~= "number" then
			return false, true, "BAD_PACKET"
		end
		if nextSelf == false or nextSelf.StoreId ~= nextStore.StoreId then
			return false, true, "STORE_MISMATCH"
		end
		local previous = state.Revisions[nextStore.StoreId]
		if previous and nextStore.Revision < previous then return false, true, "STALE_REVISION" end
		state.Revisions[nextStore.StoreId] = nextStore.Revision
	end
	state.Sequence = packet.Sequence
	if packet.Self ~= nil then state.Self = packet.Self end
	if packet.Stores ~= nil then state.Stores = packet.Stores end
	if packet.Store ~= nil then
		state.Store = packet.Store
		state.StoreTime = packet.ServerTime
	end
	if packet.Kind == "Snapshot" then state.HasSnapshot = true end
	return true, gap, nil
end

function StateStore.remaining(timer: any, sampledAt: number, now: number): number
	if type(timer) ~= "table" or type(timer.Remaining) ~= "number" then return 0 end
	return math.max(0, timer.Remaining - (if timer.Running then math.max(0, now - sampledAt) else 0))
end

return StateStore
