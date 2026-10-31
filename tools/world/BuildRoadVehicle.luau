--!strict
-- Self-authored stationary presentation; traffic authority owns motion and contacts.
local Vehicle = {}
function Vehicle.create(kind: string): Model
	assert(kind == "Compact" or kind == "Van", "Unsupported vehicle kind")
	local model = Instance.new("Model"); model.Name = "Road" .. kind
	model:SetAttribute("VehicleKind", kind)
	local function piece(name: string, size: Vector3, offset: Vector3, color: Color3)
		local p = Instance.new("Part"); p.Name=name; p.Size=size; p.CFrame=CFrame.new(offset); p.Color=color
		p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.CastShadow=false
		p:SetAttribute("OffsetX",offset.X); p:SetAttribute("OffsetY",offset.Y); p:SetAttribute("OffsetZ",offset.Z); p.Parent=model
	end
	local color=if kind=="Compact" then Color3.fromRGB(86,143,168) else Color3.fromRGB(207,191,154)
	local length=if kind=="Compact" then 8 else 11
	piece("Body",Vector3.new(length,2,4),Vector3.new(0,1.7,0),color)
	piece("Cabin",Vector3.new(if kind=="Compact" then 4 else 7,2,3.6),Vector3.new(0,3.5,0),color)
	piece("Window",Vector3.new(0.1,1.2,3.2),Vector3.new(length/2-1.1,3.5,0),Color3.fromRGB(140,190,205))
	for _, x in ipairs({-length/2+1.4,length/2-1.4}) do for _,z in ipairs({-2,2}) do
		piece("Wheel",Vector3.new(1.6,1.6,0.6),Vector3.new(x,0.8,z),Color3.fromRGB(30,35,40))
	end end
	return model
end
function Vehicle.pose(model: Model, frame: CFrame)
	for _, p in ipairs(model:GetChildren()) do if p:IsA("BasePart") then
		p.CFrame=frame*CFrame.new(p:GetAttribute("OffsetX"),p:GetAttribute("OffsetY"),p:GetAttribute("OffsetZ"))
	end end
end
return Vehicle
