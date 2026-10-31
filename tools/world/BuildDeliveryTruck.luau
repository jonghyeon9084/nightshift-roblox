--!strict
-- Self-authored visual only. The server remains authoritative for cargo and motion.
local Truck = {}
function Truck.create(storeId: string, orderId: string): (Model, Part, Part)
 local model = Instance.new("Model")
 model.Name = orderId
 model:SetAttribute("StoreId", storeId)
 model:SetAttribute("OrderId", orderId)
 local function piece(name: string, size: Vector3, offset: Vector3, color: Color3): Part
  local p = Instance.new("Part")
  p.Name = name; p.Size = size; p.CFrame = CFrame.new(offset); p.Color = color
  p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
  p:SetAttribute("OffsetX", offset.X); p:SetAttribute("OffsetY", offset.Y); p:SetAttribute("OffsetZ", offset.Z)
  p.Parent = model
  return p
 end
 local blue = Color3.fromRGB(67, 89, 115)
 local dark = Color3.fromRGB(30, 35, 40)
 local body = piece("Body", Vector3.new(7, 0.4, 10), Vector3.new(0, 1.2, 0), blue)
 piece("Cab", Vector3.new(7, 4, 2), Vector3.new(0, 3.4, -4), blue)
 piece("Windshield", Vector3.new(6, 1.5, 0.1), Vector3.new(0, 4, -5.06), Color3.fromRGB(145, 190, 205))
 piece("BedLeft", Vector3.new(0.25, 1.4, 6), Vector3.new(-3.35, 2, 1.5), blue)
 piece("BedRight", Vector3.new(0.25, 1.4, 6), Vector3.new(3.35, 2, 1.5), blue)
 piece("Ramp", Vector3.new(5.5, 0.2, 0.5), Vector3.new(0, 1.1, 5.25), blue)
 for _, x in ipairs({-3.3, 3.3}) do
  for _, z in ipairs({-3, 3}) do
   piece("Wheel", Vector3.new(0.7, 1.8, 1.8), Vector3.new(x, 0, z), dark)
  end
 end
 local cargo = piece("Cargo", Vector3.new(6, 2, 6), Vector3.new(0, 3, 0), blue)
 cargo.Transparency = 1; cargo.CanQuery = true
 cargo:SetAttribute("StoreId", storeId); cargo:SetAttribute("OrderId", orderId)
 for _, side in ipairs({-1, 1}) do
  local slot = piece("DirectNotice", Vector3.new(0.05, 1, 5), Vector3.new(side * 3.52, 2, 1.5), Color3.fromRGB(240, 245, 250))
  slot:SetAttribute("SlotId", storeId .. (if side < 0 then ":TruckLeft" else ":TruckRight"))
  slot:SetAttribute("ContentMode", "HouseInformation")
  -- Self-contained notice remains readable if the optional operator binder is absent.
  -- The owned slot identity lets that binder replace it without a second renderer.
  local gui = Instance.new("SurfaceGui")
  gui.Name = "OperatorNotice"
  gui.Face = if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right
  gui.CanvasSize = Vector2.new(768, 256); gui.AlwaysOnTop = false; gui.LightInfluence = 0; gui.MaxDistance = 100
  gui:SetAttribute("NightShiftDirectContentOwned", true)
  gui:SetAttribute("ContentSlotId", "truck." .. storeId .. "." .. orderId .. (if side < 0 then ".left" else ".right"))
  gui:SetAttribute("ContentMode", "house_notice")
  local label = Instance.new("TextLabel")
  label.Size = UDim2.fromScale(1, 1); label.BackgroundTransparency = 0.1
  label.BackgroundColor3 = Color3.fromRGB(28, 35, 49); label.TextColor3 = Color3.fromRGB(240, 245, 250)
  label.Text = "배송 안내 · 도착 후 직접 하역하세요"; label.TextWrapped = true; label.TextScaled = true; label.RichText = false
  label.Parent = gui; gui.Parent = slot
 end
 return model, body, cargo
end
function Truck.pose(model: Model, routeFrame: CFrame)
 -- Route travels along local +X. Keep the cab facing travel, including docking;
 -- Cargo's centered offset stays identical and unloading is from the lane side.
 routeFrame = routeFrame * CFrame.Angles(0, -math.pi/2, 0)
 for _, p in ipairs(model:GetChildren()) do
  if p:IsA("BasePart") then
   p.CFrame = routeFrame * CFrame.new(p:GetAttribute("OffsetX"), p:GetAttribute("OffsetY"), p:GetAttribute("OffsetZ"))
  end
 end
end
return Truck
