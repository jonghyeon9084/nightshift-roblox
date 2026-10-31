-- Targeted follow-up ONLY for the new negative Studio UserId defect found by
-- the single boot probe. Two real Studio clients use production Remotes.
assert(not game:GetService("RunService"):IsRunning())
local server=game.ServerScriptService.NightShift
local client=game.StarterPlayer.StarterPlayerScripts.NightShift
for _,parent in ipairs({server,client}) do assert(not parent:FindFirstChild("WarehouseProfileProbe")) end
local s=Instance.new("Script");s.Name="WarehouseProfileProbe";s:SetAttribute("NightShiftIntegrationProbe",true)
s.Source=[==[
local st=game:GetService("StudioTestService")
if st:GetTestArgs()~="WarehouseProfileRegression" then return end
local ns=game.ReplicatedStorage:WaitForChild("NightShift")
local r=Instance.new("RemoteEvent");r.Name="WarehouseProfileProbe";r.Parent=ns
local reports,joined={},{};local started=os.clock()
game.Players.PlayerAdded:Connect(function(p) joined[tostring(p.UserId)]=os.clock()-started end)
r.OnServerEvent:Connect(function(p,data) reports[tostring(p.UserId)]=data end)
local deadline=os.clock()+180
repeat task.wait(.5) until (reports["-1"] and reports["-2"]) or os.clock()>deadline
st:EndTest({Kind="ACTUAL_TWO_CLIENT_PROFILE_AND_START_REGRESSION",Players=#game.Players:GetPlayers(),Reports=reports,JoinedAtSeconds=joined,ElapsedSeconds=os.clock()-started})
]==];s.Parent=server
local c=Instance.new("LocalScript");c.Name="WarehouseProfileProbe";c:SetAttribute("NightShiftIntegrationProbe",true)
c.Source=[==[
local ns=game.ReplicatedStorage:WaitForChild("NightShift",60)
local report=ns:WaitForChild("WarehouseProfileProbe",60)
local r=ns:WaitForChild("Remotes",30)
local p=game.Players.LocalPlayer
local data={ClientUserId=p.UserId,Method="Scripted production Remotes on actual client",Actions={}}
local ok,err=pcall(function()
 r:WaitForChild("GetCommerceSnapshot",30)
 local function snap(remote)
  task.wait(2.3);local result=remote:InvokeServer({ProtocolVersion=1})
  if not result.Ok and result.Code=="RATE_LIMIT" then task.wait(2.3);result=remote:InvokeServer({ProtocolVersion=1}) end
  assert(result.Ok,result.Code);return result.Snapshot
 end
 local commerce=snap(r.GetCommerceSnapshot);data.ProfileState=commerce.Self.ProfileState
 assert(data.ProfileState=="Temporary","Profile not ready: "..data.ProfileState)
 local legacy=snap(r.GetSnapshot);local seq=1000
 local acks={};r.ActionResult.OnClientEvent:Connect(function(a) acks[a.RequestId]=a end)
 local function act(name,payload,target)
  seq+=1
  r.Action:FireServer({ProtocolVersion=1,RequestId=seq,Action=name,StoreId=target or legacy.Self.StoreId,RoundId=legacy.Store and legacy.Store.RoundId or false,SeatGeneration=legacy.Self.SeatGeneration,Payload=payload})
  local untilAt=os.clock()+5;repeat task.wait(.05) until acks[seq] or os.clock()>untilAt
  assert(acks[seq] and acks[seq].Ok,acks[seq] and acks[seq].Code or "Ack missing")
  table.insert(data.Actions,{Action=name,Ack=acks[seq]});legacy=snap(r.GetSnapshot)
 end
 local target=p.UserId==-1 and "Store01" or "Store02"
 act("JoinStore",{},target)
 assert(workspace:WaitForChild("NightShiftWorld",30).Stores:WaitForChild(target,30):FindFirstChild("OfficePC"),"Store not replicated")
 act("SetLoaded",{Loaded=true})
 act("SoloPractice",{RosterVersion=legacy.Store.RosterVersion})
 commerce=snap(r.GetCommerceSnapshot)
 data.StoreId=legacy.Self.StoreId;data.Phase=legacy.Store.Phase;data.RoundId=legacy.Store.RoundId
 data.Cash=commerce.Store and commerce.Store.OperatingCash
 assert(data.StoreId==target and data.Phase=="Running" and data.Cash==240,"Start failed")
end)
data.Ok=ok;data.Error=not ok and tostring(err) or false
report:FireServer(data)
]==];c.Parent=client
shared.WarehouseProfileRegression={State="Starting"}
task.spawn(function()
 local ok,result=pcall(function() return game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2,"WarehouseProfileRegression") end)
 shared.WarehouseProfileRegression={Ok=ok,Result=result}
 print("WAREHOUSE_PROFILE_REGRESSION "..game.HttpService:JSONEncode(shared.WarehouseProfileRegression))
end)
return "Targeted new-defect regression scheduled, not a pass"
