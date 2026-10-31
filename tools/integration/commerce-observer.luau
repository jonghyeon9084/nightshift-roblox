-- Public packet observer only; no server state injection.
local r=game:GetService("ReplicatedStorage").NightShift.Remotes
local mods=game:GetService("Players").LocalPlayer.PlayerScripts.NightShift.Modules
local L=require(mods.StateStore); local C=require(mods.CommerceState)
if shared.CommerceVerification then for _,c in ipairs(shared.CommerceVerification.Connections) do c:Disconnect() end end
local v={Legacy=L.new(1),Commerce=C.new(),Acks={},CommerceAcks={},Connections={}}
shared.CommerceVerification=v
table.insert(v.Connections,r.State.OnClientEvent:Connect(function(p) L.apply(v.Legacy,p) end))
table.insert(v.Connections,r.CommerceState.OnClientEvent:Connect(function(p) C.apply(v.Commerce,p,os.clock()) end))
table.insert(v.Connections,r.ActionResult.OnClientEvent:Connect(function(p) table.insert(v.Acks,p) end))
table.insert(v.Connections,r.CommerceActionResult.OnClientEvent:Connect(function(p) table.insert(v.CommerceAcks,p) end))
task.wait(2.1)
local a=r.GetSnapshot:InvokeServer({ProtocolVersion=1}); assert(a.Ok,a.Code); L.apply(v.Legacy,a.Snapshot)
local b=r.GetCommerceSnapshot:InvokeServer({ProtocolVersion=1}); assert(b.Ok,b.Code); C.apply(v.Commerce,b.Snapshot,os.clock())
return "public observers attached"
