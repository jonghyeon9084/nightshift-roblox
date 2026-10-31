-- Temporary, owned test probes; removed before local save. Never shipped by loader.
assert(not game:GetService("RunService"):IsRunning())
local server=game.ServerScriptService.NightShift
local client=game.StarterPlayer.StarterPlayerScripts.NightShift
for _,parent in ipairs({server,client}) do assert(not parent:FindFirstChild("CommerceIntegrationProbe"),"Existing probe must be reviewed") end
local s=Instance.new("Script");s.Name="CommerceIntegrationProbe";s:SetAttribute("NightShiftIntegrationProbe",true)
s.Source=[==[
local st=game:GetService("StudioTestService")
local args=st:GetTestArgs()
if args~="NightShiftCommerceProbe" then return end
local r=Instance.new("RemoteEvent");r.Name="IntegrationProbe";r.Parent=game.ReplicatedStorage.NightShift
local reports={}
local joined={}
local started=os.clock()
game.Players.PlayerAdded:Connect(function(p) joined[tostring(p.UserId)]=os.clock()-started end)
r.OnServerEvent:Connect(function(p,data) reports[tostring(p.UserId)]=data end)
-- On this 8 GB host, the original 45 s deadline ended the server while both
-- real client processes were still initializing graphics and built-in plugins.
-- Await observed client readiness, with a bounded cold-start budget.
local deadline=os.clock()+180
repeat task.wait(.5) until (function() local n=0 for _ in pairs(reports) do n+=1 end return n>=2 end)() or os.clock()>deadline
st:EndTest({Kind="ACTUAL_STUDIO_TWO_CLIENT_BOOT",Players=#game.Players:GetPlayers(),Reports=reports,JoinedAtSeconds=joined,ElapsedSeconds=os.clock()-started})
]==];s.Parent=server
local c=Instance.new("LocalScript");c.Name="CommerceIntegrationProbe";c:SetAttribute("NightShiftIntegrationProbe",true)
c.Source=[==[
local ns=game.ReplicatedStorage:WaitForChild("NightShift",45)
local probe=ns and ns:WaitForChild("IntegrationProbe",45);if not probe then return end
local r=ns:WaitForChild("Remotes",30)
if not r or not r:WaitForChild("GetCommerceSnapshot",30) then probe:FireServer({SnapshotCall=false,Error="Commerce remote missing",ClientUserId=game.Players.LocalPlayer.UserId});return end
local ok,result=pcall(function() return r.GetCommerceSnapshot:InvokeServer({ProtocolVersion=1}) end)
probe:FireServer({SnapshotCall=ok,Result=result,ClientUserId=game.Players.LocalPlayer.UserId})
]==];c.Parent=client
shared.CommerceMultiplayerResult={State="Starting"}
task.spawn(function()
 local ok,result=pcall(function() return game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2,"NightShiftCommerceProbe") end)
 shared.CommerceMultiplayerResult={Ok=ok,Result=result}
 print("COMMERCE_MULTIPLAYER_RESULT "..game.HttpService:JSONEncode(shared.CommerceMultiplayerResult))
end)
return "Official ExecuteMultiplayerTestAsync(2) scheduled; await actual result, not a pass"
