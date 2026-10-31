--!nonstrict
-- Server-only integration boundary. NPC/Traffic modules register a registry validator
-- and a non-yielding tick. They submit economic commands to Main, never mutate ledgers.
local Bridge={}
function Bridge.configure(host) Bridge.host=host end
function Bridge.registerNPC(authority,tick)
	assert(Bridge.host and type(authority.validate)=="function" and type(tick)=="function")
	Bridge.host.npcAuthority=authority; Bridge.host.npcTick=tick
end
function Bridge.registerTraffic(authority,tick,snapshot)
	assert(Bridge.host and type(authority.validate)=="function" and type(tick)=="function")
	Bridge.host.collisionAuthority=authority; Bridge.host.trafficTick=tick; Bridge.host.trafficSnapshot=snapshot
end
function Bridge.contexts() return Bridge.host and Bridge.host.contexts() or {} end
function Bridge.activityPlan(userId) return Bridge.host and Bridge.host.activityPlan(userId) or false end
function Bridge.npcInventory(userId) return Bridge.host and Bridge.host.npcInventory(userId) or {} end
-- Atomic grant MUST reserve occupancy until releaseCrossing; absent traffic denies entry.
function Bridge.registerPedestrianTraffic(adapter)
	assert(Bridge.host and type(adapter.requestCrossing)=="function" and type(adapter.releaseCrossing)=="function")
	Bridge.host.pedestrianTraffic=adapter
end
function Bridge.pedestrianTraffic() return Bridge.host and Bridge.host.pedestrianTraffic end
function Bridge.submit(kind,context,payload,callback)
	assert(Bridge.host,"NightShift Main not configured")
	assert(table.find({"EndNpcVisit","SelectNpcItems","CancelNpcSelection","CommitNpcSale","ForceDrop","OfferOpportunity","ObserveOpportunity"},kind),"Unknown server command")
	Bridge.host.enqueue(kind,context,payload,callback)
end
return Bridge
