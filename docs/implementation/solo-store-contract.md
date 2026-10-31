# 단독 매장 공유 계약 2.0.0

NightShift-Server / NightShift-SoloStoreContract-RC / 2026-11-01 KST.
이 문서는 공유 소스 계약과 오프라인 검사 인계다. 서버 서비스 구현, UI 연결, Studio 검증 또는 출시 승인 결과가 아니다. Moderator가 산출물·증거를 확인하기 전 단계 완료 표식을 발행하지 않는다.

입력: `warehouse-source-handoff.md`를 먼저 읽고 AGENTS.md, `docs/game-brief.md`, `docs/design/release-target.md`, `release-task-decisions.md`, `docs/design/release-scope-review.md` DR01~12, `release-acceptance-matrix.md`, `warehouse-integration.md`, `.setup/warehouse-verification.json`을 확인했다. R-A/R-B는 채택, 전문화/단골·종합 우승·경제 대회 보상은 보류다. 수치와 재미 효과는 실측 전 가설이다.

기존 창고 상태는 **warehouseAcceptanceComplete=false, releaseReady=false**다. 실제 Store01 물류와 수정 후 2클라이언트 근무 시작 증거를 입력으로 사용했으며, 새 Place 저장·실제 24개 적재/경합·최종 인수는 미완료다. 사용자 Escape로 중단된 Computer Use와 UI 저장을 재개하거나 다른 도구로 우회하지 않았다. 마감은 09:00 KST이며 보고 시각/기한 경과 여부는 검사 보고와 최종 응답에 구분한다.

## 변경과 호환성 경계

| 파일 | 실제 구현 책임 |
| --- | --- |
| `src/shared/CommerceConfig.luau` | 8/8/1, 프로토콜·스키마 v2, 소유권·NPC·업그레이드·수요·대회·교통 상수, 허용 액션/실패 코드 |
| `src/shared/Config.luau` | v2, 8/8/1, 8매장 위치 일치, 직원/지원 액션 목록 제거, 단독 정전 안내 |
| `src/shared/SoloStoreContract.luau` | 순수 요청 검증, 수요 유보 계획, NPC 확률 판정, 거래 커서, 수요 진행/대회 점수/실적 계산, 신호 위상 |
| `src/shared/SoloStoreProfile.luau` | 신규 프로필, 검증된 v1→v2 변환, v2 확장 검증, 원소유 재고의 저장 형태 변환 |
| `src/shared/tests/` | 공유 모듈 자체 및 실제 기존 v1 normalizer를 실행하는 오프라인 검사 |

**현재 서버/클라이언트는 v1 구현이 남아 있다. 공유 파일만 배포하면 호환되지 않는다.** `Protocol.validateCommerce`의 SeatGeneration/액션 자체 스키마, ProfileService의 normalize/defaults, CommerceService의 OperatingCash/팀 보상/SecureTheft/교대 종료 폐기, GameService 직원/지원 흐름, UI v1 상태를 후속 담당이 교체해야 한다. 기능 완료나 하위 호환이라고 표시하지 않는다. `InitialOperatingCash=0`은 옛 지급 경로를 막는 호환용 상수이며 정상 경제 구현이 아니다.

새 모듈은 ReplicatedStorage.NightShift.Shared에 설치한다. Integrator는 설치 manifest에 두 모듈을 추가하고 Main/Protocol/ProfileService가 실제 require하는지 확인한다. 계약 검증만으로 실제 Remote를 보호할 수 없으므로 v2 서버 연결 전 실행 통과 판정 금지. 기존 v1 요청에는 VERSION_MISMATCH를 반환한다. 클라이언트가 보낸 버전에 맞춰 서버 동작을 낮추지 않는다.

## 공통 원칙·소유권

- 서버 최대 운영자는 8명, Store01~08 각각 소유자 한 명이다. `OwnerUserId ↔ StoreId`는 현재 서버의 1:1 맵이다. 자동 배정 외 직원 참가·공동 소유·지원자 관리 권한은 없다. 방문/핑은 권한 상승이 아니다.
- UserId는 서버 Player에서 얻는다. 양수 정수만 정상 허용하며 음수 ID는 기존 실제 다인 회귀처럼 **IsStudio AND Memory**에서만 별도 허용한다. `abs(UserId)`를 저장 키로 쓰지 않는다. 클라이언트 UserId/Owner/가격/잔액/보상/좌표를 받아들이지 않는다.
- 프로필 Ready 또는 명시적 Memory Temporary, lease/epoch 유효, 전체 복원 완료 후 배정 확정한다. 로드 실패자는 슬롯을 운영하지 못한다. 동일 사용자의 재배정 호출은 같은 결과를 반환하고 두 번째 매장을 만들지 않는다. 비어 있는 매장이 없으면 STORE_FULL, 9번째는 대기 상태이고 기존 소유권 불변이다.
- OwnerGeneration은 배정 변경마다 단조 증가한다. StoreId는 영구 저장하지 않는다. OwnerGeneration/ProfileEpoch/RequestId는 다른 개념이다. RoundId는 영업 회차이며 퇴근으로 소유 자산을 삭제하지 않는다.
- 모든 권한/재고/지갑/도난/NPC/드롭/저장 장벽 명령은 Main의 **하나의 yield 없는 경제 큐**에서 처리한다. 멀티 소유자 사건도 동일 큐를 사용해 마지막 재고 경합을 직렬화한다. 외부 저장/표현은 큐 밖에서 수행하고 완료 시 generation/epoch/revision을 재검사한다.

## Remote와 행동 payload

CommerceAction, CommerceActionResult, CommerceState, GetCommerceSnapshot 이름을 재사용하며 ProtocolVersion=2. GetCommerceSnapshot 입력은 `{ProtocolVersion=2}`만 허용한다. legacy Action/State도 v2로 교체하고 직원/JoinStore/LeaveStore/RequestSolo/CancelSolo/패널 역할 분담 경로는 거절한다. SetReady/정전 InputShape 등 남은 야간 액션은 자기 매장 소유자만 가능하며 UI에도 직원 선택을 남기지 않는다.

CommerceAction의 정확한 7개 필드:

```lua
{ProtocolVersion=2, RequestId=1, Action="OrderStock", StoreId="Store01",
 RoundId=false, OwnerGeneration=1,
 Payload={Sku="Water",Quantity=2,StockRevision=7,AllocationId=false}}
```

`false`는 값 없음이며 nil로 필드를 누락하지 않는다. StoreId는 실제 8개 중 하나, RequestId/OwnerGeneration은 1 이상의 정수다. RoundId는 false 또는 서버 발행 ID. 구조 검증은 `SoloStoreContract.validateAction(raw, CommerceConfig) -> request?, code`를 호출한다. 이 함수는 권한·거리·lease·중복 실행 여부를 검사하지 않으므로 서버가 반드시 이어서 검사한다. ID는 1~96바이트, 제어문자 없음. 미지 키, 중첩 임의 테이블, NaN/무한/소수, 잘못된 enum을 거절한다.

| 액션 | Payload의 전부 | 서버 추가 확인 |
| --- | --- | --- |
| OrderStock | Sku, Quantity(1~4), StockRevision, AllocationId(false 또는 ID) | 자기 OfficePC 거리10/시야, 지갑·실제 공용/본인 유보분·주문한도·용량·revision |
| CancelStockOrder | OrderId | 본인 미출발 주문만 취소·실제 지불액 1회 환불, 이미 배송되면 INVALID_STATE |
| PickCargo / PickWarehouse / PickShelf | ItemId, ItemRevision | 자기 원소유품, 해당 상태/마커 거리, 인벤토리·운반 한도 |
| PlaceShelf | ItemId, ItemRevision, CarryToken, SlotId | 자기 선반, 동일 SKU·4개 한도, 본인 운반 토큰 |
| DropWarehouse | ItemId, ItemRevision, CarryToken | 자기 창고, 창고 단계별 한도 |
| BeginTheft | ItemId, ItemRevision | 타인 Shelf/Truck, 실제 거리·시야·보호·피해 cooldown |
| CancelTheft | TheftId | 자기 시도만 |
| RecoverItem | ItemId, ItemRevision | 원소유자/허용 회수 위치, 일치한 상태·거리 |
| EquipTool | ToolId | 해금 확인; 대회 인정 운반은 HandCarry만 |
| SavePreset / ApplyPreset | Index, Slots / Index | Index 1~2, Slots는 중복 없는 `{SlotId,Sku}` 배열; 설정만 변경, 상품 생성 없음 |
| BuyUpgrade | UpgradeId="Warehouse", ExpectedLevel, ProfileRevision | 자기 PC 거리10, lease/잔액/revision·단계 CAS, 가격은 서버표 |
| SetContestParticipation | CycleId, Participate(boolean) | 준비 단계 중 자기 참여 변경; 진행 중은 NEXT_CYCLE, 늦은 참가 불가 |
| RequestRecoveryStock | ProfileRevision | 아래 무료 회복의 자금/재고/부채/공급 조건 |

SecureTheft, CommitNpcSale, ForceDrop, SetOwner, GrantMoney, SetContestScore는 **클라이언트 액션이 아니다**. 미지 액션 BAD_REQUEST. 직원 소유권을 허용하는 호환 경로는 추가하지 않는다. 별도 닉네임 입력 Remote도 없다. 현재 Player.DisplayName을 서버에서 가져와 간판에 쓰며, 추후 자유 입력 닉네임은 별도 필터링 검토가 필요하다.

응답: `{ProtocolVersion=2,RequestId,Action,Ok,Code,Value=false|DTO,Sequence,OwnerGeneration,ProfileRevision}`. 동일 연결의 같은 RequestId+정규화 본문은 원 응답을 재전송하며 다시 실행하지 않는다. 본문이 다르면 REQUEST_ID_REUSED, 이미 제거된 과거 ID는 STALE_REQUEST, 실행 중은 REQUEST_IN_PROGRESS. 연결 캐시는 128개지만 high-water mark는 유지한다. 재접속은 새 연결이며 거래 커서/상품 상태/배정 세대로 이전 세션 replay를 차단한다. 클라이언트는 실패 시 돈/수량을 낙관적으로 확정하지 않는다.

오류 공통: NOT_OWNER, STALE_OWNER, STALE_PROFILE, PROFILE_FROZEN, PROFILE_UNAVAILABLE, SESSION_LOCKED, LEASE_LOST, RESTORE_FAILED, STALE_ITEM, STALE_STOCK, OUT_OF_STOCK, INSUFFICIENT_FUNDS, SLOT_FULL, TOO_FAR, INVALID_MOVEMENT, CURRENCY_CAP. 오류와 불일치한 revision이면 snapshot을 제한 빈도로 재요청한다. UI의 오류 문구만으로 서버 거절을 대신하지 않는다.

## 서버 내부 API·책임 분리

내부 결과는 기존 `{Ok, Code, Value}` 형태. 아래는 후속 서버/NPC/교통 담당이 구현할 호출 계약이며 해당 서비스 구현 완료 목록이 아니다.

| 소유 모듈 | API | 책임과 실패 |
| --- | --- | --- |
| Main / OwnershipService | `assignOwner(userId, profileEpoch)`, `getOwnerContext(player)`, `releaseOwner(userId, ownerGeneration)` | 빈 슬롯 CAS, 같은 사용자1개, 9번째 STORE_FULL, 퇴장 장벽 후 해제 |
| Protocol | `validateCommerce(raw,config)` | 공유 validateAction 위임, 서버 Player로 Context 조립, rate/replay/순서 처리 |
| CommerceService | `action(context, action, payload)` | 주문·자금·재고·임시 도난의 유일 writer, 공유 ledger와 profile revision 동시 변경 |
| CommerceService | `selectNpcItems(context,npcId,kind,opportunityId)` | Shelf 실제 단위 ID/revision 선택, 서버 selectionId·만료·매장 배정 세대 기록; 예약은 판매 아님 |
| CommerceService | `commitNpcSale(context, sale)` | 아래 원자 판매, 내부 전용 |
| CommerceService | `forceDrop(context, collision)` | 아래 운반 상태 이동, 내부 전용 |
| DemandGoalService | `prepare(cycleId,readyOwners,rotationIndex)`, `orderAllocation(context,allocationId,sku,quantity)`, `recordVerifiedSale(event)`, `releaseAllocations(now)` | 실제 ledger 유보/해제, R-A 진행·완료 |
| ContestService | `setParticipation(context,cycleId,enabled)`, `start(cycleId)`, `offerOpportunity(context,index)`, `recordVerifiedSale(event)`, `finalize(cycleId)` | 동등 기회 증거·점수·부문 결과/실적 |
| ProfileService | 기존 `load/get/mutate/save/status` + `beginBarrier(userId,reason)`, `restoreInventory(context,profile)` | lease/CAS·v1 migration·저장 스냅샷·복원 단1회 |
| NPCShoppingService | `tick(now)`, `removeOwner(storeId,generation)` | 실제 이동/상품 보기/계산대 접근 뒤 선택 토큰으로 판매 호출; 직접 돈/재고 쓰기 금지 |
| TrafficService | `tick(now)`, `observeCollision(vehicleId,player)` | 신호 상태/차량 위치·속도·접촉 증거, 서버 큐에 forceDrop만 전달 |
| WorldAdapter | `resolveTrafficMarkers()`, `getPedestrianRoute(storeId)`, `renderDrop(itemId,safeCFrame)`, `renderOwner(storeId,displayName)` | 명시한 월드 계약 검증, 표현 실패 시 영속 자산 보존 |

Context = `{UserId,StoreId,OwnerGeneration,ProfileEpoch,RoundId,Loaded,Active}`이며 서버만 생성한다. 옛 SeatGeneration을 네트워크 권한으로 인정하지 않는다. 과도기 내부 변환을 쓰더라도 값의 출처는 새 소유권 표여야 한다. 서버 Main이 snapshot·legacy 야간 서비스까지 단독 소유권과 무료 정전 회복으로 연결한다.

이벤트 공통 = `{EventId,Kind,OwnerUserId,StoreId,OwnerGeneration,ProfileEpoch,ProfileRevision,Sequence,At}`. At/공개 마감시각은 `Workspace:GetServerTimeNow()` 기반 초, 저장 lease ExpiresAt만 Unix 초. EventId/TransactionId는 서버 세션ID+epoch+sequence로 고유하게 만들며 서버 세션ID/lease 비밀값은 공개 DTO로 보내지 않는다. 서버 내부 durable item ID는 전역적으로 재사용되지 않는 GUID 등이고 UI용 96바이트 한도를 지킨다.

## 지갑·NPC 판매·실제 재고 보존

단일 영속 Wallet에서 발주 차감·판매 매출·업그레이드 지출을 처리한다. Sale XP=5/단위, 추가 Sale Coins=0이다. 새 프로필만 Wallet=240, v1 지갑에는 어떤 금액도 추가하지 않는다. 교대마다 240 지급·운영자금 환급·팀원 분할 보상은 폐기한다. 정전/교대 실패는 지갑·재고·업그레이드를 초기화하지 않는다. 잔고 상한을 넘길 판매는 CURRENCY_CAP으로 전부 거절하여 상품을 소비한 뒤 돈을 잘라 버리지 않는다.

일반 방문은 서버 RNG로 12~24초 간격, 활성 NPC 최대2/매장. 매 방문 `sample∈[0,1)` 중 `<0.03`은 Rich, 나머지는 Normal이다. Normal 최대1개, Rich 최대4개이며 품절 상한은 실제 Shelf 재고다. 부자 손님은 추가 가격/확률 구매·유료 호출이 없다. 테스트 시드는 주입된 RNG로만 사용하고 최종본 강제 생성 훅을 제거한다.

`sale = {TransactionId,NpcId,SelectionId,Kind,Items={{ItemId,ExpectedRevision}},OpportunityId=false|id}`. kind/기회/선택/매장/소유자 모두 서버 NPC 레지스트리와 대조한다. 손님이 자기 계산대에 실제 도착하고 보행 순서가 완료됐는지도 검증한다. 선택 만료10초, 다른 손님 예약/도난은 상태 재검사 대상이다. 판매는 한 요청의 전체 품목 성공 또는 전체 실패다. 충돌한 재고는 STALE_SELECTION/STALE_ITEM로 무변경 반환하고 NPC가 남은 상품을 새로 선택한다. 같은 TransactionId+본문 재전송은 같은 영수증, 다른 본문은 REQUEST_ID_REUSED다.

큐 내 한 커밋: 유효 lease/소유자·selection·Shelf·revision·중복ID·수량·잔고상한 검사 → 단위 아이템 Sold 및 선반에서 제거 → **해당 OwnerUserId** Wallet 증가·XP/도감·R-A/R-B 진도 계산 → 프로필 revision/커서 증가 → 이벤트 생성. 중간 실패는 모두 불변이다. 서비스 간 비동기 reward 재호출로 돈을 별도 지급하지 않는다. 표현 실패는 렌더링 재시도 대상이며 거래 재실행 사유가 아니다.

`NpcSaleCommitted` 추가 필드 = `{TransactionId,NpcId,Kind,CycleId=false|id,OpportunityId=false|id,OpportunityIndex=false|1..4,Units,Revenue,DebtPaid,WalletDelta}`.
각 Unit = `{ItemId,Sku,Quantity=1,UnitPrice,PurchaseCycleId=false|id,SlotId,BasicTool,OwnerLogisticsComplete,Practice,WasStolen,RecoveryLoan}`. 기록용 모든 값은 ledger에서 복사하고 클라이언트로부터 받지 않는다. Goal/Contest용 내부 event는 `Committed=true`를 서버만 설정한다. 신뢰된 커밋 경로 밖에서 이 플래그만 true로 설정해 호출하는 것은 금지한다.

아이템 하나는 수량1이며 영속 ItemId와 구매 계보가 하나다. `OwnerUserId`는 절대 불변, `OwnerStoreId`는 런타임 배치 파생값, `CarrierUserId`는 임시 보유자다. Truck/Warehouse/Carried/Shelf/TheftCarried/Recoverable/SafeStorage 중 정확히 한 상태; Sold/Recalled/Expired는 거래 정산 뒤 terminal이다. 유효 구매 상품을 시간 만료로 무보상 삭제하는 Expired 경로는 사용 금지다. 배송 미하역·퇴장·정전이면 원소유 저장으로 귀속하며 자동 판매/진열하지 않는다.

## 프로필 v2·migration·저장 장벽

DataStoreName=`NightShiftProfiles_v1`, KeyPrefix=`u:`를 유지해 기존 키를 읽고 SchemaVersion=2로 이동한다. 새 스토어 이름으로 옮겨 옛 자산을 놓치지 않는다. 현재 PersistentSave=false/DefaultMode=Memory는 유지한다. 게시/API 설정 변경으로 클라우드 검증을 우회하지 않는다.

기존 루트 필드 SchemaVersion, Revision, Wallet, XP, Level, UnlockedTools, EquippedTool, Cosmetics, Presets, Best, RareDiscoveries, CompletedFirstShift, RewardCursor, Session을 보존한다. Level/도구는 XP로 재계산한다. 구 Best의 4인 Coop/Support 기록은 **기록 보관만**, 새 단독 대회 점수에 섞지 않는다.

추가 필드의 정확한 구조:

```lua
EconomyCursor = {Epoch=0,Sequence=0}
ActivityCursor = {Epoch=0,Sequence=0}
Store = {
 DisplayName="", -- 현재 서버에서 얻은 DisplayName 캐시, 접속 때 갱신
 Upgrades={Warehouse=0},
 RecoveryDebt=0,
 Items={ -- Quantity=1; sold/temporary token/Instance/StoreId 없음
  {ItemId="persistent-id",OwnerUserId=123,Sku="Water",UnitCost=4,
   State="Shelf",SlotId="Slot01"},
  {ItemId="another-id",OwnerUserId=123,Sku="Bread",UnitCost=5,
   State="Warehouse",SlotId=false}
 },
 Achievements={DemandCompletions=0,ContestCompletions=0,
  BestDiversity=0,BestPlan=0,BestLogistics=0}
}
```

Items는 최대128개, 창고 단계0/1은24/32개, 선반 슬롯은4개·동일 SKU만. SafeStorage는 반환 초과분을 보존하며 새 발주 용량을 늘리는 수단이 아니다. 새 발주 시 **모든 비terminal 소유품+미인도 유료 주문 수량**이24/32개를 넘으면 거절한다. 이전 자산으로 총량이 초과하면 보존·회수/판매만 허용하고 신규 주문은 빈 공간이 생길 때까지 제한한다. ItemId 중복/타인 Owner/모르는 SKU/잘못된 slot·수량은 PROFILE_CORRUPT로 로드 중단하며 임의 삭제해서 저장하지 않는다.

`SoloStoreProfile.migrate(raw,config,contract,validateLegacy,userId)`는 기존 검증기를 주입받는다. 서버는 현 ProfileService의 v1 normalize를 별도 legacy 함수로 보존/내보내고 **SchemaVersion=1, SeatsPerStore=4, 옛 ModeTags** 사본으로 실행해야 한다. v2 설정으로 구 4인 기록을 검증하면 기존 데이터를 잘못 거절한다. 테스트 runner는 실제 해당 normalizer 소스를 읽어 실행한다. identity validator로 대체하지 않는다.

- nil은 migrate에서 PROFILE_CORRUPT다. 저장소의 성공한 UpdateAsync에서 **키가 실제로 없음**을 확인한 때만 `new(config)`를 호출한다. 읽기 오류/타임아웃/알 수 없는 스키마는 기본값 생성·저장 금지다.
- v1→v2는 검증된 Wallet/XP/기록만 보존하고 Store 빈 재고/0단계/실적0으로 확장한다. v1에 없던 교대 운영자금·월드 진열품을 추측해 가져오지 않는다. 현재 살아 있는 옛 서버 재고를 자동 이관하는 기능은 이번 migration에 없다. 운영 전 기존 세션 정산을 따로 확인해야 한다.
- migration은 순수 후보 생성이다. UpdateAsync에서 이전 Session 만료/Id, Revision을 확인하고 lease 획득과 함께 한 번 저장한다. 같은 v2를 다시 변환해도 초기 돈·재고를 더하지 않는다. active lease가 다른 서버이면 SESSION_LOCKED, 미래 스키마는 SCHEMA_UNSUPPORTED, 손상은 PROFILE_CORRUPT.
- 새 epoch 획득 때 RewardCursor/EconomyCursor/ActivityCursor를 모두 해당 epoch·Sequence0으로 바꾼다. 기존 epoch와 stale writer는 거절한다. `nextCursor`는 현재 epoch에서 정확히 다음 sequence만 승인하며 중복/과거/간격 누락을 거절한다. 저장 실패 중 새 lease를 발급해 같은 사건을 재실행하지 않는다.

저장 장벽 순서:

1. 해당 소유자 경제 명령을 frozen으로 전환하고 앞선 큐 커밋을 모두 마친다. 도난/충돌/판매도 같은 큐이므로 이후 사건은 PROFILE_FROZEN 또는 무변경 처리한다.
2. 미청구 예약은 취소하여 ledger 몫을 해제한다. **이미 비용을 낸 주문은 인도 완료 정책**으로 고정: OrderId+단위 index에서 파생되는 기존 ItemId를 정확히 한 번 원소유 창고/안전 보관에 넣는다. 이미 item을 만든 주문은 다시 생성하지 않는다. 배송 실패 자동 환불과 인도를 둘 다 하지 않는다. 명시 취소가 먼저 커밋된 주문만 지불액 환불·공급 반환 후 terminal.
3. Truck/운반/바닥 드롭/도난품은 모두 원소유자로 정산한다. Shelf는 slot을 유지하고 나머지는 Warehouse, 초과분 SafeStorage. `canonicalItems`는 이 **저장 후보**를 계산할 뿐 라이브 원장/주문/토큰을 정리하지 않는다. 서버가 실물 제거/반환까지 원자적으로 연결해야 한다.
4. 지갑·재고·업그레이드·실적이 같은 Revision의 전체 profile 사본을 만든다. 세션 lease fence를 검사하는 UpdateAsync 콜백은 yield·실물 생성·외부 이벤트 없이 순수 변환이다. 저장 결과의 SavedRevision은 제출한 revision까지만 올린다. 저장 중 새 revision을 허용하면 더 최신 dirty를 보존하고 재저장한다. 퇴장 장벽은 해제하지 않는다.
5. 실패는 SaveFailed+dirty 유지, 제한된3회/1·2초 backoff. 저장 성공을 표시하지 않는다. lease 만료15초 전 새 경제 입력 동결, LeaseLost면 old writer 저장/보상 불가. 종료20초 예산 초과 성공 보장은 하지 않는다.
6. 복원은 `userId+epoch` 단1회. 새 빈 매장에 먼저 비공개 staging으로 모든 아이템/선반 생성·검증한 후 공개하고 복원완료를 기록한다. 실패면 staging을 모두 정리하고 RESTORE_FAILED·입력 잠금을 유지한다. 부분 성공 후 새 ID로 재복원하지 않는다. 복원된 물류/판매 사건으로 점수·XP를 지급하지 않는다.

서버 간 여러 키를 쓰는 거래는 없다. 원소유권 불변으로 도난 때문에 타인 profile에 상품을 편입하지 않는다. 공용 도매는 서버 수명 ledger이며 영속 글로벌 시장이 아니다. Memory 재접속·fake adapter 저장은 cloud 증거가 아니다.

## 업그레이드·무료 회복·임시 도난

창고 업그레이드 0→1: 게임머니120, 용량24→32, 영속 Store.Upgrades.Warehouse. MaxLevel=1, 효과/가격/단계는 서버표, 같은 요청·ExpectedLevel 재전송 차감0. 지갑/단계/revision을 한 트랜잭션으로 변경하고 UpgradePurchased를 발행한다. 현금결제 상품 생성은 없다.

초기240으로 회차1 목표 Water2+Bread2 비용18, 회차2 Milk2+Snack2 비용20을 구매 가능하다. 재고를 모두 판매하면 일반 가격으로 이익이 생기며 무료 정상 영업이 가능하도록 설계했다. 실제 처음 하는 사람의 5분 첫 판매·품절 대기 목표는 미측정이다.

무료 회복은 재접속 현금 보조금이 아니다. Wallet<Water 도매가4, 소유품0·유료 진행 주문0·RecoveryDebt0인 원소유자에게 자기 PC에서 공용 ledger의 Water1개를 **외상 배송**한다. 같은 커밋에 RecoveryDebt=4, Item.UnitCost=0(환불불가)을 기록한다. 실제 공급이 없으면 OUT_OF_STOCK+재입고 시각, 기본품 재입고는120초 상수이며 부족 관측 후 조정한다. 다음 실제 판매에서 `DebtPaid=min(Revenue,RecoveryDebt)`를 먼저 정산한다. 외상 물7 판매이면 부채4를 갚고 지갑3, 다음 회복 판매 후6으로 정상 주문 복귀가 가능하다. 부채가 있는 동안 두 번째 지원·취소 현금 환급은 불가하며 퇴장 때 물건과 부채를 함께 보존한다. 대회/수요 점수에는 외상품을 포함하지 않는다. 정전 실패는 무료 재시작이고 자산 압류·초기화가 없다.

임시 도난: 타인 Shelf/Truck만 거리10+Hold2초, 초보 피해/가해는 접속 초기180초 또는 CompletedFirstShift=false 동안 보호, 피해 cooldown60초. 정상 품목1개를 TheftCarried로 이동, 원소유자는 그대로, CarryToken/Carrier만 변경한다. 실제 TheftAlarm12초와 원소유자 위치 안내가 필요하다. 도난자는 판매/창고 편입/SecureTheft가 불가하다. 25초 만료·회수·사망·원소유자/운반자 퇴장·충돌은 동일 item revision CAS를 통해 원소유 창고/안전보관에 한 번 귀속한다. 충돌은 아래 실제 바닥 드롭 표시를 먼저 거친다. WasStolen 계보는 회차 점수 제외, 회수 왕복 XP/점수0. 경보만 있고 임시 실물 이동/회수가 없으면 THEFT 미완료다.

## R-A 변동 수요와 R-B 영업대회

준비30초+활성300초. CycleId는 서버 발행이며 참가/목표/SKU/기회 계획을 start 전에 고정한다. Rotation1 Water/Bread, Rotation2 Milk/Snack, 각2개로 순환한다. 수요/대회 상태와 진행 중 참가표는 서버 메모리이며 재접속·다른 서버로 회차를 이어 점수 이득을 주지 않는다. 실적/검증된 최고 기록은 저장한다. 스트릭·오프라인 손해·미달 벌금·진행 잠금·접속 강요는 없다.

R-A 준비에서는 프로필 Ready·정상 참여 가능한 소유자 roster를 먼저 고정하고 `planDemand`로 기존 ledger에서 소유자별 각 SKU2개를 유보한다. 부족하면 전체 회차 준비를 대기/다음 회차로 넘기며, 공급을 새로 만들거나 시작 뒤 목표를 바꾸지 않는다. 준비 중 목표 비용 미달 사용자는 명시적 무료 회복/일반 영업 안내를 받고 다음 회차를 선택한다. 제외/대기 사유를 UI에 숨기지 않는다. 함수 자체는 participant에 자금 미달자가 있으면 INSUFFICIENT_FUNDS로 전체 계획을 거절한다.

원장 불변식(각 SKU): `PublicAvailable + Sum(UnspentOwnerAllocations) + ReservedUnpaidOrders = UnconsumedStock`. 구매 커밋에서 해당 몫을 차감하면서 유료 item 계보를 생성한다. 입고는 명시 공급 사건, 취소는 본래 몫으로 복구하되 만료 후에는 공용으로 복구한다. 유보 자체는 새 상품/지갑 지급이 아니다. 마지막1개 경쟁은 유보 밖 PublicAvailable로 검사한다. `AllocationId`에는 owner/cycle/expiry를 서버가 연결하고 다른 owner 사용·재등록/퇴장 재수령을 금지한다.

유보 마감은 활성 시작+120초, UI에 ReserveUntil 표시. 미사용량은 공용에 한 번 반환한다. 퇴장도 한 번 해제하지만 같은 UserId가 돌아왔다고 몫을 새로 주지 않는다. 활성 후 참가자는 NEXT_CYCLE. 회차 중 목표는 고정이다. R-A는 해당 회차 유료 발주→실제 NPC 구매만 인정, 단위 ItemId 중복0, 실제 판매한 단위 수를 목표2개까지 인정한다. 부자 구매도 개인 R-A 목표에는 실제 수량으로 인정해 유보한4개가 무작위 대량구매 때문에 목표 달성에 부족해지지 않게 한다. R-B 계획 점수는 별도의 일반 손님 기회당1개 제한이며 부자 추가량은0점이다. `advanceDemand`의 Completed false→true 때만 DemandCompleted와 영구 DemandCompletions+1을 같은 profile 커밋에 반영한다.

R-B는 준비 중 자발적 참가, 동일 목표2종·신규 발주 최대4개·HandCarry·Slot01/02만 인정한다. 공급 유보와12초 배송 조건은 참가자 전원 동일하다. 대회 유료품 계보는 일반 방문이 먼저 소모하지 않도록 지정 일반 손님 기회까지 선택 대상에서 보류하며, 지정 기회 종료/대회 종료 후 정상 판매 대상으로 해제한다. 이 보류는 기본 무료 정상 영업 전체를 잠그지 않는다. 재입고·배송 실패/위치별 접근 장애는 비교 기회 결함으로 기록한다.

활성 시작+90/140/190/240초에 각 참가자에게 일반 손님 실제 방문·계산 기회를 각각1회 제공한다. 동일 시드·같은 SKU 순서(첫 SKU,첫 SKU,둘째 SKU,둘째 SKU), 같은 선택량1/기회, 같은 구매 의도다. NPC를 순간이동시키거나 가짜 판매를 주지 않는다. World 경로 길이 차이는 사전 출발시각 보정으로 계산 기회 ±5초 이내를 목표로 한다. 서버는 실제 offeredAt/arrivedAt/선택/실패 사유를 기록한다. 물건을 준비하지 못한 정상 기회는 miss, 경로막힘/배송 실패/누락은 기회 불일치다. 자연 방문/부자 손님은 일반 매출에는 기여하지만 대회 점수0이다.

| 부문 | 확정 계약 수치(밸런스 가설) | 인정 조건 |
| --- | --- | --- |
| 다양한 판매 | 종당10, 최대20 | 두 목표 기본품만, 신규 유료품 실제 정상 기회 판매 |
| 계획 영업 | 단위10, 최대40 | 각2개, 기회당1개, 같은 ItemId/기회 재전송0 |
| 물류 완결 | 단위10, 최대30 | 같은 원소유자가 이번 회차 발주→직접 하역→창고→직접 진열→실제 판매한 계보 |

PM의 다양성 최대3종/30점은 DR04에 따라 **2종/20점**으로 줄였다. 동일 유보·4개 발주·일반 손님4회 안에서 세 부문을 실제 달성 가능하게 맞추기 위한 결정이다. 종합점수/종합우승은 만들지 않는다. 부자/금액·업그레이드 보너스0, 왕복 운반·재진열·환불·도난/회수·연습·외상품0. 공동 동점은 모두 표시한다. 공급/기회 공정성은 설계상 보장 선언 대신 실제 기회 로그와 위치 교환 검사로 검증한다.

`ContestFinalized` = `{CycleId,Comparable,Reason=false|code,Participants,Categories={Diversity,Plan,Logistics},Winners={Diversity={userIds},Plan={userIds},Logistics={userIds}}}`. 2명 이상+동일 기회 조건 충족 때만 Comparable=true/상점 비교 결과다. 한 명은 PersonalOnly, 중도 퇴장·동등 기회 실패는 NotComparable이며 우승자를 꾸며내지 않는다. 비교불가 결과로 경쟁 요구 완료를 선언하지 않는다. ContestCompletions와 Best*는 정상 종료한 검증 가능 회차만 `recordAchievement`로 반영(개인 1인 회차는 UI상 PersonalOnly 명시, 비교불가 장애 회차는 영구 대회기록 제외). 임시 화면 기록은 별도로 표시할 수 있다.

실적은 ActivityCursor와 같은 profile revision에서 갱신한다. 같은 회차 finalize를 새 sequence로 또 보내지 않도록 ContestService가 finalized once를 보장해야 한다. 공유 cursor 함수는 **동일 사건에 새 sequence를 부여한 중복**까지 판별하지 않는다. 중복/소유 epoch/후속 이벤트 실패는 큐에서 차단하고, durable profile 기록이 성공했는지 없이 외부 observer에서 보상을 재발행하지 않는다.

공유 점수/목표 함수는 순수 계산이며 시간·lease·인증을 자체 조회하지 않는다. 서버는 사건의 커밋 시각이 `[StartsAt,EndsAt)`이고 해당 소유자의 현재 epoch/cycle인지 검사한 뒤 호출한다. 종료 직전 판매와 finalize도 한 큐로 정렬한다. 종료 뒤 지연 이벤트는 STALE_ACTIVITY로 제외하고, 정상 판매 매출 자체는 일반 영업으로 유지한다. 미래/종료 회차를 클라이언트가 지정해 점수 입력할 경로는 없다.

## 월드 교통·보행·충돌 ForceDrop 계약

월드 루트는 Workspace.NightShiftWorld. 기존 Stores/<StoreId>/Markers의 OfficePC/WarehouseDrop/Unload/TruckDock/Alarm/TheftReturn 및 ShelfSlotIds를 보존한다. WorldAdapter가 실제 기존 계층을 찾아 반환하되 새 교통 구조는 아래로 고정한다. 마커는 Anchored·투명·CanCollide=false·CanTouch=false·CanQuery=false, 실제 길/표현과 분리한다.

| 상대 경로 | 필수 자식/속성 |
| --- | --- |
| Traffic/Routes/Route01 | VehicleSpawn, VehicleStop, VehicleCrossExit, VehicleExit (Part, 순서 고정); CrossingId="Cross01", RouteId="Route01" |
| Traffic/Crossings/Cross01 | StopLine, CrossingEntryNorth, CrossingExitSouth, WaitNorth, WaitSouth, RoadZone, DropSafeNorth, DropSafeSouth; CrossingId="Cross01" |
| Traffic/Signals/Cross01 | VehicleSignal, PedestrianSignal, Phase 속성(서버 writer), PhaseEndsAt |
| PedestrianPaths/<StoreId> | SidewalkSpawn, CrossingWait, CrossingEntry, CrossingExit, StoreApproach, Entry, Browse, Checkout, StoreExit, SidewalkExit; StoreId 및 CrossingId(false 또는 Cross01) |

각 보행 node 속성: NodeId, Order(1~10), Surface=`Sidewalk|Crosswalk|Interior`, CrossingId(false 또는 Cross01), NextNodeId(false 또는 이름). CrossingEntry/Exit는 Crosswalk, 대기 지점은 Sidewalk, 매장 내부 Browse/Checkout은 Interior. 도로 건너기 불필요한 경로는 CrossingId=false이고 실제 인도 경로로 연속 연결한다. 최종 World 담당이 좌표·폭·회전·경로 유효성을 정한다. 마커 존재만으로 NPC가 차도를 가로지르지 않음을 증명하지 않는다.

손님 상태 순서: Sidewalk→WaitingSignal→Crossing→Approach→Browse→Checkout→Exit. 자유 직선 MoveTo로 차도를 단축하지 않는다. pathfinding을 쓰더라도 인도/횡단보도 corridor와 내부 통행 가능 영역에서 검증한다. 신호는 새 진입만 제어하며 이미 횡단한 보행자는 끝까지 진행한다. crossing 점유자가 남으면 차량 녹색을 지연하는 서버 occupancy interlock이 필수다.

위상: VehicleGreen20초→AllRedToWalk3초→Walk12초→AllRedToVehicle3초. `signalAt`은 이상적인 기본 위상만 계산한다. 실제 TrafficService는 차량 정지선·최대 속도에서 제동거리·이미 진입한 차량·보행 점유를 검사해 all-red를 연장한다. Walk 동안 차량은 StopLine 전에 정지하고 VehicleGreen에는 보행자가 Wait 지점에서 기다린다. 두 통행 신호 동시 허용 금지. 누락 마커/계산 실패는 차량 정지·보행 대기로 fail closed, 순간이동 통과 금지.

`forceDrop(context,collision)`의 collision = `{CollisionId,VehicleId,ObservedAt,ServerPosition,SafeDropCFrame,Speed}`. 모든 필드는 서버 TrafficService/WorldAdapter 관측에서 생성한다. 전용 Remote 없음. 서버 소유 차량/network ownership·RoadZone 안·접촉/겹침 또는 swept collision·최소속도2·거리8 이하·현재 플레이어 위치/최대속도·fresh 관측(동일 서버 tick, 최대0.25초)·차량/플레이어 쌍 cooldown2초를 검증한다. 클라이언트 Touch/좌표만으로 충돌 승인하지 않는다.

승인 시 플레이어가 **현재 들고 있는** Carried/TheftCarried만 Recoverable로 이동, CarryToken 폐기·revision 증가, 도로 밖 안전한 바닥 위치에 실제 모델 표시. Wallet/XP/업그레이드·창고/진열 총량 불변. 빈손은 성공 no-op, 매장 안·정지차·원거리·연속 접촉 중복은 무변경. SafeDropCFrame은 DropSafeNorth/South에서 서버 raycast로 찾고 보도/바닥 충돌을 확인한다. 좌표 못 찾으면 안전 보관으로 보존하되 실제 바닥 드롭 미구현/실패로 DROP 검증을 남긴다.

25초 이내 원소유자 회수, 만료/사망/이탈은 원소유 창고 또는 SafeStorage에1회 반환한다. 도난 운반자의 충돌도 OwnerUserId를 바꾸지 않는다. CollisionId replay는 원 응답, 동일 id 다른 내용은 거절. 저장 장벽과 경합하면 하나만 상태를 이동하며 드롭 모델과 저장 항목이 동시에 서로 다른 ID로 생기면 실패다.

## UI snapshot v2

기존 CommerceState 한 스트림, 공개 상태는 서버가 allowlist로 조립한다. `GetCommerceSnapshot`은 동일 형태의 전체 snapshot. 변경마다 Sequence 단조 증가, 오래된 Sequence/OwnerGeneration은 UI가 폐기한다. Secret lease ID·서버 세션ID·다른 플레이어 지갑/재고/개인 CarryToken을 내보내지 않는다. CarryToken은 해당 운반자 본인에게만 보낸다. 아래 필드는 항상 존재하고 없음은 false/빈 배열이다.

| 필드 | DTO |
| --- | --- |
| ProtocolVersion / Sequence / ServerTime | 2 / 연결별 정수 / 동기 서버시간 |
| Self | `{UserId,StoreId=false|id,OwnerGeneration,ProfileEpoch,ProfileRevision,Wallet,XP,Level,DisplayName,Upgrades={Warehouse},Achievements,NextAction}` |
| ProfileStatus | `{State,Mode="Memory"|"DataStore",Frozen,Dirty,SavedRevision,ErrorCode=false|code}`; Temporary는 영구 저장 성공 아님 |
| Stores | 8개 `{StoreId,OwnerUserId=false|id,DisplayName,Occupied,Sales,Revenue,Alarm=false|{ItemId,RecoverUntil}}`; 직원 명단 없음 |
| Store | 본인만 `{StoreId,OwnerUserId,OwnerGeneration,Revision,WarehouseCapacity,SafeStorageCount,Orders,Items,Slots}`; 미배정 false |
| Wholesale | `{Revision,Cycle,NextRestockAt,Rows={{Sku,PublicAvailable,MyAllocated,AllocationId=false|id,ReserveUntil=false|time,UnitCost,SalePrice,Rarity}}}` |
| Items / Nearby | 공개 item `{ItemId,Sku,Quantity=1,OwnerUserId,OwnerStoreId,State,Revision,SlotId=false|id,CarrierUserId=false|id,RecoverUntil=false|time}`; 상세 UnitCost는 본인 Store만 |
| Carry / Theft | Carry=본인 item+CarryToken 배열, Theft=false 또는 `{TheftId,ItemId,State,CompleteAt,RecoverUntil}` |
| Orders / Slots | Orders=`{OrderId,Sku,Quantity,State,ArriveAt,RecallAt=false}`; Slots=`{SlotId,Sku=false|sku,ItemIds,Revision}` |
| Demand | false 또는 `{CycleId,Phase,StartsAt,EndsAt,ReserveUntil,Eligible,Reason=false|code,Targets={{Sku,Required=2,Sold}},Completed,NextTargets}` |
| Contest | false 또는 `{CycleId,Phase,Joined,Eligible,Comparable,Reason=false|code,StartsAt,EndsAt,NextOpportunityAt=false|time,Scores={Diversity,Plan,Logistics},Rows,Results=false|finalizedDTO}` |
| Traffic | `{Revision,Signals={{CrossingId,Phase,VehicleGo,PedestrianGo,PhaseEndsAt}}}` |
| NextAction | Self 내부 enum: `WaitForProfile|WaitForStore|GoToPC|WaitForDelivery|Unload|Warehouse|PlaceShelf|WaitForCustomer|RestorePower|FreeRecovery|ViewResults` |

Contest Rows는 `{OwnerUserId,DisplayName,Scores,Status="Pending"|"Active"|"PersonalOnly"|"NotComparable"|"Finished"}`이고 종합점수 없음. UI의 요청대기/실패/닫기/저장 상태는 PC·모바일 공통이다. 자기 PC가 아니면 구매 버튼 비활성+서버 NOT_OWNER를 둘 다 적용한다. 첫 판매 전에 정전/대회 팝업을 강제하지 않는다. 간판은 현재 DisplayName, raw 저장 DisplayName을 신뢰해 다른 사람 이름을 표시하지 않는다.

## 검사·실패 사례·후속 연결

재현 명령: `python src/shared/tests/run-contract.py`.
증거: `src/shared/.validation/contract-checks.txt`, `contract-report.json`(UTC·종류·exit code·소스 SHA256). 실제 공유 함수와 기존 v1 normalizer를 standalone Luau로 실행한다. **서비스 모의/Studio/클라우드 검사 실행은 아니다.** 최초 실행은 Windows 한글 절대 경로를 Luau CLI가 열지 못해 실패했고, runner를 상대 경로로 바꾼 뒤 통과했다. 최초 실행 실패를 게임 버그나 통과로 바꾸지 않는다.

| 확인 영역 | 이번 공유 검사 | 후속 서버/실제 검사(아직 미검증) |
| --- | --- | --- |
| OWN | 8/8/1·world IDs·직원 액션 제거·위조 payload/구버전 거절 | 실제 A/B 배정, 동시8명·9번째 거절, 오래된 세대·퇴장/재접속 |
| SALE | 3% 경계·정상/부자 상수·커서/replay | NPC 보행→선택→계산, 마지막1개/NPC둘/도난/이탈 경합, owner만 매출 |
| SAVE | 실제 v1 검증기 migration·무지급·재실행·4인 구 기록 보존, item canonical/중복·foreign/overflow | 실패 주입 load/save/lease/중간복원/종료/저장 중 판매, 실제 cloud 별도 |
| R-A | 8명 유보 합 보존·공급0/부족·자금미달·중복 참가·회차 변경, 진행·재처리·실적 | 실제 ledger 연결/마지막 공용1개/만료·퇴장 재등록/2회차 목표 |
| R-B | 실제 점수함수·natural/rich·도난·옛 회차·연습·상위도구/슬롯·반복 사건 제외·상한 | A/B 신규/부유 프로필 위치 교환, 공급·배송·기회 로그, 비교가능 결과 |
| ROAD/DROP | 기본 신호3주기 상호배제·경계 | 실제 차량 제동·점유 interlock·인도/횡단·빈손/상점안/연속충돌·바닥 드롭 |
| GROW/UI | 업그레이드 비용/용량, 이벤트/DTO/실적 계약 | 무료 업그레이드 실제 차감·저장, 실제 PC/모바일 닫기·오류·다음행동 |

후속 소유권: Server는 src/server 안에서 Main/Protocol/Profile/Commerce 및 작은 Ownership/DemandGoal/Contest 모듈을 연결한다. NPC와 Traffic 전문 작업은 서버 담당과 파일 소유권·서버 facade 완료 시점을 먼저 합의한다. UI는 src/client에서 v2 상태·직원 UI 제거·저장/목표/대회/업그레이드를 연결한다. World는 tools/world에서 마커/실제 경로/신호·간판을 구현한다. Review는 읽기 전용으로 원자성/권한/회차 재처리와 미검증을 확인한다. Studio 조작은 Integrator만 소유하고 사용자 중단 제한을 준수한다.

운영자 체크(실행 안 함): 실제 Place MaxPlayers는 기존 보고상30이므로 승인된 운영 시 **8 설정 확인**이 별도로 필요하다. 서버9번째 소유권 거절은 공개 설정과 무관하게 구현해야 한다. 실제8인 부하·모바일 터치·클라우드 재접속·최종 rbxl 저장/해시/재열기·광고 공급/수익·음성은 아직 검증되지 않았다. 공개 게시·상품 생성/판매·유료 API/에셋·외부 메시지는 실행하지 않았다. DR09 광고/시설과 DR10 최종 저장은 해당 소유 작업으로 연결하며, 이 공유 계약이 해당 완료를 대신하지 않는다.

최종 오프라인 확인: 2026-11-01T01:46:22+09:00 (KST, 09:00 기한 전). 공유 Luau 5개 파일 compile exit=0, **291 assertions PASS**, test exit=0. `git diff --check -- src/shared docs/implementation/solo-store-contract.md` 공백 오류 없음. 보고서 생성 UTC=2026-10-31T16:46:02.765296+00:00. 실행 종류는 OFFLINE_PURE_LUAU이며 studioRun=false, cloudRun=false, serviceMocksRun=false다. 공식 Codex 세션의 01:43 KST 잔량27%를 확인했고 추가 모델 배정은 하지 않았다. 본 단계 완료 표식은 Moderator 검토 대기다.
