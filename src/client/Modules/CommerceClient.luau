--!nonstrict
-- Presentation only. All revisions, stock, money and carry tokens come from server packets.
local Model = require(script.Parent.CommerceState)
local Client = {}
Client.__index = Client
local toolNames = {HandCarry="손운반", Handcart="손수레 (2개)", StockScanner="재고 스캐너", LayoutPreset="진열 프리셋", ToolStyle="도구 외형"}
local states = {Reserved="예약 · 출발 전 취소 가능", InTransit="배송 중", Docked="도착 · 직접 하역", Completed="배송 완료", Cancelled="취소됨", Recalled="회수됨",
	Truck="트럭", Warehouse="창고", Shelf="진열대", Carried="운반 중", TheftCarried="도난 운반 중", Recoverable="회수 가능"}
local errors = {STALE_STOCK="공용 재고가 바뀌었어요. 최신 잔량을 확인하세요.", OUT_OF_STOCK="공용 재고 소진", INSUFFICIENT_FUNDS="개인 게임머니가 부족해요.",
	PROTECTED="초보 또는 빈 점포 보호 중", TOO_FAR="대상 가까이 (10 studs 이내) 이동하세요.", NO_LINE_OF_SIGHT="대상이 보이는 곳으로 이동하세요.",
	STALE_ITEM="상품 상태가 바뀌었어요.", BAD_TOKEN="운반 권한이 바뀌었어요.", LEVEL_LOCKED="무료 해금 레벨에 도달해 주세요.",
	PROFILE_UNAVAILABLE="프로필 준비 또는 저장 복구를 기다려 주세요.", SLOT_FULL="진열 슬롯이 가득 찼어요.", SKU_MISMATCH="같은 상품만 한 슬롯에 진열할 수 있어요.",
	ORDER_LIMIT="점포 보관·진행 주문·회차 주문 한도를 확인하세요.", CARRY_FULL="운반 공간을 먼저 비워 주세요.", RATE_LIMIT="잠시 후 다시 시도하세요.",
	INVALID_STATE="현재 상태에서는 처리할 수 없어요. 취소는 출발 전에만 가능합니다.", NOT_OWNER="자기 점포 상품과 컴퓨터를 이용하세요.",
	NOT_ACTIVE="근무가 진행 중일 때 이용하세요.", DELIVERY_FAILED="배송을 준비하지 못했어요. 확정 상태를 확인하세요.", NOT_FOUND="대상이 사라졌어요. 최신 상태를 확인하세요.",
	NOT_LOADED="점포 준비가 끝날 때까지 기다려 주세요.", NOT_MEMBER="내 매장 자동 배정을 기다려 주세요.", STORE_UNAVAILABLE="점포 준비 상태를 확인하세요.",
	STALE_ROUND="근무 회차가 바뀌었어요. 최신 상태를 확인하세요.", STALE_SEAT="매장 소유 상태가 바뀌었어요. 최신 상태를 확인하세요.",
	INVALID_MOVEMENT="이동 상태 확인 중이에요. 대상 앞에서 잠시 멈춘 뒤 다시 시도하세요."}
for code,text in pairs({STALE_OWNER="매장 배정이 바뀌었어요 · 최신 상태를 확인하세요",STALE_PROFILE="프로필이 갱신됐어요 · 최신 상태를 확인하세요",PROFILE_FROZEN="자산 보호 중 · 저장 복구를 기다리세요",LEASE_LOST="저장 연결 종료 · 재접속이 필요해요",SESSION_LOCKED="다른 연결에서 사용 중 · 기존 저장을 보호합니다",RESTORE_FAILED="재고 복원 실패 · 기존 저장 보호 중",STORE_FULL="8개 매장 사용 중 · 빈 매장을 기다리세요",NEXT_CYCLE="참가 변경 마감 · 다음 회차 준비 중 선택하세요",UPGRADE_MAX="최대 창고 단계입니다",SAVE_FAILED="저장 실패 · 마지막 저장 이후 변경은 보존되지 않을 수 있어요"}) do errors[code]=text end
function Client.new(deps)
	return setmetatable({deps=deps, config=deps.Config, state=Model.new(), remotes={}, pending={}, requestId=0,
		lastInput=-math.huge, lastSnapshot=-math.huge, snapshotBusy=false, snapshotNext=0,
		status="상거래 연결 대기", section="shop", selectedSlot="Slot01", quantity=1, restockCycle=false,
		connections={}, bound=false, versionMismatch=false}, Client)
end
function Client:name(sku)
	local p=self.config.Products[sku]
	return p and ((p.Rarity=="Rare" and "★ 희귀 · " or "") .. p.Name) or tostring(sku)
end
function Client:context()
 local me=self.state.Self
 if not me or not me.StoreId then return nil end
 return {StoreId=me.StoreId,OwnerGeneration=me.OwnerGeneration,RoundId=me.RoundId or false}
end
function Client:notify(text)
	self.status=text
	self.deps.Dirty()
end
function Client:receive(packet)
 if self.deps.Player.UserId and (type(packet)~="table" or (packet.Self~=nil and (type(packet.Self)~="table" or packet.Self.UserId~=self.deps.Player.UserId))) then return false end
	local accepted, gap, code=Model.apply(self.state, packet, os.clock())
	if code=="VERSION_MISMATCH" then self.versionMismatch=true self:notify("상거래 버전 불일치 · 재접속이 필요해요.") end
	if accepted then
  local me=self.state.Self
  local ownerContext=table.concat({tostring(me.UserId),tostring(me.StoreId),tostring(me.OwnerGeneration),tostring(me.ProfileEpoch),tostring(me.RoundId)},":")
  if self.noticeContext~=ownerContext then self.lastSales=nil; self.salesNotice=nil; self.notice=nil end
  self.noticeContext=ownerContext
  for _,e in ipairs(self.state.NewCustomerEvents or {}) do
   if e.CustomerKind=="Rich" then
    local text=e.Kind=="NpcSaleCommitted" and ("부자 손님 구매 · "..e.Units.."개 / 매출 "..e.Revenue)
     or (e.Kind=="NpcVisited" and "부자 손님 방문 · 진열대 도착" or "부자 손님 퇴장")
    self.notice={Text=text,ExpiresAt=e.ExpiresAt,EventId=e.EventId}
   end
  end
  local wholesale=self.state.Wholesale
		if wholesale and wholesale.Cycle~=self.restockCycle then
			self.restockCycle=wholesale.Cycle
			local rare={}
			for _, row in ipairs(wholesale.Rows) do if row.Rarity=="Rare" and (row.PublicAvailable or 0)>0 then table.insert(rare,self:name(row.Sku)) end end
			-- Identical server Wholesale cycle for every store; no private scanner advantage.
			self.rareNotice=#rare>0 and ("공용 희귀 재고 알림: " .. table.concat(rare,", ")) or "이번 회차 희귀 재고 없음"
		end
		local owner=self.state.Self
  for _,summary in ipairs(self.state.Stores) do if owner and summary.OwnerUserId==owner.UserId then
   if self.lastSales~=nil and summary.Sales>self.lastSales then
    self.salesNotice="서버 확정 매출 갱신 · 판매 "..summary.Sales.."개 / 매출 "..summary.Revenue
   end
   self.lastSales=summary.Sales
  end end
  self.deps.Dirty()
 end
 if gap then self.snapshotNext=math.max(os.clock(),self.lastSnapshot+2) end
 return accepted
end
function Client:bind(folder)
	if self.bound then return true end
	local found={}
	for key, class in pairs({Action="RemoteEvent", ActionResult="RemoteEvent", State="RemoteEvent", GetSnapshot="RemoteFunction"}) do
		local remote=folder and folder:FindFirstChild(self.config.Network.Remotes[key])
		if not remote or not remote:IsA(class) then self:notify("상거래 서버 연결 대기 · 다시 연결을 누르세요.") return false end
		found[key]=remote
	end
	self.remotes=found self.bound=true
	table.insert(self.connections,found.State.OnClientEvent:Connect(function(packet) self:receive(packet) end))
	table.insert(self.connections,found.ActionResult.OnClientEvent:Connect(function(ack)
		if type(ack)~="table" or ack.ProtocolVersion~=2 or not self.pending[ack.RequestId] then return end
		local entry=self.pending[ack.RequestId]
  if ack.Action~=entry.Action or (self.state.Self and ack.OwnerGeneration~=self.state.Self.OwnerGeneration) then
   self.snapshotNext=math.max(os.clock(),self.lastSnapshot+2); return
  end
  self.pending[ack.RequestId]=nil
  self:notify(ack.Ok and "서버 승인 · 상태 갱신을 기다리는 중" or (errors[ack.Code] or ("요청 거부: " .. tostring(ack.Code))))
		self.snapshotNext=math.max(os.clock(),self.lastSnapshot+2)
	end))
	-- Subscribe before invoking snapshot. Ack is never an inventory/profile update.
	self:snapshot()
	return true
end
function Client:snapshot()
	if not self.bound or self.snapshotBusy or self.versionMismatch then return end
	local now=os.clock()
	if now-self.lastSnapshot<2 then self.snapshotNext=self.lastSnapshot+2 return end
	self.lastSnapshot=now self.snapshotBusy=true self.snapshotNext=0 self.snapshotStarted=now self.slow=false
	task.spawn(function()
		local ok,result=pcall(function() return self.remotes.GetSnapshot:InvokeServer({ProtocolVersion=2}) end)
		self.snapshotBusy=false
		if ok and type(result)=="table" and result.Ok and type(result.Snapshot)=="table" then
			if self:receive(result.Snapshot) then self:notify("서버 상태 연결됨") else self:notify("서버 패킷을 적용하지 못했어요 · 버전/소유권 확인 필요") end
		else
			if ok and type(result)=="table" and result.Code=="VERSION_MISMATCH" then self.versionMismatch=true end
			self:notify("상거래 상태 확인 실패 · 상태 재시도를 누르세요.")
		end
	end)
end
function Client:send(action,payload)
	local context=self:context()
	if not self.bound or self.versionMismatch or not self.state.HasSnapshot or not context then return end
	-- Recheck at dispatch: a visible callback can outlive the player's PC proximity.
	if action=="OrderStock" or action=="BuyUpgrade" or action=="RequestRecoveryStock" or action=="SavePreset" or action=="ApplyPreset" then
		if not self:active() or not self:near(context.StoreId,"OfficePC") then
			self:notify("조회 전용 · 자기 사무실 컴퓨터 앞으로 이동해 Q 또는 터치 안내를 누르세요.") return
		end
	end
	if not self:active() then self:notify("프로필 또는 소유권 확인 중 · 변경할 수 없어요.") return end
	if next(self.pending) then self:notify("이전 요청 확인 중 · 중복 입력을 기다려 주세요.") return end
	if os.clock()-self.lastInput<0.2 then return end
	if self.requestId>=self.config.Network.MaxRequestId then self:notify("요청 번호 한도 · 재접속하세요.") return end
	self.lastInput=os.clock() self.requestId+=1
	local request=Model.request(context,action,payload,self.requestId)
	self.pending[self.requestId]={At=os.clock(),Action=action,OwnerGeneration=context.OwnerGeneration}
	self.remotes.Action:FireServer(request)
	self:notify("서버 승인 요청 중 · " .. action)
end
function Client:tick()
	local now=os.clock()
	if self.snapshotNext>0 and now>=self.snapshotNext then self:snapshot() end
	if self.snapshotBusy and now-self.snapshotStarted>=10 and not self.slow then
		self.slow=true self:notify("상거래 응답 10초 지연 · 계속되면 재접속하세요.")
	end
	for id, entry in pairs(self.pending) do if now-entry.At>=10 then
		self.pending[id]=nil; self.snapshotNext=math.max(os.clock(),self.lastSnapshot+2); self:notify("상거래 요청 응답 지연 · 재시도로 확정 상태를 확인하세요.")
	end end
end
function Client:near(storeId,marker,slotId)
	local root=self.deps.Player.Character and self.deps.Player.Character:FindFirstChild("HumanoidRootPart")
	local world=workspace:FindFirstChild("NightShiftWorld")
	local stores=world and world:FindFirstChild("Stores")
	local store=stores and stores:FindFirstChild(storeId or "")
	local markers=store and store:FindFirstChild("Markers")
	local target=store and (store:FindFirstChild(marker) or (markers and markers:FindFirstChild(marker)))
	if slotId then target=target and target:FindFirstChild(slotId) end
	return root and target and target:IsA("BasePart") and (root.Position-target.Position).Magnitude<=self.config.Interaction.Distance or false
end
function Client:active()
 local s=self.state; local p=s.ProfileStatus; local me=s.Self; local store=s.Store
 return s.HasSnapshot and not self.versionMismatch and p and not p.Frozen
  and (p.State=="Ready" or p.State=="Temporary" or p.State=="Saving" or p.State=="SaveFailed")
  and me and store and me.StoreId==store.StoreId and me.UserId==store.OwnerUserId and me.OwnerGeneration==store.OwnerGeneration
end
function Client:itemNear(item)
	if item.State=="Warehouse" or item.State=="SafeStorage" then return self:near(item.OwnerStoreId,"WarehouseDrop") end
 if item.State=="TheftCarried" and self.deps.Players then
  local carrier=self.deps.Players:GetPlayerByUserId(item.CarrierUserId)
  local other=carrier and carrier.Character and carrier.Character:FindFirstChild("HumanoidRootPart")
  local own=self.deps.Player.Character and self.deps.Player.Character:FindFirstChild("HumanoidRootPart")
  return own and other and (own.Position-other.Position).Magnitude<=self.config.Interaction.Distance or false
 end
	if item.State=="Shelf" then return self:near(item.OwnerStoreId,"ShelfSlots",item.SlotId) end
	local root=self.deps.Player.Character and self.deps.Player.Character:FindFirstChild("HumanoidRootPart")
	local world=workspace:FindFirstChild("NightShiftWorld")
	local runtime=world and world:FindFirstChild("CommerceRuntime")
	local items=runtime and runtime:FindFirstChild("Items")
	local target=items and items:FindFirstChild(item.ItemId)
	if item.State=="Truck" then
		local trucks=runtime and runtime:FindFirstChild("Trucks")
		local truck=trucks and trucks:FindFirstChild(item.OrderId or "")
		target=(truck and truck:FindFirstChild("Cargo")) or target
	end
	local position=target and (target:IsA("BasePart") and target.Position or target:IsA("Model") and target:GetPivot().Position)
 return root and position and (root.Position-position).Magnitude<=self.config.Interaction.Distance or false
end
-- Every visible number below is a projection of the accepted v2 stream.
local nextWords={WaitForProfile="프로필 확인을 기다리세요",WaitForStore="빈 매장 자동 배정을 기다리세요",GoToPC="내 사무실 PC에서 발주하세요",WaitForDelivery="배송 트럭을 기다리세요",Unload="트럭 짐칸에서 직접 집으세요",Warehouse="창고 앞에서 상품을 보관하세요",PlaceShelf="창고에서 꺼내 선반에 직접 진열하세요",WaitForCustomer="진열 상품을 구매할 손님을 기다리세요",RestorePower="표시판 순서를 확인하고 차단기를 복구하세요",FreeRecovery="내 PC에서 무료 외상 회복을 확인하세요",ViewResults="회차 결과와 다음 목표를 확인하세요"}
local reasons={Departed="회차 도중 퇴장 · 이번 비교 제외",PersonalOnly="혼자 진행한 개인 기록",NotComparable="동등한 비교 기회 미충족",NEXT_CYCLE="다음 회차 참가 가능",INSUFFICIENT_FUNDS="목표 발주 비용 부족 · 일반 영업/무료 회복 후 다음 회차",SUPPLY_UNAVAILABLE="목표 물량 준비 대기",OUT_OF_STOCK="목표 공급 부족",NO_PARTICIPANTS="참가자 없음"}
local phaseWords={Preparing="준비",Prepare="준비",Active="진행",Running="진행",Finished="종료",Ended="종료",Finalized="결과 확정",Pending="대기",Waiting="준비 대기"}
function Client:reason(code) return reasons[code] or errors[code] or (code and tostring(code) or "사유 수신 대기") end
function Client:nextAction() return nextWords[self.state.Self and self.state.Self.NextAction] or "서버의 다음 행동 안내를 기다리세요" end
function Client:render(ui)
 local label=ui.Label
 local primary=false
 local function button(text,callback,enabled,key,id)
  if next(self.pending) and id and string.sub(id,1,4)=="act-" then enabled=false end
  if enabled and not key and id and string.sub(id,1,4)=="act-" and not primary then key=Enum.KeyCode.E; primary=true end
  return ui.Button(text,callback,enabled,key,id)
 end
 local s=self.state
 label(self.status,48)
 if not self.bound then button("서버 다시 연결",self.deps.Rebind,true,nil,"rebind"); return end
 button("상태 새로고침",function() self:snapshot() end,not self.snapshotBusy,Enum.KeyCode.F5,"refresh")
 if not s.HasSnapshot then label("내 매장 자동 배정·프로필·재고 수신 대기\n서버 확정 전에는 구매할 수 없어요.",88); return end
 local me,store=s.Self,s.Store
 local own=me.StoreId; local active=self:active(); local pc=active and self:near(own,"OfficePC")
 local now=Model.now(s,os.clock()); local storage=Model.storage(store,self.config.Wholesale.MaxItemsPerStore)
 label(me.DisplayName.." · "..(own or "빈 매장 자동 배정 대기").."\n게임머니 "..me.Wallet.." · Lv."..me.Level.." / XP "..me.XP,76)
 label("다음 행동 · "..self:nextAction(),64)
 local save=s.ProfileStatus
 if save then
  local text=save.Mode=="Memory" and "임시 저장 모드 · 서버 종료 뒤 보존되지 않아요" or (save.Dirty and "저장 대기 · 마지막 변경 저장 미확인" or "서버 저장 확인 · 버전 "..tostring(save.SavedRevision))
  if save.Frozen then text="진행 보호 중 · 자산 변경 일시 중지" end
  label(text.."\n프로필 "..save.State..(save.ErrorCode and (" · "..self:reason(save.ErrorCode)) or ""),80)
 end
 if self.salesNotice then label(self.salesNotice,64) end
 if self.notice and self.notice.ExpiresAt>now then label(self.notice.Text,64) end
 label("차량 주의 · 횡단보도와 보행 신호를 이용하세요. 충돌하면 운반 상품만 떨어지며 지갑·업그레이드는 유지됩니다.",96)
 for _,signal in ipairs(s.Traffic and s.Traffic.Signals or {}) do
  label(signal.CrossingId.." · "..(signal.PedestrianGo and "보행 가능 · 좌우 확인" or "보행 대기").." · "..math.ceil(math.max(0,signal.PhaseEndsAt-now)).."초",56)
 end
 for _,summary in ipairs(s.Stores) do
  local alarm=summary.Alarm
  if alarm and alarm.RecoverUntil>now then label("도난 경보 · "..summary.StoreId.."\n상품 "..alarm.ItemId.." · 원소유자 회수 "..math.ceil(alarm.RecoverUntil-now).."초 · 상품 화면에서 위치 확인",96) end
 end
 local keys={Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,Enum.KeyCode.Four}
 for i,tab in ipairs({{"shop","발주"},{"items","창고·진열"},{"goals","목표·영업대회"},{"profile","성장·도감"}}) do
  button((self.section==tab[1] and "● " or "")..tab[2],function() self.section=tab[1]; self.deps.Dirty() end,true,keys[i],"tab-"..tab[1])
 end
 if self.section=="shop" then
  label(pc and "내 사무실 PC 앞 · 발주 가능" or "조회 전용 · 내 사무실 PC 10 studs 이내에서 Q / 화면 버튼으로 주문하세요.",80)
  label("발주 → 트럭 직접 하역 → 창고 보관 → 꺼내서 선반 직접 진열 → NPC 계산·구매",88)
  label("전체 보관 "..storage.Used.."/"..tostring(store and store.WarehouseCapacity or "—").." · 추가 "..storage.Remaining.."개",56)
  button("수량 "..self.quantity.."개 · 눌러 1~4 선택",function() self.quantity=self.quantity%4+1; self.deps.Dirty() end,true,Enum.KeyCode.F,"quantity")
  local wholesale=s.Wholesale
  if wholesale then
   label("재입고까지 "..math.ceil(math.max(0,wholesale.NextRestockAt-now)).."초",48)
   for _,row in ipairs(wholesale.Rows) do
    label(self:name(row.Sku).." · 공용 "..row.PublicAvailable.." / 내 목표 유보 "..row.MyAllocated.."\n매입 "..row.UnitCost.." · 판매 "..row.SalePrice..(row.ReserveUntil and (" · 유보 "..math.ceil(math.max(0,row.ReserveUntil-now)).."초") or ""),88)
    -- Prefer the owner's allocation only when it can satisfy the whole order. Never mix counters locally.
    local allocation=row.AllocationId and row.ReserveUntil and row.ReserveUntil>now and row.MyAllocated>=self.quantity and row.AllocationId or false
    local available=allocation and row.MyAllocated or row.PublicAvailable
    button("발주 "..self:name(row.Sku).." ×"..self.quantity,function()
     self:send("OrderStock",{Sku=row.Sku,Quantity=self.quantity,StockRevision=wholesale.Revision,AllocationId=allocation})
    end,pc and available>=self.quantity and storage.Remaining>=self.quantity and me.Wallet>=row.UnitCost*self.quantity,nil,"act-buy-"..row.Sku)
   end
  else label("도매 재고 수신 대기",48) end
  local orders=store and store.Orders or {}
  if #orders==0 then label("진행 중 발주 없음 · PC에서 상품을 선택하세요.",64) end
  for _,order in ipairs(orders) do
   label(self:name(order.Sku).." ×"..order.Quantity.." · "..(states[order.State] or order.State)..(order.ArriveAt and order.State=="InTransit" and (" · 도착 "..math.ceil(math.max(0,order.ArriveAt-now)).."초") or ""),72)
   button("출발 전 발주 취소",function() self:send("CancelStockOrder",{OrderId=order.OrderId}) end,active and order.State=="Reserved",nil,"act-cancel-"..order.OrderId)
  end
 elseif self.section=="items" then
  label("창고 "..storage.Warehouse.."개 · 안전 보관 "..tostring(store and store.SafeStorageCount or 0).."개\n실물 가까이 이동한 뒤 E / 버튼으로 조작하세요.",88)
  if storage.Warehouse==0 then label("창고가 비어 있어요. 도착한 트럭에서 집어 창고 앞에 내려놓으세요.",80) end
  for _,slot in ipairs(store and store.Slots or {}) do
   button((slot.SlotId==self.selectedSlot and "● " or "")..slot.SlotId.." · "..(slot.Sku and self:name(slot.Sku) or "빈 진열").." "..#slot.ItemIds.."/4",function() self.selectedSlot=slot.SlotId; self.deps.Dirty() end,true,nil,"slot-"..slot.SlotId)
  end
  for _,item in ipairs(s.Carry) do
   label("운반 중 · "..self:name(item.Sku),48)
   local function payload() return {ItemId=item.ItemId,ItemRevision=item.Revision,CarryToken=item.CarryToken} end
   local owned=item.OwnerUserId==me.UserId and item.State=="Carried"
   button("선택 선반 "..self.selectedSlot.."에 직접 진열",function() local p=payload(); p.SlotId=self.selectedSlot; self:send("PlaceShelf",p) end,active and owned and self:near(own,"ShelfSlots",self.selectedSlot),nil,"act-place-"..item.ItemId)
   button("창고에 직접 내려놓기",function() self:send("DropWarehouse",payload()) end,active and owned and self:near(own,"WarehouseDrop"),nil,"act-drop-"..item.ItemId)
   if not owned then label("임시 도난 운반품 · 판매·소유 편입 불가 · 기한 후 원소유자에게 반환됩니다.",80) end
  end
  local theft=s.Theft
  if theft and theft.State=="Holding" then
   label("도난 시도 · 상품 옆에서 "..math.ceil(math.max(0,theft.CompleteAt-now)).."초 대기",56)
   button("도난 시도 취소",function() self:send("CancelTheft",{TheftId=theft.TheftId}) end,active,nil,"act-cancel-theft")
  end
  local seen={}; local count=0
  for _,list in ipairs({store and store.Items or {},s.Nearby,s.Items}) do for _,item in ipairs(list) do
   if not seen[item.ItemId] then
    seen[item.ItemId]=true; count+=1
    label(self:name(item.Sku).." · "..(states[item.State] or item.State).."\n"..tostring(item.OwnerStoreId).." / "..tostring(item.SlotId or item.ItemId),72)
    local function payload() return {ItemId=item.ItemId,ItemRevision=item.Revision} end
    local close=self:itemNear(item)
    if item.OwnerUserId==me.UserId then
     local action=({Truck="PickCargo",Warehouse="PickWarehouse",Shelf="PickShelf"})[item.State]
     if action then button(({Truck="트럭에서 하역",Warehouse="창고에서 꺼내기",Shelf="진열에서 집기"})[item.State],function() self:send(action,payload()) end,active and close and #s.Carry<(me.EquippedTool=="Handcart" and self.config.Interaction.MaxCarryWithCart or self.config.Interaction.MaxCarry),nil,"act-pick-"..item.ItemId) end
     if item.State=="TheftCarried" or item.State=="Recoverable" or item.State=="SafeStorage" then button("내 상품 회수",function() self:send("RecoverItem",payload()) end,active and close,nil,"act-recover-"..item.ItemId) end
    elseif item.State=="Shelf" or item.State=="Truck" then
     button("임시 도난 시도 · 2초 대기 / 초보 보호",function() self:send("BeginTheft",payload()) end,active and close and #s.Carry==0,nil,"act-theft-"..item.ItemId)
    end
   end
  end end
  if count==0 then label("표시할 상품 없음 · 발주와 배송 상태를 확인하세요.",72) end
 elseif self.section=="goals" then
  local d=s.Demand
  label("R-A · 이번 회차 변동 수요",52)
  if not d then label("목표 준비 대기 · 일반 영업은 계속할 수 있어요.",72) else
   label("회차 "..d.CycleId.." · "..(phaseWords[d.Phase] or d.Phase).."\n"..(d.Eligible and "이번 회차 목표 대상" or self:reason(d.Reason)),80)
   for _,t in ipairs(d.Targets) do label(self:name(t.Sku).." · 실제 NPC 판매 "..t.Sold.."/"..t.Required,52) end
   label(d.Completed and "개인 목표 달성 · 추가 게임머니 보상 없음" or "이번 회차 유료 발주 상품의 실제 NPC 구매만 인정 · 미달 벌금 없음",80)
   label("종료까지 "..math.ceil(math.max(0,d.EndsAt-now)).."초 · 유보 해제까지 "..math.ceil(math.max(0,d.ReserveUntil-now)).."초",64)
   if #d.NextTargets==0 then label("다음 목표 수신 대기",48) end
   for _,t in ipairs(d.NextTargets) do label("다음 목표 · "..self:name(type(t)=="table" and t.Sku or t)..(type(t)=="table" and t.Required and (" ×"..t.Required) or ""),52) end
  end
  local c=s.Contest
  label("R-B · 다부문 영업대회",52)
  label("종합 우승·경제 보상 없음 · 다양한 판매 / 계획 영업 / 물류 완결을 각각 비교합니다.",88)
  if not c then label("대회 준비 대기 · 참가하지 않아도 정상 영업 가능",64) else
   label("회차 "..c.CycleId.." · "..(phaseWords[c.Phase] or c.Phase).."\n"..(c.Eligible and (c.Joined and "참가 중" or "미참가") or self:reason(c.Reason)),80)
   local preparing=c.Phase=="Preparing" or c.Phase=="Prepare"
   button(c.Joined and "다음 대회 참가 취소" or "대회 자발적 참가",function() self:send("SetContestParticipation",{CycleId=c.CycleId,Participate=not c.Joined}) end,active and c.Eligible and preparing,nil,"act-contest")
   if not preparing then label("이번 회차 참가 변경 마감 · 다음 준비 회차에서 선택하세요.",64) end
   local score=c.Scores
   label("내 기록 · 다양성 "..score.Diversity.."/20 · 계획 "..score.Plan.."/40 · 물류 "..score.Logistics.."/30",72)
   label("종료까지 "..math.ceil(math.max(0,c.EndsAt-now)).."초"..(c.NextOpportunityAt and (" · 다음 일반 손님 기회 "..math.ceil(math.max(0,c.NextOpportunityAt-now)).."초") or " · 예정 기회 없음"),72)
   if #c.Rows==0 then label("표시할 대회 기록 없음",48) end
   for _,r in ipairs(c.Rows) do label(r.DisplayName.." · "..(reasons[r.Status] or phaseWords[r.Status] or r.Status).."\n다양성 "..r.Scores.Diversity.." / 계획 "..r.Scores.Plan.." / 물류 "..r.Scores.Logistics,80) end
   local result=c.Results
   if result then
    label("회차 종료 · "..(result.Comparable and "상점 간 비교 가능" or self:reason(result.Reason or c.Reason)),72)
    if result.Comparable and result.Winners then
     for _,category in ipairs({{"Diversity","다양한 판매"},{"Plan","계획 영업"},{"Logistics","물류 완결"}}) do
      local names={}
      for _,id in ipairs(result.Winners[category[1]] or {}) do
       local name=tostring(id)
       for _,r in ipairs(c.Rows) do if r.OwnerUserId==id then name=r.DisplayName end end
       table.insert(names,name)
      end
      label(category[2].." 공동 1위 · "..(#names>0 and table.concat(names,", ") or "해당 없음"),72)
     end
    else label("비교 순위 없음 · 개인 기록과 비교 불가를 구분합니다.",64) end
   elseif not c.Comparable then label("현재 비교 가능 미확정 · 결과 확정 전 우승자를 표시하지 않습니다.",72) end
  end
 else
  local upgrade=me.Upgrades and me.Upgrades.Warehouse or 0
  label("창고 개선 "..upgrade.."단계 · 현재 "..tostring(store and store.WarehouseCapacity or "—").."개\n개인 게임머니로 구매 · 현금결제 없음",80)
  local price=self.config.Upgrades.Warehouse.Prices[upgrade+1]
  button(price and ("창고 32개로 개선 · "..price.." 게임머니") or "창고 개선 완료",function() self:send("BuyUpgrade",{UpgradeId="Warehouse",ExpectedLevel=upgrade,ProfileRevision=me.ProfileRevision}) end,pc and price~=nil and me.Wallet>=(price or math.huge),nil,"act-upgrade")
  button("무료 회복 · 물 1개 외상 배송",function() self:send("RequestRecoveryStock",{ProfileRevision=me.ProfileRevision}) end,pc and me.NextAction=="FreeRecovery",nil,"act-recovery")
  label("무료 회복은 재고·잔액 부족 시만 가능하며 다음 매출에서 원가 4를 먼저 갚습니다. 반복 지급·대회 보상은 없습니다.",104)
  local a=me.Achievements
  if a and a.DemandCompletions~=nil and a.ContestCompletions~=nil then label("개인 영구 실적 · 수요 완료 "..a.DemandCompletions.." / 대회 완료 "..a.ContestCompletions.."\n최고 다양성 "..a.BestDiversity.." / 계획 "..a.BestPlan.." / 물류 "..a.BestLogistics,96) end
  label("상품도감 · 서버 발견 기록",52)
  -- The v2 required DTO has no discovery slice. Never infer discovery from available stock.
  if type(me.RareDiscoveries)=="table" then
   local count=0
   local seen={}
   for _,sku in ipairs(me.RareDiscoveries) do
    if type(sku)=="string" and self.config.Products[sku] and not seen[sku] then seen[sku]=true; count+=1; label(self:name(sku),48) end
   end
   if count==0 then label("아직 발견한 상품이 없어요.",56) end
  else label("상품도감 서버 기록 미수신 · 임의 발견 처리하지 않습니다.",72) end
  label("매장 전문화 · 이번 버전 보류\n현재 목표품을 선택해 진열할 수 있으며 별도 전문화 보너스는 없습니다.",88)
  label("무료 진열 프리셋 · 배치 안내만 변경",56)
  for index=1,2 do
   button("현재 진열을 프리셋 "..index.."에 기록",function() self:send("SavePreset",{Index=index,Slots=Model.preset(store and store.Slots or {})}) end,pc and me.Level>=4,nil,"act-preset-"..index)
   button("프리셋 "..index.." 배치 안내 적용",function() self:send("ApplyPreset",{Index=index}) end,pc and me.Level>=4,nil,"act-apply-"..index)
  end
  for _,id in ipairs({"HandCarry","Handcart","StockScanner","LayoutPreset","ToolStyle"}) do
   button(toolNames[id].." · 무료 Lv."..self.config.Progression.Tools[id],function() self:send("EquipTool",{ToolId=id}) end,active and me.Level>=self.config.Progression.Tools[id] and type(me.UnlockedTools)=="table" and table.find(me.UnlockedTools,id)~=nil,nil,"act-equip-"..id)
  end
 end
end
return Client
