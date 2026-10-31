--!nonstrict
local Players = game:GetService("Players")
local WorldAdapter = {}
WorldAdapter.__index = WorldAdapter
local function vec(a) return Vector3.new(a[1], a[2], a[3]) end
local function unique(parent, name, class)
	local found
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			if found or child.ClassName ~= class then return nil end
			found = child
		end
	end
	return found
end
function WorldAdapter.new(world, config)
	assert(world:IsA("Model") and world.Name == config.World.Name and world:GetAttribute(config.World.OwnerAttribute) == true, "Invalid NightShiftWorld ownership")
	local hub, stores = unique(world, "Hub", "Model"), unique(world, "Stores", "Folder")
	assert(hub and stores, "NightShiftWorld root structure missing")
	local self = setmetatable({ world = world, config = config, stores = {}, hub = hub }, WorldAdapter)
	self.hubSpawn = unique(hub, "Spawn", "SpawnLocation")
	assert(self.hubSpawn and (self.hubSpawn.Position - vec(config.World.HubSpawn)).Magnitude < 0.05, "Invalid Hub Spawn")
	assert(unique(hub, "StoreSelect", "Part"), "Invalid Hub StoreSelect")
	assert(self:safe(self.hubSpawn), "Hub Spawn is obstructed or has no floor")
	for _, storeId in ipairs(config.World.StoreIds) do
		local model = unique(stores, storeId, "Model")
		local entry = { model = model, markers = {}, lights = {}, available = true, reason = false }
		local def = config.World.Stores[storeId]
		local pivot = CFrame.new(vec(def.Position)) * CFrame.Angles(0, math.rad(def.YawDegrees), 0)
		if not model or model:GetAttribute("StoreId") ~= storeId then
			entry.available, entry.reason = false, "점포 모델 또는 StoreId 오류"
		else
			for _, name in ipairs(config.World.MarkerOrder) do
				local spec = config.World.Markers[name]
				local marker = unique(model, name, spec.ClassName)
				local expected = pivot * CFrame.new(vec(spec.Position))
				if not marker or marker:GetAttribute("StoreId") ~= storeId or not marker.Anchored
					or marker.CanTouch or marker.CastShadow or (marker.Size - vec(spec.Size)).Magnitude > 0.05
					or (marker.Position - expected.Position).Magnitude > 0.05
					or marker.CFrame.LookVector:Dot(expected.LookVector) < 0.999
					or marker.CFrame.UpVector:Dot(expected.UpVector) < 0.999
					or (name == "Entry" and (marker.CanCollide or marker.Transparency ~= 1))
					or (name ~= "Entry" and not marker.CanCollide)
					or (name == "Spawn" and (marker.Enabled or not marker.Neutral or marker.Duration ~= 0)) then
					entry.available, entry.reason = false, "필수 마커 오류: " .. name
					break
				end
				entry.markers[name] = marker
			end
			if entry.available and (not self:safe(entry.markers.Spawn) or not self:safe(entry.markers.Entry)) then
				entry.available, entry.reason = false, "Spawn/Entry 바닥 또는 안전 공간 오류"
			end
			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("Light") then entry.lights[descendant] = descendant.Enabled end
			end
		end
		self.stores[storeId] = entry
	end
	return self
end
function WorldAdapter:safe(marker, character)
	if not marker or not marker:IsDescendantOf(self.world) then return false end
	local destination = marker.CFrame * CFrame.new(0, self.config.World.SpawnLift, 0)
	local exclude = {}
	-- Players do not make a correctly built spawn permanently Unavailable.
	for _, player in ipairs(Players:GetPlayers()) do if player.Character then table.insert(exclude, player.Character) end end
	if character then table.insert(exclude, character) end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclude
	overlap.RespectCanCollide = true
	for _, part in ipairs(workspace:GetPartBoundsInBox(destination, Vector3.new(4, 5.5, 4), overlap)) do
		if part.CanCollide then return false end
	end
	local ray = RaycastParams.new()
	-- Check our supporting floor explicitly. A preserved Baseplate/SpawnLocation
	-- may be coplanar and win the nearest-hit tie; it must not hide our floor.
	-- Clearance above still tests ALL collidable scene geometry (except players).
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = { self.world }
	ray.RespectCanCollide = true
	local floor = workspace:Raycast(destination.Position, Vector3.new(0, -8, 0), ray)
	if not floor or not floor.Instance:IsDescendantOf(self.world) or floor.Normal.Y < 0.8 then return false end
	return destination
end
function WorldAdapter:alive(player)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local human = character and character:FindFirstChildOfClass("Humanoid")
	return root and root:IsA("BasePart") and human and human.Health > 0 and root or nil
end
function WorldAdapter:near(player, storeId, markerName)
	local entry = self.stores[storeId]
	local marker = entry and entry.markers[markerName]
	local root = self:alive(player)
	return root ~= nil and marker ~= nil and marker:IsDescendantOf(self.world)
		and (root.Position - marker.Position).Magnitude <= self.config.Interaction.Distance
end
function WorldAdapter:inside(player, storeId)
	local root = self:alive(player)
	if not root then return false end
	local spec = self.config.World.Stores[storeId]
	local pivot = CFrame.new(vec(spec.Position)) * CFrame.Angles(0, math.rad(spec.YawDegrees), 0)
	local localPosition = pivot:PointToObjectSpace(root.Position)
	local size = self.config.World.StoreSize
	return math.abs(localPosition.X) <= size[1] / 2 and math.abs(localPosition.Z) <= size[3] / 2
		and localPosition.Y >= 0 and localPosition.Y <= size[2]
end
function WorldAdapter:move(player, storeId, markerName)
	if not self:alive(player) then return false end
	local marker = storeId and self.stores[storeId].markers[markerName] or self.hubSpawn
	local destination = self:safe(marker, player.Character)
	if not destination then return false end
	player.Character:PivotTo(destination)
	local root = self:alive(player)
	if root then root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero end
	return true
end
function WorldAdapter:setOutage(storeId, active)
	local entry = self.stores[storeId]
	for light, original in pairs(entry.lights) do
		if light:IsDescendantOf(entry.model) then light.Enabled = not active and original end
	end
	entry.model:SetAttribute("OutageActive", active)
end
function WorldAdapter:setLayout(storeId, products)
	for index, product in ipairs(products) do
		local shelf = self.stores[storeId].markers["Shelf" .. index]
		shelf:SetAttribute("ProductId", product)
		shelf:SetAttribute("ProductName", self.config.Products[product].Name)
		shelf:SetAttribute("ProductGlyph", self.config.Products[product].Glyph)
	end
end
return WorldAdapter
