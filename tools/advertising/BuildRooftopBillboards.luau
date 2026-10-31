-- Independent rooftop ads. build/rebuild/validate(world, mode): mode "ad" (default)
-- or "notice". Returns Ok, Code, Reason, Folder, PartCount, AdUnits, Reused.
-- Integrator: install as ModuleScript; call build after Stores exist; log failure and
-- continue core loading. Verify both modes and clearances in Studio before use.
local M = {}
local NAME, OWNER = "RooftopAdvertising", "NightShiftRooftopAdvertisingV1"
local IDS = {"Store01", "Store03", "Store06", "Store08"}
local BOARD_X, FRAME_HALF_WIDTH, FRAME_HALF_DEPTH, EDGE_INSET = -12, 8.4, 0.3, 0.05
local NOTICE = "오늘도 정상영업"
local function modeValue(mode)
    assert(mode == nil or mode == "ad" or mode == "notice", "invalid mode")
    return mode or "ad"
end
local function owned(x)
    return x and x:IsA("Folder") and x:GetAttribute("Owner") == OWNER
end
local function getStores(world)
    assert(world and world:IsA("Model") and world.Name == "NightShiftWorld", "invalid world")
    assert(world:GetAttribute("NightShiftOwned") == true, "foreign world")
    assert(world:GetAttribute("CommerceLayoutVersion") == 2, "unsupported world layout")
    local container = world:FindFirstChild("Stores")
    assert(container and container:IsA("Folder"), "missing Stores")
    local found = {}
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Model") then
            local id = child:GetAttribute("StoreId")
            if table.find(IDS, id) then
                assert(not found[id], "duplicate " .. id)
                found[id] = child
            end
        end
    end
    for _, id in ipairs(IDS) do assert(found[id], "missing " .. id) end
    return found
end
-- A single solid named roof must cover the whole frame footprint in store coordinates.
-- Reject uncertain geometry rather than guessing a height; never include our own folder.
local function roofLayout(store, pivot)
    assert(pivot.UpVector:Dot(Vector3.new(0, 1, 0)) > 0.9999, "tilted store pivot")
    local bounds = {}
    for _, p in ipairs(store:GetDescendants()) do
        if p:IsA("BasePart") and p.Transparency < 1 then
            local h = p.Size * 0.5
            local loX, hiX, loZ, hiZ, hiY = math.huge, -math.huge, math.huge, -math.huge, -math.huge
            for _, x in ipairs({-1, 1}) do for _, y in ipairs({-1, 1}) do for _, z in ipairs({-1, 1}) do
                local w = p.CFrame:PointToWorldSpace(Vector3.new(x*h.X, y*h.Y, z*h.Z))
                local q = pivot:PointToObjectSpace(w)
                loX = math.min(loX, q.X); hiX = math.max(hiX, q.X)
                loZ = math.min(loZ, q.Z); hiZ = math.max(hiZ, q.Z); hiY = math.max(hiY, w.Y)
            end end end
            table.insert(bounds, {part=p, loX=loX, hiX=hiX, loZ=loZ, hiZ=hiZ, top=hiY})
        end
    end
    local roof, boardZ
    local minX, maxX = BOARD_X - FRAME_HALF_WIDTH, BOARD_X + FRAME_HALF_WIDTH
    for _, b in ipairs(bounds) do
        local p = b.part
        local relative = pivot:ToObjectSpace(p.CFrame)
        local aligned = relative.UpVector:Dot(Vector3.new(0,1,0)) > 0.9999
            and (math.abs(relative.RightVector.X) > 0.9999 or math.abs(relative.RightVector.Z) > 0.9999)
        if aligned and p:IsA("Part") and p.Shape == Enum.PartType.Block and p.CanCollide
            and string.find(string.lower(p.Name), "roof", 1, true)
            and b.loX <= minX and b.hiX >= maxX and b.hiZ - b.loZ >= 2 * FRAME_HALF_DEPTH + EDGE_INSET then
            if not roof or b.top > roof then
                roof = b.top
                boardZ = b.hiZ - FRAME_HALF_DEPTH - EDGE_INSET
            end
        end
    end
    assert(roof, "no solid aligned roof covering billboard footprint")
    for _, b in ipairs(bounds) do
        if b.hiX > minX and b.loX < maxX and b.hiZ > boardZ - FRAME_HALF_DEPTH and b.loZ < boardZ + FRAME_HALF_DEPTH then
            assert(b.top <= roof + 0.01, "store geometry obstructs billboard footprint")
        end
    end
    return roof, boardZ, "road-edge"
end
local function expectedFrames(store)
    local pivot = store:GetPivot()
    local roof, boardZ, source = roofLayout(store, pivot)
    local center = pivot:PointToWorldSpace(Vector3.new(BOARD_X, 0, boardZ))
    local base = CFrame.new(center.X, roof, center.Z) * (pivot - pivot.Position)
    return base, base * CFrame.new(0, 6.5, 0) * CFrame.Angles(0, math.pi, 0), source
end
local function closeFrame(a, b)
    return (a.Position-b.Position).Magnitude < 0.01
        and a.RightVector:Dot(b.RightVector) > 0.9999
        and a.UpVector:Dot(b.UpVector) > 0.9999
        and a.LookVector:Dot(b.LookVector) > 0.9999
end
local function part(parent, name, size, cf)
    local p = Instance.new("Part")
    p.Name = name; p.Size = size; p.CFrame = cf; p.Color = Color3.fromRGB(38, 43, 49)
    p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
    p.Parent = parent
    return p
end
local function board(folder, store, id, mode)
    local base, facing, source = expectedFrames(store)
    -- Local +Z points at the road for both rows in the current shared layout.
    local model = Instance.new("Model"); model.Name = id; model:SetAttribute("StoreId", id)
    model:SetAttribute("RoofSource", source); model.Parent = folder
    local panel = part(model, "AdSurface", Vector3.new(16, 9, 0.4), facing)
    if mode == "ad" then
        local gui = Instance.new("AdGui"); gui.Name = "AdGui"; gui.Face = Enum.NormalId.Front
        gui.AdShape = Enum.AdShape.HorizontalRectangle; gui.Enabled = true
        gui.EnableVideoAds = false; gui.Parent = panel
    else
        local gui = Instance.new("SurfaceGui"); gui.Name = "HouseNotice"; gui.Face = Enum.NormalId.Front
        gui.Enabled = true; gui.AlwaysOnTop = false; gui.Parent = panel
        local label = Instance.new("TextLabel"); label.Size = UDim2.fromScale(1, 1)
        label.Position = UDim2.fromScale(0, 0)
        label.Name = "Message"; label.Visible = true; label.BackgroundTransparency = 0; label.TextTransparency = 0
        label.BackgroundColor3 = Color3.fromRGB(35, 65, 62); label.TextColor3 = Color3.fromRGB(255,255,255)
        label.Text = NOTICE; label.TextScaled = true; label.Parent = gui
    end
    part(model, "FrameLeft", Vector3.new(0.4, 9.8, 0.6), facing * CFrame.new(-8.2, 0, 0))
    part(model, "FrameRight", Vector3.new(0.4, 9.8, 0.6), facing * CFrame.new(8.2, 0, 0))
    part(model, "FrameTop", Vector3.new(16, 0.4, 0.6), facing * CFrame.new(0, 4.7, 0))
    part(model, "FrameBottom", Vector3.new(16, 0.4, 0.6), facing * CFrame.new(0, -4.7, 0))
    for _, x in ipairs({-6, 6}) do
        part(model, "Support", Vector3.new(0.5, 2, 0.5), base * CFrame.new(x, 1, 0))
    end
end
local function inspect(world, mode)
    local stores = getStores(world)
    local folder
    for _, x in ipairs(world:GetChildren()) do
        if x.Name == NAME then assert(not folder and owned(x), "duplicate or unowned folder"); folder = x end
    end
    assert(folder and folder:GetAttribute("Mode") == mode, "missing folder or mode mismatch")
    local seen, count, units = {}, 0, 0
    for _, model in ipairs(folder:GetChildren()) do
        assert(model:IsA("Model"), "unexpected child")
        local id = model:GetAttribute("StoreId")
        assert(table.find(IDS, id) and not seen[id] and model.Name == id, "invalid board"); seen[id] = true
        local surface = model:FindFirstChild("AdSurface")
        assert(surface and surface:IsA("Part") and surface.Size == Vector3.new(16,9,0.4), "invalid surface")
        local base, facing = expectedFrames(stores[id])
        assert(closeFrame(surface.CFrame, facing), "surface position or road direction changed")
        local expected = {
            FrameLeft = {facing * CFrame.new(-8.2, 0, 0), Vector3.new(0.4, 9.8, 0.6)},
            FrameRight = {facing * CFrame.new(8.2, 0, 0), Vector3.new(0.4, 9.8, 0.6)},
            FrameTop = {facing * CFrame.new(0, 4.7, 0), Vector3.new(16, 0.4, 0.6)},
            FrameBottom = {facing * CFrame.new(0, -4.7, 0), Vector3.new(16, 0.4, 0.6)},
        }
        local seenParts, left, right, total = {}, false, false, 0
        for _, item in ipairs(model:GetChildren()) do
            assert(item:IsA("Part"), "unexpected board child")
            total += 1
            if item == surface then
                assert(not seenParts.AdSurface, "duplicate surface"); seenParts.AdSurface = true
            elseif item.Name == "Support" then
                assert(item.Size == Vector3.new(0.5, 2, 0.5), "invalid support size")
                if closeFrame(item.CFrame, base * CFrame.new(-6, 1, 0)) then
                    assert(not left, "duplicate left support"); left = true
                elseif closeFrame(item.CFrame, base * CFrame.new(6, 1, 0)) then
                    assert(not right, "duplicate right support"); right = true
                else error("support moved") end
            else
                local spec = expected[item.Name]
                assert(spec and not seenParts[item.Name] and item.Size == spec[2] and closeFrame(item.CFrame, spec[1]), "invalid frame: " .. item.Name)
                seenParts[item.Name] = true
            end
        end
        assert(total == 7 and left and right, "invalid board parts")
        for name in pairs(expected) do assert(seenParts[name], "missing frame: " .. name) end
        local guis = surface:GetChildren(); assert(#guis == 1, "surface must have one GUI")
        local gui = guis[1]
        assert(gui.Face == Enum.NormalId.Front, "invalid face")
        if mode == "ad" then
            assert(gui:IsA("AdGui") and gui.Enabled and not gui.EnableVideoAds
                and gui.AdShape == Enum.AdShape.HorizontalRectangle and #gui:GetChildren() == 0, "invalid AdGui")
            -- Compare with the engine's current default without installing custom fallback content.
            local defaults = Instance.new("AdGui")
            local fallbackMatches = gui.FallbackImage == defaults.FallbackImage
                and gui.FallbackImageContent == defaults.FallbackImageContent
            defaults:Destroy()
            assert(fallbackMatches, "custom fallback is not allowed")
            units += 1
        else
            assert(gui:IsA("SurfaceGui") and gui.Enabled and not gui.AlwaysOnTop, "invalid notice")
            local children = gui:GetChildren()
            local label = children[1]
            assert(#children == 1 and label:IsA("TextLabel") and label.Name == "Message"
                and label.Visible and label.Text == NOTICE and label.TextScaled
                and label.TextTransparency == 0 and label.BackgroundTransparency == 0
                and label.Size == UDim2.fromScale(1, 1) and label.Position == UDim2.fromScale(0, 0)
                and label.TextColor3 == Color3.fromRGB(255,255,255)
                and label.BackgroundColor3 == Color3.fromRGB(35,65,62)
                and #label:GetChildren() == 0, "missing or hidden notice message")
        end
        for _, x in ipairs(model:GetDescendants()) do
            if x:IsA("BasePart") then
                count += 1
                assert(x.Anchored and not x.CanCollide and not x.CanTouch and not x.CanQuery and not x.CastShadow, "unsafe part")
            elseif x:IsA("AdGui") then assert(x == gui and mode == "ad", "unexpected AdGui") end
        end
    end
    for _, id in ipairs(IDS) do assert(seen[id], "missing board " .. id) end
    assert(count == 28 and count <= 80, "invalid count")
    return {Ok=true, Code="OK", Folder=folder, PartCount=count, AdUnits=units}
end
local function protected(fn)
    local ok, value = pcall(fn)
    if not ok then return {Ok=false, Code="ROOFTOP_ADS_ERROR", Reason=tostring(value)} end
    return value
end
function M.validate(world, mode)
    return protected(function() return inspect(world, modeValue(mode)) end)
end
function M.rebuild(world, mode)
    return protected(function()
        mode = modeValue(mode)
        local found = getStores(world)
        local old
        for _, x in ipairs(world:GetChildren()) do
            if x.Name == NAME then assert(not old and owned(x), "duplicate or unowned folder"); old = x end
        end
        local candidate = Instance.new("Folder"); candidate.Name = NAME
        candidate:SetAttribute("Owner", OWNER); candidate:SetAttribute("Mode", mode)
        local ok, err = pcall(function() for _, id in ipairs(IDS) do board(candidate, found[id], id, mode) end end)
        if not ok then candidate:Destroy(); error(err) end
        local committed, reason = pcall(function()
            if old then old.Name = NAME .. "_Replacing" end
            candidate.Parent = world
            inspect(world, mode)
        end)
        if not committed then
            candidate:Destroy()
            if old then old.Name = NAME end
            error(reason)
        end
        if old then old:Destroy() end
        return {Ok=true, Code="OK", Folder=candidate, AddedParts=28, PartCount=28, AdUnits=mode == "ad" and 4 or 0, Reused=false}
    end)
end
function M.build(world, mode)
    local checked = M.validate(world, mode)
    if checked.Ok then checked.Reused = true; checked.AddedParts = 0; return checked end
    return M.rebuild(world, mode)
end
return M
