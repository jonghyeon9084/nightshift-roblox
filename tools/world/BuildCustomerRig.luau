--!strict
-- Lightweight authored visual. No economy, automatic movement or player control.
local Rig = {}
function Rig.create(kind: string): Model
	assert(kind=="Normal" or kind=="Rich", "Unsupported customer kind")
	local model=Instance.new("Model"); model.Name="Customer"..kind; model:SetAttribute("CustomerKind",kind)
	local function piece(name: string, size: Vector3, offset: Vector3, color: Color3)
		local p=Instance.new("Part"); p.Name=name; p.Size=size; p.CFrame=CFrame.new(offset); p.Color=color
		p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.CastShadow=false
		p:SetAttribute("OffsetX",offset.X); p:SetAttribute("OffsetY",offset.Y); p:SetAttribute("OffsetZ",offset.Z); p.Parent=model
	end
	local shirt=if kind=="Rich" then Color3.fromRGB(68,63,95) else Color3.fromRGB(83,143,125)
	local skin=Color3.fromRGB(220,181,151); local dark=Color3.fromRGB(48,53,68)
	piece("Torso",Vector3.new(2,2,1),Vector3.new(0,3,0),shirt)
	piece("Head",Vector3.new(1.4,1.4,1.4),Vector3.new(0,4.8,0),skin)
	for _,x in ipairs({-1.4,1.4}) do piece("Arm",Vector3.new(0.7,2,0.8),Vector3.new(x,3,0),skin) end
	for _,x in ipairs({-0.55,0.55}) do piece("Leg",Vector3.new(0.8,2,0.8),Vector3.new(x,1,0),dark) end
	if kind=="Rich" then piece("Hat",Vector3.new(1.8,0.3,1.8),Vector3.new(0,5.6,0),dark) end
	return model
end
function Rig.pose(model: Model, frame: CFrame)
	for _,p in ipairs(model:GetChildren()) do if p:IsA("BasePart") then
		p.CFrame=frame*CFrame.new(p:GetAttribute("OffsetX"),p:GetAttribute("OffsetY"),p:GetAttribute("OffsetZ"))
	end end
end
return Rig
