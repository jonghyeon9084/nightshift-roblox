--!strict
-- Presentation only. TrafficService alone chooses safe phases and occupancy timing.
local Signals = {}
local red = Color3.fromRGB(220, 55, 55)
local green = Color3.fromRGB(60, 210, 110)
function Signals.apply(world: Instance, phase: string, endsAt: number): boolean
	if not world:IsA("Model") or world:GetAttribute("NightShiftOwned")~=true then return false end
	local traffic=world:FindFirstChild("Traffic")
	local folder=traffic and traffic:FindFirstChild("Signals")
	local cross=folder and folder:FindFirstChild("Cross01")
	local vehicle=cross and cross:FindFirstChild("VehicleSignal")
	local pedestrian=cross and cross:FindFirstChild("PedestrianSignal")
	local valid=cross~=nil and vehicle~=nil and vehicle:IsA("BasePart") and pedestrian~=nil and pedestrian:IsA("BasePart")
		and (phase=="VehicleGreen" or phase=="AllRedToWalk" or phase=="Walk" or phase=="AllRedToVehicle")
		and type(endsAt)=="number" and endsAt==endsAt and endsAt>=0 and endsAt<math.huge
	-- Invalid input never displays a green signal. No movement permission is conferred.
	local vehicleGo=valid and phase=="VehicleGreen"
	local pedestrianGo=valid and phase=="Walk"
	if vehicle and vehicle:IsA("BasePart") then vehicle.Color=if vehicleGo then green else red; vehicle:SetAttribute("SignalState",if vehicleGo then "Go" else "Stop") end
	if pedestrian and pedestrian:IsA("BasePart") then pedestrian.Color=if pedestrianGo then green else red; pedestrian:SetAttribute("SignalState",if pedestrianGo then "Go" else "Stop") end
	if cross then cross:SetAttribute("Phase",if valid then phase else "AllRedToWalk"); cross:SetAttribute("PhaseEndsAt",if valid then endsAt else 0) end
	return valid == true
end
return Signals
