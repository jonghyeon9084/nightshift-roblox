-- Pure state tests; inject actual module/config, never another worker's module.
return function(Service, Config)
	local checks=0
	local function eq(a,b,label) checks+=1; assert(a==b,(label or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
	local function clone(v) if type(v)~="table" then return v end; local t={}; for k,x in pairs(v) do t[k]=clone(x) end; return t end
	local profiles={epoch=1,fail=false,p={Wallet=0,XP=0,Level=1,UnlockedTools={"HandCarry"},EquippedTool="HandCarry",
		Cosmetics={},Presets={},Best={},RareDiscoveries={},RewardCursor={Epoch=1,Sequence=0}}}
	function profiles:get() return {Ok=true,Code="OK",Value=clone(self.p)} end
	function profiles:status() return {Epoch=self.epoch} end
	function profiles:mutate(_,epoch,fn)
		if self.fail or epoch~=self.epoch then return {Ok=false,Code="PROFILE_UNAVAILABLE",Value=false} end
		local nextValue=fn(clone(self.p)); if not nextValue then return {Ok=false,Code="INVALID_STATE",Value=false} end
		self.p=nextValue; return self:get()
	end
	local service=Service.new({Config=Config,Profiles=profiles,NewId=function() error("award must not invent transaction identity") end})
	local function award(tx,kind,sku,eligible,epoch)
		return service:award(1,{TransactionId=tx,Epoch=epoch or 1,Kind=kind or "Sale",Sku=sku or "Water",Eligible=eligible~=false})
	end
	eq(service:equip(1,"Handcart").Code,"LEVEL_LOCKED")
	eq(award("sale-1").Code,"OK"); eq(profiles.p.Wallet,2); eq(profiles.p.XP,5)
	eq(award("sale-1").Code,"OK"); eq(profiles.p.Wallet,2); eq(profiles.p.RewardCursor.Sequence,1)
	eq(award("sale-1","Sale","Milk").Code,"INVALID_STATE")
	profiles.fail=true; eq(award("retry").Ok,false); eq(profiles.p.Wallet,2)
	profiles.fail=false; eq(award("retry").Code,"OK"); eq(profiles.p.Wallet,4)
	eq(award("stolen","Sale","StarJelly",false).Code,"OK"); eq(profiles.p.XP,10); eq(#profiles.p.RareDiscoveries,0)
	eq(award("rare","Delivery","StarJelly").Code,"OK"); eq(profiles.p.XP,12); eq(profiles.p.Wallet,4); eq(#profiles.p.RareDiscoveries,1)
	eq(award("rare2","Sale","StarJelly").Code,"OK"); eq(#profiles.p.RareDiscoveries,1)
	eq(award("old",nil,nil,nil,0).Code,"LEASE_LOST")
	for i=1,5 do eq(award("level-"..i).Code,"OK") end
	eq(profiles.p.Level,2); eq(service:equip(1,"Handcart").Code,"OK"); eq(profiles.p.EquippedTool,"Handcart")
	eq(service:equip(1,"PaidTool").Code,"BAD_REQUEST")
	eq(service:savePreset(1,1,{}).Code,"LEVEL_LOCKED")
	profiles.p.XP=180; eq(award("normalize","Delivery").Code,"OK"); eq(profiles.p.Level,4)
	eq(service:savePreset(1,1,{{SlotId="Slot01",Sku="Water"}}).Code,"OK")
	eq(service:savePreset(1,3,{}).Code,"PRESET_INVALID")
	eq(service:savePreset(1,1,{{SlotId="Slot01",Sku="Water"},{SlotId="Slot01",Sku="Milk"}}).Code,"PRESET_INVALID")
	eq(service:savePreset(1,1,{{SlotId="Slot01",Sku="Invalid"}}).Code,"PRESET_INVALID")
	eq(service:savePreset(1,1,{{SlotId="Slot01",Sku="Water",Quantity=9}}).Code,"PRESET_INVALID")
	eq(service:savePreset(1,1,{[2]={SlotId="Slot01",Sku="Water"}}).Code,"PRESET_INVALID")
	eq(service:savePreset(1,1,{{SlotId="Slot02",Sku="Milk"}}).Code,"OK"); eq(#profiles.p.Presets,1)
	local view=service:view(1); view.Presets[1].Slots[1].Sku="Water"; eq(profiles.p.Presets[1].Slots[1].Sku,"Milk")
	profiles.epoch=2; eq(award("sale-1").Code,"LEASE_LOST"); eq(award("sale-1",nil,nil,nil,2).Code,"INVALID_STATE")
	eq(award("new-epoch",nil,nil,nil,2).Code,"OK"); eq(profiles.p.RewardCursor.Sequence,1); eq(profiles.p.RewardCursor.Epoch,2)
	profiles.p.XP=Config.Progression.MaxXP; profiles.p.Wallet=Config.Economy.MaxCurrency
	eq(award("cap",nil,nil,nil,2).Code,"OK"); eq(profiles.p.XP,Config.Progression.MaxXP); eq(profiles.p.Wallet,Config.Economy.MaxCurrency)
	eq(profiles.p.Level,5); eq(#profiles.p.UnlockedTools,5)
	print("ProgressionService: "..checks.." checks passed (fake Profiles; no cloud/Studio)")
	return checks
end
