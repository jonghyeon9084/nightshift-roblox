--!nonstrict
-- Only Main's economic queue calls assign/release. No network or storage IO.
local Ownership = {}; Ownership.__index=Ownership
function Ownership.new(config, profiles, restore, world)
	return setmetatable({config=config,profiles=profiles,restore=restore,world=world,owners={},slots={},generation=0},Ownership)
end
function Ownership:assignOwner(player,epoch)
	local id=player.UserId; local current=self.owners[id]
	if current then
		if current.ProfileEpoch~=epoch then return {Ok=false,Code="STALE_PROFILE"} end
		return {Ok=true,Code="OK",Value=table.clone(current)}
	end
	local status=self.profiles:status(id); local profile=self.profiles:get(id)
	if not profile.Ok or status.Frozen or status.Epoch~=epoch then return {Ok=false,Code="PROFILE_UNAVAILABLE"} end
	local slot
	for _,s in ipairs(self.config.World.StoreIds) do
		if not self.slots[s] and (not self.world or self.world.stores[s].available) then slot=s; break end
	end
	if not slot then return {Ok=false,Code="STORE_FULL"} end
	self.generation+=1
	local c={UserId=id,StoreId=slot,OwnerGeneration=self.generation,ProfileEpoch=epoch,RoundId=false,
		Loaded=false,Active=true,DisplayName=player.DisplayName}
	-- Restoration stages and validates ALL items before publishing either map.
	local restored=self.restore(c,profile.Value)
	if not restored.Ok then return {Ok=false,Code="RESTORE_FAILED"} end
	self.slots[slot]=id; self.owners[id]=c
	return {Ok=true,Code="OK",Value=table.clone(c)}
end
function Ownership:getOwnerContext(player)
	local c=self.owners[type(player)=="number" and player or player.UserId]
	return c and table.clone(c) or nil
end
function Ownership:validate(c)
	local own=c and self.owners[c.UserId]
	if not own or own.StoreId~=c.StoreId then return "NOT_OWNER" end
	if own.OwnerGeneration~=c.OwnerGeneration then return "STALE_OWNER" end
	if own.ProfileEpoch~=c.ProfileEpoch then return "STALE_PROFILE" end
	if self.profiles:status(c.UserId).Frozen then return "PROFILE_FROZEN" end
	return "OK"
end
function Ownership:releaseOwner(id,generation)
	local c=self.owners[id]
	if not c or c.OwnerGeneration~=generation then return {Ok=false,Code="STALE_OWNER"} end
	self.slots[c.StoreId]=nil; self.owners[id]=nil
	return {Ok=true,Code="OK"}
end
return Ownership
