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
	object.CFrame = cf
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

local function bench(parent: Instance, cf: CFrame, name: string)
	part(parent, name .. "Seat", Vector3.new(10, 0.6, 3), cf * CFrame.new(0, 2, 0), C.wood)
	part(parent, name .. "Back", Vector3.new(10, 2.5, 0.5), cf * CFrame.new(0, 3.3, -1.4), C.wood)
	for _, x in ipairs({ -3.5, 3.5 }) do
		part(parent, name .. "Leg", Vector3.new(0.6, 2, 2.6), cf * CFrame.new(x, 1, 0), C.dark)
	end
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

local function makeStore(stores: Instance, streets: Instance, config: any, storeId: string, index: number)
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
	local accent = ACCENTS[index]
	local function block(name: string, size: Vector3, position: Vector3, color: Color3, solid: boolean?): Part
		return part(decor, name, size, pivot * CFrame.new(position), color, solid)
	end
	block("Floor", Vector3.new(56, 1, 48), Vector3.new(0, -0.5, 0), C.floor)
	block("BackWall", Vector3.new(56, 18, 1), Vector3.new(0, 9, -24.5), C.wall)
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
	-- Warehouse in the rear right: its eight-stud open doorway is x=20..28, z=-12.
	block("WarehouseSide", Vector3.new(0.5, 12, 12), Vector3.new(10, 6, -18), C.wall)
	block("WarehouseFront", Vector3.new(10, 12, 0.5), Vector3.new(15, 6, -12), C.wall)
	local warehouseSign = block("WarehouseSign", Vector3.new(8, 2, 0.4), Vector3.new(24, 11, -12), C.dark, false)
	text(warehouseSign, "창고\n차단기 ↓")
	for _, x in ipairs({ 13, 16 }) do
		block("StorageBox", Vector3.new(2, 2, 2), Vector3.new(x, 1, -21), C.wood)
	end
	for _, markerName in ipairs(config.World.MarkerOrder) do
		local spec = config.World.Markers[markerName]
		if markerName == "Spawn" then
			spawn(store, pivot * CFrame.new(vector(spec.Position)), vector(spec.Size), storeId)
		else
			local marker = part(store, markerName, vector(spec.Size), pivot * CFrame.new(vector(spec.Position)),
				if markerName == "Counter" then accent else C.dark, markerName ~= "Entry")
			marker:SetAttribute("StoreId", storeId)
			if markerName == "Entry" then marker.Transparency = 1 end
		end
	end
	local memo = block("ShiftMemo", Vector3.new(12, 3.5, 0.15), Vector3.new(-12, 7, 8), C.paper, false)
	text(memo, config.Text.Memo, nil, true)
	local panelSign = block("PanelHelp", Vector3.new(10, 2, 0.2), Vector3.new(-21, 8, -19), C.paper, false)
	text(panelSign, "표시판 · 구간 읽기\n연결 → 순서 공유", nil, true)
	local breakerSign = block("BreakerHelp", Vector3.new(8, 2, 0.2), Vector3.new(22, 8, -19), C.paper, false)
	text(breakerSign, "차단기 · 순서 입력\n공유 상태는 화면에서 확인", nil, true)
	-- No product labels or tray Parts here: the server owns their live contents.
	for i, pos in ipairs({ Vector3.new(-15, 12, 2), Vector3.new(15, 12, 2), Vector3.new(22, 10, -18) }) do
		local fixture = part(lights, "Fixture" .. i, Vector3.new(5, 0.3, 2), pivot * CFrame.new(pos), C.paper, false)
		lamp(fixture, storeId)
	end
	store.WorldPivot = pivot
	-- Streets use the same +Z direction, ending exactly at the Hub edge (local z=108).
	local street = container("Model", "Street" .. index, streets)
	part(street, "Road", Vector3.new(config.World.RoadWidth, 1, 84), pivot * CFrame.new(0, -0.5, 66), C.road)
	for _, x in ipairs({ -12, 12 }) do
		part(street, "Sidewalk", Vector3.new(6, 1, 84), pivot * CFrame.new(x, -0.45, 66), C.pavement)
	end
	for z = 42, 98, 14 do
		part(street, "LaneDash", Vector3.new(0.4, 0.03, 5), pivot * CFrame.new(0, 0.025, z), C.paper, false)
	end
	for _, z in ipairs({ 48, 88 }) do
		part(street, "LampPole", Vector3.new(0.7, 14, 0.7), pivot * CFrame.new(-14, 7, z), C.dark)
		local fixture = part(street, "StreetLamp", Vector3.new(3, 0.5, 3), pivot * CFrame.new(-14, 14, z), C.paper, false)
		lamp(fixture, nil)
	end
	local wayfinding = part(street, "Wayfinding", Vector3.new(12, 4, 0.5), pivot * CFrame.new(12, 5, 66), accent, false)
	text(wayfinding, "↑ " .. definition.Name .. " " .. definition.Shape .. "\n↓ 중앙광장")
	text(wayfinding, "↑ 중앙광장\n↓ " .. definition.Name .. " " .. definition.Shape, Enum.NormalId.Front)
	part(street, "SignPost", Vector3.new(0.5, 4, 0.5), pivot * CFrame.new(12, 2, 66), C.dark)
	-- Short side alley with a resting nook; not a required objective detour.
	part(street, "Alley", Vector3.new(22, 1, 16), pivot * CFrame.new(25, -0.5, 44), C.pavement)
	bench(street, pivot * CFrame.new(28, 0, 42), "Rest")
	local backToHub = block("ExitGuide", Vector3.new(8, 2, 0.2), Vector3.new(0, 8, 23), C.dark, false)
	text(backToHub, "중앙광장 ↑\n이동은 무료", Enum.NormalId.Front)
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
	local config = require(module :: ModuleScript)
	assert(config.ContractVersion == "1.0.0", "Unsupported world contract")
	local root = Instance.new("Model")
	root.Name = config.World.Name
	root:SetAttribute(config.World.OwnerAttribute, true)
	local ok, problem = pcall(function()
		local hub = Instance.new("Model")
		hub.Name = config.World.HubName
		hub.Parent = root
		part(hub, "Plaza", vector(config.World.HubSize), CFrame.new(0, -0.5, 0), C.pavement)
		spawn(hub, CFrame.new(vector(config.World.HubSpawn)), Vector3.new(8, 1, 8), nil)
		local selection = part(hub, "StoreSelect", Vector3.new(12, 4, 2), CFrame.new(vector(config.World.HubStoreSelect)), C.dark)
		text(selection, "오늘도 정상영업\n점포 선택 · 무료 이동")
		local map = part(hub, "Directory", Vector3.new(22, 7, 0.6), CFrame.new(0, 6, -24), C.dark)
		text(map, "↑ 01 달빛점 ○\n← 04 별빛점 ◇     02 골목점 △ →\n↓ 03 새벽점 □\n준비 후 근무 · 음성 없이 협동")
		bench(hub, CFrame.new(-24, 0, 10) * CFrame.Angles(0, math.rad(90), 0), "West")
		bench(hub, CFrame.new(24, 0, 10) * CFrame.Angles(0, math.rad(-90), 0), "East")
		local stores = container("Folder", config.World.StoresName, root)
		local streets = container("Model", "Streets", root)
		for index, storeId in ipairs(config.World.StoreIds) do makeStore(stores, streets, config, storeId, index) end
		checkRoot(root)
		checkBudget(root, config)
	end)
	if not ok then
		root:Destroy() -- Only our unattached, partially built model.
		error("NightShift world construction failed: " .. tostring(problem))
	end
	root.Parent = parent -- Publish only after the complete hierarchy exists.
	return root
end

return Builder
