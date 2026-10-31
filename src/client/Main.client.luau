--!nonstrict
-- NightShift client: presentation and requests only; the server owns all rules.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then
	warn("NightShift: PlayerGui unavailable after 10 seconds")
	return
end
local old = playerGui:FindFirstChild("NightShiftHUD")
local gui = old or Instance.new("ScreenGui")
gui.Name = "NightShiftHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui
-- Reuse only our namespace; do not clear any other game's GUI.
gui:ClearAllChildren()

local panel = Instance.new("Frame")
panel.Name = "Console"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 12)
panel.Size = UDim2.new(0.38, 0, 0.78, 0)
panel.BackgroundColor3 = Color3.fromRGB(19, 27, 39)
panel.Parent = gui
local size = Instance.new("UISizeConstraint")
size.MinSize = Vector2.new(280, 180)
size.MaxSize = Vector2.new(440, 760)
size.Parent = panel
local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, -16, 0, 30)
header.Position = UDim2.fromOffset(8, 4)
header.BackgroundTransparency = 1
header.Font = Enum.Font.GothamBold
header.TextSize = 20
header.TextColor3 = Color3.fromRGB(246, 244, 229)
header.Text = "오늘도 정상영업"
header.Parent = panel
local notice = header:Clone()
notice.Name = "Notice"
notice.Position = UDim2.fromOffset(8, 36)
notice.Size = UDim2.new(1, -16, 0, 52)
notice.TextSize = 15
notice.TextWrapped = true
notice.Text = "서버 연결 중 · 이동은 WASD / 화면 조이스틱"
notice.Parent = panel
local nav = Instance.new("Frame")
nav.Position = UDim2.fromOffset(8, 92)
nav.Size = UDim2.new(1, -16, 0, 44)
nav.BackgroundTransparency = 1
nav.Parent = panel
local navLayout = Instance.new("UIListLayout")
navLayout.FillDirection = Enum.FillDirection.Horizontal
navLayout.Padding = UDim.new(0, 4)
navLayout.Parent = nav
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Content"
scroll.Position = UDim2.fromOffset(8, 142)
scroll.Size = UDim2.new(1, -16, 1, -150)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

local Config, reducer, state, trayView, loadReporter, loadReport
local trays = {}
local trayCounter
local trayContext
local remotes = {}
local remoteConnections = {}
local page = "work"
local dirty = true
local collapsed = false
local hotkeys = {}
local timers = {}
local liveLabels = {}
local markers: {[string]: any} = {}
local markerConnections = {}
local markerModel
local markerStatus = "맵 준비 중"
local bindKey = false
local bindAttempt = 0
local bindDeadline = 0
local bindNext = 0
local localLoaded = false
local snapshotBusy = false
local snapshotStarted = 0
local snapshotTimedOut = false
local snapshotAttempts = 0
local snapshotNext = 0
local lastSnapshot = -math.huge
local networkStatus = "서버 연결 중"
local feedbackUntil = 0
local versionMismatch = false
local bootstrapBusy = false
local bootstrapAttempts = 0
local bootstrapNext = 0
local requestId = 0
local pending = {}
local lastInput = {}
local lastRenew = 0
local lastSignal = 0
local preview = false
local previewAdornment
local previewColor = 1
local previewColors = { Color3.fromRGB(80, 130, 160), Color3.fromRGB(166, 113, 80), Color3.fromRGB(113, 148, 99) }
local render, snapshot, bootstrap, setPage

local words = {
	Counter="계산대", Shelf1="진열대 1", Shelf2="진열대 2", Shelf3="진열대 3", SignalPanel="표시판", Breaker="차단기",
	Lobby="준비실", Starting="시작 확인", Running="근무 중", Recovery="복귀 대기", Result="근무 결과", Unavailable="이용 불가",
	Hub="광장", Active="진행자", Waiting="다음 근무 대기", Returning="복귀 준비", Reserved="복귀 예약",
	Uncollected="미수집", Carried="운반 중", Tray="계산대 대기", Accepted="접수 완료", Cancelled="인원 조정 취소",
	Pending="예정", Done="완료", None="없음", OrderTimeout="주문 시간 초과", OutageDelay="정전 지연",
	Coop="공동 해결", Solo="단독 해결", Support="지원 복구", Anxiety="불안도 상한", TimeLimit="근무 시간 상한", SoloLeft="단독 진행자 퇴장", AllLeft="진행자 없음",
	NotActive="진행자만 조작 가능", Loading="점포 준비 중", MissingOwner="필요 담당자가 연결되지 않음", Unshared="아직 공유되지 않은 구간이 있어요", NotBreakerOwner="차단기 역할을 맡으세요", NoOutage="정전 없음",
}
local errors = {
	TOO_FAR="대상에서 10걸음(studs) 이내로 이동하세요.", NOT_LOADED="점포 로딩을 다시 확인해 주세요.",
	STALE_ROSTER="명단이 바뀌었어요. 다시 준비해 주세요.", STORE_FULL="정원 4명이 찼어요. 다른 점포를 선택하세요.",
	MOVE_FAILED="이동하지 못했어요. 좌석 상태를 확인하고 무료 재배치를 눌러 주세요.", RATE_LIMIT="잠시 후 다시 눌러 주세요.",
	COOLDOWN="무료 이동은 10초 간격이에요.", NOT_READY="서버 준비 중이에요.", ROLE_TAKEN="동료가 먼저 맡은 역할이에요.",
	NOT_SHARED="표시판 구간을 모두 공유해 주세요.", NOT_ACTIVE="다음 근무 대기 중에는 조작할 수 없어요.",
	INVALID_STATE="현재 단계에서 사용할 수 없어요.", CARRY_FULL="먼저 들고 있는 상품을 놓거나 무료 반납하세요.",
}
local function word(value) return words[value] or tostring(value or "없음") end
local function feedback(message)
	networkStatus = message
	feedbackUntil = os.clock() + 5
	notice.Text = message
end
local function selfState() return state and state.Self or false end
local function storeState() return state and state.Store or false end
local function syncPreview()
	local store = storeState()
	local character = player.Character
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	local eligible = preview and page=="work" and store
		and (store.Phase=="Lobby" or store.Phase=="Starting") and torso and torso:IsA("BasePart")
	if not eligible then
		if previewAdornment then previewAdornment:Destroy() previewAdornment=nil end
		return
	end
	if not previewAdornment or previewAdornment.Adornee~=torso then
		if previewAdornment then previewAdornment:Destroy() end
		previewAdornment=Instance.new("BoxHandleAdornment")
		previewAdornment.Name="NightShiftApronPreview"
		previewAdornment.Adornee=torso
		previewAdornment.AlwaysOnTop=false
		previewAdornment.Transparency=0.15
		previewAdornment.Parent=gui
	end
	previewAdornment.Size=Vector3.new(torso.Size.X*0.8, torso.Size.Y*0.9, 0.06)
	previewAdornment.CFrame=CFrame.new(0, -torso.Size.Y*0.04, -torso.Size.Z/2-0.04)
	previewAdornment.Color3=previewColors[previewColor]
end
local function product(id)
	local p = Config and Config.Products[id]
	return p and (p.Glyph .. " " .. p.Name) or tostring(id)
end
local function clearTrays()
	for _, tray in ipairs(trays) do
		tray.Gui:Destroy()
		tray.Anchor:Destroy()
	end
	trays = {}
	trayCounter = nil
	trayContext = nil
end
local function syncTrays()
	local me = selfState()
	local store = storeState()
	local counter = markers.Counter
	if not trayView or not localLoaded or not store or not me or me.StoreId ~= store.StoreId
		or not counter or not counter:IsDescendantOf(workspace)
		or not markerModel or markerModel:GetAttribute("StoreId") ~= store.StoreId then
		clearTrays()
		return
	end
	local context = trayView.context(store)
	if trayCounter ~= counter or trayContext ~= context then
		clearTrays()
		trayCounter = counter
		trayContext = context
		for index = 1, 3 do
			local offset = Config.World.TrayOffsets[index]
			for _, child in ipairs(counter:GetChildren()) do
				if child.Name == "NightShiftTrayAnchor" .. index or child.Name == "NightShiftTray" .. index then child:Destroy() end
			end
			local anchor = Instance.new("Attachment")
			anchor.Name = "NightShiftTrayAnchor" .. index
			anchor.Position = Vector3.new(offset[1], offset[2], offset[3])
			anchor.Parent = counter
			local trayGui = Instance.new("BillboardGui")
			trayGui.Name = "NightShiftTray" .. index
			trayGui.Adornee = anchor
			trayGui.Size = UDim2.fromOffset(145, 78)
			trayGui.AlwaysOnTop = true
			trayGui.MaxDistance = 28
			trayGui.Parent = counter
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundColor3 = Color3.fromRGB(28, 43, 53)
			text.BackgroundTransparency = 0.1
			text.BorderSizePixel = 2
			text.BorderColor3 = Color3.fromRGB(208, 218, 221)
			text.Font = Enum.Font.GothamBold
			text.TextSize = 16
			text.TextColor3 = Color3.new(1, 1, 1)
			text.TextWrapped = true
			text.Parent = trayGui
			table.insert(trays, {Anchor=anchor, Gui=trayGui, Text=text})
		end
	end
	for index, slot in ipairs(trayView.slots(store)) do
		trays[index].Text.Text = trayView.text(slot, Config.Products)
	end
end
local function shape(id) return Config.ShapeLabels[id] or "? 미공유" end
local function ownerName(id)
	local store = storeState()
	for _, seat in ipairs(store and store.Seats or {}) do
		if seat.UserId == id then return seat.DisplayName .. " (#" .. seat.Seat .. ")" end
	end
	return if id == false then "빈 역할" else "직원 " .. tostring(id)
end
local function send(action, payload, target)
	local me = selfState()
	if not me or not remotes.Action or versionMismatch then return end
	local now = os.clock()
	if action ~= "SetLoaded" and now - (lastInput[action] or -math.huge) < 0.18 then return end
	lastInput[action] = now
	if requestId >= Config.Network.MaxRequestId then
		feedback("요청 번호 한도: 서버에 다시 접속해 주세요.")
		return
	end
	requestId += 1
	local store = storeState()
	local request = { ProtocolVersion=Config.ProtocolVersion, RequestId=requestId, Action=action,
		StoreId=target or me.StoreId, RoundId=if target then false else (store and store.RoundId or false),
		SeatGeneration=me.SeatGeneration, Payload=payload or {} }
	pending[requestId] = { SentAt=now, Action=action, Request=request }
	remotes.Action:FireServer(request)
	return requestId
end

local function reportLoad(desired)
	if not loadReporter then return end
	local now = os.clock()
	if loadReporter.poll(loadReport, selfState(), storeState(), desired, now) then
		local id = send("SetLoaded", {Loaded=desired})
		if id then loadReporter.sent(loadReport, id, now) end
	end
end

local function clearMarkers()
	clearTrays()
	for _, connection in ipairs(markerConnections) do connection:Disconnect() end
	markerConnections = {}
	for _, part in pairs(markers) do
		for _, child in ipairs(part:GetChildren()) do
			if child.Name == "NightShiftLocalLabel" or child.Name == "NightShiftStorePrompt" then child:Destroy() end
		end
	end
	markers = {}
	markerModel = nil
	localLoaded = false
end
local function startBinding(reset)
	clearMarkers()
	if reset then bindAttempt = 0 end
	bindAttempt += 1
	bindDeadline = os.clock() + Config.Loading.MarkerTimeout
	bindNext = 0
	markerStatus = Config.Text.Loading .. " (" .. bindAttempt .. "/" .. Config.Loading.AutomaticAttempts .. ")"
	dirty = true
end
local function findMarkers()
	local world = workspace:FindFirstChild(Config.World.Name)
	local me = selfState()
	local container
	local names
	if me and me.StoreId then
		local stores = world and world:FindFirstChild(Config.World.StoresName)
		container = stores and stores:FindFirstChild(me.StoreId)
		names = Config.World.MarkerOrder
		if not container or container:GetAttribute("StoreId") ~= me.StoreId then return nil end
	else
		container = world and world:FindFirstChild(Config.World.HubName)
		names = { "Spawn", "StoreSelect" }
	end
	if not container then return nil end
	local found = {}
	for _, name in ipairs(names) do
		local part = container:FindFirstChild(name)
		local class = if me and me.StoreId then Config.World.Markers[name].ClassName elseif name=="Spawn" then "SpawnLocation" else "Part"
		if not part or not part:IsA(class) then return nil end
		if me and me.StoreId and part:GetAttribute("StoreId") ~= me.StoreId then return nil end
		found[name] = part
	end
	return found, container
end
local function installLabels()
	local round = storeState() and storeState().Round
	for name, part in pairs(markers) do
		if name ~= "Entry" and name ~= "Spawn" then
			for _, child in ipairs(part:GetChildren()) do
				if child.Name == "NightShiftLocalLabel" then child:Destroy() end
			end
			local labelGui = Instance.new("BillboardGui")
			labelGui.Name = "NightShiftLocalLabel"
			labelGui.Size = UDim2.fromOffset(180, 42)
			labelGui.StudsOffset = Vector3.new(0, 3, 0)
			labelGui.MaxDistance = 35
			labelGui.AlwaysOnTop = true
			labelGui.Parent = part
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundColor3 = Color3.fromRGB(19, 27, 39)
			label.BackgroundTransparency = 0.15
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextSize = 17
			label.Font = Enum.Font.GothamBold
			label.TextWrapped = true
			local index = tonumber(string.match(name, "^Shelf(%d)$"))
			label.Text = if index and round then product(round.ShelfProducts[index]) else ({Counter="계산대 · 놓기 / 접수", SignalPanel="표시판 · 구간 공유", Breaker="차단기 · 순서 입력", StoreSelect="점포 선택 · M"})[name] or name
			label.Parent = labelGui
		end
	end
end
local function watchMarkers()
	local selection = markers.StoreSelect
	if selection then
		local oldPrompt = selection:FindFirstChild("NightShiftStorePrompt")
		if oldPrompt then oldPrompt:Destroy() end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "NightShiftStorePrompt"
		prompt.ActionText = "점포 선택"
		prompt.ObjectText = "무료 이동 안내판"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = Config.Interaction.Distance
		prompt.RequiresLineOfSight = false
		prompt.ClickablePrompt = true
		prompt.HoldDuration = 0
		prompt.Parent = selection
		table.insert(markerConnections, prompt.Triggered:Connect(function() setPage("stores") end))
	end
	for _, part in pairs(markers) do
		table.insert(markerConnections, part.AncestryChanged:Connect(function()
			if localLoaded and (part.Parent ~= markerModel or not part:IsDescendantOf(workspace)) then
				startBinding(true)
				local me = selfState()
				if me and me.StoreId then
					reportLoad(false)
				end
			end
		end))
	end
end
local function refreshLabels()
	if not localLoaded then return end
	for _, part in pairs(markers) do
		local label = part:FindFirstChild("NightShiftLocalLabel")
		if label then label:Destroy() end
	end
	installLabels()
end
local function distance(name)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local part = markers[name]
	if not root or not part or not part:IsDescendantOf(workspace) then return math.huge end
	return (root.Position - part.Position).Magnitude
end
local function nearby(name) return localLoaded and distance(name) <= Config.Interaction.Distance end
local function distanceText(name)
	local value = distance(name)
	return value < math.huge and tostring(math.floor(value)) or "미도착"
end
local function rolePayload(role)
	return { OutageId=role.OutageId, RoleId=role.RoleId, Generation=role.Generation }
end

local function receive(packet)
	local previous = storeState()
	local previousRole = selfState() and selfState().Role
	local accepted, gap, code = reducer.apply(state, packet)
	if code == "VERSION_MISMATCH" then
		versionMismatch = true
		feedback("서버와 버전이 달라요. 게임을 업데이트해 다시 접속하세요.")
		dirty = true
	end
	if not accepted then
		if gap then snapshotNext = math.max(os.clock(), lastSnapshot + Config.Network.SnapshotCooldown) end
		return
	end
	local current = storeState()
	local currentRole = selfState() and selfState().Role
	if currentRole and (not previousRole or currentRole.Generation ~= previousRole.Generation) then
		-- A fresh claim already starts a server lease; do not immediately renew it.
		lastRenew = os.clock()
	end
	if previous and current and previous.RoundId ~= current.RoundId then hotkeys = {} end
	if not current or (current.Phase ~= "Lobby" and current.Phase ~= "Starting") then preview = false end
	syncPreview()
	if packet.Store ~= nil then refreshLabels() end
	syncTrays()
	dirty = true
	if gap then snapshotNext = math.max(os.clock(), lastSnapshot + Config.Network.SnapshotCooldown) end
end

snapshot = function(manual)
	if snapshotBusy or not remotes.GetSnapshot or versionMismatch then return end
	if os.clock() - lastSnapshot < Config.Network.SnapshotCooldown then
		snapshotNext = lastSnapshot + Config.Network.SnapshotCooldown
		return
	end
	if manual then snapshotAttempts = 0 end
	snapshotAttempts += 1
	snapshotBusy = true
	snapshotStarted = os.clock()
	snapshotTimedOut = false
	lastSnapshot = snapshotStarted
	snapshotNext = 0
	feedback("상태 확인 중")
	task.spawn(function()
		local ok, result = pcall(function() return remotes.GetSnapshot:InvokeServer({ ProtocolVersion=Config.ProtocolVersion }) end)
		snapshotBusy = false
		if ok and type(result) == "table" and result.Ok and type(result.Snapshot) == "table" then
			receive(result.Snapshot)
			feedback("상태 연결됨 · 버튼 또는 E로 상호작용")
			snapshotAttempts = 0
		elseif ok and type(result) == "table" and result.Code == "VERSION_MISMATCH" then
			versionMismatch = true
			feedback("서버 버전이 달라요. 게임을 업데이트해 다시 접속하세요.")
		else
			feedback("상태 연결 실패 · 재시도 버튼을 이용하세요.")
			if snapshotAttempts < Config.Loading.AutomaticAttempts then
				snapshotNext = os.clock() + math.max(Config.Loading.RetryDelay, (ok and type(result) == "table" and tonumber(result.RetryAfter)) or 0)
			end
		end
		dirty = true
	end)
end

local function waitPath(root, path, timeout)
	local deadline = os.clock() + timeout
	repeat
		local cursor = root
		for _, name in ipairs(path) do cursor = cursor and cursor:FindFirstChild(name) end
		if cursor then return cursor end
		task.wait(0.1)
	until os.clock() >= deadline
	return nil
end
bootstrap = function(manual)
	if bootstrapBusy or remotes.State or versionMismatch then return end
	if manual then bootstrapAttempts = 0 end
	bootstrapBusy = true
	bootstrapAttempts += 1
	bootstrapNext = 0
	task.spawn(function()
		local configModule = waitPath(ReplicatedStorage, {"NightShift", "Shared", "Config"}, 10)
		local modules = script.Parent:FindFirstChild("Modules")
		local reducerModule = modules and modules:FindFirstChild("StateStore")
		local trayModule = modules and modules:FindFirstChild("TrayView")
		local loadModule = modules and modules:FindFirstChild("LoadReporter")
		local ok, config, storeReducer, storeTrayView, reporter = pcall(function()
			assert(configModule and configModule:IsA("ModuleScript"), "공유 Config 없음")
			assert(reducerModule and reducerModule:IsA("ModuleScript"), "UI StateStore 없음")
			assert(trayModule and trayModule:IsA("ModuleScript"), "UI TrayView 없음")
			assert(loadModule and loadModule:IsA("ModuleScript"), "UI LoadReporter 없음")
			return require(configModule), require(reducerModule), require(trayModule), require(loadModule)
		end)
		if ok then
			Config = config
			reducer = storeReducer
			trayView = storeTrayView
			loadReporter = reporter
			loadReport = loadReport or loadReporter.new()
			state = state or reducer.new(Config.ProtocolVersion)
			local folder = waitPath(ReplicatedStorage, {Config.Namespace, "Remotes"}, Config.Network.BootstrapTimeout)
			local all = {}
			for name, class in pairs({Action="RemoteEvent", ActionResult="RemoteEvent", State="RemoteEvent", GetSnapshot="RemoteFunction"}) do
				local object = folder and folder:FindFirstChild(Config.Network.Remotes[name])
				if not object or not object:IsA(class) then
					ok = false
					break
				end
				all[name] = object
			end
			if ok then
				remotes = all
				table.insert(remoteConnections, remotes.State.OnClientEvent:Connect(receive))
				table.insert(remoteConnections, remotes.ActionResult.OnClientEvent:Connect(function(ack)
					if type(ack) ~= "table" or ack.ProtocolVersion ~= Config.ProtocolVersion then return end
					local entry = pending[ack.RequestId]
					if not entry then return end
					pending[ack.RequestId] = nil
					if entry.Action == "SetLoaded" then loadReporter.ack(loadReport, ack.RequestId, os.clock()) end
					if not ack.Ok then
						feedback(errors[ack.Code] or ("요청 거부: " .. tostring(ack.Code) .. " · 상태를 확인해 주세요."))
						-- LoadReporter bounds reconciliation to two attempts per current context.
						snapshotNext = math.max(os.clock(), lastSnapshot + Config.Network.SnapshotCooldown)
					elseif ack.MoveCode == "MOVE_FAILED" then feedback(errors.MOVE_FAILED) end
				end))
				-- Subscribe before the first snapshot; reducer rejects late/stale responses.
				snapshot(false)
			end
		end
		bootstrapBusy = false
		if not ok then
			feedback("게임 구성 연결 실패 · 연결 재시도 버튼을 눌러 주세요.")
			if bootstrapAttempts < 2 then bootstrapNext = os.clock() + 2 end
		end
		dirty = true
	end)
end

local rows, rowOrder, rowEpoch, rowSerial = {}, 0, 0, 0
local function row(class, identity)
	rowOrder += 1
	local me, store = selfState(), storeState()
	local context = page .. ":" .. tostring(me and me.StoreId) .. ":" .. tostring(store and store.RoundId)
	local id = context .. ":" .. class .. ":" .. (identity or tostring(rowOrder))
	local entry = rows[id]
	if not entry then
		rowSerial += 1
		entry = { Object=Instance.new(class) }
		entry.Object.Name = "NightShiftRow" .. rowSerial
		entry.Object.Parent = scroll
		rows[id] = entry
		if class == "TextButton" then
			entry.Object.Activated:Connect(function()
				-- Refresh callback/revisions before dispatch, keeping the same action object.
				if dirty then render() end
				if rows[id] == entry and entry.Enabled and entry.Callback then entry.Callback() end
			end)
		end
	end
	entry.Epoch = rowEpoch
	entry.Object.LayoutOrder = rowOrder
	return entry
end
local function label(text, height)
	local obj = row("TextLabel").Object
	obj.Size = UDim2.new(1, -8, 0, height or 44)
	obj.BackgroundTransparency = 1
	obj.Font = Enum.Font.Gotham
	obj.TextSize = 16
	obj.TextColor3 = Color3.fromRGB(239, 240, 233)
	obj.TextWrapped = true
	obj.TextXAlignment = Enum.TextXAlignment.Left
	obj.TextYAlignment = Enum.TextYAlignment.Center
	obj.Text = text
	obj.Parent = scroll
	return obj
end
local function button(text, callback, enabled, key, identity)
	local entry = row("TextButton", identity or text)
	local obj = entry.Object
	entry.Callback, entry.Enabled = callback, enabled ~= false
	obj.Size = UDim2.new(1, -8, 0, 48)
	obj.BackgroundColor3 = if enabled == false then Color3.fromRGB(48, 55, 66) else Color3.fromRGB(46, 91, 106)
	obj.TextColor3 = if enabled == false then Color3.fromRGB(168, 173, 180) else Color3.new(1, 1, 1)
	obj.Font = Enum.Font.GothamMedium
	obj.TextSize = 16
	obj.TextWrapped = true
	obj.Text = (if key then "[" .. key.Name .. "] " else "") .. text
	obj.AutoButtonColor = enabled ~= false
	obj.Parent = scroll
	if enabled ~= false then
		if key then hotkeys[key] = function()
			if dirty then render() end
			if entry.Epoch == rowEpoch and entry.Enabled then entry.Callback() end
		end end
	end
	return obj
end
local function liveLabel(callback, height)
	local obj = label(callback(), height)
	table.insert(liveLabels, {Label=obj, GetText=callback})
end
local function timerLabel(title, timer)
	local obj = label("")
	table.insert(timers, { Label=obj, Title=title, Timer=timer, Sample=state.StoreTime })
end
local function resultView(result, current)
	label(Config.Text[result.Code] or "이번 근무가 끝났어요.", 62)
	label("성공 주문 " .. result.SuccessCount .. "/5 · 정전 " .. word(result.OutageResolution) .. "\n종료 원인: " .. word(result.FailureReason), 60)
	label("인원 감소 " .. (result.HadReduction and "있음" or "없음") .. " · 단독 " .. (result.HadSolo and "있음" or "없음") .. " · 지원 " .. (result.HadSupport and "있음" or "없음"), 48)
	if current then
		button(Config.Text.FreeRetry .. " · 새 명단에서 다시 준비", function() send("AcknowledgeResult") end, true, Enum.KeyCode.E)
		timerLabel("자동 준비실 복귀", storeState().ResultTimer)
	end
end

local function renderContent()
	dirty = false
	local oldPosition = scroll.CanvasPosition
	hotkeys = {}
	timers = {}
	liveLabels = {}
	if not Config or not remotes.State then
		label(networkStatus, 80)
		button("연결 재시도", function() bootstrap(true) end, not bootstrapBusy and not versionMismatch, Enum.KeyCode.F5)
		return
	end
	if versionMismatch then
		label("서버 버전이 달라요. 게임을 업데이트해 다시 접속하세요.", 90)
		return
	end
	local me = selfState()
	local store = storeState()
	if not me then
		label(networkStatus, 80)
		button("상태 재시도", function() snapshot(true) end, not snapshotBusy)
		return
	end
	if page == "help" then
		label(Config.Text.Memo, 110)
		label("이동: WASD / 터치 조이스틱\n상호작용: 가까이 가서 E 또는 화면 버튼\n반납 R · 위치 신호 G · 도형 1/2/3\n점포 M · 도움말 H · Tab 화면 접기", 132)
		label("상품: 주문의 번호·이름·도형 확인 → 현재 진열대에서 집기 → 계산대에 놓기 → 접수. 모든 단계는 화면 버튼으로도 가능해요.", 100)
		label(Config.Text.CoopHelp .. "\n" .. Config.Text.SoloHelp, 128)
		label("역할을 맡은 자리에서 연결을 유지하세요. 공유된 순서는 정전 종료까지 남아요. 오입력은 진도만 초기화해요. 음성이나 소리는 필요 없어요.", 104)
		label("혼자 전환 요청은 활성 2명일 때 한 번만 가능해요. 10초 뒤 요청자만 진행하고 동료는 다음 근무를 기다려요. 상대는 기한 전에 취소할 수 있어요.", 112)
		if store then
			button("무료: 점포 입구로 이동", function() send("TravelToEntry") end)
			button("무료: 내 점포 Spawn으로 재배치", function() send("Reposition") end)
			button("점포 퇴장 후 광장으로", function() send("LeaveStore") end)
		end
		if me.LastResult then resultView(me.LastResult, false) end
	elseif page == "stores" or not store then
		label("네 야간 점포 · 빈 좌석을 선택하면 입구로 무료 이동해요. 진행 중 합류는 다음 근무 대기입니다.", 78)
		for index, summary in ipairs(state.Stores) do
			label(summary.SignShape .. " " .. summary.DisplayName .. " · " .. word(summary.Phase) .. "\n좌석 " .. summary.OccupiedSeats .. "/4 · 접속 " .. summary.OnlineCount .. " · 빈자리 " .. summary.FreeSeats, 66)
			local enabled = summary.Available and summary.FreeSeats > 0 and (not store or store.Phase == "Lobby" or store.Phase == "Result")
			local keys = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four}
			button("입장: " .. summary.DisplayName, function() send("JoinStore", {}, summary.StoreId) page="work" dirty=true end, enabled, keys[index])
			if not summary.Available then label("이용 불가: " .. tostring(summary.UnavailableReason), 48) end
		end
		if store and store.Phase ~= "Lobby" and store.Phase ~= "Result" then
			button("현재 점포 퇴장 후 팀 선택", function() send("LeaveStore") end)
		end
		if not store then label(markerStatus, 48) end
	else
		label(Config.World.Stores[store.StoreId].Name .. " · " .. word(store.Phase) .. " · " .. word(me.Participant), 48)
		label(markerStatus, 44)
		local mine
		for _, seat in ipairs(store.Seats) do
			if seat.UserId == me.UserId then mine=seat end
			label("#" .. seat.Seat .. " " .. seat.DisplayName .. " · " .. word(seat.Participant) .. " · " .. (seat.Online and "접속" or "오프라인 예약") .. " · " .. (seat.Ready and "준비 완료" or "준비 전") .. " · " .. (seat.Loaded and "로드 완료" or "로딩"), 56)
		end
		if store.Phase == "Lobby" or store.Phase == "Starting" then
			label(Config.Text.Start, 58)
			button(mine and mine.Ready and "준비 취소" or "팀 준비", function() send("SetReady", {Ready=not (mine and mine.Ready), RosterVersion=store.RosterVersion}) end, localLoaded and me.Loaded, Enum.KeyCode.E, "SetReady")
			if store.Phase == "Starting" then timerLabel("전원 준비 · 시작까지", store.StartTimer) end
			if store.Phase == "Lobby" and #store.Seats == 1 then
				button("혼자 연습 · 정전도 직접 해결", function() send("SoloPractice", {RosterVersion=store.RosterVersion}) end, localLoaded and me.Loaded, Enum.KeyCode.P)
			end
			button(preview and "무료 꾸미기 미리보기 닫기" or "무료 꾸미기 미리보기 · 판매하지 않음", function() preview=not preview dirty=true end)
			if preview then
				local sample = label("앞치마 색 · 내 캐릭터에 나에게만 표시\n무료 · 판매하지 않음 · 소유권을 부여하지 않음", 85)
				sample.BackgroundTransparency = 0
				sample.BackgroundColor3 = previewColors[previewColor]
				button("다음 색 보기", function() previewColor=previewColor % #previewColors + 1 dirty=true end)
			end
		elseif store.Phase == "Result" and store.Result then
			resultView(store.Result, true)
		else
			local round = store.Round
			local active = me.Participant == "Active" and store.Phase == "Running" and localLoaded and me.Loaded
			if round then
				label("주문 " .. round.SuccessCount .. "/5 · 불안 " .. round.Anxiety .. "/100\n증가 원인 " .. word(round.AnxietyCause) .. " · " .. (round.Mode == "Solo" and "혼자 진행" or (round.ActiveCount .. "인 협동")), 64)
				timerLabel("근무 남은 시간", round.ShiftTimer)
				label("진열 변경 " .. word(round.ShuffleStatus) .. " · 정전 " .. word(round.OutageStatus), 44)
				if round.BoundaryKind ~= "None" then
					label(round.BoundaryKind == "Shuffle" and "진열이 바뀝니다. 새 위치를 확인하세요." or "다음 주문 준비 중", 50)
					timerLabel("경계 안내", round.BoundaryTimer)
				end
				if round.BellShown then label("호출벨 표지 · 빈 통로입니다. 손님 탐색은 필요 없어요.", 48) end
				if store.Phase == "Recovery" and round.Recovery then
					label(Config.Text.Recovery .. " · 상품과 도형 진도 보존", 58)
					timerLabel("남은 복귀 대기", round.Recovery.Timer)
					label("재개 준비: " .. (mine and mine.ResumeReady and "완료" or "아직") .. " · 예약 " .. #round.Recovery.ReservedUserIds .. "명", 46)
					button("복귀 / 재개 준비 전환", function() send("ResumeReady", {Ready=not (mine and mine.ResumeReady)}) end, localLoaded and me.Loaded and (me.Participant=="Returning" or me.UserId==round.Recovery.SurvivorUserId), Enum.KeyCode.E)
					if me.UserId == round.Recovery.SurvivorUserId then button("지금 혼자 마무리", function() send("FinishSolo") end, true, Enum.KeyCode.F) end
				end
				if me.Participant == "Waiting" then label("다음 근무 대기 중 · 현재 팀의 주문과 정전은 관람할 수 있어요.", 70) end
				if round.SoloRequest then
					label(ownerName(round.SoloRequest.RequesterUserId) .. "의 혼자 전환 요청 · 완료 시 요청자만 진행하고 동료는 대기합니다.", 76)
					timerLabel("혼자 전환까지", round.SoloRequest.Timer)
					if me.UserId ~= round.SoloRequest.RequesterUserId then button("전환 취소 · 협동 유지", function() send("CancelSolo") end, active) end
				elseif active and round.Mode=="Coop" and round.ActiveCount==2 and not round.SoloRequestUsed and page=="work" then
					button("혼자 전환 요청 · 상대에게 10초 취소 기회", function() send("RequestSolo") end)
				end
				local outage = round.OutageStatus == "Active" and round.Outage
				if outage then
					label(Config.Text.Outage .. "\n" .. (round.Mode=="Solo" and Config.Text.SoloHelp or Config.Text.CoopHelp), 110)
					if round.Order then
						label("진행 중 주문 보존 · 정전이 끝나면 다시 운반 / 접수할 수 있어요.", 66)
						timerLabel("정지된 주문 잔여", round.Order.Timer)
						for _, line in ipairs(round.Order.Lines) do
							label("품목 " .. line.LineId .. ": " .. product(line.ProductId) .. " · " .. word(line.Status), 48)
						end
					end
					if me.Carry then label("손에 든 상품 보존: " .. product(me.Carry.ProductId), 48) end
					timerLabel("지원 복구까지", outage.Timer)
					label("표시판 필요 " .. outage.RequiredPanelCount .. "명 / 연결 " .. outage.ConnectedPanelCount .. "명 · 차단기 필요 " .. outage.RequiredBreakerCount .. "명", 58)
					for _, role in ipairs(outage.Roles) do
						local indices = {}
						for _, index in ipairs(role.Indices) do table.insert(indices, tostring(index)) end
						label((role.RoleId=="Breaker" and "차단기" or "표시판 " .. table.concat(indices, ",") .. "번") .. " · " .. ownerName(role.OwnerUserId) .. "\n" .. (role.Connected and "연결됨" or "미연결") .. " · " .. (role.Shared and "공유 완료" or "공유 전"), 62)
						if not role.OwnerUserId then
							local marker = role.RoleId=="Breaker" and "Breaker" or "SignalPanel"
							button("역할 맡기: " .. (role.RoleId=="Breaker" and "차단기" or "표시판 " .. table.concat(indices, ",") .. "번"), function() send("ClaimRole", {OutageId=outage.OutageId, RoleId=role.RoleId, Generation=role.Generation}) end, active and not me.Role and nearby(marker), not hotkeys[Enum.KeyCode.E] and nearby(marker) and Enum.KeyCode.E or nil)
						end
					end
					local shared, missing = {}, {}
					for index=1,3 do table.insert(shared, index .. ": " .. shape(outage.SharedShapes[index])) end
					for _, index in ipairs(outage.MissingSegments) do table.insert(missing, tostring(index)) end
					label("팀 공유 순서\n" .. table.concat(shared, "  ") .. "\n누락 구간: " .. (#missing>0 and table.concat(missing, ", ") or "없음"), 90)
					local read = {}
					for _, item in ipairs(me.ReadShapes) do table.insert(read, item.Index .. ": " .. shape(item.Shape)) end
					if #read>0 then label("내 표시판 구간: " .. table.concat(read, "  "), 66) end
					label("입력 진도 " .. outage.Progress .. "/3 · " .. (outage.CanInput and "입력 가능" or word(outage.InputBlockReason)), 58)
					if me.Role then
						if me.Role.RoleId ~= "Breaker" then
							button("내 구간 순서 공유", function() send("ShareSegment", rolePayload(me.Role)) end, active and nearby("SignalPanel"), Enum.KeyCode.E)
						else
							for index, id in ipairs(Config.Outage.Shapes) do
								local keys = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three}
								button("입력 " .. shape(id), function() send("InputShape", {OutageId=outage.OutageId, Generation=me.Role.Generation, Shape=id}) end, active and outage.CanInput and nearby("Breaker"), keys[index])
							end
						end
						button("역할 연결 해제", function() send("ReleaseRole", rolePayload(me.Role)) end, true, Enum.KeyCode.Q)
					end
					liveLabel(function() return "표시판 " .. distanceText("SignalPanel") .. " / 차단기 " .. distanceText("Breaker") .. " studs · 역할을 맡을 곳에서 10 이내로 이동" end, 64)
				else
					for index, id in ipairs(round.ShelfProducts) do label("진열대 " .. index .. ": " .. product(id), 40) end
					local order = round.Order
					if order then
						label("주문 " .. order.Stage .. "/5 · 접수 " .. order.AcceptedCount .. "/" .. order.RequiredCount, 46)
						timerLabel("주문 남은 시간", order.Timer)
						for _, line in ipairs(order.Lines) do
							label("품목 " .. line.LineId .. ": " .. product(line.ProductId) .. " · " .. word(line.Status) .. (line.CarrierUserId and (" · " .. ownerName(line.CarrierUserId)) or ""), 58)
							if line.Status == "Uncollected" then
								for index, id in ipairs(round.ShelfProducts) do
									if id==line.ProductId then
										local shelf="Shelf" .. index
										local close = nearby(shelf)
										button("진열대 " .. index .. "에서 집기 · 10 studs 이내에서", function() send("PickUp", {OrderId=order.OrderId, LineId=line.LineId, LineRevision=line.LineRevision, Shelf=shelf}) end, active and not me.Carry and close, not hotkeys[Enum.KeyCode.E] and close and Enum.KeyCode.E or nil)
									end
								end
							elseif line.Status == "Tray" then
								button("품목 " .. line.LineId .. " 계산 접수", function() send("AcceptLine", {OrderId=order.OrderId, LineId=line.LineId, LineRevision=line.LineRevision}) end, active and nearby("Counter"), not hotkeys[Enum.KeyCode.E] and Enum.KeyCode.E or nil)
							end
						end
					end
					if me.Carry then
						label("손에 든 상품: " .. product(me.Carry.ProductId) .. " · 계산대에 놓은 후 접수하세요.", 62)
						local carry=me.Carry
						local payload={OrderId=carry.OrderId, LineId=carry.LineId, LineRevision=carry.LineRevision, CarryToken=carry.CarryToken}
						button("계산대에 상품 놓기", function() send("PutDown", payload) end, active and nearby("Counter"), Enum.KeyCode.E)
						button("무료 반납 · 거리 제한 없음", function() send("ReturnItem", payload) end, active, Enum.KeyCode.R)
					end
				end
				local nearest, best = nil, math.huge
				for _, name in ipairs({"Counter", "Shelf1", "Shelf2", "Shelf3", "SignalPanel", "Breaker"}) do
					local d=distance(name)
					if d<best then nearest=name best=d end
				end
				if nearest then
					local message=if nearest=="SignalPanel" then "PanelHelp" elseif nearest=="Breaker" then "BreakerHelp" else "Here"
					button("위치 신호: " .. word(nearest) .. " · 동료에게 5초 표시", function()
						if os.clock()-lastSignal >= Config.Interaction.SignalCooldown then lastSignal=os.clock() send("Signal", {Target=nearest, Message=message}) end
					end, active and best<=Config.Interaction.Distance, Enum.KeyCode.G)
				end
				for _, signal in ipairs(store.Signals) do
					if signal.ExpiresAt > workspace:GetServerTimeNow() then
						label(ownerName(signal.SenderUserId) .. " → " .. word(signal.Target) .. " · " .. ({Here="여기예요", PanelHelp="표시판 도움 요청", BreakerHelp="차단기 도움 요청"})[signal.Message], 64)
					end
				end
			end
		end
	end
	if bindAttempt >= Config.Loading.AutomaticAttempts and not localLoaded then
		button("맵 재시도 · 최대 5초씩 2회", function() startBinding(true) end)
	end
	if store then
		button("무료: 내 점포 Spawn으로 재배치", function() send("Reposition") end, true, Enum.KeyCode.B)
		button("점포 퇴장 후 광장으로", function() send("LeaveStore") end, true, Enum.KeyCode.X)
	end
	button("상태 재시도", function() loadReporter.reset(loadReport) snapshot(true) end, not snapshotBusy, Enum.KeyCode.F5)
	scroll.CanvasPosition = oldPosition
end

render = function()
	rowEpoch += 1
	rowOrder = 0
	renderContent()
	for id, entry in pairs(rows) do
		if entry.Epoch ~= rowEpoch then entry.Object:Destroy() rows[id]=nil end
	end
end

local function navButton(text, callback)
	local obj=Instance.new("TextButton")
	obj.Size=UDim2.new(1/4, -3, 1, 0)
	obj.BackgroundColor3=Color3.fromRGB(42, 57, 72)
	obj.TextColor3=Color3.new(1, 1, 1)
	obj.TextSize=15
	obj.Font=Enum.Font.GothamMedium
	obj.Text=text
	obj.Parent=nav
	obj.Activated:Connect(callback)
end
setPage = function(value)
	page=value
	scroll.CanvasPosition=Vector2.zero
	dirty=true
end
local function collapse()
	collapsed=not collapsed
	scroll.Visible=not collapsed
	panel.Size=collapsed and UDim2.new(0.38,0,0,142) or UDim2.new(0.38,0,0.78,0)
	size.MinSize=Vector2.new(280, collapsed and 142 or 180)
end
navButton("근무", function() setPage("work") end)
navButton("점포 M", function() setPage("stores") end)
navButton("도움 H", function() setPage("help") end)
navButton("접기 Tab", collapse)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode==Enum.KeyCode.M then setPage("stores")
	elseif input.KeyCode==Enum.KeyCode.H then setPage(page=="help" and "work" or "help")
	elseif input.KeyCode==Enum.KeyCode.Tab then collapse()
	elseif not collapsed and hotkeys[input.KeyCode] then hotkeys[input.KeyCode]() end
end)
player.CharacterRemoving:Connect(function()
	if Config then clearMarkers() bindKey=false loadReporter.reset(loadReport) dirty=true end
end)

-- Reconcile stable action instances at most four times per second.
local elapsed=0
local proximityKey=""
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.25 then return end
	elapsed=0
	local now=os.clock()
	if bootstrapNext>0 and now>=bootstrapNext then bootstrap(false) end
	if snapshotBusy and now-snapshotStarted>=10 and not snapshotTimedOut then
		snapshotTimedOut=true
		feedback("상태 확인 실패 · 응답이 10초 넘게 지연됐어요. 계속되면 다시 접속해 주세요.")
		dirty=true
	end
	if snapshotNext>0 and now>=snapshotNext then snapshot(false) end
	if Config and state then
		syncPreview()
		local me=selfState()
		local key=me and (me.StoreId or "Hub") or "Hub"
		if key~=bindKey then bindKey=key loadReporter.reset(loadReport) startBinding(true) end
		if localLoaded then
			local valid=markerModel and markerModel:IsDescendantOf(workspace)
			for _, part in pairs(markers) do
				if part.Parent ~= markerModel or not part:IsDescendantOf(workspace) then valid=false end
			end
			if not valid then startBinding(true) end
		elseif bindNext>0 then
			if now>=bindNext then startBinding(false) end
		elseif bindDeadline>0 then
			local found, model=findMarkers()
			if found then
				markers=found markerModel=model localLoaded=true bindDeadline=0
				markerStatus="점포 준비 완료 · 가까이 이동해 버튼 / E로 조작"
				installLabels()
				watchMarkers()
				syncTrays()
				snapshotNext=math.max(now, lastSnapshot+Config.Network.SnapshotCooldown)
				dirty=true
			elseif now>=bindDeadline then
				bindDeadline=0
				markerStatus="맵을 불러오지 못했어요. 재시도 / 무료 재배치 / 광장 복귀를 이용하세요."
				if bindAttempt<Config.Loading.AutomaticAttempts then bindNext=now+Config.Loading.RetryDelay end
				dirty=true
			end
		end
		reportLoad(localLoaded)
		if me and me.Role and localLoaded and now-lastRenew>=Config.Outage.RoleRenewSeconds then
			lastRenew=now
			local marker=me.Role.RoleId=="Breaker" and "Breaker" or "SignalPanel"
			if nearby(marker) then send("RenewRole", rolePayload(me.Role)) else send("ReleaseRole", rolePayload(me.Role)) end
		end
		local near={}
		local nearest, closest = "", math.huge
		for _, name in ipairs({"Counter", "Shelf1", "Shelf2", "Shelf3", "SignalPanel", "Breaker"}) do
			local value=distance(name)
			table.insert(near, tostring(value<=Config.Interaction.Distance))
			if value<closest then closest=value nearest=name end
		end
		table.insert(near, nearest)
		local newKey=table.concat(near, ":")
		if newKey~=proximityKey then proximityKey=newKey dirty=true end
		if now>feedbackUntil and me then
			local store=storeState()
			local round=store and store.Round
			local goal
			if versionMismatch then goal="서버 버전이 달라요. 업데이트 후 다시 접속하세요."
			elseif not store then goal="지금 할 일: 점포 M → 빈 점포를 선택하세요."
			elseif not localLoaded then goal="지금 할 일: 맵 재시도 / B 무료 재배치 / X 광장 복귀"
			elseif not me.Loaded then goal="점포 로드 확인 중 · 오래 걸리면 F5 상태 재시도"
			elseif store.Phase=="Lobby" or store.Phase=="Starting" then goal="지금 할 일: E 팀 준비 · 혼자라면 P 연습"
			elseif store.Phase=="Result" then goal="지금 할 일: 결과 확인 → E 무료로 다시 준비"
			elseif store.Phase=="Recovery" then goal="입력 중지: E 복귀 준비 · 남은 직원은 F 혼자 마무리"
			elseif me.Participant~="Active" then goal="다음 근무 대기 중 · 결과 후 새 명단에서 준비하세요."
			elseif round and round.OutageStatus=="Active" and round.Outage then
				if not me.Role then goal="지금 할 일: 빈 표시판 / 차단기 앞으로 이동 → E 역할 맡기"
				elseif me.Role.RoleId=="Breaker" then goal="지금 할 일: 공유 순서 확인 → 차단기에서 1 ○ / 2 △ / 3 □"
				else goal="지금 할 일: 표시판에서 E 내 구간 공유 · 그 자리에서 연결 유지" end
			elseif me.Carry then goal="지금 할 일: 계산대로 이동 → E 놓기 → E 접수 · R 무료 반납"
			else goal="지금 할 일: 미수집 상품은 진열대에서 E 집기 · 계산대 대기는 E 접수" end
			notice.Text=goal
		end
	end
	for id, entry in pairs(pending) do
		if now-entry.SentAt>10 then pending[id]=nil feedback("요청 응답이 지연됐어요. 상태 재시도로 현재 결과를 확인하세요.") end
	end
	if dirty then render() end
	for _, timer in ipairs(timers) do
		local seconds=math.ceil(reducer.remaining(timer.Timer, timer.Sample, workspace:GetServerTimeNow()))
		timer.Label.Text=timer.Title .. ": " .. seconds .. "초" .. (timer.Timer and not timer.Timer.Running and " · 정지" or "")
	end
	for _, item in ipairs(liveLabels) do item.Label.Text=item.GetText() end
end)
bootstrap(false)
render()
