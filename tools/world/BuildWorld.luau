--!strict
-- ServerStorage.NightShift.BuildWorld; requiring this module never builds a world.
-- All geometry/text is authored here. No assets, services that sell items, or global Lighting edits.
local Builder = {}

local C = {
	road = Color3.fromRGB(35, 42, 56), pavement = Color3.fromRGB(83, 92, 109),
	wall = Color3.fromRGB(185, 192, 201), floor = Color3.fromRGB(120, 133, 144),
	dark = Color3.fromRGB(28, 35, 49), paper = Color3.fromRGB(242, 231, 201),
	wood = Color3.fromRGB(132, 99, 73), white = Color3.fromRGB(240, 245, 250),
}
local ACCENTS = {
	Color3.fromRGB(78, 151, 205), Color3.fromRGB(102, 177, 138),
	Color3.fromRGB(194, 143, 82), Color3.fromRGB(155, 124, 200),
}

local function vector(values: {number}): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

local function container(className: string, name: string, parent: Instance): Instance
	local object = Instance.new(className)
	object.Name = name
	object.Parent = parent
	return object
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, solid: boolean?): Part
	local object = Instance.new("Part")
	object.Name = name
	object.Size = size
	-- Lift each owned ground layer above the user's Y=0 Baseplate. Distinct
	-- heights also separate overlapping paving; contracts retain original coordinates.
	local groundHeight = { MainRoad = 0.08, Plaza = 0.16, Sidewalk = 0.24,
		ServiceLane = 0.24, HubWalk = 0.32, Floor = 0.40, Forecourt = 0.48,
		SideWalk = 0.56, RearWalk = 0.64, LoadingPad = 0.72,
		WarehousePad = 0.30, LaneDash = 0.08 }
	object.CFrame = cf + Vector3.new(0, groundHeight[name] or 0, 0)
	object.Color = color
	object.Material = Enum.Material.SmoothPlastic
	object.Anchored = true
	object.CanCollide = solid ~= false
	object.CanTouch = false
	object.CanQuery = solid ~= false
	object.CastShadow = false
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.Parent = parent
	return object
end

local function text(board: BasePart, message: string, face: Enum.NormalId?, darkInk: boolean?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "WorldText"
	gui.Face = face or Enum.NormalId.Back -- local +Z, the storefront's entrance side
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(768, 256)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 100
	local label = Instance.new("TextLabel")
	label.Name = "Caption"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = message
	label.TextColor3 = if darkInk then C.dark else C.white
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.TextWrapped = true
	label.RichText = false
	label.Parent = gui
	gui.Parent = board
end

local function lamp(fixture: Part, storeId: string?)
	fixture.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Name = "WorkLight"
	light.Color = Color3.fromRGB(255, 230, 191)
	light.Brightness = 1.1
	light.Range = 28
	light.Shadows = false
	if storeId then
		fixture:SetAttribute("StoreId", storeId)
		fixture:SetAttribute("OutageControlled", true)
		light:SetAttribute("StoreId", storeId)
		light:SetAttribute("OutageControlled", true)
	end
	light.Parent = fixture
end

local function spawn(parent: Instance, cf: CFrame, size: Vector3, storeId: string?): SpawnLocation
	local object = Instance.new("SpawnLocation")
	object.Name = "Spawn"
	object.CFrame = cf
	object.Size = size
	object.Anchored = true
	object.CanCollide = true
	object.CanTouch = false
	object.CastShadow = false
	object.Neutral = true
	object.Enabled = false
	object.Duration = 0
	object.Transparency = 1
	if storeId then object:SetAttribute("StoreId", storeId) end
	object.Parent = parent
	return object
end

local function makeStore(stores: Instance, config: any, commerce: any, storeId: string, index: number)
	local definition = config.World.Stores[storeId]
	local pivot = CFrame.new(vector(definition.Position)) * CFrame.Angles(0, math.rad(definition.YawDegrees), 0)
	local store = Instance.new("Model")
	store.Name = storeId
	store:SetAttribute("StoreId", storeId)
	store:SetAttribute("DisplayName", definition.Name)
	store.Parent = stores
	local decor = container("Folder", "Architecture", store)
	local lights = container("Folder", "Lights", store)
	lights:SetAttribute("StoreId", storeId)
	local accent = ACCENTS[(index - 1) % #ACCENTS + 1]
	local function block(name: string, size: Vector3, position: Vector3, color: Color3, solid: boolean?): Part
		return part(decor, name, size, pivot * CFrame.new(position), color, solid)
	end
	block("Floor", Vector3.new(56, 1, 48), Vector3.new(0, -0.5, 0), C.floor)
	-- Ten-stud rear opening at x=18..28, with thirteen studs headroom.
	block("BackWall", Vector3.new(46, 18, 1), Vector3.new(-5, 9, -24.5), C.wall)
	block("BackHeader", Vector3.new(10, 5, 1), Vector3.new(23, 15.5, -24.5), C.wall)
	block("LeftWall", Vector3.new(1, 18, 48), Vector3.new(-28.5, 9, 0), C.wall)
	block("RightWall", Vector3.new(1, 18, 48), Vector3.new(28.5, 9, 0), C.wall)
	block("Roof", Vector3.new(58, 1, 50), Vector3.new(0, 18.5, 0), C.dark)
	-- A permanent 14 x 13 stud opening. No door, invisible collider, or threshold across it.
	for _, x in ipairs({ -17.5, 17.5 }) do
		block("WindowBase", Vector3.new(21, 3, 1), Vector3.new(x, 1.5, 24), accent)
		local pane = block("Window", Vector3.new(21, 10, 0.3), Vector3.new(x, 8, 24), Color3.fromRGB(158, 201, 213))
		pane.Material = Enum.Material.Glass
		pane.Transparency = 0.75
	end
	block("EntranceHeader", Vector3.new(56, 5, 1), Vector3.new(0, 15.5, 24), accent)
	local sign = block("StoreSign", Vector3.new(44, 4, 0.5), Vector3.new(0, 15.5, 24.8), C.dark, false)
	text(sign, definition.Name .. " " .. definition.Shape .. "\n오늘도 정상영업")
	block("Awning", Vector3.new(58, 0.5, 7 + index), Vector3.new(0, 13, 27), accent)
	block("Forecourt", Vector3.new(56, 1, 12), Vector3.new(0, -0.5, 30), C.pavement)
	-- Rear office/storage remain open to the shelf aisle and rear loading door.
	block("OfficeDesk", Vector3.new(6, 2, 3), Vector3.new(-16, 1, -22), C.wood)
	local officeSign = block("OfficeSign", Vector3.new(10, 2, 0.2), Vector3.new(-16, 7, -23), C.dark, false)
	text(officeSign, "사무실 PC · 재고 주문")
	block("WarehousePad", Vector3.new(10, 0.05, 6), Vector3.new(0, 0.135, -18), C.pavement, false)
	local warehouseSign = block("WarehouseSign", Vector3.new(12, 2, 0.2), Vector3.new(0, 7, -23), C.dark, false)
	text(warehouseSign, "창고 · 직접 운반\n하역은 후문 →")
	block("LoadingPad", Vector3.new(12, 1, 1), Vector3.new(23, -0.5, -33.5), C.pavement)
	for _, x in ipairs({ -33, 33 }) do
		block("SideWalk", Vector3.new(8, 1, 68), Vector3.new(x, -0.5, 1), C.pavement)
	end
	block("RearWalk", Vector3.new(74, 1, 8), Vector3.new(0, -0.5, -29), C.pavement)
	-- Compact, self-authored store fittings. No decorative product is inventory.
	block("DrinkCooler", Vector3.new(2, 7, 5), Vector3.new(26, 3.6, -3.5), C.white)
	-- Painted display silhouettes are decoration, never stock or purchasable objects.
	for i, z in ipairs({ -5, -3.5, -2 }) do
		local silhouette = block("CoolerSilhouette", Vector3.new(0.15, 1.3, 0.7), Vector3.new(24.92, 4, z), ACCENTS[i], false)
		silhouette:SetAttribute("DecorativeOnly", true)
	end
	block("ServiceCounter", Vector3.new(1, 2, 7), Vector3.new(-26.5, 1.1, 3.5), C.wood)
	block("Microwave", Vector3.new(0.8, 1, 2), Vector3.new(-26.5, 2.6, 1), C.dark, false)
	block("CoffeeWater", Vector3.new(0.8, 1.5, 2), Vector3.new(-26.5, 2.85, 5), C.dark, false)
	block("StandingTable", Vector3.new(1, 0.3, 6), Vector3.new(-26.5, 3, 18), C.wood)
	-- Partition sides leave the entire front open for entry and the existing rear door unchanged.
	block("OfficeWarehouseDivider", Vector3.new(0.5, 8, 6), Vector3.new(-9, 4.1, -21), C.wall)
	block("WarehouseSide", Vector3.new(0.5, 8, 6), Vector3.new(12, 4.1, -21), C.wall)
	-- Open front entrance spans between the two side partitions.
	block("WarehouseDoorHeader", Vector3.new(21, 2, 0.4), Vector3.new(1.5, 9.1, -16.2), C.wall)
	block("OfficeDoorHeader", Vector3.new(17, 1, 0.4), Vector3.new(-18, 8.6, -16.2), C.wall)
	local doorwaySign = block("WarehouseDoorSign", Vector3.new(7, 1, 0.1), Vector3.new(0, 9.1, -15.94), C.dark, false)
	text(doorwaySign, "창고")
	-- A side rack provides marked physical storage without occupying WarehouseDrop.
	for _, y in ipairs({ 1.5, 3.5, 5.5 }) do
		local shelf = block("WarehouseShelf", Vector3.new(2, 0.25, 6), Vector3.new(-6, y, -20), C.wood)
		shelf:SetAttribute("StoreId", storeId)
		shelf:SetAttribute("StorageVisualOnly", true)
	end
	local lcd = block("InformationLCD", Vector3.new(0.2, 3.6, 6.4), Vector3.new(-27.35, 10, 3.5), C.dark, false)
	lcd:SetAttribute("SlotId", storeId .. ":IndoorDirect")
	lcd:SetAttribute("ContentMode", "HouseInformation")
	local frame = block("LCDFrame", Vector3.new(0.1, 4, 6.8), Vector3.new(-27.51, 10, 3.5), C.white, false)
	block("LCDStand", Vector3.new(0.2, 0.8, 0.4), Vector3.new(-27.35, 7.8, 3.5), C.dark, false)
	text(lcd, "오늘도 정상영업\n매장 안내", Enum.NormalId.Right)
	-- Legacy Shelf markers keep their contract coordinates; open racks expose lower slots.
	for _, x in ipairs({ -16, 0, 16 }) do
		block("RackLower", Vector3.new(8, 0.3, 3), Vector3.new(x, 1.5, -8), C.wood)
		block("RackUpper", Vector3.new(8, 0.3, 3), Vector3.new(x, 4.5, -8), C.wood)
		block("RackBack", Vector3.new(8, 6, 0.3), Vector3.new(x, 3, -9.7), C.dark)
	end
	for _, markerName in ipairs(config.World.MarkerOrder) do
		local spec = config.World.Markers[markerName]
		if markerName == "Spawn" then
			spawn(store, pivot * CFrame.new(vector(spec.Position)), vector(spec.Size), storeId)
		else
			local logical = markerName == "Entry" or string.sub(markerName, 1, 5) == "Shelf"
			local marker = part(store, markerName, vector(spec.Size), pivot * CFrame.new(vector(spec.Position)),
				if markerName == "Counter" then accent else C.dark, not logical)
			marker:SetAttribute("StoreId", storeId)
			if logical then marker.Transparency = 1 end
		end
	end
	for _, markerName in ipairs(commerce.World.MarkerOrder) do
		local spec = commerce.World.Markers[markerName]
		local marker = part(store, markerName, vector(spec.Size), pivot * CFrame.new(vector(spec.Position)), C.dark, false)
		marker:SetAttribute("StoreId", storeId)
		if markerName == "OfficePC" then
			marker.Color = Color3.fromRGB(65, 170, 185)
			text(marker, "재고 주문 PC")
		elseif markerName == "Alarm" then
			marker.Color = Color3.fromRGB(255, 68, 62)
			local light = Instance.new("PointLight")
			light.Name = "AlarmLight"
			light.Color = marker.Color
			light.Brightness = 2
			light.Range = 24
			light.Shadows = false
			light.Enabled = false
			light:SetAttribute("StoreId", storeId)
			light:SetAttribute("AlarmControlled", true)
			light.Parent = marker
		else marker.Transparency = 1 end
	end
	-- Stable storage anchors for a future authoritative item-to-slot assignment.
	local warehouseSlots = container("Folder", "WarehouseSlots", store)
	local storageIndex = 0
	for _, y in ipairs({ 2.4, 4.4 }) do
		for _, x in ipairs({ -6.4, -5.6 }) do
			for _, z in ipairs({ -22.5, -21.5, -20.5, -19.5, -18.5, -17.5 }) do
				storageIndex += 1
				local id = string.format("Storage%02d", storageIndex)
				local slot = part(warehouseSlots, id, Vector3.new(0.7, 1.4, 0.7), pivot * CFrame.new(x, y, z), C.dark, false)
				slot.Transparency = 1
				slot:SetAttribute("StoreId", storeId)
				slot:SetAttribute("SlotId", id)
				slot:SetAttribute("Capacity", 1)
			end
		end
	end
	local slots = container("Folder", "ShelfSlots", store)
	for i, slotId in ipairs(commerce.World.ShelfSlotIds) do
		local slot = part(slots, slotId, vector(commerce.World.ShelfSlotSize), pivot * CFrame.new(vector(commerce.World.ShelfSlotPositions[i])), C.dark, false)
		slot.Transparency = 1
		slot:SetAttribute("StoreId", storeId)
		slot:SetAttribute("SlotId", slotId)
		slot:SetAttribute("Capacity", commerce.World.ShelfSlotCapacity)
	end
	local route = container("Folder", "TruckRoute", store)
	for i, routeId in ipairs(commerce.World.TruckRouteOrder) do
		local marker = part(route, routeId, Vector3.new(1, 1, 1), pivot * CFrame.new(vector(commerce.World.TruckRoutePositions[routeId])), C.dark, false)
		marker.Transparency = 1
		marker:SetAttribute("StoreId", storeId)
		marker:SetAttribute("RouteId", routeId)
		marker:SetAttribute("Order", i)
	end
	-- No product labels or tray Parts here: the server owns their live contents.
	for i, pos in ipairs({ Vector3.new(-15, 12, 2), Vector3.new(15, 12, 2), Vector3.new(22, 10, -18) }) do
		local fixture = part(lights, "Fixture" .. i, Vector3.new(5, 0.3, 2), pivot * CFrame.new(pos), C.paper, false)
		lamp(fixture, storeId)
	end
	store.WorldPivot = pivot

end

local function unique(parent: Instance, name: string, className: string): Instance
	local found: Instance? = nil
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			assert(found == nil, "NightShift duplicate root child: " .. name)
			assert(child.ClassName == className, "NightShift wrong root type: " .. name)
			found = child
		end
	end
	assert(found, "NightShift missing root child: " .. name)
	return found
end

local function checkRoot(root: Instance): Model
	assert(root:IsA("Model") and root:GetAttribute("NightShiftOwned") == true, "NightShiftWorld ownership/type conflict")
	assert(root:GetAttribute("CommerceLayoutVersion") == 2, "COMMERCE_LAYOUT_MISMATCH: stage and validate a replacement in Edit mode")
	unique(root, "CommerceRuntime", "Folder")
	local hub = unique(root, "Hub", "Model")
	unique(root, "Stores", "Folder")
	unique(hub, "Spawn", "SpawnLocation")
	unique(hub, "StoreSelect", "Part")
	-- Individual store validation belongs to the server, so one damaged store cannot remove the others.
	return root :: Model
end

local function checkBudget(root: Model, config: any)
	local stores = root:FindFirstChild("Stores") :: Folder
	local commonParts, commonLights, totalParts, totalLights, guiObjects = 0, 0, 0, 0, 0
	for _, object in ipairs(root:GetDescendants()) do
		local isStore = object:IsDescendantOf(stores)
		if object:IsA("BasePart") then
			totalParts += 1
			assert(object.Anchored and not object.CastShadow, "World physics/shadow budget violated")
			if not isStore then commonParts += 1 end
		elseif object:IsA("Light") then
			totalLights += 1
			assert(not object.Shadows, "World light shadows must be disabled")
			if not isStore then commonLights += 1 end
		elseif object:IsA("GuiObject") then
			guiObjects += 1
		end
	end
	for _, store in ipairs(stores:GetChildren()) do
		local parts, lights = 0, 0
		for _, object in ipairs(store:GetDescendants()) do
			if object:IsA("BasePart") then parts += 1 end
			if object:IsA("Light") then lights += 1 end
		end
		assert(parts <= config.Budget.StoreParts and lights <= config.Budget.StoreLights, "Store budget exceeded")
		store:SetAttribute("BuildPartCount", parts)
		store:SetAttribute("BuildLightCount", lights)
	end
	assert(commonParts <= config.Budget.CommonParts and commonLights <= config.Budget.CommonLights, "Common budget exceeded")
	assert(totalParts <= config.Budget.TotalParts and totalLights <= config.Budget.TotalLights, "World budget exceeded")
	root:SetAttribute("BuildPartCount", totalParts)
	root:SetAttribute("BuildLightCount", totalLights)
	root:SetAttribute("BuildWorldGuiObjectCount", guiObjects)
end

function Builder.build(parent: Instance): Model
	assert(typeof(parent) == "Instance", "build(parent) expects an Instance")
	local existing: Instance? = nil
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == "NightShiftWorld" then
			assert(existing == nil, "Multiple NightShiftWorld roots; refusing to overwrite")
			existing = child
		end
	end
	if existing then return checkRoot(existing) end
	-- The caller has already bootstrapped Config. Never wait or yield in build().
	local namespace = game:GetService("ReplicatedStorage"):FindFirstChild("NightShift")
	local shared = if namespace then namespace:FindFirstChild("Shared") else nil
	local module = if shared then shared:FindFirstChild("Config") else nil
	assert(module and module:IsA("ModuleScript"), "ReplicatedStorage.NightShift.Shared.Config is required")
	local legacy = require(module :: ModuleScript)
	local commerceModule = shared:FindFirstChild("CommerceConfig")
	assert(commerceModule and commerceModule:IsA("ModuleScript"), "CommerceConfig is required")
	local commerce = require(commerceModule :: ModuleScript)
	assert(commerce.World.LayoutVersion == 2, "Unsupported commerce layout")
	local config = table.clone(legacy)
	config.World = table.clone(legacy.World)
	for _, key in ipairs({ "Name", "OwnerAttribute", "StoreSize", "RoadWidth", "RoadLength", "SidewalkWidth", "HubPosition", "HubSize", "HubSpawn", "HubStoreSelect", "StoreIds", "Stores" }) do
		config.World[key] = commerce.World[key]
	end
	config.Capacity = commerce.Capacity
	config.Budget = commerce.Budget
	assert(config.ContractVersion == "2.0.0", "Unsupported world contract")
	local root = Instance.new("Model")
	root.Name = config.World.Name
	root:SetAttribute(config.World.OwnerAttribute, true)
	root:SetAttribute("CommerceLayoutVersion", commerce.World.LayoutVersion)
	container("Folder", "CommerceRuntime", root)
	local ok, problem = pcall(function()
		local hub = Instance.new("Model")
		hub.Name = config.World.HubName
		hub.Parent = root
		local hubPosition = vector(config.World.HubPosition)
		part(hub, "Plaza", vector(config.World.HubSize), CFrame.new(hubPosition + Vector3.new(0, -0.5, 0)), C.pavement)
		spawn(hub, CFrame.new(vector(config.World.HubSpawn)), Vector3.new(8, 1, 8), nil)
		local selection = part(hub, "StoreSelect", Vector3.new(12, 4, 2), CFrame.new(vector(config.World.HubStoreSelect)), C.dark, false)
		text(selection, "오늘도 정상영업\n8개 점포 · 무료 이동")
		local map = part(hub, "Directory", Vector3.new(18, 7, 0.6), CFrame.new(hubPosition + Vector3.new(0, 6, 16)), C.dark, false)
		text(map, "직선도로 양쪽 4개 점포\nPC 주문 → 후문 하역 → 직접 진열\n음성 없이도 협동 가능")
		local stores = container("Folder", config.World.StoresName, root)
		local streets = container("Model", "Streets", root)
		part(streets, "MainRoad", Vector3.new(config.World.RoadLength, 1, config.World.RoadWidth), CFrame.new(0, -0.5, 0), C.road)
		for _, side in ipairs({ -1, 1 }) do
			part(streets, "Sidewalk", Vector3.new(config.World.RoadLength, 1, config.World.SidewalkWidth), CFrame.new(0, -0.5, side * 17), C.pavement)
			part(streets, "ServiceLane", Vector3.new(config.World.RoadLength, 1, 12), CFrame.new(0, -0.5, side * 91), C.road)
		end
		part(streets, "HubWalk", Vector3.new(10, 1, 12), CFrame.new(-190, -0.5, 27), C.pavement)
		for x = -180, 180, 20 do
			part(streets, "LaneDash", Vector3.new(8, 0.03, 0.4), CFrame.new(x, 0.025, 0), C.paper, false)
		end
		-- Static route contract. The server owns signal phases and movement; these
		-- markers alone never authorize a crossing or a collision/drop.
		local traffic = container("Folder", "Traffic", root)
		local routes = container("Folder", "Routes", traffic)
		local route = container("Folder", "Route01", routes)
		local crossings = container("Folder", "Crossings", traffic)
		local cross = container("Folder", "Cross01", crossings)
		local signals = container("Folder", "Signals", traffic)
		local signal = container("Folder", "Cross01", signals)
		signal:SetAttribute("Phase", "AllRedToWalk"); signal:SetAttribute("PhaseEndsAt", 0)
		local function trafficMarker(parent: Instance, name: string, pos: Vector3, size: Vector3?): Part
			local p = part(parent, name, size or Vector3.new(1, 1, 1), CFrame.new(pos), C.dark, false)
			p.Transparency = 1; p:SetAttribute("CrossingId", "Cross01"); return p
		end
		-- Stops are vehicle centers: the longer 11-stud van keeps its front
		-- behind the visual stop line at x=±10 with 0.5 stud clearance.
		for i, entry in ipairs({ {"VehicleSpawn", -195}, {"VehicleStop", -16}, {"VehicleCrossExit", 16}, {"VehicleExit", 195} }) do
			local p = trafficMarker(route, entry[1] :: string, Vector3.new(entry[2] :: number, 1, -6))
			p:SetAttribute("RouteId", "Route01"); p:SetAttribute("Order", i)
		end
		local reverseRoute = container("Folder", "Route02", routes)
		for i, entry in ipairs({ {"VehicleSpawn", 195}, {"VehicleStop", 16}, {"VehicleCrossExit", -16}, {"VehicleExit", -195} }) do
			local p = trafficMarker(reverseRoute, entry[1] :: string, Vector3.new(entry[2] :: number, 1, 6))
			p:SetAttribute("RouteId", "Route02"); p:SetAttribute("Order", i)
		end
		for _, entry in ipairs({ {"StopLine", -10, -6}, {"CrossingEntryNorth", 0, -12}, {"CrossingExitSouth", 0, 12}, {"WaitNorth", 0, -17}, {"WaitSouth", 0, 17}, {"DropSafeNorth", -5, -17}, {"DropSafeSouth", -5, 17} }) do
			trafficMarker(cross, entry[1] :: string, Vector3.new(entry[2] :: number, 1, entry[3] :: number))
		end
		trafficMarker(cross, "RoadZone", Vector3.new(0, 2, 0), Vector3.new(400, 4, 24))
		for _, spec in ipairs({ {"VehicleSignal", -16.35}, {"PedestrianSignal", 16.35} }) do
			local lampPart = trafficMarker(signal, spec[1] :: string, Vector3.new(-6, 8, spec[2] :: number), Vector3.new(0.6, 0.6, 0.2))
			lampPart.Transparency = 0; lampPart.Material = Enum.Material.Neon; lampPart.Color = Color3.fromRGB(220, 55, 55)
			lampPart:SetAttribute("SignalState", "Stop")
		end
		for _, side in ipairs({ -1, 1 }) do
			part(streets, "SignalPost", Vector3.new(0.5, 8, 0.5), CFrame.new(-6, 4, side*17), C.dark, false)
			local head = part(streets, "SignalHousing", Vector3.new(1.5, 2.5, 1), CFrame.new(-6, 8, side*17), C.dark, false)
			head:SetAttribute("CrossingId", "Cross01")
		end
		for z = -10, 10, 4 do
			part(streets, "CrosswalkStripe", Vector3.new(6, 0.03, 2), CFrame.new(0, 0.11, z), C.paper, false)
		end
		for _, x in ipairs({ -10, 10 }) do
			part(streets, "StopLine", Vector3.new(0.3, 0.03, 10), CFrame.new(x, 0.11, if x < 0 then -6 else 6), C.paper, false)
		end
		local paths = container("Folder", "PedestrianPaths", root)
		for _, storeId in ipairs(config.World.StoreIds) do
			local definition = config.World.Stores[storeId]
			local pivot = CFrame.new(vector(definition.Position)) * CFrame.Angles(0, math.rad(definition.YawDegrees), 0)
			local north = definition.Position[3] < 0
			local s = if north then -1 else 1
			local path = container("Folder", storeId, paths)
			path:SetAttribute("StoreId", storeId); path:SetAttribute("CrossingId", "Cross01")
			local names = { "SidewalkSpawn", "CrossingWait", "CrossingEntry", "CrossingExit", "StoreApproach", "Entry", "Browse", "Checkout", "StoreExit", "SidewalkExit" }
			local positions = { Vector3.new(-6,1,-s*17), Vector3.new(0,1,-s*17), Vector3.new(0,1,-s*12), Vector3.new(0,1,s*17),
				Vector3.new(definition.Position[1],1,s*17), (pivot*CFrame.new(0,1,26)).Position,
				(pivot*CFrame.new(0,1,3)).Position, (pivot*CFrame.new(12,1,12)).Position,
				(pivot*CFrame.new(0,1,26)).Position, Vector3.new(definition.Position[1],1,s*17) }
			for i, name in ipairs(names) do
				local node = trafficMarker(path, name, positions[i]); node:SetAttribute("StoreId", storeId)
				node:SetAttribute("NodeId", name); node:SetAttribute("Order", i)
				node:SetAttribute("NextNodeId", names[i+1] or false)
				node:SetAttribute("Surface", if i==3 or i==4 then "Crosswalk" elseif i>=6 and i<=9 then "Interior" else "Sidewalk")
			end
		end
		for _, x in ipairs({ -160, -80, 80, 160 }) do
			for _, side in ipairs({ -1, 1 }) do
				part(streets, "LampPole", Vector3.new(0.6, 14, 0.6), CFrame.new(x, 7, side * 21), C.dark)
				local fixture = part(streets, "StreetLamp", Vector3.new(3, 0.5, 3), CFrame.new(x, 14, side * 21), C.paper, false)
				lamp(fixture, nil)
			end
		end
		for index, storeId in ipairs(config.World.StoreIds) do makeStore(stores, config, commerce, storeId, index) end
		checkRoot(root)
		checkBudget(root, config)
		Builder.validate(root)
	end)
	if not ok then
		root:Destroy() -- Only our unattached, partially built model.
		error("NightShift world construction failed: " .. tostring(problem))
	end
	root.Parent = parent -- Publish only after the complete hierarchy exists.
	return root
end

-- Explicit candidate validation is separate from per-store runtime availability checks.
-- Use a temporary Folder as build(parent), then validate before replacing the live root.
function Builder.validate(root: Model): Model
	checkRoot(root)
	local namespace = game:GetService("ReplicatedStorage"):FindFirstChild("NightShift")
	local shared = if namespace then namespace:FindFirstChild("Shared") else nil
	assert(shared, "Missing Shared")
	local legacyModule = unique(shared, "Config", "ModuleScript")
	local commerceModule = unique(shared, "CommerceConfig", "ModuleScript")
	local legacy = require(legacyModule :: ModuleScript)
	local commerce = require(commerceModule :: ModuleScript)
	local stores = unique(root, "Stores", "Folder")
	assert(#stores:GetChildren() == #commerce.World.StoreIds, "Unexpected store count")
	local runtime = unique(root, "CommerceRuntime", "Folder")
	assert(#runtime:GetChildren() == 0, "Replacement candidate contains runtime state")
	for _, storeId in ipairs(commerce.World.StoreIds) do
		local store = unique(stores, storeId, "Model") :: Model
		local definition = commerce.World.Stores[storeId]
		local pivot = CFrame.new(vector(definition.Position)) * CFrame.Angles(0, math.rad(definition.YawDegrees), 0)
		assert(store:GetAttribute("StoreId") == storeId and store:GetAttribute("DisplayName") == definition.Name, "Store identity mismatch: " .. storeId)
		assert((store:GetPivot().Position - pivot.Position).Magnitude < 0.001, "Store pivot mismatch: " .. storeId)
		local function marker(parent: Instance, name: string, spec: any, logical: boolean): BasePart
			local object = unique(parent, name, spec.ClassName or "Part") :: BasePart
			assert(object:GetAttribute("StoreId") == storeId, "Marker ownership mismatch: " .. name)
			assert((object.Size - vector(spec.Size)).Magnitude < 0.001, "Marker size mismatch: " .. name)
			assert((object.Position - (pivot * CFrame.new(vector(spec.Position))).Position).Magnitude < 0.001, "Marker position mismatch: " .. name)
			assert(object.Anchored and not object.CanTouch and not object.CastShadow, "Unsafe marker: " .. name)
			if logical then assert(not object.CanCollide and not object.CanQuery, "Solid logic marker: " .. name) end
			return object
		end
		for _, name in ipairs(legacy.World.MarkerOrder) do
			marker(store, name, legacy.World.Markers[name], name == "Entry" or string.sub(name, 1, 5) == "Shelf")
		end
		for _, name in ipairs(commerce.World.MarkerOrder) do
			local object = marker(store, name, commerce.World.Markers[name], true)
			if name ~= "OfficePC" and name ~= "Alarm" then assert(object.Transparency == 1, "Visible logic marker") end
		end
		local slots = unique(store, "ShelfSlots", "Folder")
		assert(#slots:GetChildren() == #commerce.World.ShelfSlotIds, "Unexpected slot count")
		for i, id in ipairs(commerce.World.ShelfSlotIds) do
			local slot = marker(slots, id, {Size = commerce.World.ShelfSlotSize, Position = commerce.World.ShelfSlotPositions[i]}, true)
			assert(slot.Transparency == 1 and slot:GetAttribute("SlotId") == id and slot:GetAttribute("Capacity") == commerce.World.ShelfSlotCapacity, "Slot metadata mismatch")
		end
		local route = unique(store, "TruckRoute", "Folder")
		assert(#route:GetChildren() == #commerce.World.TruckRouteOrder, "Unexpected route count")
		for i, id in ipairs(commerce.World.TruckRouteOrder) do
			local point = marker(route, id, {Size = {1, 1, 1}, Position = commerce.World.TruckRoutePositions[id]}, true)
			assert(point.Transparency == 1 and point:GetAttribute("RouteId") == id and point:GetAttribute("Order") == i, "Route metadata mismatch")
		end
		local alarm = unique(store, "Alarm", "Part")
		local light = unique(alarm, "AlarmLight", "PointLight") :: PointLight
		assert(#alarm:GetChildren() == 1 and not light.Enabled and light:GetAttribute("OutageControlled") == nil, "Alarm must start disabled and separate from outage lights")
	end
	checkBudget(root, commerce)
	return root
end

function Builder.replaceInEdit(parent: Instance, candidate: Model): Model
	assert(not game:GetService("RunService"):IsRunning(), "Replacement requires Edit mode; stop the session first")
	assert(candidate.Parent ~= parent and candidate.Name == "NightShiftWorld", "Build candidate in a separate staging Folder")
	Builder.validate(candidate)
	local old: Instance? = nil
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == "NightShiftWorld" then
			assert(old == nil, "Duplicate existing world roots")
			assert(child:IsA("Model") and child:GetAttribute("NightShiftOwned") == true, "Refusing to replace foreign world")
			old = child
		end
	end
	-- No yielding; unrelated Baseplate, Spawn and Lighting are never touched.
	local previousParent = candidate.Parent
	if old then old.Name = "NightShiftWorld_Previous" end
	local ok, problem = pcall(function() candidate.Parent = parent end)
	if not ok then
		candidate.Parent = previousParent
		if old then old.Name = "NightShiftWorld" end
		error("World replacement failed: " .. tostring(problem))
	end
	if old then old:Destroy() end
	return candidate
end

return Builder
