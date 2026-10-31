-- CLI-only pure state checks. This does not start Roblox or simulate players.
local StateStore = require("../Modules/StateStore")
local checks = 0
local function check(condition, message)
	assert(condition, message)
	checks += 1
end
local function packet(sequence, revision, kind)
	return { ProtocolVersion=1, Kind=kind or "Snapshot", Sequence=sequence, ServerTime=100,
		Self={StoreId="Store01"}, Stores={}, Store={StoreId="Store01", RoundId="r1", Revision=revision} }
end
local state = StateStore.new(1)
local accepted, gap = StateStore.apply(state, packet(1, 5))
check(accepted and not gap and state.HasSnapshot, "initial snapshot")
check(not StateStore.apply(state, packet(1, 5)), "duplicate sequence ignored")
check(not StateStore.apply(state, packet(0, 5)), "older sequence ignored")
accepted, gap = StateStore.apply(state, packet(3, 6, "Delta"))
check(accepted and gap and state.Store.Revision==6, "sequence gap applies new state and requests repair")
local staleAccepted, staleGap = StateStore.apply(state, packet(4, 4, "Delta"))
check(not staleAccepted and staleGap and state.Store.Revision==6, "older store revision rejected")
local nextRound = packet(5, 7)
nextRound.Store.RoundId="r2"
check(StateStore.apply(state, nextRound) and state.Store.RoundId=="r2", "new round keeps monotone revision")
local sampledAt = state.StoreTime
local delta = {ProtocolVersion=1, Kind="Delta", Sequence=6, ServerTime=110, Self={StoreId="Store01"}}
check(StateStore.apply(state, delta) and state.StoreTime==sampledAt, "self-only delta preserves store timer sample")
check(StateStore.remaining({Remaining=30, Running=true}, sampledAt, 115)==15, "running timer extrapolation")
check(StateStore.remaining({Remaining=30, Running=false}, sampledAt, 115)==30, "paused timer stays frozen")
check(StateStore.remaining({Remaining=3, Running=true}, sampledAt, 115)==0, "expired timer clamps at zero")
check(StateStore.remaining({Remaining=3, Running=true}, sampledAt, 99)==3, "clock adjustment never adds time")
local wrong = packet(7, 8)
wrong.ProtocolVersion=2
check(not StateStore.apply(state, wrong), "version mismatch")
local missingSlice = packet(7, 8)
missingSlice.Stores=nil
check(not StateStore.apply(state, missingSlice), "snapshot requires all slices")
local mismatch = packet(7, 8)
mismatch.Store.StoreId="Store02"
check(not StateStore.apply(state, mismatch), "cross-store detail rejected")
check(StateStore.apply(state, {ProtocolVersion=1, Kind="Snapshot", Sequence=8, ServerTime=120,
	Self={StoreId=false}, Stores={}, Store=false}) and state.Store==false, "explicit false clears store")
local fresh = StateStore.new(1)
accepted, gap=StateStore.apply(fresh, packet(20, 1, "Delta"))
check(accepted and gap and not fresh.HasSnapshot, "first delta requests snapshot")
print("PASS: " .. checks .. " pure reducer assertions; Roblox/Studio not executed")
