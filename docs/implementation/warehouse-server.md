# 창고·배송 서버 인계

2026-11-01 / NightShift-StoreStorage, Server 소속 임시 워커. 수정 범위는 `src/server/`와 이 문서뿐이다. Studio 실행·설치, 공유 설정/계약, UI, `tools/world/`는 수정하지 않았다. 작업 시작 전 존재하던 Profile·주문·이동 통합 수정은 유지했다.

## 선행 확인과 변경 범위

`commerce-contract.md`, `CommerceConfig`, 실제 Commerce/Delivery/WorldAdapter/Main/Protocol과 UI 호출을 확인했다. 실제 액션은 `PickCargo`, `PickWarehouse`, `PickShelf`이며 **`PickItem` Remote/API는 없다**. 기존 `OrderStock → Reserved/InTransit/Docked → Truck → Carried → Warehouse → Carried → Shelf` 흐름, 취소·회수 환불, 토큰·Revision 검사, 단일 서버 큐를 재작성하지 않았다. 트럭에서 선반으로 직접 운반하는 기존 경로도 유지한다.

이번 변경 파일:

- `src/server/Modules/CommerceService.luau`: 창고 진입 시 가장 낮은 빈 `WarehouseBin` 1..24 배정, 이탈 시 해제. 출발 시 상품별 `CargoIndex` 1..주문수량 기록. 두 값은 서버 표현용이고 기존 공개 DTO/액션 스키마에는 추가하지 않는다.
- `src/server/Modules/WorldAdapter.luau`: 실제 상품별 분리 배치, 창고 칸 번호·수량, 트럭 잔량·배송 위치 표시, TruckWorld의 실제 create/pose 연결, OfficePC 소속·활성·로드 방어 검사, 직접 안내면 연결.
- `src/server/Modules/OperatorContent.luau`: 운영자 전용 자체 안내 설정·슬롯 ID·빈 asset allowlist/creative 목록, 면 충돌 검사. 신규 모듈.
- `src/server/Main.server.luau`: OperatorContent 주입, 설치된 BuildDeliveryTruck을 선택적으로 주입. 기존 프로필 저장·직렬 큐·이동 경로는 변경하지 않는다.
- `src/server/tests/WarehouseServer.spec.luau`, `WarehouseWorld.spec.luau`, `Run-WarehouseChecks.py`: 실제 도메인 모듈 모의검사와 재현 실행기.

## 재고·권한 보존

상품은 서버 주문으로 생성된 Item만 취급한다. 보관/집기/진열에는 현재 점포·RoundId·활성 근무·프로필 epoch/좌석 세대·ItemRevision을 검사한다. 내려놓기는 현재 운반자와 CarryToken도 일치해야 한다. 클라이언트가 상품·가격·수량·칸 번호를 생성하지 못한다.

창고 24칸은 각 1단위이며 **점포 전체 상한24와 별도로 24개를 추가 제공하지 않는다**. 기존 `_size`는 예약수량과 모든 비종료 소유 상품을 센다. 운반 중이거나 도난 회수 대기 상태라도 원점포 상한을 점유하므로 반환을 위한 공간이 보존된다. 창고에만 있는 상품은 `WarehouseBin`이 서로 다르다. 선반은 기존 단일 SKU/칸당4개 규칙이다.

`_move`는 창고칸 가용 불변식을 상태 변경 전 검사한다. 정상 서버 경로에서 빈칸이 없을 수 없도록 기존 주문/도난확보 상한이 보장한다. 불변식 위반은 조용한 삭제·덮어쓰기 대신 assert로 드러낸다. 창고 도난은 허용하지 않으며 기존 Truck/Shelf 도난 범위만 유지한다. 중복 클릭은 기존 Protocol replay 및 ItemRevision/토큰으로 차단된다. 회수는 아직 Truck인 단위만 환불하고 이미 창고/진열된 단위는 환불하지 않는다.

OfficePC 주문은 `Commerce:_auth`의 최신 근무 권한과 자기 StoreId에서만 허용한다. 이후 `WorldAdapter:check`가 생존·이동 예산·거리10·시야를 검사한다. 추가 방어로 OfficePC target과 context 소속/Loaded/Active도 비교한다. UI를 멀리서 호출해도 주문되지 않는다. 기존 레벨/지갑·지원금·보상 코드는 변경하지 않았다.

## 실제 표현과 월드 연결

| 대상 | 현재 코드가 사용하는 경로·속성 |
| --- | --- |
| PC/창고/하역/트럭 기준 | `NightShiftWorld/Stores/<StoreId>`의 기존 `OfficePC`, `WarehouseDrop`, `Unload`, `TruckDock`; 좌표와 StoreId 불변 |
| 트럭 경로 | 기존 `TruckRoute/Approach,Dock,Exit`; Dock 위치=TruckDock |
| 실제 트럭 | `NightShiftWorld/CommerceRuntime/Trucks/<OrderId>` Model, StoreId·OrderId·CargoCount·PresentationKind·RouteSegment·RouteAlpha·DeliveryPhase |
| Cargo | 트럭 직접 자식 Part; 기존 `Dock.CFrame * CFrame.new(0,3,0)`, StoreId·OrderId. 거리판정은 이 기준을 유지 |
| 상품 | `CommerceRuntime/Items/<ItemId>` Part 하나/재고 단위; Quantity=1, 기존 ItemId/Sku/OwnerStoreId/State/Revision/OrderId/CarrierUserId/SlotId 및 표현용 WarehouseBin/CargoIndex |
| 창고 수량 | WarehouseDrop의 WarehouseCount/WarehouseCapacity와 `WarehouseCount` BillboardGui. 품목별 Part에는 칸 번호 표시 |

트럭 상자는 Cargo 기준 2×2로 분리하며 y=-0.9에서 실제 BuildDeliveryTruck Body 상판에 놓인다. 출발/이동/정차/퇴장 위치는 DeliveryService가 호출하는 `moveTruck`만 결정한다. 이동 시 실제 Truck 상태 상자도 같은 단계에서 움직인다. 선반의 같은 슬롯4개, 손수레2개도 서로 떨어져 표시한다. 종료된 상품 표현은 제거되며 렌더 재시도 때문에 경제 전이를 재실행하지 않는다. 캐릭터가 잠시 없어 렌더가 실패해도 수량은 마지막 커밋 상태를 따른다.

창고칸 배치는 WarehouseDrop 기준 4열×2행×3단이다. 1.2×1.4×1.2 상자를 포함한 로컬 외곽은 x=-2.85..2.85, z=-19.35..-16.65(점포 좌표), y=1.1..5.5다. 설계상 별도 적치 범위 x=-3..3 안에 있고 오른쪽 보호 동선 x=5.5..11.5에는 놓지 않는다. 측면 WarehouseShelf 장식은 추가 재고가 아니다. 칸 번호는 서버 내부 위치이며 새 영구저장/공유 SlotId 계약이 아니다. 빈칸은 논리 위치이고 별도 24개 바닥 Part를 생성하지 않는다.

### TruckWorld 실소스 연결

작업 중 작성된 `tools/world/BuildDeliveryTruck.luau`를 읽기만 하여 실제 API에 연결했다:

```lua
BuildDeliveryTruck.create(storeId, orderId) -- model, body, cargo
BuildDeliveryTruck.pose(model, routeFrame) -- OffsetX/Y/Z로 모든 직접 자식 Part 이동
```

Integrator가 해당 파일을 **`ServerStorage.NightShift.BuildDeliveryTruck` ModuleScript**로 설치해야 한다. Main은 설치된 모듈을 require하여 WorldAdapter에 주입한다. 현재 읽은 build-loader는 서버 Modules를 자동 포함하지만 월드 모듈은 별도 manifest 행이므로 **Integrator가 BuildDeliveryTruck 설치 행을 추가해야 한다**. 이 워커는 로더를 수정하지 않았다. 모듈이 없으면 `PresentationKind=FallbackFlatbed`로 기본 직접 하역 표현을 유지하며 최종 TruckWorld 설치 완료로 표시하지 않는다. 설치되면 `PresentationKind=BuildDeliveryTruck`인지 확인한다. 생성 모델의 Cargo/로컬 좌표·pose 존재를 확인하고 Script/Remote/AdGui가 든 모델은 거절한다.

최종 차량 외곽·휠/하역 공간·남쪽 180도 매장 회전·8매장 동선은 Studio 확인 대상이다. 오프라인 벡터 모의환경은 평행이동만 구현했으므로 회전·실제 raycast·렌더 성공을 증명하지 않는다.

## 운영자 콘텐츠 연결과 미확정 규약

OperatorContent의 `Settings.Notices`가 LCD/Truck 자체 안내 문구다. `SponsorshipEnabled=false`, `VideoEnabled=false`, `AllowedAssetIds={}`, `Creatives={}`다. `resolve`는 자체 안내만 반환하며 creativeId가 주어지면 FEATURE_DISABLED다. 현재 설정값을 바꾸는 것만으로 협찬/영상 송출이 활성화되지 않는다. 미래 승인·적격성 구현 전에는 차단을 유지한다. 외부 이미지/영상·광고 요청·결제·클릭 추적·개인정보 수집·Remote를 추가하지 않았다.

| 매체 | 실제 World 이름/속성 | 서버 논리 슬롯·표시면 |
| --- | --- | --- |
| LCD | `InformationLCD`, 기존 SlotId=`<StoreId>:IndoorDirect`, ContentMode=HouseInformation | `lcd.<StoreId>.main`, Right |
| 트럭 좌측 | `DirectNotice`, SlotId=`<StoreId>:TruckLeft` | `truck.<StoreId>.<OrderId>.left`, Left |
| 트럭 우측 | `DirectNotice`, SlotId=`<StoreId>:TruckRight` | `truck.<StoreId>.<OrderId>.right`, Right |

이는 현재 실소스와 설계 제안 ID 사이의 서버 매핑이다. World의 기존 SlotId를 덮지 않으며 `ContentSlotId`는 서버가 만든 SurfaceGui에 기록한다. 트럭 DirectNotice가 두 개이므로 이름 단독 FindFirstChild가 아닌 SlotId 속성으로 구별한다. 기존 InformationLCD의 WorldText 자체 안내만 식별하여 교체한다. 나머지 타 renderer는 삭제하지 않고 FACE_OCCUPIED를 반환한다. `OperatorBindingStatus` 속성으로 결과를 확인할 수 있다.

동일 Part/Face의 AdGui/SurfaceGui/Decal/Texture를 검사하며 다른 부모의 Adornee 참조도 포함한다. 공식 AdGui 면은 건드리지 않는다. API 구성은 [AdGui](https://create.roblox.com/docs/reference/engine/classes/AdGui)와 [SurfaceGui](https://create.roblox.com/docs/reference/engine/classes/SurfaceGui) 공식 문서를 확인했으나 실제 Roblox 렌더 검증은 별도다. 최종 직접 콘텐츠 슬롯 표준 이름·미래 승인 creative 스키마·시청 적격성·광고 송출은 아직 확정/활성화하지 않았다.

## 개인프로필 영구유지 / 근무별 물품 재접속 정책

**개인프로필:** 기존 ProfileService의 Wallet/XP/Level/해금/프리셋/개인기록 저장·epoch fencing·실패 보존 정책을 유지한다. 창고나 운영자금을 개인 지갑으로 변환하지 않는다. 이 구현은 저장 기능을 새로 만들거나 켜지 않는다. 현재 `PersistentSave=false`, 명시적 Memory 모드이므로 같은 서버 메모리의 재접속 복원과 실제 서버 종료 후 영구유지는 다르다. 실제 DataStore 영구유지는 명시적으로 해당 모드가 선택된 배포 환경 및 실제 저장 검증이 필요하며 이번에 수행하지 않았다.

**근무별 물품:** 재고·주문·WarehouseBin·운영자금은 서버의 해당 RoundId에만 존재한다. 사망/퇴장/재배치 시 운반 상품은 기존 원래 선반의 빈칸 우선, 아니면 자기 창고로 반환한다. 도난 운반자는 원소유 점포의 유효 근무로 반환한다. 개인 인벤토리로 저장하거나 재접속 시 복제하지 않는다. 같은 진행 중 근무는 자금/지원 한도를 다시 지급하지 않는다. 마지막 참여자 이탈 등으로 기존 GameService가 근무를 종료하면 남은 소유상품은 Expired, 운영자금은0이므로 재접속으로 복구하지 않는다. 서버 종료·다른 서버 접속에도 근무 재고를 이어주지 않는다.

## 실행한 검증과 남은 통합

실행: `python src/server/tests/Run-WarehouseChecks.py`. 기존 공식 로컬 Luau CLI만 사용. 산출물은 Git 제외 `src/server/.validation/warehouse-checks.luau`, `warehouse-checks.txt`; 로그에는 검사에 사용한 TruckWorld 소스 SHA256을 포함한다.

- 서버 Luau 소스/spec 컴파일 성공.
- 신규 WarehouseServer 469 assertions: 실제 Commerce+Delivery와 가짜 clock/world로 PC 거절, 직접 보관/꺼내기/진열, 24개 상한·빈칸 재사용, 타인 조작, 창고도난 거절, 중복 클릭/토큰, 부분 하역 후 회수환불1회, 퇴장·같은 근무 재접속, 도난회수 공간, 종료 폐기.
- 신규 WarehouseWorld 163 assertions: 실제 WorldAdapter/OperatorContent/BuildDeliveryTruck과 가짜 Instance/벡터/raycast로 PC 거리·시야·소속·활성, 차량 create/pose/제거/실패 정리, Cargo별 상자·수량·상판 높이, 창고 외곽/24개 분리, 렌더 실패 후 수량, 손수레/선반 분리, LCD 안내 교체, 공식면/Decal 중첩 거절. 실제 엔진 테스트가 아니다.
- 기존 Profile 29 cases/476 checks, Progression53, Commerce313, ServerCommerce179, Movement98, Delivery21/21, CommerceCritical 회귀 통과. Profile 저장소와 공간/엔진은 fake이며 실제 클라우드/멀티플레이 통과가 아니다.

Integrator 남은 항목: BuildDeliveryTruck 설치 manifest 연결 → 새 서버 모듈 설치 → Studio에서 PresentationKind·OperatorBindingStatus 확인 → 8매장 회전/출입/거리·벽 시야와 PC 주문→Cargo 하역→창고 보관/꺼내기→진열 실플레이 → 2인 동시 물류·퇴장·도난회수·기존 정전/완주 회귀. LCD/트럭 면 실제 가독성과 설치 예산도 확인한다. 공개 게시·실제 상품판매·외부광고 송출은 실행하지 않았다.
