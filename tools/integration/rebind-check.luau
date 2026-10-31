-- Synthetic client marker removal, not a claim of real streaming eviction.
local p=game:GetService("Players").LocalPlayer
local v=shared.NightShiftVerification
local store=workspace.NightShiftWorld.Stores[v.State.Self.StoreId]
local marker=store.Shelf1
marker.Parent=nil
task.wait(1)
local unloaded=v.State.Self.Loaded==false
marker.Parent=store
task.wait(2)
local loaded=v.State.Self.Loaded==true
assert(unloaded and loaded,"Automatic load reconciliation failed")
local trays=0
for _,x in ipairs(store.Counter:GetChildren()) do if x:IsA("BillboardGui") and string.find(x.Name,"NightShiftTray") then trays+=1 end end
assert(trays==3,"Expected exactly three restored trays")
return game:GetService("HttpService"):JSONEncode({SyntheticMarkerRemoval=true,Unloaded=unloaded,ReloadedWithoutF5=loaded,Trays=trays})
