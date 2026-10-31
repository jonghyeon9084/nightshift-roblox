assert(not game:GetService("RunService"):IsRunning(),"Must finish in Edit")
local probes={}
for _,service in ipairs({game.ServerScriptService,game.StarterPlayer.StarterPlayerScripts}) do
 for _,v in ipairs(service:GetDescendants()) do if v:GetAttribute("NightShiftIntegrationProbe") then table.insert(probes,v:GetFullName()) end end
end
assert(#probes==0,"Temporary probes remain")
local world=workspace.NightShiftWorld
require(game.ServerStorage.NightShift.BuildWorld).validate(world)
local config=require(game.ReplicatedStorage.NightShift.Shared.CommerceConfig)
assert(workspace.Baseplate.Position==Vector3.new(0,-8,0) and workspace.Baseplate.Size==Vector3.new(2048,16,2048))
assert(workspace.SpawnLocation.Position==Vector3.new(0,.5,0) and workspace.SpawnLocation.Size==Vector3.new(12,1,12))
return game.HttpService:JSONEncode({Mode="Edit",Probes=probes,Stores=#world.Stores:GetChildren(),RuntimeChildren=#world.CommerceRuntime:GetChildren(),Parts=world:GetAttribute("BuildPartCount"),AdUnits=world:GetAttribute("BuildAdUnitCount"),WorldHash=world:GetAttribute("NightShiftSourceHash"),TruckSourceHash=game.ServerStorage.NightShift.BuildDeliveryTruck:GetAttribute("NightShiftSourceHash"),BaseplatePreserved=true,SpawnPreserved=true,ConfiguredTargetPlayers=config.Capacity.TargetPlayers,ConfiguredSeatsPerStore=config.Capacity.SeatsPerStore,ActualMaxPlayers=game.Players.MaxPlayers,PersistentSave=config.Features.PersistentSave,SaveMode=config.Profile.DefaultMode})
