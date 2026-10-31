--!nonstrict
-- Solo-store v2 client. Local UI only; economy and ownership remain server authoritative.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui",10)
if not playerGui then warn("NightShift PlayerGui timeout"); return end
local previous=playerGui:FindFirstChild("NightShiftHUD")
if previous then previous:Destroy() end
local gui=Instance.new("ScreenGui")
gui.Name="NightShiftHUD"; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
-- Default safe inset avoids the Roblox top bar; layout uses the actual available GUI size.
gui.Parent=playerGui
local panel=Instance.new("Frame")
panel.Name="Console"; panel.AnchorPoint=Vector2.new(1,0); panel.Position=UDim2.new(1,-12,0,12)
panel.BackgroundColor3=Color3.fromRGB(19,27,39); panel.BorderSizePixel=0; panel.Parent=gui
local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,12); corner.Parent=panel
local title=Instance.new("TextLabel")
title.Position=UDim2.fromOffset(12,0); title.Size=UDim2.new(1,-72,0,56)
title.BackgroundTransparency=1; title.Text="오늘도 정상영업"; title.Font=Enum.Font.GothamBold
 title.TextSize=20; title.TextColor3=Color3.fromRGB(246,244,229); title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=panel
local close=Instance.new("TextButton")
close.Name="Close"; close.Position=UDim2.new(1,-56,0,4); close.Size=UDim2.fromOffset(48,48)
close.Text="닫기"; close.TextSize=14; close.Font=Enum.Font.GothamMedium; close.BackgroundColor3=Color3.fromRGB(46,91,106)
close.TextColor3=Color3.new(1,1,1); close.Parent=panel
local nav=Instance.new("Frame"); nav.Position=UDim2.fromOffset(12,60); nav.Size=UDim2.new(1,-24,0,48); nav.BackgroundTransparency=1; nav.Parent=panel
local scroll=Instance.new("ScrollingFrame")
scroll.Name="Content"; scroll.Position=UDim2.fromOffset(12,116); scroll.Size=UDim2.new(1,-24,1,-128)
scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=6
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.CanvasSize=UDim2.new(); scroll.Parent=panel
local layout=Instance.new("UIListLayout"); layout.Padding=UDim.new(0,8); layout.SortOrder=Enum.SortOrder.LayoutOrder; layout.Parent=scroll
local modules=script.Parent:WaitForChild("Modules",10)
if not modules then title.Text="UI 모듈 연결 실패"; return end
local Model=require(modules:WaitForChild("CommerceState",10))
local Client=require(modules:WaitForChild("CommerceClient",10))
local commerce,config,nightConfig,folder
local collapsed=false; local page="home"; local dirty=true; local hotkeys={}; local rows={}; local epoch=0; local order=0
local night={Sequence=0,Self=false,Store=false}; local nightRemote={}; local nightPending={}; local nightId=0
local connectionStatus="서버 연결 중"; local bootstrapBusy=false; local attempts=0
local render,bootstrap
local function viewport()
 local camera=workspace.CurrentCamera
 local size=gui.AbsoluteSize
 if size.X<=0 or size.Y<=0 then size=camera and camera.ViewportSize or Vector2.new(390,600) end
 local spec=Model.layout(size.X,size.Y)
 panel.Size=UDim2.fromOffset(spec.Width,collapsed and 56 or spec.Height)
 nav.Visible=not collapsed; scroll.Visible=not collapsed
 close.Text=collapsed and "열기" or "닫기"
end
local function show(nextPage)
 page=nextPage; collapsed=false; dirty=true; scroll.CanvasPosition=Vector2.new(); viewport()
end
local function back()
 if not collapsed and page~="home" then show("home") else collapsed=not collapsed; dirty=true; viewport() end
end
close.Activated:Connect(back)
local function navButton(text,x,callback)
 local b=Instance.new("TextButton"); b.Size=UDim2.new(0.5,-4,1,0); b.Position=UDim2.new(x,x==0 and 0 or 4,0,0)
 b.Text=text; b.Font=Enum.Font.GothamMedium; b.TextSize=16; b.TextColor3=Color3.new(1,1,1)
 b.BackgroundColor3=Color3.fromRGB(46,91,106); b.Parent=nav; b.Activated:Connect(callback)
end
navButton("내 매장 H",0,function() show("home") end)
navButton("발주·재고 V",0.5,function() show("commerce") end)
local function row(class,id)
 order+=1; id=page..":"..class..":"..tostring(id or order)
 local entry=rows[id]
 if not entry then
  entry={Object=Instance.new(class)}; rows[id]=entry; entry.Object.Parent=scroll
  if class=="TextButton" then entry.Object.Activated:Connect(function()
   if dirty then render() end
   if rows[id]==entry and entry.Epoch==epoch and entry.Enabled and entry.Callback then entry.Callback() end
  end) end
 end
 entry.Epoch=epoch; entry.Object.LayoutOrder=order
 return entry
end
local function label(text,height)
 local o=row("TextLabel").Object
 o.Size=UDim2.new(1,-12,0,height or 48); o.AutomaticSize=Enum.AutomaticSize.Y
 o.BackgroundTransparency=1; o.Font=Enum.Font.Gotham; o.TextSize=16; o.TextColor3=Color3.fromRGB(239,240,233)
 o.TextWrapped=true; o.RichText=false; o.TextXAlignment=Enum.TextXAlignment.Left; o.TextYAlignment=Enum.TextYAlignment.Center
 o.Text=tostring(text); return o
end
local function button(text,callback,enabled,key,id)
 local entry=row("TextButton",id or text); local o=entry.Object
 entry.Callback=callback; entry.Enabled=enabled~=false
 o.Size=UDim2.new(1,-12,0,48); o.AutomaticSize=Enum.AutomaticSize.Y; o.TextWrapped=true; o.RichText=false
 o.Font=Enum.Font.GothamMedium; o.TextSize=16; o.TextColor3=enabled==false and Color3.fromRGB(180,186,192) or Color3.new(1,1,1)
 o.BackgroundColor3=enabled==false and Color3.fromRGB(48,55,66) or Color3.fromRGB(46,91,106)
 o.AutoButtonColor=enabled~=false; o.Selectable=enabled~=false
 o.Text=(key and ("["..key.Name.."] ") or "")..text
 if key and entry.Enabled then hotkeys[key]=function()
  if dirty then render() end
  if entry.Epoch==epoch and entry.Enabled then entry.Callback() end
 end end
 return o
end
local function nightSend(action,payload)
 local me=commerce and commerce.state.Self
 if not me or not me.StoreId or not nightRemote.Action or next(nightPending) or not commerce:active() then return end
 nightId+=1
 nightPending[nightId]=os.clock()
 nightRemote.Action:FireServer({ProtocolVersion=2,RequestId=nightId,Action=action,StoreId=me.StoreId,
  RoundId=me.RoundId or false,OwnerGeneration=me.OwnerGeneration,Payload=payload or {}})
end
local function receiveNight(packet)
 if type(packet)~="table" or packet.ProtocolVersion~=2 or type(packet.Sequence)~="number" or packet.Sequence<=night.Sequence then return end
 -- This optional stream only drives the night minigame, never commerce authority.
 if packet.Self then night.Self=packet.Self end
 if packet.Store~=nil then night.Store=packet.Store end
 night.Sequence=packet.Sequence; dirty=true
end
local function renderNight()
 local store=night.Store; local me=night.Self; local owner=commerce.state.Self
 if not store or not me or store.StoreId~=owner.StoreId then label("야간 영업 상태 수신 대기 · 자산과 발주 상태는 위 화면에서 확인하세요.",80); return end
 label("야간 영업 · "..tostring(store.Phase),52)
 if not me.Loaded then button("매장 로드 확인",function() nightSend("SetLoaded",{Loaded=true}) end,true,Enum.KeyCode.L,"loaded") end
 if store.Phase=="Lobby" or store.Phase=="Starting" then
  button(me.Ready and "준비 취소" or "내 매장 영업 시작",function() nightSend("SetReady",{Ready=not me.Ready,RosterVersion=store.RosterVersion}) end,me.Loaded,Enum.KeyCode.E,"ready")
 elseif store.Phase=="Result" then
  label("야간 회차 종료 · 무료로 다시 시작할 수 있어요. 개인 자산은 유지됩니다.",80)
  button("결과 확인 · 무료 재시작",function() nightSend("AcknowledgeResult",{}) end,true,Enum.KeyCode.E,"retry-night")
 end
 local round=store.Round
 if round and round.OutageStatus=="Active" and round.Outage then
  local outage=round.Outage
  label("정전 · 표시판을 읽고 차단기에서 순서대로 복구하세요. 무료이며 자산을 초기화하지 않습니다.",88)
  local shapes={Circle="○",Triangle="△",Square="□"}
  if commerce:near(owner.StoreId,"SignalPanel") then
   local sequence={}
   for _,shape in ipairs(outage.SharedShapes or {}) do table.insert(sequence,shapes[shape] or "?") end
   label("표시판 순서 · "..table.concat(sequence," → "),64)
  else label("표시판 10 studs 이내에서 순서를 확인하세요.",64) end
  label("복구 진도 "..tostring(outage.Progress).."/3",48)
  for _,shape in ipairs({"Circle","Triangle","Square"}) do
   button("차단기 입력 "..shapes[shape],function() nightSend("InputShape",{OutageId=outage.OutageId,Generation=outage.Generation,Shape=shape}) end,
    outage.CanInput and commerce:near(owner.StoreId,"Breaker"),nil,"shape-"..shape)
  end
 end
end
render=function()
 dirty=false; epoch+=1; order=0; hotkeys={}
 if not commerce then
  label(connectionStatus,80)
  button("연결 다시 시도",bootstrap,not bootstrapBusy,Enum.KeyCode.F5,"bootstrap")
 elseif page=="commerce" then commerce:render({Label=label,Button=button})
 else
  local s=commerce.state
  label("1인 1매장 · 빈 매장이 자동 배정됩니다. 매장 번호는 서버마다 달라질 수 있어요.",80)
  if not s.HasSnapshot then label(commerce.status,72); button("서버 상태 재시도",function() commerce:snapshot() end,true,Enum.KeyCode.F5,"snapshot")
  else
   local me=s.Self
   label(me.DisplayName.." · "..(me.StoreId or "빈 매장 대기").."\n게임머니 "..me.Wallet.." · Lv."..me.Level.." / XP "..me.XP,80)
   label("다음 행동 · "..commerce:nextAction(),72)
   if s.ProfileStatus and s.ProfileStatus.Frozen then label("자산 보호 중 · 변경 일시 중지 · "..commerce:reason(s.ProfileStatus.ErrorCode),80) end
   if s.ProfileStatus then label(s.ProfileStatus.Mode=="Memory" and "임시 저장 · 서버 종료 시 보존되지 않아요" or (s.ProfileStatus.Dirty and "저장 대기" or "서버 저장 확인"),64) end
   button("발주·창고·직접 진열 열기",function() show("commerce") end,true,Enum.KeyCode.V,"open-commerce")
   button("개인 목표·대회 결과",function() commerce.section="goals"; show("commerce") end,true,Enum.KeyCode.G,"open-goals")
   renderNight()
  end
  label("WASD / 화면 조이스틱 이동 · PC 근처 Q 발주 · V 재고 · H 내 매장 · Backspace 뒤로 · Tab 접기 · E 표시된 동작\n모든 화면 버튼은 터치와 키보드 선택으로 조작할 수 있어요.",120)
  label("도로에서는 횡단보도·보행 신호를 확인하세요. 음성 없이도 혼자 영업과 정전 복구가 가능합니다.",88)
 end
 for id,entry in pairs(rows) do if entry.Epoch~=epoch then
  if GuiService.SelectedObject==entry.Object then GuiService.SelectedObject=nil end
  entry.Object:Destroy(); rows[id]=nil
 end end
end
bootstrap=function()
 if bootstrapBusy then return end
 bootstrapBusy=true; attempts+=1; dirty=true
 task.spawn(function()
  local ok,reason=pcall(function()
   local root=ReplicatedStorage:WaitForChild("NightShift",10); assert(root,"NightShift timeout")
   local shared=root:WaitForChild("Shared",10); assert(shared,"Shared timeout")
   config=require(shared:WaitForChild("CommerceConfig",10))
   folder=root:WaitForChild("Remotes",10); assert(folder,"Remotes timeout")
   commerce=commerce or Client.new({Config=config,Player=player,Players=Players,Dirty=function() dirty=true end,
    LegacyStore=function() return night.Store end,Work=function() show("home") end,
    Rebind=function() commerce:bind(folder) end})
   commerce:bind(folder)
   local cfg=shared:FindFirstChild("Config")
   if cfg and not nightRemote.Action then
    nightConfig=require(cfg)
    local names=nightConfig.Network.Remotes
    for _,key in ipairs({"Action","ActionResult","State","GetSnapshot"}) do nightRemote[key]=folder:FindFirstChild(names[key]) end
    if nightRemote.State then nightRemote.State.OnClientEvent:Connect(receiveNight) end
    if nightRemote.ActionResult then nightRemote.ActionResult.OnClientEvent:Connect(function(ack)
     if type(ack)~="table" or ack.ProtocolVersion~=2 or not nightPending[ack.RequestId] then return end
     nightPending[ack.RequestId]=nil
     if not ack.Ok then commerce:notify("야간 요청 거절 · "..commerce:reason(ack.Code)) end
    end) end
    if nightRemote.GetSnapshot then task.spawn(function()
     local received,result=pcall(function() return nightRemote.GetSnapshot:InvokeServer({ProtocolVersion=2}) end)
     if received and type(result)=="table" and result.Ok then receiveNight(result.Snapshot) end
    end) end
   end
  end)
  bootstrapBusy=false
  connectionStatus=ok and "서버 상태 확인 중" or ("연결 실패 · F5 재시도 · "..tostring(reason))
  dirty=true
 end)
end
UserInputService.InputBegan:Connect(function(input,processed)
 if processed or UserInputService:GetFocusedTextBox() then return end
 if input.KeyCode==Enum.KeyCode.Backspace or input.KeyCode==Enum.KeyCode.Escape then back()
 elseif input.KeyCode==Enum.KeyCode.Tab then collapsed=not collapsed; dirty=true; viewport()
 elseif input.KeyCode==Enum.KeyCode.H then show("home")
 elseif input.KeyCode==Enum.KeyCode.V then show(page=="commerce" and "home" or "commerce")
 elseif input.KeyCode==Enum.KeyCode.Q and commerce and commerce:active() and commerce:near(commerce.state.Self.StoreId,"OfficePC") then commerce.section="shop"; show("commerce")
 elseif not collapsed and hotkeys[input.KeyCode] then hotkeys[input.KeyCode]() end
end)
local officePrompt,officePart
local function syncOfficePrompt()
 if not commerce or not commerce.state.Self then return end
 local world=workspace:FindFirstChild("NightShiftWorld")
 local stores=world and world:FindFirstChild("Stores")
 local store=stores and stores:FindFirstChild(commerce.state.Self.StoreId or "")
 local markers=store and store:FindFirstChild("Markers")
 local target=store and (store:FindFirstChild("OfficePC") or (markers and markers:FindFirstChild("OfficePC")))
 if officePart~=target then
  if officePrompt then officePrompt:Destroy(); officePrompt=nil end
  officePart=target
  if target and target:IsA("BasePart") then
   officePrompt=Instance.new("ProximityPrompt"); officePrompt.Name="NightShiftLocalOfficePrompt"
   officePrompt.ActionText="발주·재고 열기"; officePrompt.ObjectText="내 매장 사무실 PC"
   officePrompt.KeyboardKeyCode=Enum.KeyCode.Q; officePrompt.MaxActivationDistance=10
   officePrompt.RequiresLineOfSight=true; officePrompt.Parent=target
   officePrompt.Triggered:Connect(function()
    if commerce:active() and commerce:near(commerce.state.Self.StoreId,"OfficePC") then commerce.section="shop"; show("commerce") end
   end)
  end
 end
 if officePrompt then officePrompt.Enabled=commerce:active()==true end
end
local elapsed=0
RunService.Heartbeat:Connect(function(dt)
 elapsed+=dt
 if elapsed<0.2 then return end; elapsed=0
 viewport()
 if commerce then commerce:tick(); syncOfficePrompt(); dirty=true end
 for id,at in pairs(nightPending) do if os.clock()-at>=10 then nightPending[id]=nil; if commerce then commerce:notify("야간 요청 응답 지연 · 상태 확인 후 다시 시도하세요.") end end end
 if dirty and not collapsed then render() end
end)
viewport(); render(); bootstrap()
