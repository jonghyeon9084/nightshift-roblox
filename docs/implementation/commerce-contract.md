# 상거래 확장 계약 1.0.0

2026-10-31 / 최신 기준: `AGENTS.md`, `docs/commerce-expansion-brief.md`. 이 문서는 기존 `contract.md`의 추가·우선 적용 부분이며 기존 완주 코드를 삭제하지 않는다. 공개 상수의 단일 원본은 `src/shared/CommerceConfig.luau`(이하 C), 기존 값은 Config(이하 L). 가격·시간·성장·부하 수치는 설계 가설이다. 이번 산출물은 계약과 상수뿐이며 실행 기능 구현이나 Studio 통과가 아니다.

## 1. 파일 소유권·설치·기존 계약과의 접점
| 담당 | 독점 변경 파일 / 설치 경로 |
| --- | --- |
| Integrator | 이 문서, `src/shared/CommerceConfig.luau` → `ReplicatedStorage.NightShift.Shared.CommerceConfig` ModuleScript |
| Profiles | `src/server/Modules/ProfileService.luau`, `src/server/tests/ProfileService.spec.luau` |
| Economy | `src/server/Modules/CommerceService.luau`, `ProgressionService.luau`, `src/server/tests/CommerceService.spec.luau`, `ProgressionService.spec.luau` |
| Delivery | `src/server/Modules/DeliveryService.luau`, `src/server/tests/DeliveryService.spec.luau` |
| World | `tools/world/`만; `BuildWorld.luau` → `ServerStorage.NightShift.BuildWorld` |
| Server | 기존 `src/server/Main.server.luau`, Modules의 `Protocol.luau`·`GameService.luau`·`WorldAdapter.luau`, 신규 `RankingService.luau` 및 대응 server spec |
| UI | `src/client/`만; Main → `StarterPlayer.StarterPlayerScripts.NightShift.Main`, Modules → 같은 경로의 Modules |

서버 모듈은 모두 `ServerScriptService.NightShift.Modules.<Name>` ModuleScript. spec은 설치하지 않는다. 로더 `tools/integration/` 수정은 이후 Integrator 통합 작업이며 이번 범위 밖이다. 워커는 다른 워커 소스를 require하지 않고 아래 주입 객체를 사용한다. 인터페이스 변경은 Moderator에 보고한다.
Server는 L을 deep copy한 런타임 설정에 C.Capacity, C.World의 배치/Hub/StoreIds/Stores/StoreSize, C.Budget을 명시적으로 덮어쓴다. L.World의 기존 MarkerOrder/Markers는 보존하고 새 마커는 별도 검증한다. L과 C 자체는 변경하지 않는다. World도 동일한 배치를 사용한다.
기존 Action/State v1, 좌석 세대·정전·회복·결과 구조는 보존한다. Commerce 활성 시 기존 무한 선반 상품 생성·자동 셔플은 비활성: 실제 Shelf Item으로 기존 PickUp→PutDown→AcceptLine에 연결한다. 물/빵/우유 ID는 유지하고 주문 생성기는 C.Products를 사용한다. 남은 8종도 실제 주문 후보다.
첫 주문 전 준비 단계는 Running 내 물류 준비로 처리하여 Shift/Order 타이머를 멈춘다. 첫 Shelf 재고 확보 후 기존 근무 타이머를 시작하며 이후 물류 대기로 전체 시간을 무한 정지하지 않는다. 다음 손님 주문은 소유·진열된 SKU 중 구성하고 부족하면 기본 SKU 주문 안내를 제공한다. 희귀 상품은 완주 필수가 아니다.
상점 소속과 방문 위치를 분리한다. 타 점포 방문을 이유로 자동 귀환하지 않는다. 낙하/월드 이탈 복구만 유지한다. 이동·재배치·퇴장 직전 모든 운반을 원상 회수하여 상품 순간이동을 막는다. 기존 Carry와 상거래 Carry를 동시에 소유할 수 없다.

## 2. 월드 제작 계약
`build(parent):Model`은 기존처럼 yield 없이 소유 모델 하나를 생성한다. `NightShiftWorld`에 `NightShiftOwned=true`, `CommerceLayoutVersion=2`. 기존 버전 모델을 조용히 재사용하지 말고 명시적 불일치를 반환한다. 통합자는 Edit에서 대체 모델 검증 후 소유 모델만 교체한다.
직선 도로는 world X축, z=0, 폭24·길이400. 북쪽 Store01~04는 z=-52/yaw0, 남쪽 Store05~08은 z=52/yaw180; x=-120,-40,40,120. 로컬 +Z 입구가 도로를 향한다. Hub 중심은 (-190,0,52). 각 위치·크기는 C.World를 사용한다.
`Stores/<StoreId>`는 Model, StoreId·DisplayName Attributes. 기존 Counter/Shelf1~3/SignalPanel/Breaker/Entry/Spawn 직접 자식과 타입·로컬 좌표는 L 그대로. Office/창고는 뒤쪽, 하역은 뒤·오른쪽. 앞 인도와 뒤 서비스 통로, 건물 옆 보행로, 뒤 출입문을 연결하고 최소 폭6을 확보한다.
추가 직접 자식 `OfficePC,WarehouseDrop,Unload,TruckDock,Alarm,TheftReturn`는 모두 Part, C.World.Markers 좌표·크기, StoreId Attribute. Anchored=true/CanCollide=false/CanTouch=false/CastShadow=false. PC/Alarm은 보이는 장식, 나머지는 Transparency=1인 논리 마커다. 바닥과 장식은 별도 Part다.
`<StoreId>/ShelfSlots` Folder에 `Slot01`~`Slot12` Part를 C.World.ShelfSlotPositions 순서로 만든다. StoreId, SlotId 문자열 Attributes, Capacity=4. 크기 C.World.ShelfSlotSize, Anchored=true/CanCollide=false/CanTouch=false/Transparency=1/CastShadow=false. 한 슬롯은 단일 SKU, 최대4 단위; 점포 전체 상품 상한24가 별도 우선한다.
`<StoreId>/TruckRoute` Folder에 `Approach,Dock,Exit` Part를 C.World.TruckRoutePositions 로컬 좌표에 만든다. StoreId·RouteId=이름, Order=1/2/3 Attributes, 크기(1,1,1), 위 논리 마커 속성. Dock과 TruckDock 중심은 일치한다. 뒤 서비스 통로는 트럭 폭8 이상이며 보행 진입을 막지 않는다.
월드는 빈 `NightShiftWorld/CommerceRuntime` Folder만 만든다. 서버 엔진이 그 아래 Trucks/Items Folder 및 트럭 Model을 소유한다. `<OrderId>` 트럭 Model의 `Cargo` Part는 현재 Dock CFrame*CFrame.new(C.World.CargoOffset), Anchored=true/CanCollide=false, OrderId·StoreId Attributes. Cargo는 서버 거리 판정 기준이다. 장식 모델의 물리 접촉으로 재고를 이전하지 않는다.
World는 진열 상품·Prompt·Remote·스크립트·SoundId를 만들지 않는다. Alarm에는 자체 PointLight 하나를 Enabled=false로 두며 경보광은 정전광과 별도로 제어한다. 위치·명칭 오류는 해당 점포 Unavailable; 공통 경로 오류는 시작 중단. 기존 타인 Baseplate/Spawn/Lighting은 보존한다.

## 3. 모듈 주입 API (이름·대소문자 고정)
공통 `Result={Ok:boolean,Code:string,Value:any|false}`. 아래 메서드는 `object:method(...)`, 생성은 `Module.new(deps)`; 결과 table은 복사본이다. `Now():number`는 서버 게임시각, `UnixNow():int`는 lease용 UTC초, `NewId(prefix):ID`는 서버 세션 UUID+증가번호. 클라이언트 값으로 대체하지 않는다.
`Context={UserId:int,StoreId:ID|false,RoundId:ID|false,SeatGeneration:int,Loaded:boolean,Active:boolean,Mode:string,OnlineCount:int,ToolId:string,ProfileEpoch:int}`는 Main이 현재 권한에서 매 요청 생성한다. GameService 원본 user 테이블을 워커에 넘기지 않는다. 모든 비저장 mutation은 Main의 단일 직렬 큐에서 yield 없이 실행한다.
| 모듈 | 생성 주입 / 공개 API |
| --- | --- |
| ProfileService | `new({Config=C,Store=StorageAdapter,UnixNow,SessionId,OnStatus})`; `load(userId):Result`, `save(userId,release:boolean):Result`는 yield 가능. `get(userId):Result`, `mutate(userId,epoch,fn):Result`, `status(userId):table`, `due():{userId}`는 yield 금지 |
| ProgressionService | `new({Config=C,Profiles=profileFacade,NewId})`; `award(userId,event):Result`, `equip(userId,toolId):Result`, `savePreset(userId,index,slots):Result`, `view(userId):table` (모두 무yield) |
| CommerceService | `new({Config=C,Now,NewId,Delivery=deliveryFacade,World=worldFacade,Progression=progressionFacade})`; `beginShift(storeId,roundId,shift):Result`, `syncContext(context):()`, `action(context,action,payload):Result`, `tick(now):()`, `depart(userId):()`, `endShift(storeId,roundId):Result`, `view(context):table` |
| Commerce→기존 주문 | `claimForLine(context,itemId,itemRevision,lineId):Result`, `returnLine(context,lineId):Result`, `sellLine(context,lineId,transactionId):Result`; claim이 반환한 CarryToken은 기존 Self.Carry에만 노출. 기존 Line과 Item을 동일 큐에서 연결/해제 |
| DeliveryService | `new({Config=C,Now,Engine=LogisticsEngine})`; `register(order):Result`, `cancel(orderId):Result`, `complete(orderId):Result`, `tick(now):{DeliveryEvent}`, `closeStore(storeId,roundId):{DeliveryEvent}`, `view(storeId):{DeliveryView}` (전부 무yield) |
| RankingService | `new({Config=C,Profiles=profileFacade})`; `record(result):Result`, `view():{RankingRow}`; 검증된 교대 종료당1회, 저장 갱신은 Profiles.mutate 경유 |

`profileFacade`는 위 get/mutate/status 메서드만, `progressionFacade`는 award/view만, `deliveryFacade`는 register/cancel/complete/tick/closeStore/view만 전달한다. tick은 Commerce만 호출한다. 다른 모듈의 내부 상태를 공유하지 않는다.
`shift={InitialUserIds:{int},TeamSize:int,Mode:string,Protected:boolean}`이며 Protected는 Main이 초기 명단 프로필로 결정한다. beginShift는 같은 RoundId 재호출에 기존 결과만 반환하고 자금을 재지급하지 않는다. Main은 membership/Loaded/정전/회복/프로필 상태 변화마다 syncContext를 호출하며 Active는 현재 경제 입력 허용 여부까지 반영한다. tick의 Holding 검증도 이 최신 Context를 사용한다.
`Commerce.view`는 `{Wholesale,Stores,Store,Nearby,Carry,Theft}` DTO를 반환한다. `Progression.view`는 CommerceSelf의 Wallet/XP/Level/Tools/EquippedTool/Cosmetics/RareDiscoveries/Presets/Best를 반환한다. Main이 Profile.status·Voice와 합쳐 Self를 만든다. `DeliveryView={OrderId,StoreId,RoundId,State,ArriveAt,RecallAt}`이며 미정 시각은 false다.
`Ranking.record` 입력은 RankingRow의 필드와 `{TransactionId,InitialUserIds,Completed:boolean}`이며 Main만 생성한다. 같은 거래 재호출은 무효 성공. Completed이면 해당 참여자 CompletedFirstShift를 profile mutation으로 갱신하고 개인 최고는 해당 분류 Key에서 비교한다. Profile.mutate fn은 새 Profile을 반환하거나 nil로 취소하며 임의 in-place 원본 변경은 금지한다.
Main은 EquipTool/SavePreset만 Progression.equip/savePreset으로 라우팅하고 나머지는 Commerce.action에 전달한다. ApplyPreset은 Progression.view의 저장된 목표를 조회한다. UI는 CommerceSelf.Presets로 안내를 그린다. 모든 라우트는 동일 Protocol 검증과 replay 캐시를 거친다.
`worldFacade:check(context,target):Result`는 서버 생존·거리·시야·이동 검증; target=`{StoreId,Marker}` 또는 `{StoreId,SlotId}` 또는 `{OrderId,Cargo=true}` 또는 `{ItemId}`. `worldFacade:renderItem(item):Result`, `worldFacade:setAlarm(storeId,alarm|false):Result`는 커밋 후 표현만 변경한다. 실패하면 재시도할 dirty 표시를 유지하고 다음 check는 없는 대상을 거절한다.
`LogisticsEngine:createTruck(orderId,storeId):Result`, `:moveTruck(orderId,segment,alpha):Result`, `:destroyTruck(orderId):Result`. segment는 `ApproachToDock|DockToExit`, alpha는 서버 계산 0..1. Server의 WorldAdapter가 위 경로 마커 간 CFrame 보간·서버 소유 anchored 트럭을 구현한다. 생성/이동/파괴는 멱등이고 yield 금지, 실패는 DELIVERY_FAILED. Delivery는 Instance/Players/TweenService를 직접 참조하지 않는다.
`order={OrderId,StoreId,RoundId,Sku,Quantity,UnitCost,ReservedAt}`. Delivery.register는 스케줄 등록만 수행하며 엔진을 호출하지 않는다. 이후 tick이 생성/이동한다. `DeliveryEvent={EventId:ID,OrderId:ID,StoreId:ID,RoundId:ID,Kind:C.Enums.DeliveryEventKind,At:number}`; Kind는 `Dispatched|Arrived|Recall|Failed|Cancelled`, At은 전이를 확정한 서버 게임시각이다. EventId는 Delivery가 전이당 한 번 발급·보존하며 재전달 시 전체 필드를 그대로 유지한다. 이벤트는 서버 내부 전용이며 수량·가격·환불액은 전달하지 않는다.
`cancel(orderId)`는 Reserved→Cancelled 후 `Result.Value=DeliveryEvent(Kind=Cancelled)`를 즉시 반환한다. 이미 Cancelled면 같은 이벤트를 반환하고, 없는 주문은 NOT_FOUND, 그 외 상태는 INVALID_STATE다. `closeStore(storeId,roundId)`는 일치하는 Reserved마다 Cancelled, InTransit/Docked마다 Recall 이벤트를 즉시 반환한다. 이미 종료된 주문은 새 이벤트를 만들지 않으며 반복 closeStore는 해당 교대의 최초 반환 배열을 재사용한다. 두 API가 반환한 이벤트를 tick이 새 ID로 재발행하지 않는다.
Commerce는 cancel의 Value/closeStore 배열을 같은 직렬 큐에서 즉시 소비한다. 주문 원장의 OrderId·StoreId·RoundId·예상 전이를 검사하고, Cancelled이면 미출발 예약 Quantity 전부 해제+Quantity*UnitCost 운영자금 환불+재고 반환(cap 적용)+주문 Cancelled를 하나의 커밋으로 확정한다. 회차 주문 한도는 복구하지 않는다. Delivery는 스케줄/트럭만 정리하며 돈·재고를 수정하지 않는다. closeStore 정산은 endShift의 잔여 상품·운영자금 폐기보다 먼저 수행한다.
Commerce는 EventId와 주문별 취소/회수 정산 완료 표식을 서버 세션 끝까지 보존한다. 같은 이벤트 또는 이미 정산한 주문의 중복 취소는 무효 성공이며 재환불하지 않는다. 같은 EventId의 다른 본문, 원장과 다른 점포/교대, 존재하지 않는 주문은 INVALID_STATE로 거절하고 상태를 만들지 않는다. 실패/회수도 같은 원장 검증·중복 방지를 적용하며 환불 대상은 §6의 미생성 예약/남은 Truck 상품으로 제한한다.
Main 시작 순서: L/C 검증→build→WorldAdapter→Profiles→Progression→Delivery→Commerce→Ranking→기존 GameService 연결→Remote 활성. 테스트는 table 기반 fake를 주입한다. Profile load/save worker 결과는 Main 큐로 전달하고 epoch가 바뀐 오래된 완료는 폐기한다. 핸들러나 거래 잠금 안에서 DataStore를 호출하지 않는다.

## 4. Remote와 wire DTO
기존 Remotes Folder에 `CommerceAction`(C→S Event), `CommerceActionResult`(S→해당 C Event), `CommerceState`(S→C Event), `GetCommerceSnapshot`(C→S Function)을 추가한다. 기존 Remote v1과 RequestId/Sequence 공간은 분리하되 입력 rate bucket은 합산한다.
`Request={ProtocolVersion:1,RequestId:int,Action:string,StoreId:ID|false,RoundId:ID|false,SeatGeneration:int,Payload:table}`. StoreId는 언제나 자기 소속이며 표적 점포는 서버가 ItemId에서 찾는다. RequestId는 연결별1부터 증가, 문자열 ID≤96bytes, Payload≤4필드, 미허용 키/Instance/NaN/무한수/중첩 table 거부. 유일한 중첩 예외는 SavePreset.Slots의 최대12개 아래 DTO다.
`Ack={ProtocolVersion:1,RequestId,Ok,Code,RetryAfter:number,StoreId,RoundId,Revision:int,EntityId:ID|false}`. EntityId는 OrderId 또는 TheftId 등 생성 결과이며 상태를 대체하지 않는다. carry token은 개인 slice만 전달한다.
`GetCommerceSnapshot({ProtocolVersion=1})→{Ok,Code,RetryAfter,Snapshot:Packet|false}`는 준비된 복사본만 무yield 반환. 최대2초/회, 비정상 지연10초 UI 안내. 이벤트 연결 후 호출한다.
`Packet={ProtocolVersion:1,Kind:"Snapshot"|"Delta",Sequence:int,ServerTime:number,Self?:CommerceSelf,Wholesale?:Wholesale,Stores?:{CommerceSummary},Store?:CommerceStore|false,Nearby?:{PublicItem},Rankings?:{RankingRow}}`.
Snapshot은 모든 slice 필수, Delta는 있는 slice 전체 교체/누락 유지, false는 삭제. Sequence는 수신자별 단조 증가. 5Hz 상태·1Hz 시간, 동일 StockRevision은 모든 수신자에게 동일 재고. 총 budget은 기존 통신 목표를 공유한다. Nearby는 서버가 C.Network.NearbyDistance 이내 공개 상품만 MaxSnapshotItems개까지 선별한다.
`CommerceSelf={ProfileState,SaveMode:"Memory"|"DataStore",Dirty:boolean,SavedRevision:int,Wallet:int,XP:int,Level:int,Tools:{string},EquippedTool:string,Cosmetics:{string},RareDiscoveries:{Sku},Presets:{Preset},Best:{BestRecord},Carry:{PrivateCarry},Theft:PrivateTheft|false,Voice:"PlatformManaged"|"Unavailable"}`. 다른 사람의 저장/토큰은 전송하지 않는다.
`Wholesale={Revision:int,Cycle:int,NextRestockAt:number,Rows:{StockRow}}`; `StockRow={Sku,Available:int,UnitCost:int,SalePrice:int,Rarity:string}`. 기본8종·희귀3종 모두 포함하고 없는 희귀는0이다. `CommerceSummary={StoreId,RoundId,Sales:int,Revenue:int,OnlineCount:int,Protected:boolean,Alarm:Alarm|false}`.
`CommerceStore={StoreId,RoundId,Revision,OperatingCash:int,Orders:{StockOrder},Items:{PublicItem},Slots:{Slot},SupportUsed:boolean}`. `StockOrder={OrderId,Sku,Quantity,UnitCost,State,ArriveAt:number|false,RecallAt:number|false}`. `Slot={SlotId,Sku:string|false,ItemIds:{ID},Revision:int}`.
`PublicItem={ItemId,Sku,Quantity:1,UnitCost:int,SalePrice:int,OwnerStoreId,State,Revision:int,OrderId:ID|false,SlotId:ID|false,CarrierUserId:int|false,Stolen:boolean,RecoverUntil:number|false}`. PrivateCarry는 PublicItem+CarryToken. 신규 매입은 각각 Quantity=1인 Item을 발급하여 분할/합침 복제를 제거한다.
`Alarm={AlarmId,Sku,Location:"Truck"|"Shelf",SourceId:ID,ExpiresAt:number}`. `PrivateTheft={TheftId,ItemId,State,CompleteAt:number,RecoverUntil:number|false}`. `RankingRow={StoreId,RoundId,UserId:int|false,Sales,Revenue,TeamSize,ToolTier,Mode,HadSupport:boolean,HadReduction:boolean,FinishedAt}`. ID/enum 외 부재는 false; 화폐/수량/버전은 유한 비음수 정수다.

## 5. Action 스키마·권한
| Action | 정확한 Payload | 조건/효과 |
| --- | --- | --- |
| OrderStock | `{Sku,Quantity,StockRevision}` | 자기 OfficePC·활성 근무. C 상한/실재고/운영자금 검사 후 원자 예약 |
| CancelStockOrder | `{OrderId}` | 자기 OfficePC, Reserved만 가능; 원예약 전량1회 반환 |
| PickCargo | `{ItemId,ItemRevision}` | 자기 점포 Docked 트럭 Cargo, 빈손/손수레 여유; Item→Carried |
| PickWarehouse / PickShelf | `{ItemId,ItemRevision}` | 자기 WarehouseDrop/해당 Slot에서 Carried, 판매 claim과 배타 |
| PlaceShelf | `{ItemId,ItemRevision,CarryToken,SlotId}` | 자기 운반·자기 슬롯·SKU 일치/용량 검사, 직접1단위 배치 |
| DropWarehouse | `{ItemId,ItemRevision,CarryToken}` | 자기 WarehouseDrop, Carried→Warehouse |
| BeginTheft | `{ItemId,ItemRevision}` | 타점포 Truck/Shelf에 접근, 빈손·양쪽 점포 보호/쿨다운 검사; 어느 쪽이든 보호면 PROTECTED, 아니면 Hold 시작 |
| CancelTheft | `{TheftId}` | 본인 Holding 취소; 상품은 변경 없음 |
| RecoverItem | `{ItemId,ItemRevision}` | 피해 소속만, 도난 상품/운반자 현재 위치 가까이서 기한 내 회수 |
| SecureTheft | `{ItemId,ItemRevision,CarryToken}` | 자기 TheftReturn, 회수기한 경과 후 소유권 이전·Warehouse |
| EquipTool | `{ToolId}` | 프로필 준비/무료 레벨 해금, 운반 중 도구 변경 거절 |
| SavePreset | `{Index,Slots}` | 자기 OfficePC, 해금 확인; Slots=`{{SlotId,Sku}}` 최대12, 중복/미등록 SKU 금지 |
| ApplyPreset | `{Index}` | 자기 OfficePC, 해금 확인; 목표 SKU 안내만, 아이템 생성·자동 진열 없음 |

모든 물류/도난 동작은 현재 좌석·RoundId·SeatGeneration/Active/Loaded/생존 확인. Recovery/Result/정전 동안 시작·완료 입력을 막고 Holding을 취소한다. 경보/재입고/배송/회수 기한은 서버 실시간으로 계속 흐른다. 기본 주문/운반/판매/경보는 레벨1부터 가능하다.
검증 순서: 형식·버전→합산 rate→멱등 캐시→현재 membership→대상 ID/버전/소유권/token→상태·보호·예산→거리10/서버 raycast 시야/이동 이력→직렬 커밋. 캐릭터 복제 위치만 신뢰하지 않고 dt*MaxSpeed+MovementSlack 초과 이동을 거절하며 서버 텔레포트 후 유예2초에는 경제 입력을 금지한다.
재전송은 같은 RequestId/정규화된 같은 본문만 허용: 최근128개 결과 반환, 다른 본문 REQUEST_ID_REUSED, 처리 중 REQUEST_IN_PROGRESS, 캐시 밖 high-water 이하 STALE_REQUEST. 새 연결은 새 ID 공간이며 이전 token/epoch는 무효. 검증 실패도 캐시하므로 수정 요청은 새 ID를 사용한다.
오류 코드는 C.ErrorCodes가 전부다. BAD_REQUEST=타입/키/범위; STALE_STOCK=재고 revision; OUT_OF_STOCK=잔량; ORDER_LIMIT=회차/열린 주문/용량; NOT_OWNER=자기 관리 권한; STALE_ITEM/BAD_TOKEN=버전/운반권한; PROTECTED/COOLDOWN=약탈 제한; PROFILE_UNAVAILABLE/SAVE_FAILED/SESSION_LOCKED/LEASE_LOST/SCHEMA_UNSUPPORTED/PROFILE_CORRUPT=저장 보호. 그 외 이름 그대로이며 새 문자열을 임의 추가하지 않는다.

## 6. 재고·자금·상품·배송 상태 전이
공유재고는 이 서버 하나의 ledger다. 모든 점포 주문/취소/재입고/도난/판매를 동일 직렬 큐에서 처리한다. 수정 전 전체 검증·복사본 계획 후 무yield 커밋하여 예외 시 부분 차감을 남기지 않는다. 엔진 표현 실패는 커밋의 재실행 이유가 아니다.
회차0은 기본 SKU 각 StockCap, 희귀0. 120초마다 Cycle+1, 기본 재고를 cap까지 보충; 3의 배수 회차에는 RareRotation의 다음 SKU를3개까지 보충하고 그 외 희귀 기존 잔량은 보존한다. 자동 예약분은 이미 Available에서 제외되어 재입고로 복제되지 않는다. 희귀는 게임머니 직접 선택 구매뿐이다.
OrderStock은 현재 StockRevision 일치, Quantity1..4, 점포 회차8개/희귀1개/동시 미종료주문2개/현재+예약 상품24개를 검사한다. Available-=qty, OperatingCash-=cost, Reserved 주문 생성과 Delivery.register를 한 커밋으로 수행한다. 실패 시 모두 불변. 회차 한도는 취소·환불로 복구하지 않아 예약 방해를 제한한다.
`Reserved→InTransit→Docked→Completed|Recalled`; `Reserved→Cancelled`. 5초 예약 유예 후 출발, 출발 후12초 도착, 도착 후75초 회수. 같은 점포 트럭은1대라 후속 주문은 Reserved에서 대기하며 취소 가능하다. 선행 트럭 파괴 후에만 출발한다. register 성공은 배송 성공이 아니다.
출발 성공 시 각 단위 Item(State=Truck)을 생성한다. Reserved 취소/Failed는 미생성 예약 수량만 전량 환불·재고 반환. 도착 실패/회수는 아직 Truck인 Item만 Recalled 처리하여 개별 UnitCost를 운영자금에1회 환불하고 재고 반환한다. 이미 운반/진열/도난/판매된 Item은 절대 환불하지 않는다.
반환 재고는 min(cap,Available+returned), cap 초과분은 폐기 처리하며 환불은 원금 그대로다. StockRevision은 변경마다 증가. 회수·취소 이벤트 ID와 Item terminal 상태로 중복을 막는다. 기한과 같은 시각 입력에서는 회수/종료가 먼저여서 마지막 틱 집기로 환불과 상품을 함께 얻지 못한다.
트럭 내 물건이 모두 떠나면 Commerce가 Delivery.complete(orderId)를 호출하여 주문 Completed, 즉시 출구 이동 후3초에 제거한다. complete는 Docked에서만 처음 적용하고 이미 Completed면 무효 성공이다. 회수 시 Recalled 후 동일 제거. closeStore는 Reserved→Cancelled에 Kind=Cancelled, InTransit/Docked→Recalled에 Kind=Recall을 반환한다. Commerce가 §3대로 정산한 뒤 남은 상품은 Expired, 운영자금과 함께 근무 종료 시 폐기한다. 재접속은 같은 교대 자금/지원 한도를 초기화하지 않는다.
자기 물류 `Truck|Warehouse|Shelf→Carried→Warehouse|Shelf`. 기존 손님 주문은 `Shelf→Carried(line claim)→Sold`; Tray는 기존 주문 Line 상태로만 표현하고 Item은 Carried 유지. ReturnItem/사망/퇴장 시 원래 빈 슬롯 우선, 아니면 Warehouse로 회수한다. 각 전환마다 Revision 증가·token 회전/폐기, 단일 운반자·단일 슬롯만 허용한다.
기존 PickUp.Shelf1/2/3은 각각 Slot01~04/05~08/09~12 중 Line SKU에 맞는 최저 ItemId를 서버가 선택한다. claim된 Item은 물류/도난 액션에 재사용 불가. 손수레는 자기 일반 물류2개만 허용하고 기존 Line 운반은1개·다른 carry가 없어야 한다. Tray에서도 연결 Item의 token은 유지하되 재운반/도난을 금지한다.
sellLine은 기존 AcceptLine 검증 성공과 같은 큐에서 Item 소모/Sold, 점포 Sales/Revenue/OperatingCash 가산, 서버 거래ID 소비까지 커밋한다. 수량·가격·보상·누적점수는 클라이언트에서 받지 않는다. 준비 중 재고가 없어도 무한 생성하지 않고 OfficePC 기본 구매를 안내한다.
운영자금240은 교대 소유이며 개인 Wallet과 이체 API가 없다. 지원금40은 잔액으로 최저 기본1개도 못 사고 소유/예약 상품0일 때 교대당1회, HadSupport=true, 개인 보상 없음. 지원 소진 후에도 무료 교대 재시작 가능하다. 운영자금·환불·도난 수익을 개인 영구 화폐로 직접 전환하지 않는다.

## 7. 도난·경보·무료 회복
BeginTheft는 item 잠금 없는 Holding(2초)만 만든다. 유지 중과 완료 시 모두 거리/시야/속도/원 ItemRevision/양쪽 활성 근무를 재검증한다. 먼저 성공한 1명만 Truck|Shelf→TheftCarried로 원자 변경하며 경쟁자는 STALE_ITEM. 같은 팀은 정상 운반 API만 사용한다.
첫 영업 미완료 프로필이 교대 시작 명단에 있으면 그 교대는 보호한다. 보호 점포는 도난의 피해·가해 모두 금지한다. 서버는 가해자의 현재 소속과 Item.OwnerStoreId로 양쪽 점포를 찾고 BeginTheft 시작·Holding 유지·완료 커밋 직전에 `attacker.Protected or victim.Protected or attacker.OnlineActiveCount==0 or victim.OnlineActiveCount==0`이면 PROTECTED로 거절한다. Holding 중 해당 조건이 생기면 Cancelled로 끝내고 상품/소유권/운반 토큰을 변경하지 않는다. 피해점포 마지막 성공도난 후60초 미경과는 COOLDOWN이다. Protected·OnlineActiveCount는 서버 프로필/명단에서 계산하며 클라이언트 신고를 쓰지 않는다. 영구 자산은 도난 대상이 아니다.
성공 직후 원소유권을 유지하고 Stolen=true, RecoverUntil=now+25, token을 가해자에게만 발급한다. 상품명·원 Truck/Shelf 위치 알림과 경광등12초를 피해팀에 전송한다. 현재 추적 위치는 근처 PublicItem과 실제 표현으로 확인한다. 무료 음원이 확인되기 전 시각/문자 경보만 사용한다.
회수기한 동안 판매·진열·타인 양도·재도난 금지. 피해팀 RecoverItem은 상품 현재 위치에서 token 무효화 후 자기 Warehouse로 자동 반환한다(회복 예외이며 정상 입고 자동 진열 아님). 가해자 사망/이탈/재배치 시 즉시 같은 반환, 피해점포 근무 종료면 Expired. 도난은 손수레와 무관하게1개만 운반한다.
25초 경과만으로 소유권을 바꾸지 않는다. RecoverItem은 now<RecoverUntil, SecureTheft는 now>=RecoverUntil에만 허용한다. 살아 있는 가해자가 자기 TheftReturn에서 자기 점포 상품 상한까지 검사한 뒤 SecureTheft를 완료해야 자기 Warehouse가 된다. 가해자 이탈 시 반환 규칙은 확보 전 계속 적용한다. 바닥에 강제 분리된 표현은 Recoverable로 두고 서버가 원소유 Warehouse로 회수한다.
반환은 TheftState=Recovered, 확보는 Secured, Holding 중 실패는 Cancelled. 회수된 상품은 Stolen=false; 확보된 상품은 Stolen=true를 유지하여 해당 상품 판매는 개인 XP/Coins/희귀발견/랭킹 매출에서 제외한다(운영자금에는 판매금 가산). 반복 탈취를 성장 최적 경로로 만들지 않는 초기 가설이다.

## 8. 저장 스키마·실패·세션 소유권
P0 저장 키 `NightShiftProfiles_v1/u:<UserId>`, 서버 전용 UpdateAsync. 기본 Memory 어댑터는 Studio 임시 상태로 표시하며 DataStore로 자동 전환하거나 로드 실패를 Memory 신규 유저로 대체하지 않는다. 실제 클라우드 모드는 별도 준비된 배포 설정에서만 선택한다.
`Profile={SchemaVersion:1,Revision:int,Wallet:int,XP:int,Level:int,UnlockedTools:{string},EquippedTool:string,Cosmetics:{string},Presets:{Preset},Best:{BestRecord},RareDiscoveries:{Sku},CompletedFirstShift:boolean,RewardCursor:{Epoch:int,Sequence:int},Session:{Id:string,Epoch:int,ExpiresAt:int}|false}`.
`Preset={Index:int,Slots:{{SlotId,Sku}}}`는 무료2개/향후 최대6개, 해금 전 저장 없음. 현재 구매 기능이 꺼져 있으므로 Index는1..2만 허용한다. 슬롯 좌표/상품 수량/소유점포/재고는 저장하지 않는다. `BestRecord={Key:string,Sales:int,Revenue:int,TeamSize:int,ToolTier:int,Mode:string,HadSupport:boolean,HadReduction:boolean}`. Key는 mode/teamSize/toolTier/support/reduction 조합, C.Ranking.MaxBestRecords=320(4*4*5*2*2)개 조합만 허용한다.
금액/XP는 C 상한, Level은 XP로 재계산, Tools는 레벨표의 허용값과 일치하게 정규화, Cosmetics≤64 허용 ID, RareDiscoveries는 희귀3종만 중복 제거. 알 수 없는 미래 SchemaVersion이나 손상 필수값은 읽기 실패로 보존한다. v1 신규 기본값은 UpdateAsync가 확실히 nil을 읽었을 때만 생성한다.
`StorageAdapter:UpdateAsync(key,transform):table|nil`은 yield 가능/오류 throw, `:GetBudget():number`는 무yield. Memory fake도 transform 재호출·실패/확정 후 응답유실·동시 소유자를 재현해야 한다. transform은 순수·무yield이며 외부 보상·토큰발급·상태 변경을 하지 않는다.
load는 UpdateAsync로 활성 타 Session이면 nil 반환(SESSION_LOCKED), 없거나 만료됐으면 새 Id/증가 Epoch/120초 lease를 원자 획득한다. 소유권 획득 응답이 불명확하면 같은 SessionId로 재시도하며 이미 자기 lease인 경우 Epoch를 다시 증가시키지 않는다. 완료 전 mutation을 차단한다.
30초마다 저장/lease 갱신을 병합하고 한 유저당 writer 하나만 허용한다. 저장 transform은 현재 Session.Id/Epoch 일치와 미만료를 검사하여 아니면 nil/LEASE_LOST. 저장 시작 시 복사본과 Revision을 고정하고, 성공 후 SavedRevision만 올린다. 쓰기 도중 더 최신 mutation은 dirty로 남겨 덮어쓰지 않는다.
실패 재시도는 최대3회/간격1·2초, budget 부족은 같은 한도 내 연기, 무한 루프 금지. SaveFailed는 메모리 dirty 유지·UI 안내; 마지막 확인 lease 만료15초 전부터 영구 변경/새 상거래 참여를 동결한다. lease 상실 시 탈취 금지·옛 소유자 저장 취소. load 실패 시 기본 프로필 저장/기존 값 삭제를 절대 하지 않는다.
leave 및 BindToClose에서 최종 save(release=true), 전체 종료 예산20초. 데이터와 Session=false를 같은 UpdateAsync로 저장하고 성공할 때만 Released. 실패하면 lock을 억지 해제하지 않고 만료에 맡긴다. 확정됐으나 응답이 유실된 release도 이전 Revision/Session 불일치로 재덮어쓰기하지 않는다.
Profiles.mutate는 유효한 epoch/lease에서 복사본 fn 실행→전체 스키마 검증→Revision 증가로만 커밋한다. fn 오류/거부는 원본 불변. status=`{State,Mode,Dirty,SavedRevision,Epoch}`; OnStatus(userId,status)는 비밀 SessionId 없이 Main에 알린다. Ready/Temporary 및 유효 lease 내 Saving/SaveFailed만 변경 가능하다.
Progression.award event=`{TransactionId,Epoch,Kind:"Delivery"|"Sale"|"CoopClose",Sku:string|false,Eligible:boolean}`는 서버 전용. Progression은 사용자별 현재 Epoch에서 미소비 거래에만 RewardCursor.Sequence+1을 내부 발급한다. 소비된 거래 재처리는 무효 성공, 이전 Epoch는 거부한다. cursor와 Wallet/XP/발견을 하나의 profile mutation으로 저장하며 mutation 실패 때 거래를 소비 처리하지 않는다.
Delivery 보상은 합법 매입 Item의 최초 Shelf 배치당1회, Sale은 합법 Sold당1회, CoopClose는 지원/연습 제외 협동 성공 참여자당1회. 동일 상품 내려놓기 반복·재접속·취소는 새 보상이 아니다. 서버가 원본 거래 소비표를 교대 종료까지 유지하며 새 Sequence로 동일 TransactionId를 재발급하지 않는다.
영구 exactly-once를 여러 키 거래로 과장하지 않는다. 저장 전 충돌 종료는 마지막 저장 이후 보상이 유실될 수 있다. 이미 저장된 cursor의 중복 지급은 차단하며 오래된 교대/epoch의 보상을 새 세션에서 재생하지 않는다. UI는 dirty 동안 저장 완료로 표시하지 않는다.

## 9. 성장·기록·음성·유료 초안
XP 누적0/40/100/180/300에서 레벨1~5, 손운반/자기점포 손수레2개/재고 스캐너/진열 프리셋/도구 외형 무료 해금. 프리셋은 배치 안내이며 직접 진열을 대체하지 않는다. 스캐너는 공개 재고 탐색 편의로서 희귀 입고 선점 정보를 추가하지 않는다. 밸런스 변경은 C에서 조율한다.
Ranking은 서버 확인 판매와 합법 매출만 집계, 개인 최고는 검증된 종료 결과로만 Profiles 갱신. 인원은 교대 시작 TeamSize, ToolTier는 교대 중 최고, Mode·지원·감소 플래그는 별도 분류하며 일반 순위에 합치지 않는다. 주간 기록은 P1, C.Ranking.WeeklyEnabled=false.
음성은 Roblox 기본 근접 방식 준비만. 플랫폼의 자격/사용자 동의를 따르고 마이크 강제 활성화·녹음·전사·외부 API는 없다. 계정/게시/설정 변경 없이 UI는 PlatformManaged 또는 Unavailable과 핑 대안을 표시한다. 실제 연결 성공을 주장하지 않는다. [공식 음성 문서](https://create.roblox.com/docs/chat/voice-chat)
상품 후보는 ToolSkins/ExtraPresetSlots/SignUniformBundle. 기능 동등 무료 도구·프리셋2칸 제공, 구매 ID/Robux 가격은 빈 table, 결제·영수증·Prompt 호출 모두 비활성. 도난 우위/알람 해제/희귀 선점/확률형/랭킹 점수 판매와 피해 직후 구매 유도 금지.
저장 기본 동작과 비yield UpdateAsync 콜백 근거는 [공식 DataStore 문서](https://create.roblox.com/docs/cloud-services/data-stores). lease·cursor·실패 동결은 이 프로젝트의 설계이며 외부 라이브러리 기능이 이미 설치됐다는 뜻이 아니다.

## 10. 다음 구현의 완료 조건·현재 검증 한계
Profiles spec: nil 신규/로드 장애/미래 스키마/손상/타세션 lock/lease 만료/이전 writer/transform 재실행/응답유실/저장 중 mutation/종료예산. Economy spec: 마지막 재고 동시주문, replay/변조ID/음수/잔액부족/취소-출발 경합/재입고 반환 cap/보상 반복/도난-판매 경합. Delivery spec: fake clock/engine 실패/한 점포1대/도착·회수·종료 중복/취소 후 늦은 이벤트.
Server·World·UI 통합: 8매장 방문/소속 분리, PC 주문→트럭→직접 하역→진열→판매, 초보·빈점포 보호, 트럭/진열 도난 경보·회수·확보, 저장 상태 표시·재로드, 기존 정전/완주 회귀. 다중 클라이언트/모바일/16인 부하/실제 DataStore/음성/재미·유지율은 별도 실제 증거 전까지 미검증이다.
의도적 변경: 기존 contract의4매장/3상품/무한재고/자동셔플/타점포 귀환/Shared Config 단일 규칙을 위 확장으로 대체한다. 기존 실제1인 완주 기록은 `integration-report.md`의 당시 결과로 보존한다. 이번 작업은 Studio·판매·게시·계정 설정을 변경하지 않는다.
