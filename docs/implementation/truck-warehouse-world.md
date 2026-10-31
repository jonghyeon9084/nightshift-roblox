# 배송 트럭·창고 월드 인계

## 범위와 출처

8매장의 구획·진열·트럭·문구는 Roblox 기본 Part/Model과 직접 작성한 색·글자로 제작했다. 외부 모델·이미지·실제 브랜드·유료 API·구매는 사용하지 않았다. 이 문서는 오프라인 코드 및 수학 검사 결과이며 Studio 설치·플레이·렌더 검증 결과가 아니다.

## 창고와 상품

각 `Workspace.NightShiftWorld.Stores.StoreNN`에 기존 `WarehouseDrop`, `OfficePC`, `TruckDock`, `TruckRoute`, `ShelfSlots`를 그대로 유지한다. 점포 후방에 나란한 사무실과 창고 측면 벽, 후방 건물 벽, 창고 전면의 열린 출입구와 상단 표지, 기존 후문을 배치했다. 사무실의 책상과 주문 마커 `OfficePC`는 왼쪽, `WarehouseDrop`은 창고 중앙이다. 기존 후문은 로컬 x=18..28이며 창고 전면을 통해 매장 내부에서 후문으로 접근한다. 출입구는 문짝이 없는 개구다.

`Stores.StoreNN.WarehouseSlots.Storage01`부터 `Storage24`까지 각 Part는 `StoreId=StoreNN`, `SlotId=StorageNN`, `Capacity=1`, 투명·비충돌이다. 좌표 순서는 y={2.4,4.4}, 그 안에서 x={-6.4,-5.6}, 그 안에서 z={-22.5,-21.5,-20.5,-19.5,-18.5,-17.5}이며 점포 pivot을 적용한다. 세 개 선반 판 위 두 층에 24칸이 들어간다. 각 칸은 0.7×1.4×0.7이므로 연결 시 창고 상품의 크기를 이보다 작거나 같게 조정하고 상태 이탈 시 기존 1.2×1.4×1.2 크기로 복원해야 한다. 이러한 축소 표시와 앵커 연결은 아직 구현하지 않았다.

검토 시점의 `CommerceService`는 `WarehouseBin=1..24`를 이미 관리하고, `WorldAdapter:itemCFrame`은 현재 이 번호를 `WarehouseDrop` 주변 4열×2행×3층에 매핑한다. 이 기존 방식의 24개 1.2×1.4×1.2 상품은 서로 및 건축물과 겹치지 않도록 오프라인 검사했다. 창고 앵커를 실제로 쓰려면 Integrator가 상태를 변경하지 말고 `item.State == "Warehouse"`일 때 `store.model.WarehouseSlots:FindFirstChild(string.format("Storage%02d", item.WarehouseBin))`에 맞는 안전한 탐색/검증을 추가해야 한다. 실제 store 엔트리의 모델 참조 이름은 해당 시점 WorldAdapter를 확인하여 사용한다. WarehouseBin 누락·범위 오류에는 기존 WarehouseDrop 좌표로 안전하게 돌아가며, 동시 수정·재접속·줍기 raycast도 검증해야 한다. 여러 실제 아이템의 상태와 권한은 서버가 계속 소유한다.

## 트럭 설치와 연결

설치 목록: `tools/world/BuildWorld.luau` → `ServerStorage.NightShift.BuildWorld`, `tools/world/BuildBillboards.luau` → `ServerStorage.NightShift.BuildBillboards`, `tools/world/BuildDeliveryTruck.luau` → `ServerStorage.NightShift.BuildDeliveryTruck` ModuleScript. 기존 로더가 새 모듈을 설치하는지 Integrator가 확인해야 한다. 트럭 팩토리 `create(storeId,orderId)`는 `(model,body,cargo)`를 반환하고 `pose(model,routeFrame)`은 모든 부품을 이동한다. body/cargo를 따로 이동시키지 않는다. Cargo 위치는 경로 프레임 기준 (0,3,0), 기존 CargoOffset과 일치한다. 생성한 모델은 서버가 `CommerceRuntime.Trucks`에 넣고 OrderId·StoreId를 보존해야 한다.

동시 수정 중인 최신 `WorldAdapter:createTruck`에는 `self.presentation.TruckBuilder`를 이용하는 선택 경로가 추가되어 있으므로 최종 소스를 고정한 뒤 팩토리 주입, 실패 정리, `pose` 호출, 취소/퇴장 정리를 통합자가 확인해야 한다. 아직 이번 작업에서 Studio 연결이나 실제 배송을 실행하지 않았다. 도착 지점 로컬 z=-39에서 짧은 램프 끝은 z=-33.5, 뒤 보행로 시작은 z=-33으로 평면 간격 0.5다. 차량 충돌을 끈 상태이므로 접근 가능성을 실제 캐릭터·raycast와 트럭 경로 전체로 확인해야 한다. 네 CargoIndex 표시의 계획 위치는 Cargo 기준 x/z=±0.9로 1.2 크기 아이템들이 서로 분리된다.

## 광고와 화면

기존 `BuildBillboards`는 도로 공식 AdGui 2개와 매장별 1개씩 8개, 총 **10개**, 28 Parts다. 광고 노출·수익 실적이 아니다. 실내 별도 `Architecture.InformationLCD`는 `SlotId=StoreNN:IndoorDirect`, `ContentMode=HouseInformation`, Right면에 자체 안내 `WorldText` SurfaceGui를 사용한다. LCD 뒤의 별도 얇은 판과 받침은 장식이다. 공식 광고면은 반대 벽의 별도 Part다.

트럭 `DirectNotice` 2개는 `StoreNN:TruckLeft`/`:TruckRight`, `ContentMode=HouseInformation`이고 빈 자체 안내면이다. 트럭에는 AdGui가 없다. 추후 권리와 플랫폼 정책·승인 및 이용자 노출 조건을 검증한 콘텐츠만 배치할 수 있다. 실내는 기존 Right면의 `WorldText` 내용으로 이미지를 교체하거나 해당 GUI를 비활성화하고 같은 면에 단 하나의 SurfaceGui/ImageLabel을 설치한다. 트럭은 각 슬롯 외측 면(Left 또는 Right)에 별도 SurfaceGui/ImageLabel을 설치하고 승인된 asset ID를 Image에 지정한다. 기존 안내를 fallback으로 유지하고 공식 AdGui·다른 SurfaceGui·Decal을 같은 면에 중첩하지 않는다. 현재 이미지 ID·광고주·자동 송출은 없다.

## 오프라인 검사 결과

- `./tools/Invoke-Node.ps1 tools/world/verify-world.cjs tools/world/.validation/luau-0.745`: 컴파일, 8점포 변환, 14개 기존 마커 접근, 격자 기반 폭6 통로와 폭8 트럭 중심 경로, 후문·도난/반환 마커 접근, 24개 창고 앵커 및 현재 24개 WarehouseBin 상품의 AABB 분리 통과. 단순 정적 모델이며 실제 아이템·캐릭터·카메라·raycast 검사가 아니다.
- `./tools/Invoke-Node.ps1 tools/world/verify-truck-warehouse.cjs tools/world/.validation/luau-0.745`: 트럭 컴파일, 포장 지면 높이, LoadingPad/RearWalk 경계, 램프와 후방 보행로 간격, 네 화물의 분리, 일부 간판·LCD 표면의 간격 확인 통과. 모든 면과 이동 중 카메라를 완전 열거한 검사는 아니다.
- `./tools/Invoke-Node.ps1 tools/world/verify-billboards.cjs tools/world/.validation/luau-0.745`: 컴파일 및 거리2·실내8, 28 Parts, mock 생성·재생성·소유권·fallback 검사 통과. 실제 Roblox AdGui는 미검증.
- 생성기 소스 AST와 고정 반복 횟수로 산출한 정적 모델: 매장당 103/180 Parts, 공통 45/400, 8매장 월드 869, 광고판 포함 897/1840. 동적 차량 1대는 13 Parts, 아이템은 별도다. 이 수치는 실제 Studio Instance census가 아니며 동적 물량과 다른 시스템 비용은 포함하지 않는다.

지면 상단은 Baseplate Y=0보다 0.02~0.16 높고 포장별 높이를 분리했다. LoadingPad(-34..-33)와 RearWalk(-33..-25)는 경계에서 만난다. 인접 소유 지면의 부피는 일부 겹치며 단차와 깜박임은 실측해야 한다. 사용자 Baseplate·Spawn·비소유 콘텐츠는 변경하지 않았다.

통합자는 새 모듈 설치와 로더/서버 경로 연결을 완료하고 8매장에서 PC 주문→배송·차량 접근→하역→창고 보관·회수→진열, 도난/반환, 두 사람 교차, 창고 바닥과 벽 장식·상품·트럭 표면 및 광고 가독성을 Studio에서 검증해야 한다. 슬롯에 실제 상품을 배치하는 변경은 서버 소유 범위이며 현재 표시 방식과 별도다.

## 2026-11-01 추가: 생성기 mock 및 겹침·동선 근거

`./tools/Invoke-Node.ps1 tools/world/verify-world-mock.cjs tools/world/.validation/luau-0.745`는 실제 BuildWorld/BuildBillboards/BuildDeliveryTruck Luau 생성 함수를 대체 Instance·CFrame·Vector3 환경에서 실행한다. 각 Store01..08은 각각 **103 Parts, WarehouseSlots 24개**, 전체 앵커는 **192개**로 집계됐다. 소유 월드 869개(공통 45개), 광고판 28개·10 AdGui 포함 897개, 별도 트럭 13개다. 예산 180/400/1840 이내다. mock은 Roblox 엔진 실행이나 동적 상품·트럭의 누적 개수/성능 측정이 아니다.

`verify-world.cjs`는 55개 점포 형상의 평면 격자에서 반경3 보수적 사각형의 연결 성분으로 입구→창고 입구→WarehouseDrop, 후문→후방 보행로→램프 접근점, TheftReturn 접근을 검사했다. 8개 점포의 평행이동 및 yaw 0/180은 같은 판정을 보존한다. 이 검사는 모델상 폭6을 통과할 수 있는 중심 경로를 뜻하며 실제 캐릭터, 적재 상품, 카메라, raycast 및 램프 표면을 밟는 물리 통행을 뜻하지 않는다. 트럭의 전 부품이 비충돌이므로 램프는 시각적 접근 표지다. 경로가 폭6이면 두 캐릭터 교행까지 보장하지 않는다.

동일면 전수 범위는 제한된다. 점포의 BackWall, OfficeDesk/Sign, WarehousePad/Sign, 양쪽 구획 벽, 사무실·창고 상단, 창고 표지·3단 선반, LCD·프레임·받침의 축 정렬 상자끼리 공유 평면을 비교했다. 발견된 세 접촉은 구획 벽 두 개와 BackWall의 맞닿는 끝면, LCD와 받침의 맞닿는 끝면이다. 트럭은 mock 생성된 모든 **보이는 부품 쌍**의 직교 상자 공유 평면을 비교하며 운전석/차체 수평 접합과 램프/차체 끝면 접합 두 가지만 허용한다. Cargo는 투명 논리 볼륨이므로 표면 비교에서 제외한다. 이 검사로 운전석 외벽과 차체의 외부 공면, 트럭 측면 안내판과 운전석의 공면을 발견해 각 부품을 분리했다. 창고 상품은 기존 WarehouseBin 24개, 제안된 앵커 24개에 놓는 상품의 상자 간·고형 건축물과의 교차를 검사했다. 적재함 상품은 4개 좌표의 상호 분리를 검사했으나 다른 임의 아이템 표현·모든 이동 자세의 교차와 모든 월드 장식을 전수 검사한 것은 아니다. 지면 경계와 의도된 선반/상품, 벽/바닥 접합은 표면 맞닿음으로 처리하며 엔진 렌더에서 깜박임 유무는 미확인이다.

## 2026-11-01 추가: 화물 지상 접근의 수직·시야 검토

현재 `CommerceService:_pick`의 PickCargo는 주문이 Docked인지 확인한 다음 `WorldAdapter:check`에 `OrderId`를 보낸다. 어댑터는 주문의 개별 상품 중심이 아니라 트럭 `Cargo` Part 중심을 대상으로 삼는다. 실제 `HumanoidRootPart`와 대상 중심 사이의 3차원 거리가 `Interaction.Distance=10` 이하여야 하며, `Workspace:Raycast`는 `CommerceRuntime` 및 캐릭터를 제외하고 `RespectCanCollide=true`로 검사한다. 충돌 물체가 경로를 가리고 그 명중점이 목표 중심으로부터 1.5보다 멀면 거부한다. 따라서 현재 게임 로직은 적재함에 올라갈 것을 요구하지 않는다. 범위·상태·소유권 등 서버의 다른 조건도 여전히 적용된다.

도착 시 점포 로컬 프레임에서 Cargo 중심은 `(23,4,-39)`다. 후방 보행로 바닥을 `(23,0.16,-32)`로 잡고 아바타 루트가 그로부터 3스터드 위라는 **검사용 가정**을 적용하면 루트 `(23,3.16,-32)`에서 Cargo 중심까지 거리는 약 **7.05**로 10 이내다. 이 선분이 검사 대상 점포 고형 형상에 닿지 않음을 `verify-world.cjs`가 검사한다. 트럭·상품은 서버 광선 검사에서 제외되는 CommerceRuntime 안에 있어 시야를 가리지 않는다. 이 계산은 yaw 0/180 양쪽 점포에 똑같이 적용되는 국소 좌표다. 실제 루트 높이, 사용자 콘텐츠·광고판 등의 추가 충돌물, Studio raycast 결과는 확인하지 않았다.

현재 램프는 **걷는 경로가 아니라 평평한 비충돌 시각 표지**다. 도착 시 뒤 보행로 상단 y=0.16, 램프 상단 y=2.20, 적재함 바닥 상단 y=2.40이다. 지면→램프 높이 차는 2.04, 램프→바닥은 0.20이며 램프는 길이 0.5·폭 5.5·기울기 0°이다. 램프와 바닥에는 충돌이 없고 보행로 경계에서 램프 끝까지 수평 0.5 차이가 있으므로 보행로→램프→적재함으로 올라가는 물리 경사로는 존재하지 않는다. 뒤 보행로의 평면 접근 검사 폭6과 램프 모형 너비5.5는 별도 수치다. 아래 LoadingPad도 램프를 지탱하는 구조가 아니다.

Integrator는 `BuildDeliveryTruck`을 `ServerStorage.NightShift.BuildDeliveryTruck`에 설치하고 WorldAdapter에 `presentation.TruckBuilder`로 주입한 뒤 실제 도착 포즈에서 지상의 각 아바타가 Cargo를 집는지, 거리가 먼 경우와 벽에 가린 경우가 거부되는지 확인한다. 현 WorldAdapter는 모든 트럭 Part의 충돌을 강제로 끄므로 탑승형 접근으로 바꾸려면 별도의 서버 계약·이동 중 충돌 정책과 경사로 재설계가 필요하다. 이번 변경은 지상 하역 계약을 유지한다.
