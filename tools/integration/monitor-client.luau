-- Read-only public-wire observer for actual input tests; never changes server state.
local r=game:GetService("ReplicatedStorage").NightShift.Remotes
if shared.NightShiftVerification then
 for _, c in ipairs(shared.NightShiftVerification.Connections) do c:Disconnect() end
end
local reducer=require(game:GetService("Players").LocalPlayer.PlayerScripts.NightShift.Modules.StateStore)
local v={State=reducer.new(1),Acks={},Connections={}}
shared.NightShiftVerification=v
table.insert(v.Connections,r.State.OnClientEvent:Connect(function(p) reducer.apply(v.State,p) end))
table.insert(v.Connections,r.ActionResult.OnClientEvent:Connect(function(p) table.insert(v.Acks,p) end))
task.wait(2.1)
local snap=r.GetSnapshot:InvokeServer({ProtocolVersion=1})
if snap.Ok then reducer.apply(v.State,snap.Snapshot) end
return game:GetService("HttpService"):JSONEncode({Attached=true,Snapshot=snap.Ok})
