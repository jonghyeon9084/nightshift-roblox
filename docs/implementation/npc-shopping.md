# NPC 쇼핑 소스·오프라인 검증 인계

NightShift-CustomerNPC / NightShift-NpcShopping-RC / 2026-11-01 KST.

**소스 단계 검토 준비. 완료 표식은 Moderator의 파일·근거 확인을 기다린다. `releaseReady=false`, `warehouseAcceptanceComplete=false`, `studioRun=false`다.** 보이는 리그를 움직이는 소스를 구현했지만, 실제 Roblox에서 보행·구매를 실행했다는 뜻은 아니다. Traffic 점유 어댑터 연결과 Integrator 설치·실플레이가 남아 있다.

`warehouse-source-handoff.md`를 먼저 읽고 AGENTS.md, release-target, release-task-decisions(DR01~12), release-acceptance-matrix, solo-store-contract/server를 적용했다. 이전 창고의 Escape 저장 중단·새 Place 저장·실제 적재/경합·최종 인수 미완료를 유지한다. Studio/Computer Use를 호출하거나 저장을 우회하지 않았다. 공개 게시·실제 상품 판매·유료 에셋·유료 API 실행은 없다.

## 변경 파일과 소유권

배정 `src/server/` 및 이 문서만 변경했다. 다른 담당자의 기존 변경을 되돌리지 않았다.

| 파일 | 이번 변경 |
| --- | --- |
| `src/server/Modules/NPCShoppingService.luau` 신규 | 서버 NPC registry, 방문·신호 대기·진열 접근·선택·계산·퇴장, 자연/VIP/대회 일정, 상한·재시도·정리 |
| `src/server/Modules/NPCWorldAdapter.luau` 신규 | 실제 World 마커/계산대/슬롯 연결, 보행 경로·바닥 ray·몸체 Blockcast, 리그/봉투/한글 상태 표현, 무료 자체 리그 fallback |
| `src/server/Modules/RuntimeBridge.luau` | `npcInventory`, `CancelNpcSelection`, 보행 점유 어댑터 등록/조회 추가 |
| `src/server/Main.server.luau` | 같은 서버에서 NPC 생성·등록, 읽기 전용 진열 조회, 선택 취소 큐 명령, 종료 시 NPC 정리 |
| `src/server/Modules/CommerceService.luau` | NPC가 실제 바라본 SlotId로 선택 범위 제한, 동일 NPC/소유 세대/epoch 선택 취소 |
| `src/server/tests/NPCShopping.spec.luau` 신규 | 실제 NPC/경제 모듈을 함께 실행하는 시간·월드·교통 fake 검사 |
| `src/server/tests/Run-NPCChecks.py` 신규 | Luau compile/run, stdout/stderr와 소스 SHA256 기록 |
| `src/server/tests/NPCWorld.spec.luau` 신규 | 실제 BuildWorld/리그/어댑터의 8×12 경로를 fake ray/AABB로 샘플링 |
| `src/server/tests/NPCWorldMock.luau` 신규 | 기존 월드 검사에서 재사용한 fake Instance/벡터/회전 기반 fixture; Roblox 엔진이 아님 |
| `src/server/tests/Run-NPCWorldChecks.py` 신규 | 기하 모의검사 bundle/run, 결과·입력 해시 기록 |
| `docs/implementation/npc-shopping.md` 신규 | 이 인계와 실제 Studio 검사 절차 |

`src/server/.validation/npc-shopping-*`, `npc-world-*`는 생성된 로컬 검사 근거다. 기존 `Run-SoloChecks.py`를 재실행하여 그 기존 산출물도 갱신했다. shared/world/client/설치 manifest/worker-pool은 수정하지 않았다. 작업 시작 전에 이미 있던 ServerOwner/UI/World 변경은 이번 작성 목록에 포함하지 않았다.

## 실행되는 흐름과 경제 경계

Main이 기존 단일 경제 큐를 유지하며 NPC를 등록한다. NPC는 서버 전용 `Bridge.submit`만 사용하고 Wallet/Items/수요/대회 상태를 직접 쓰지 않는다. 신뢰되지 않은 새 Remote나 테스트 강제 VIP 액션은 추가하지 않았다.

1. 서버 RNG로 자연 방문 간격 12~24초를 정한다. 매장별 자연 손님은 최대1명, 전체 손님은 공유 계약대로 최대2명/매장 및 16명/서버다. 서버 sample `<0.03`은 Rich, 나머지는 Normal이며 금전 결제나 유료 호출이 없다.
2. 실제 모델을 인도에 생성한다. World의 SidewalkSpawn→CrossingWait를 따라간 뒤 Traffic의 원자적 횡단 허가/점유 확보를 기다린다. 허가 후 CrossingEntry→CrossingExit→StoreApproach→Entry를 순서대로 이동한다. 일반 직선 pathfinding으로 차도를 단축하지 않는다.
3. 서버 진열 조회에서 구매 가능한 슬롯을 무작위 선택하고 그 슬롯 앞 통로까지 간다. 약 0.75초 상품 보기 후 선택 API를 호출한다. 선택 가능한 상품이 없으면 보이는 방문 후 무구매 퇴장한다.
4. authority는 NPC ID, Kind, StoreId/UserId, OwnerGeneration, ProfileEpoch, 방문 순서, 현재 모델 Torso 위치, 현재 Browse/Checkout 상태를 대조한다. Commerce는 해당 SlotId의 실제 Shelf 재고만 선택한다. Normal 최대1개, Rich 최대4개이며 같은 슬롯의 실제 재고보다 많을 수 없다. 이번 bulk는 여러 슬롯을 순회하는 장바구니가 아닌 **한 슬롯의 동일 SKU 묶음 구매**다.
5. 선택 상품 ID/revision·10초 lease를 들고 실제 계산대 앞까지 이동한다. 봉투에 수량·SKU 속성을 표시하되 상품 ledger 소유권은 결제 전 그대로다. 실제 도착 후 `CommitNpcSale` 하나가 재고 감소, 해당 주인 Wallet/XP/도감, 수요·대회 사건을 처리한다. 수량/가격/상한/프로필 freeze/세대/품절/도난은 기존 원자 커밋에서 다시 검사한다.
6. 성공하면 통로→입구→인도 퇴장 후 모델·registry를 정리한다. 선택 후 상품 이동/도난/만료는 무변경 실패 후 자연 손님에 한해 한 번 다시 걸어가 재선택한다. 통신 결과 유실에 해당하는 일시 실패는 같은 TransactionId와 본문으로 한 번 재시도한다. 새 거래로 중복 지급하지 않는다.

총 체류 제한은 90초, 서버 이동 갱신은 최대20Hz, 일정 검사는 매장별 최대4Hz다. 한 이동 tick은 최대0.2초분만 전진하여 긴 프레임 지연을 순간이동으로 만회하지 않는다. 경로 장애/리그 소실/타임아웃은 판매 없이 정리한다. owner 이탈·세대 변경·캐릭터 미로드·세션 종료에도 모델과 교통 점유를 해제한다. 선택 취소는 원 소유자·NPC·세대·epoch가 일치해야 하며, 결제된 선택의 사용 표식은 되돌리지 않는다. 진단 사건 ring은128개, owner 일정은 최대8개, 대회 pending은 회차당4개다.

## 수요·대회 연결과 일정 선택

대회는 기존 `OfferOpportunity`로 지정 SKU·DueAt을 받는다. 경로 길이/보행속도와 최대 기본 신호 주기 여유를 반영하여 사전 출발하고, 너무 일찍 도착하면 진열 앞에서 기다린다. 실제 계산대 도착 시각만 `ObserveOpportunity`에 넣는다. 재고가 없으면 Miss, 경로/용량/신호 장애는 Blocked 또는 실제 늦은 시각으로 남는다. 시각을 DueAt으로 꾸미거나 순간이동·가짜 구매로 보정하지 않는다. 비교 여부는 기존 ContestService의 ±5초/누락 검증이 결정한다.

**구현 중 확인한 운영 선택:** 50초 간격의 고정 기회보다 긴 사전 접근 때문에 두 대회 손님이 겹칠 수 있다. 자연1명+대회1명으로 항상 슬롯을 분리하면 세 번째 기회가 NPC_CAP으로 차단되는 회귀를 발견했다. 따라서 참가 매장의 준비/활성 회차에는 새 자연/VIP 방문을 잠시 보류하고 두 자리를 고정 기회에 우선한다. 이미 입장한 자연 손님은 계속 진행하며, 자리가 부족한 대회 기회는 bounded pending으로 재시도한다. 회차 종료/미참가 매장은 자연 무작위 방문을 계속한다. 자연 방문과 대회를 동시에 늘리려면 2명 상한·기회 간격·World/Traffic 실제 이동시간을 함께 검토해야 한다. 이 변경의 재미/체감/대회 공정성은 아직 실측하지 않았다.

성공한 Normal 고정 기회의 실제 단위만 대회 점수로 인정된다. 자연/Rich 판매는 대회 점수0이며 실제 유료 발주 단위의 수요 진척은 기존 계약대로 인정된다. 오프라인에서 NPC 일정부터 4회 실제 서비스 판매까지 연결하여 수요 완료1회, 다양성20/계획40/물류30을 확인했다. 해당 숫자는 Studio 실측이 아니다.

## World·Traffic 연결 계약

World는 현행 `PedestrianPaths/<StoreId>` 10개 순서/Surface/StoreId, 실제 `Stores/<StoreId>/Counter`, `ShelfSlots/Slot01..12`를 사용한다. `ServerStorage.NightShift.BuildCustomerRig`가 있으면 `create(kind)` 리그를 검증하여 사용한다. 없거나 실패하면 서버 어댑터의 자체 6파트 리그로 보이는 손님을 만든다. 외부 에셋이나 외부 스크립트를 가져오지 않는다. 리그 자식 OffsetX/Y/Z 좌표 계약으로 서버에서 pose하며, 스크립트 포함/비고정/충돌 모델은 거절한다.

현행 World의 Checkout 마커는 local `(12,1,12)`로 실제 Counter의 반대편이다. NPC 어댑터는 그 마커를 결제 증거로 쓰지 않고 실제 Counter 앞 local `(-12,1,14.5)`의 바닥 위치를 계산한다. 또한 스폰 패드 `(x=-4..4,z=11..17)`를 직선 통과하면 몸체가 막혀, 입구→`(0,20)`→`(6.5,20)`→`(6.5,3)`→중앙 통로로 우회한다. 계산대는 같은 통로를 거쳐 `(-12,20)`에서 접근한다. 회전한 팔·봉투·부자 모자까지 포함하는 4.6×5.8×4.6 몸체 상자로 이동을 검사한다. 이는 server 소스 보정이며 World 마커 자체를 수정한 것이 아니다. World/Integrator가 마커와 실제 사용 경로의 일치를 후속 확인해야 한다.

Traffic 담당은 Main의 `Bridge.configure` 이후 아래 adapter를 등록해야 한다.

```lua
Bridge.registerPedestrianTraffic({
    requestCrossing = function(self, npcId, crossingId, observedAt, requiredSeconds)
        -- 동일 서버 tick, yield 금지.
        -- 보행 녹색 + 차도 차량/점유 없음 + 안전한 시간 여유를 검사한다.
        -- OK를 반환하기 전에 npcId 점유를 원자적으로 등록한다.
        -- 이미 진입한 보행자의 점유가 남으면 차량 녹색을 지연한다.
        return {Ok=false, Code="WAIT_SIGNAL", Value=false}
    end,
    releaseCrossing = function(self, npcId, crossingId)
        -- 반복 호출에도 안전하게 점유 해제.
        return {Ok=true, Code="OK", Value=false}
    end,
})
```

위 코드는 인터페이스 예시이며 실제 Traffic 구현이나 신호 통과 증거가 아니다. `registerTraffic`의 차량 충돌 authority와 별개다. 신호 없음/adapter 없음/오류/yield는 진입 거절이다. 진입 후 신호가 바뀌어도 끝까지 걸은 뒤 점유를 해제하며, 제거 시 먼저 리그를 제거하고 같은 granting adapter의 점유를 해제한다. 단순 `Phase="Walk"` 속성 읽기로 occupancy interlock을 우회하지 않는다. **현재 Traffic 어댑터가 연결되지 않으면 손님은 보도에서 대기하고 90초 후 정리되며 매출이 나지 않는다.**

## 실행한 검증과 근거

로컬에 이미 준비된 `tools/world/.validation/luau-0.745` 실행기를 사용했다. 다운로드/유료 API/추가 모델 호출은 하지 않았다.

```powershell
python src/server/tests/Run-NPCChecks.py
python src/server/tests/Run-NPCWorldChecks.py
python src/server/tests/Run-SoloChecks.py
git diff --check -- src/server/Main.server.luau src/server/Modules/CommerceService.luau src/server/Modules/RuntimeBridge.luau src/server/Modules/NPCShoppingService.luau src/server/Modules/NPCWorldAdapter.luau src/server/tests/NPCShopping.spec.luau src/server/tests/NPCWorld.spec.luau src/server/tests/NPCWorldMock.luau src/server/tests/Run-NPCChecks.py src/server/tests/Run-NPCWorldChecks.py
```

| 검사 | 결과 | 근거 |
| --- | --- | --- |
| NPC compile/실제 상태·경제 모듈 fake-engine 실행 | exit0, 기존546 + NPC527 assertions PASS | `src/server/.validation/npc-shopping-checks.txt`, `npc-shopping-report.json`, `npc-shopping-tests.luau` |
| 실제 생성 월드/리그/어댑터, fake ray/yaw/AABB | exit0, 8매장×12슬롯, 218869 샘플 assertions PASS | `src/server/.validation/npc-world-checks.txt`, `npc-world-report.json`, `npc-world-tests.luau` |
| 기존 서버·공유 회귀 검사 | compile/test exit0, 서버546·공유291 PASS | `src/server/.validation/solo-server-checks.txt`, `solo-server-report.json` |
| 지정 소스 whitespace | exit0, 오류 없음 | 위 git 명령 재현 가능 |

assertion 수에는 setup과 반복 기하 샘플이 포함되며, 서로 다른 실제 플레이 시나리오 수가 아니다. 각 JSON은 실행 UTC·입력 SHA256·`studioRun=false`를 기록한다. Main은 compile했지만 Roblox에서 부팅하지 않았다. 기하 검사는 실제 builder 출력과 실제 NPC adapter를 실행하되 **fake 바닥 ray 및 0.1-stud AABB 샘플**이므로 Roblox Blockcast, 캐릭터/차량 동적 충돌, 렌더링/복제 성능을 증명하지 않는다.

검사 범위: 3% 경계, 1/4/품절 수량 상한, 진열 SlotId 제한, 결제 전 무수익, 마지막1개 두 NPC 경쟁, 실제 TheftService hold 완료 후 원소유 보존/다른 상품 재선택, 선택 만료, 동일 TransactionId 재전송·한 번만 경제 사건, owner 이탈·freeze·종료 중 callback, 신호 없음/빨강 대기, 횡단 중 빨강 전환·점유 해제, 이동 장애/90초 timeout, 매장2/서버16 상한, 쿨다운, 대회 Miss/실제4회 판매·수요·점수, 8방향 매장 12슬롯 접근·계산·퇴장·lease 내 이동, authored rig와 fallback, 잘못된 횡단 마커 거절.

초기 실패도 구분한다. 첫 서비스 검사는 fake traffic의 Lua `and nil or` 표현 때문에 “adapter 없음”이 잘못 구현되어 fixture를 수정했다. 기하 검사는 실제 스폰 패드 충돌을 발견해 런타임 경로를 수정했다. 4회 대회 검사는 NPC_CAP 때문에 점수30/40이 되어 위 일정 우선순위를 수정했다. 최초 기하 전수 검사는 전체 물체 선형 탐색으로 오래 걸려 중단하고 공간 격자 broad phase를 넣어 동일 검사를 완료했다. 최종 PASS는 위 수정 후 실행 결과다.

## Integrator 최종 Studio 절차 — 아직 실행하지 않음

Escape로 중단된 Computer Use/저장 작업을 이 인계로 재개 승인했다고 해석하지 않는다. 아래는 Integrator가 허용된 최종 검증 환경에서 수행할 절차다.

1. 설치 manifest에 `NPCShoppingService`, `NPCWorldAdapter`를 ModuleScript로 추가하고 변경 Main/Commerce/RuntimeBridge와 선행 v2 서버/shared 모듈을 동일 소스로 설치한다. `BuildCustomerRig`를 ServerStorage에 설치한다. 없을 때 fallback 검사도 별도 수행한다. Traffic의 원자 점유 hook 연결을 먼저 확인한다.
2. 별도 테스트 복제본에서 플레이어2명·서로 다른 매장에 정상 PC발주→하역→창고→직접 진열한다. Workspace `NightShiftWorld/ServerCustomers`에 실제 모델이 보이는지 확인한다. 매장 양방향 각각 인도/빨강 대기/횡단/입구/스폰패드 우회/진열/계산대/퇴장 영상을 남긴다. 계산 전 Wallet 불변, 계산 후 Shelf 수량 감소와 같은 owner Wallet/부채/Revenue 변화가 일치해야 한다.
3. 리그의 `CustomerKind`, `ShoppingPhase`, `ShelfSlotId`, ShoppingBag의 `Units/Skus`와 서버 `Bridge.host.npcAuthority.events`, Commerce의 `NpcSaleCommitted`를 같은 NpcId/거래로 대조한다. 다른 매장 돈은 불변이어야 한다. 모델 없는 시간 기반 지급은 실패다.
4. 테스트 복제본의 생성자에 고정 RNG를 주입하여 0.029999/0.03 경계, Rich 표시와 최대4개·재고1개·품절을 확인한다. 운영 소스에 Remote 강제 VIP를 추가하지 않는다. 중간 도난/주인 회수·선택10초 만료·동일 거래 재전송·owner 퇴장/재접속·서버 종료를 반복하여 원소유·수량·수익 보존을 기록한다.
5. 양방향 차량이 정지선에 멈추고 보행 신호 때만 NPC가 횡단하는지 검사한다. 횡단 중 신호 전환, adapter 제거, 마커 삭제, 임시 통로 장애에서 차량 점유 interlock·무수익 정리·90초 timeout을 확인한다. 도로 밖 임의 직선 통과나 보도 아래/공중 이동은 실패다.
6. 두 매장이 같은 회차에 참가하여 4회 실제 일반 손님의 offeredAt/DueAt/arrivedAt/선택/실패를 기록한다. 정상 ±5초, 동일 SKU/기회/단위, 실제 수요/대회 점수와 영구 실적을 대조한다. 품절은 Miss, 경로/차량/자리 장애는 NotComparable로 이어져야 한다. 대회 중 자연/VIP 보류와 종료 후 재개를 확인한다.
7. 실제8인/서버16 NPC, 차량2대, 아이템·UI 복제 부하/프레임·정리 후 모델0·점유0을 확인한다. NPC Blockcast의 플레이어 일시 가로막기 동작, 96개 슬롯 접근, 한글/봉투/리그 가시성을 PC와 모바일에서 확인한다.
8. 테스트 RNG/재고 조작/관측 전용 스크립트를 최종본에서 제거하고 저장 상태·소스 해시·실제 파일 해시를 대조한다. 기존 창고 실제 적재/경합과 최종 rbxl 저장·재열기 미완료를 별도 해소해야 한다. 공개 게시·실제 판매는 이 단계 범위가 아니다.

## 남은 연결과 판정

- Traffic: `registerPedestrianTraffic` 구현·점유 interlock·실제 차량과의 대조가 필수다. 현재 NPC 코드만으로 ROAD 통과가 아니다.
- World/Integrator: 실제 Checkout 마커 불일치와 스폰 패드 우회 좌표를 검토하고 설치 manifest에 모듈을 추가한다. 10개 마커 존재만으로 실제 엔진 보행 합격으로 표시하지 않는다.
- Review: 자연/VIP 일시 보류의 대회 체감, 긴 신호 대기·기존 손님으로 인한 기회 지연, 선택 lease/큐 지연, 프로필 경계·재전송을 독립 검토한다.
- 미검증: Roblox Main 부팅·리그 렌더/복제·Blockcast/raycast·실제 보행 신호/차량·실제2/8인·모바일·클라우드 저장·종료/rejoin·최종 Place 정합성/저장/재열기. SALE/VIP/ROAD/GROW의 실플레이 합격과 전체 출시 준비를 선언하지 않는다.

공식 Codex 세션 rate_limits 확인: 2026-11-01 02:30:19 KST 잔량23%, `stopNew=false`, `stopActive=false`, 예비10% 정책 유지. 신규 워커/다른 계정/유료 모델 호출은 없었다. 관측 이후 계정 전체 지연 집계까지 제어한다고 보장하지 않는다.
