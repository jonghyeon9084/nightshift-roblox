--!strict
-- ServerStorage.NightShift.BuildBillboards. Requiring this module has no side effects.
-- Optional image ads only; Roblox owns eligibility, delivery and the default fallback.
local Builder = {}

export type Result = {
	Ok: boolean,
	Code: string,
	Folder: Folder?,
	AddedParts: number,
	PartCount: number,
	AdUnits: number,
	Reused: boolean,
	Reason: string?,
}

local FOLDER_NAME = "Advertising"
local OWNER_ATTRIBUTE = "NightShiftBillboardsOwned"
local VERSION = 1
local STREET_PLACEMENTS = {
	{ Name = "RoadWestImage", Position = { -180, 18, -32 }, YawDegrees = 0 },
	{ Name = "RoadEastImage", Position = { 180, 18, 32 }, YawDegrees = 180 },
}
-- Offsets are local to each advertising face; Back (+Z) faces the main road.
local STREET_COMPONENTS = {
	{ Name = "AdSurface", Size = { 16, 9, 0.5 }, Offset = { 0, 0, 0 } },
	{ Name = "Backing", Size = { 17, 10, 0.5 }, Offset = { 0, 0, -0.5 } },
	{ Name = "LeftPost", Size = { 0.5, 13, 0.5 }, Offset = { -5, -11.5, -0.5 } },
	{ Name = "RightPost", Size = { 0.5, 13, 0.5 }, Offset = { 5, -11.5, -0.5 } },
	{ Name = "LeftFoot", Size = { 2, 0.3, 2 }, Offset = { -5, -17.85, -0.5 } },
	{ Name = "RightFoot", Size = { 2, 0.3, 2 }, Offset = { 5, -17.85, -0.5 } },
}
local POSTER = { Position = { 27.75, 10, 6 }, YawDegrees = -90 }
local POSTER_COMPONENTS = {
	{ Name = "AdSurface", Size = { 8, 4.5, 0.2 }, Offset = { 0, 0, 0 } },
	{ Name = "Backing", Size = { 8.5, 5, 0.1 }, Offset = { 0, 0, -0.15 } },
}

type Component = { Name: string, Size: {number}, Offset: {number} }
type Layout = { Name: string, Pivot: CFrame, Components: {Component}, StoreId: string? }

local function vector(values: {number}): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

local function unique(parent: Instance, name: string): Instance?
	local found: Instance? = nil
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			assert(found == nil, "Duplicate billboard child: " .. name)
			found = child
		end
	end
	return found
end

local function checkRoot(root: Model)
	assert(typeof(root) == "Instance" and root:IsA("Model"), "Billboards require an explicit world Model")
	assert(root.Name == "NightShiftWorld" and root:GetAttribute("NightShiftOwned") == true, "Foreign world root")
	assert(root:GetAttribute("CommerceLayoutVersion") == 2, "Unsupported billboard world layout")
end

local function checkOwned(folder: Instance)
	assert(folder:IsA("Folder") and folder:GetAttribute(OWNER_ATTRIBUTE) == true, "Foreign Advertising folder")
end

local function layouts(root: Model): {Layout}
	local result: {Layout} = {}
	for _, placement in ipairs(STREET_PLACEMENTS) do
		table.insert(result, {
			Name = placement.Name,
			Pivot = CFrame.new(vector(placement.Position)) * CFrame.Angles(0, math.rad(placement.YawDegrees), 0),
			Components = STREET_COMPONENTS,
		})
	end
	local stores = unique(root, "Stores")
	assert(stores and stores:IsA("Folder"), "Stores folder is required for wall posters")
	local storeModels = stores:GetChildren()
	assert(#storeModels > 0, "No stores available for wall posters")
	table.sort(storeModels, function(a, b) return a.Name < b.Name end)
	local seen: {[string]: boolean} = {}
	for _, store in ipairs(storeModels) do
		assert(store:IsA("Model") and store:GetAttribute("StoreId") == store.Name, "Invalid store identity")
		assert(not seen[store.Name], "Duplicate store identity")
		seen[store.Name] = true
		table.insert(result, {
			Name = store.Name .. "WallImage", StoreId = store.Name,
			Pivot = store:GetPivot() * CFrame.new(vector(POSTER.Position)) * CFrame.Angles(0, math.rad(POSTER.YawDegrees), 0),
			Components = POSTER_COMPONENTS,
		})
	end
	return result
end

local function countParts(folder: Instance?): number
	local count = 0
	if folder then
		for _, object in ipairs(folder:GetDescendants()) do
			if object:IsA("BasePart") then count += 1 end
		end
	end
	return count
end

local function validateFolder(folder: Instance, definitions: {Layout})
	checkOwned(folder)
	assert(folder:GetAttribute("BillboardVersion") == VERSION, "Billboard version mismatch; use rebuild")
	assert(#folder:GetChildren() == #definitions, "Unexpected billboard count")
	for _, placement in ipairs(definitions) do
		local model = unique(folder, placement.Name)
		assert(model and model:IsA("Model"), "Missing billboard model: " .. placement.Name)
		assert(model:GetAttribute("StoreId") == placement.StoreId, "Billboard store identity mismatch")
		assert(#model:GetChildren() == #placement.Components, "Unexpected billboard components")
		local pivot = placement.Pivot
		for _, spec in ipairs(placement.Components) do
			local object = unique(model, spec.Name)
			assert(object and object:IsA("Part"), "Missing billboard Part: " .. spec.Name)
			assert(object.Shape == Enum.PartType.Block, "Ad geometry must use blocks")
			assert((object.Size - vector(spec.Size)).Magnitude < 0.001, "Billboard size mismatch")
			local expected = pivot * CFrame.new(vector(spec.Offset))
			assert((object.Position - expected.Position).Magnitude < 0.001, "Billboard position mismatch")
			assert(object.CFrame.LookVector:Dot(expected.LookVector) > 0.9999, "Billboard direction mismatch")
			assert(object.CFrame.UpVector:Dot(expected.UpVector) > 0.9999, "Billboard roll mismatch")
			assert(object.Anchored and not object.CanCollide and not object.CanTouch and not object.CanQuery and not object.CastShadow, "Unsafe billboard physics")
			if spec.Name == "AdSurface" then
				assert(#object:GetChildren() == 1, "Ad face must contain exactly one AdGui")
				local ad = unique(object, "ImageAd")
				assert(ad and ad:IsA("AdGui"), "Image AdGui missing")
				assert(ad.Face == Enum.NormalId.Back and ad.Adornee == nil, "AdGui must use its parent Back face")
				assert(ad.AdShape == Enum.AdShape.HorizontalRectangle and ad.Enabled and not ad.EnableVideoAds, "Only enabled image ads are permitted")
				assert(#ad:GetChildren() == 0, "AdGui may not contain custom content")
			else
				assert(#object:GetChildren() == 0, "Decor must not contain interactive content")
			end
		end
	end
end

local function success(folder: Folder, addedParts: number, reused: boolean, adUnits: number): Result
	return {
		Ok = true, Code = "BILLBOARDS_READY", Folder = folder,
		AddedParts = addedParts, PartCount = countParts(folder), AdUnits = adUnits, Reused = reused,
	}
end

local function unavailable(problem: any): Result
	-- This optional subsystem never throws into the world/game bootstrap.
	return { Ok = false, Code = "BILLBOARDS_UNAVAILABLE", AddedParts = 0, PartCount = 0, AdUnits = 0, Reused = false, Reason = tostring(problem) }
end

local function construct(folder: Folder, definitions: {Layout})
	for _, placement in ipairs(definitions) do
		local model = Instance.new("Model")
		model.Name = placement.Name
		if placement.StoreId then model:SetAttribute("StoreId", placement.StoreId) end
		model.Parent = folder
		local pivot = placement.Pivot
		for _, spec in ipairs(placement.Components) do
			local object = Instance.new("Part")
			object.Name = spec.Name
			object.Shape = Enum.PartType.Block
			object.Size = vector(spec.Size)
			object.CFrame = pivot * CFrame.new(vector(spec.Offset))
			object.Color = Color3.fromRGB(28, 35, 49)
			object.Material = Enum.Material.SmoothPlastic
			object.Anchored = true
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.CastShadow = false
			object.TopSurface = Enum.SurfaceType.Smooth
			object.BottomSurface = Enum.SurfaceType.Smooth
			object.Parent = model
			if spec.Name == "AdSurface" then
				local ad = Instance.new("AdGui")
				ad.Name = "ImageAd"
				ad.Parent = object -- Attach before property writes so failure cleanup owns it.
				ad.Face = Enum.NormalId.Back
				ad.AdShape = Enum.AdShape.HorizontalRectangle
				ad.EnableVideoAds = false
				ad.Enabled = true
				-- Do not set FallbackImage/Content or fetch policy: retain Roblox's default logo.
			end
		end
	end
end

local function build(root: Model, force: boolean): Result
	local staged: Folder? = nil
	local ok, result = pcall(function(): Result
		checkRoot(root)
		local definitions = layouts(root)
		local previous = unique(root, FOLDER_NAME)
		if previous then
			checkOwned(previous)
			if not force then
				validateFolder(previous, definitions)
				return success(previous :: Folder, 0, true, #definitions)
			end
		end
		local oldPartCount = countParts(previous)
		local candidate = Instance.new("Folder")
		staged = candidate
		candidate.Name = FOLDER_NAME
		candidate:SetAttribute(OWNER_ATTRIBUTE, true)
		candidate:SetAttribute("BillboardVersion", VERSION)
		construct(candidate, definitions)
		validateFolder(candidate, definitions)
		local ready = success(candidate, countParts(candidate) - oldPartCount, false, #definitions)
		-- No yield: validate the entire candidate before changing the owned subtree.
		candidate.Parent = root
		if previous then previous:Destroy() end
		staged = nil
		return ready
	end)
	if not ok then
		if staged then staged:Destroy() end
		return unavailable(result)
	end
	return result
end

function Builder.build(root: Model): Result
	return build(root, false)
end

function Builder.rebuild(root: Model): Result
	return build(root, true)
end

function Builder.validate(root: Model): Result
	local ok, result = pcall(function(): Result
		checkRoot(root)
		local definitions = layouts(root)
		local folder = unique(root, FOLDER_NAME)
		assert(folder, "Advertising folder missing")
		validateFolder(folder, definitions)
		return success(folder :: Folder, 0, true, #definitions)
	end)
	return if ok then result else unavailable(result)
end

return Builder
