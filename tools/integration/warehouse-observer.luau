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
task.wait(2.2)
local function get(remote)
 local result=remote:InvokeServer({ProtocolVersion=1})
 if not result.Ok and result.Code=="RATE_LIMIT" then task.wait(math.max(2.2,result.RetryAfter or 0)+.1); result=remote:InvokeServer({ProtocolVersion=1}) end
 return result
end
local a=get(r.GetSnapshot); assert(a.Ok,a.Code); L.apply(v.Legacy,a.Snapshot)
local b=get(r.GetCommerceSnapshot); assert(b.Ok,b.Code); C.apply(v.Commerce,b.Snapshot,os.clock())
return "public observers attached"
