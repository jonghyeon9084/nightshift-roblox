--!strict
local LoadReporter = require("../Modules/LoadReporter")
local n = 0
local function check(value: boolean) n += 1 assert(value, "LoadReporter assertion " .. n) end
local s = LoadReporter.new()
local me: any = {StoreId="Store01", SeatGeneration=4, Loaded=false}
local store: any = {StoreId="Store01", RoundId="r-result"}
check(LoadReporter.poll(s, me, store, true, 0))
LoadReporter.sent(s, 10, 0)
check(not LoadReporter.poll(s, me, store, true, 1))
-- Result -> Lobby: same seat generation, old report rejected STALE_ROUND.
store.RoundId = false
check(LoadReporter.poll(s, me, store, true, 1))
LoadReporter.sent(s, 11, 1)
LoadReporter.ack(s, 10, 1.5) -- old acknowledgement cannot clear current flight
check(s.pendingId == 11)
LoadReporter.ack(s, 11, 2)
check(not LoadReporter.poll(s, me, store, true, 3))
check(LoadReporter.poll(s, me, store, true, 4))
LoadReporter.sent(s, 12, 4)
LoadReporter.ack(s, 12, 5)
check(not LoadReporter.poll(s, me, store, true, 100)) -- bounded even on repeated rejection
LoadReporter.reset(s)
check(LoadReporter.poll(s, me, store, true, 101))
LoadReporter.sent(s, 13, 101)
me.Loaded = true
check(not LoadReporter.poll(s, me, store, true, 102))
check(LoadReporter.poll(s, me, store, false, 102)) -- unload uses a fresh desired context
LoadReporter.sent(s, 14, 102)
check(not LoadReporter.poll(s, me, store, false, 111))
check(not LoadReporter.poll(s, me, store, false, 112)) -- timeout backs off
check(LoadReporter.poll(s, me, store, false, 114))
LoadReporter.sent(s, 15, 114)
check(not LoadReporter.poll(s, me, store, false, 130))
check(not LoadReporter.poll(s, me, store, false, 132)) -- lost responses still bounded
me.SeatGeneration = 5
check(LoadReporter.poll(s, me, store, false, 133))
me.StoreId = false
check(not LoadReporter.poll(s, me, store, false, 134))
check(s.pendingId == false)
print("PASS: " .. n .. " pure load-report race/retry assertions; Studio not executed")
