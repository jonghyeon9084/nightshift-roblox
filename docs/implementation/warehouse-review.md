# 창고·트럭·주문·광고 독립 검토

2026-11-01 / NightShift-Review / Moderator 검토 대기.

현재 소스에서 **P1 두 건, P2 네 건**을 확인했다. 서버·프로필·경제 모의 회귀는 통과했지만, 새 트럭 설치 누락과 보호 통로 축소가 남아 있어 통합 완료로 판정하지 않는다. Studio를 조작하거나 플레이 테스트하지 않았다. 이 보고서만 작성했으며 코드·설정·검사 파일은 수정하지 않았다.

## 1. 확인된 결함

심각도: P1은 요청한 기능의 설치/공간 완료 조건을 막는 문제, P2는 특정 경계의 조작 불일치 또는 명확한 표현·설계 불일치다. 아래 재현은 별도 표시가 없으면 소스·좌표 검토이며 실제 Studio 재현이 아니다.

### WR-01 / P1 — 설치 로더가 새 트럭 모듈을 설치하지 않는다

- 근거: `tools/integration/build-loader.cjs:7-18` manifest에는 BuildWorld/BuildBillboards만 있고 BuildDeliveryTruck이 없다. 자동 순회 대상도 `src/server/Modules`와 `src/client/Modules`뿐이다. `src/server/Main.server.luau:218-220`은 해당 모듈이 없으면 nil을 주입한다. `src/server/Modules/WorldAdapter.luau:338-365`는 이 경우 FallbackFlatbed를 만든다.
- 재현 조건: BuildDeliveryTruck이 없는 새 로컬 place에 현재 로더만 설치하고 주문한다. 로더 목록과 분기상 `PresentationKind=FallbackFlatbed`가 선택된다. 기존 수동 설치가 있는 Studio의 현재 상태는 확인하지 않았다.
- 영향: 작성된 13-Part 트럭과 두 DirectNotice 슬롯이 배포되지 않는다. fallback에는 DirectNotice가 없어 트럭 안내 바인딩도 없다. fallback의 기본 화물 운반 기능과 새 트럭 표현 설치 완료는 구별해야 한다.
- 수정안: 설치 manifest에 `tools/world/BuildDeliveryTruck.luau → ServerStorage.NightShift.BuildDeliveryTruck` ModuleScript를 추가하고 소스 해시/소유권 검사를 기존 설치 절차에 포함한다. 신규 설치와 기존 모듈 갱신 모두 검증한다.
- 완료 조건: 실제 설치 목록에서 모듈을 확인하고 주문 시 PresentationKind=BuildDeliveryTruck, 양쪽 OperatorBindingStatus=OK, 주문별 생성/파괴를 확인한다. 기존 world/server 보고서도 설치를 통합자의 남은 일로 정확히 적고 있으므로 이를 이미 완료된 기능으로 취급하면 안 된다.

### WR-02 / P1 — 실물 진열대가 보호 통로를 침범한다

- 근거: `tools/world/BuildWorld.luau:181-185`의 RackLower/RackUpper/RackBack은 중심 X=-16,0,16에 폭12다. 좌우 외곽은 각각 [-22,-10], [-6,6], [10,22]이므로 **선반 사이 실제 폭은 4**다. `docs/design/korean-store-reference.md:81-89`의 선반 사이8, 보호 경로 최소6 및 주 물류축 X=4..12와 다르다.
- 재현 조건: 각 점포 로컬 Z=-8.5에서 세 선반 사이를 측정한다. 주 물류축 X=4..12에 중앙 선반 X≤6과 오른쪽 선반 X≥10이 들어온다. RackBack의 Z 외곽 [-10.65,-10.35]도 보호 후방 통로 Z=-16..-10에 0.65 침범한다. 왼쪽 보호 띠 X=-26..-20에도 왼 선반 외곽이 2 들어온다. 180도 회전한 남쪽 점포에서도 폭은 동일하다.
- 영향: 지정된 중앙 물류/교행 경로의 완료 조건 미충족. 전체 매장이 통행 불가능하다는 뜻은 아니다. 기존 flood-fill은 바깥쪽 우회로로 연결될 수 있어 통과한다.
- 수정안: 고정 마커를 옮기지 말고 선반 판·뒤판·상품 배치를 함께 축소/재배열하여 보호 구간을 비운다. 판만 폭8로 줄이면 현재 슬롯당 네 상품의 가로 배치가 판 밖으로 나갈 수 있으므로 `WorldAdapter.luau:235-240`의 상품 외곽까지 함께 조정해야 한다.
- 완료 조건: 모든 지정 통로의 최소 폭과 상품 포함 외곽을 직접 assertion으로 검사하고, Studio에서 두 사람/손수레 왕복을 검증한다. `verify-world.cjs:80-99,148-159`의 연결 성분·목표 근방 도달 검사는 특정 중앙 통로의 최소 폭을 보장하지 않는다.

### WR-03 / P2 — 집기 버튼과 서버의 거리 기준점이 다르다

- 근거: `src/client/Modules/CommerceClient.luau:135-141,272`는 실제 Item Part 중심으로 집기 버튼을 활성화한다. 서버 `CommerceService.luau:294-299`는 WarehouseDrop / Cargo / ShelfSlot을 사용하고, `WorldAdapter.luau:261-268`은 해당 기준점으로 거리10을 검사한다.
- 재현: 창고 Bin04 중심은 점포 로컬 (2.25,1.8,-18.75), WarehouseDrop=(0,1,-18)이다. 루트=(-8.5,3.16,-18)일 때 마커 거리는 **8.770**, 상품 거리는 **10.862**다. 서버의 거리 조건은 만족하지만 버튼은 비활성화된다. 반대 방향 경계에서는 버튼 활성 후 TOO_FAR가 가능하다. 접근·시야·이동 예산을 모두 통과한다는 주장과는 구별한다.
- 실제 검사: 기존 클라이언트 spec에 메모리에서만 추가한 검사로 production near/itemNear를 실행했다. 같은 두 기준점 차이로 near=true/itemNear=false가 재현됐다. 위 3D 거리도 별도 산술 계산했다.
- 영향: 같은 창고에서 상품별로 집기 허용 안내가 달라지고, 트럭/선반도 같은 종류의 경계 불일치가 생긴다. 서버 권한 우회나 재고 복제는 확인되지 않았다.
- 수정안: 상태별로 WarehouseDrop, 주문의 Cargo, ShelfSlots의 SlotId를 찾는 클라이언트 집기 거리 함수를 사용하고 서버 기준과 일치시킨다. 시야·이동·권한은 계속 서버가 판정한다. 9.99/10/10.01 경계와 24칸·4화물·다단 선반을 검사한다.

### WR-04 / P2 — 창고 내려놓기에 E가 배정되지 않는다

- 근거: `CommerceClient.luau:164-168`의 기본 E 후보는 buy/pick/place/secure/recover/theft/equip/save-preset이고 **drop이 없다**. `:250`은 nil 키와 `drop-<ItemId>`를 전달한다.
- 재현: 자기 상품을 운반하고 WarehouseDrop만 가까우며 모든 선반이 먼 상태에서 상품 화면을 연다. 내려놓기 버튼은 Enabled=true인데 Key=nil이다. 이를 실제 render 함수와 기존 fake UI로 추가 실행하여 확인했다.
- 영향: 직접 물류를 E로 이어갈 수 없고 마우스/터치 클릭이 필요하다. 버튼을 통한 내려놓기 자체는 존재한다.
- 수정안: drop을 E 후보에 포함하고, 운반 중에는 유효한 내려놓기/진열 동작이 무관한 집기 후보보다 우선하는지 확인한다. 창고 단독 근접·창고/선반 동시 근접을 검사한다.

### WR-05 / P2 — 트럭이 진행 방향에 대해 옆으로 이동한다

- 근거: `src/shared/CommerceConfig.luau:60-61`의 Approach→Dock→Exit는 로컬 X=-36→23→36, Z=-39 고정이다. `BuildWorld.luau:244-250`은 각 위치에 회전 없는 CFrame을 만든다. `WorldAdapter.luau:395-398`은 그 프레임을 그대로 pose에 전달한다. `BuildDeliveryTruck.luau:20-21,40-44`의 운전석/앞유리는 로컬 -Z를 향한다.
- 재현 조건: alpha=0,0.5,1에서 모델의 프레임을 비교하면 이동 벡터는 +X인데 앞유리 방향은 -Z로 유지된다. 두 방향 내적은0이며 남쪽 매장의180도 회전도 이 관계를 보존한다.
- 영향: 배송 트럭이 옆걸음하는 표현이다. 실제 배송 시각/권한 오류로 판정하지는 않는다.
- 수정안: 이동 구간에서 진행 방향을 보도록 시각 프레임을 분리하고 정차 시 후면 하역 방향으로 회전하는 정책을 정한다. Cargo 계약을 임의 변경하지 말고 화물·광선 기준·회전 외곽을 함께 조율한다.
- 완료 조건: 이동/정차/퇴장 시 차체 방향, 화물 동기화, 회전 중 보행로 침범을 검증한다. 현재 translation-only 서버 mock은 이 회전 문제를 검출하지 못한다.

### WR-06 / P2 — 트럭 안내 슬롯이 적재함 대신 운전석 옆에 있다

- 근거: `BuildDeliveryTruck.luau:34` DirectNotice는 (±3.56,3.5,-4), 크기(0.1,1,1.8)이다. Z 범위 [-4.9,-3.1]은 Cab의 [-5,-3]에 속한다. BedLeft/Right의 적재함 Z 범위는 [-1.5,4.5]이다 (`:20,22-23`). `docs/design/advertiser-content.md:44,50`은 적재함 양옆·차체 안쪽·비돌출 면을 요구한다.
- 재현 조건: 생성 모델의 두 DirectNotice와 Cab/Bed 경계를 비교한다. 현재 판은 운전석 표면 X=±3.5보다 바깥 3.51..3.61에 있어 얇게 돌출한다. 다만 Wheel까지 포함한 기존 최대 폭은±3.65이므로 판이 차량 전체 최대 폭을 늘렸다고 주장하지 않는다.
- 영향: 적재함 광고 슬롯 요구와 다른 위치이며 작은 운전석 표지 크기로 구현됐다. 현재는 실제 광고가 아닌 자체 배송 안내다. 앞유리/화물/하역을 가린다는 결함은 확인하지 않았다.
- 수정안: 적재함 양 측판의 외측에 붙는 면으로 재배치하거나, Moderator가 운전석 안내판으로 설계 변경을 명시한다. 적재함으로 이동할 경우 측판과의 면 중첩, Cargo/후면 개구, 바퀴·카메라 가림 및 문자 가독성을 다시 확인한다.

## 2. 결함으로 단정하지 않은 항목과 계약 대조

| 검토 대상 | 확인한 구현과 판단 |
| --- | --- |
| PC 주문 권한 | Commerce `_auth:89-101`은 최신 소속·좌석 세대·회차·프로필 epoch·Loaded/Active를 검사한다. `_order:181`은 자기 OfficePC 검사 후에만 주문/차감한다. WorldAdapter `249-274`의 생존·이동 예산·거리·raycast를 확인했다. 타 점포/원거리 거절은 모의 검사 통과. |
| 창고/진열 한도 | `_size:124-128`은 예약과 모든 비종료 소유 상품을 합산한다. 창고24는 추가 용량이 아니다. `_warehouseBin/_move:140-162`가 빈 번호 재사용·이탈 해제를 수행한다. `_place:306-319`는 운반자/토큰/Revision, 선반4개와 단일 SKU를 검사한다. |
| 중복·도난·반환 | `_theftValid:327-339`는 Truck/Shelf만 허용하며 Warehouse 도난은 거절한다. 도난 회수 대기 중에도 원소유 상한을 점유하고, `_secure:375-380`은 새 소유 점포 상한을 검사한다. `_returnStolen:352-359`는 EverSecured provenance를 유지한다. 부분 하역 회수는 Truck 상태만 1회 환불한다(`222-239`). 퇴장/근무 종료·동시 요청은 직렬화된 모의 경계에서 통과했다. |
| 창고 선반 연결 | WarehouseSlots 24개는 실제 생성되지만 WorldAdapter `242-245`가 사용하는 것은 WarehouseDrop 주변 4×2×3 배열이다. 두 보고서가 이 차이를 명시한다. 설계도 X=-3..3 별도 적치를 허용하므로 미연결만으로 재고 결함으로 보지 않는다. 현재 창고 상자는 첫 층 바닥Y=1.1로 지면/패드보다 떠 있고 측면 랙은 비어 있다. 자연스러운 적치 연출 완료는 아니다. |
| 트럭 접근 | 실제 상자는 네 개의 분리 좌표에 표시되고 해당 트럭의 이동에 따라 이동한다. 램프는 폭5.5/길이0.5/기울기0인 비충돌 장식이다. 램프/적재함으로 걸어 올라갈 수 있다는 구현은 없다. 지상 루트=(23,3.16,-32) 가정에서 Cargo까지7.050이며 검사된 고형물과 광선 교차 없음. 지상 하역 계약에는 모순 없으나 실제 아바타/엔진 raycast는 미검증이다. |
| Baseplate와 지면 | BuildWorld `32-37`은 Baseplate 상단Y=0을 가정해 소유 포장 상단을0.02~0.16으로 분리한다. LoadingPad/RearWalk는 같은 높이지만 경계에서만 만난다. 검사 범위에서 동일한 노출 윗면 중첩을 발견하지 않았다. 실제 Baseplate 상단/크기, 비소유 인스턴스, 거리별 깊이 정밀도에 따른 깜박임은 미확인이다. |
| 내부 겹침 | 창고24칸/앵커24개/네 화물의 상호 분리, 선택된 사무실·창고·LCD 면, 트럭 보이는 부품 쌍 검사는 통과했다. 진열 상품 전체와 모든 장식/모든 이동 자세의 전수 충돌검사는 아니다. WR-02의 보호 공간 침범은 별도다. |
| 한국 편의점 구조 | 유리 전면·가로 자체 간판·후방 사무실/창고·전자레인지/커피·얕은 취식대·냉장고 블록은 있다. 냉장고 유리/상품 실루엣·카테고리 표지는 구체화되지 않았다. PC는 z=-18, 책상 전면은z=-20.5이므로 화면과 책상 사이 지지 구조도 없다. 기능 배치 초안 수준이며 자연스러운 실내 표현 완료로 보지 않는다. |
| 후문 | 구현 x=18..28은 기존 후문 유지안이고 설계 제안 x=5..13과 다르다. world 보고서가 공개한 차이이며 우회 연결 계산은 통과했다. 따라서 그 자체를 닫힌 경로 결함으로 단정하지 않되, 보호 경로 변경 수용 여부를 Moderator 결정에 남겨야 한다. |
| LCD | 왼쪽 벽 Right면6.4×3.6, 프레임/받침이 따로 있고 오른쪽 공식 광고와 분리돼 있다. 실제 영상이 아닌 정적 한글 안내다. 현재 CanvasSize768×256의 글자 비율·일반 눈높이·야간/모바일 가독성은 엔진 확인이 필요하다. |
| 모바일 | 스크롤과 줄바꿈 AutomaticSize, Q/ClickablePrompt 연결이 존재한다. 네 viewport 수학 검사 통과. 실제 ScreenGui 사용 영역과 화면 inset/노치, 글꼴 측정, 터치 조이스틱·Prompt 가림은 검사하지 않았다. |

## 3. 광고·에셋 출처

- `tools/world/BuildDeliveryTruck.luau:5-37`은 기본 Model/Part 13개를 직접 만든다. 외부 Mesh/이미지/브랜드 포장/숫자 require/InsertService/LoadAsset/HTTP 로딩을 발견하지 않았다. BuildWorld도 자체 색·기하·한글 문구로 구성된다. **검토한 생성 코드에 대해서는 외부 구매나 에셋 다운로드 없이 자체 제작되는 트럭임을 확인했다.** 제작자의 모든 과거 파일·계정 구매 내역이나 현재 Studio의 수동 삽입물까지 감사한 결과는 아니다.
- `src`와 `tools/world`에서 외부 에셋/로딩/브랜드 토큰을 검색했고 발견된 관련 문자열은 검사기의 금지 목록이었다. GS25/CU 참고 이미지·로고를 소스가 로드하는 경로는 없다. 외형의 시각적 유사성이나 법적 권리 보증은 하지 않는다. 디자인 문서의 외부 참고 열람/라이선스 주장은 이번 검토에서 웹 원본까지 재검증하지 않았다.
- `WorldAdapter.luau:348-350`은 주입된 트럭 안의 LuaSourceContainer/RemoteEvent/RemoteFunction/AdGui를 거절한다. 생성된 트럭 내부에 외부 스크립트는 없다. 서버의 로컬 Builder ModuleScript 자체와 모델에 끼워 넣은 외부 스크립트는 구별한다.
- `OperatorContent.luau:4-7,19-25`는 SponsorshipEnabled/VideoEnabled=false, AllowedAssetIds/Creatives 빈 값이며 실제 resolve는 house_notice만 반환한다. creativeId가 있으면 FEATURE_DISABLED다. 설정을 true로 바꾸는 것만으로 광고가 켜지지 않는다. 받은 소재 없는 상태를 가짜 광고주/자산 ID로 채우지 않았다.
- 운영자 설정은 서버 모듈이고 공개14개 액션에는 소재/문구/URL 설정 액션이 없다. 클라이언트가 서버의 광고 소재를 바꾸는 경로는 발견하지 않았다. 별도 운영자 업로드/관리 UI가 구현됐다는 뜻은 아니다.
- `OperatorContent.bind:28-56`은 같은 Part/Face의 AdGui/SurfaceGui/Decal/Texture를 검사하며 world 하위의 Adornee 참조도 포함한다. 기존 LCD WorldText 또는 같은 소유 슬롯만 교체한다. 모의 검사에서 기존 공식면과 Decal 중첩은 FACE_OCCUPIED였다. world 밖에 부모가 있는 renderer나 다른 Part의 물리 공면까지 전역 탐색하는 검사는 아니며, 현재 생성 코드에서는 그러한 중복을 찾지 못했다.
- `BuildBillboards.luau:175-182`의 공식10면은 AdGui/이미지 전용/기본 Roblox fallback이다. 운영자 협찬을 fallback에 넣지 않는다. `:166-170`에서 광고판 전체가 비충돌/비접촉/비쿼리여서 생성된 판 자체가 물리 이동이나 서버 광선을 막지는 않는다. 실제 시야/경보/카메라 가림과 광고 노출·계정 자격·수익은 확인하지 않았다.
- 현재 자체 안내와 공식 광고의 코드 경로는 분리돼 있다. 협찬의 플랫폼 승인·권리 allowlist·개인별 적격성·기간/로드 실패 fallback은 미래 기능이며 활성화되지 않았다. 따라서 실제 협찬 실패 복귀를 테스트 통과로 표시하지 않는다.

## 4. 실제 수행한 검사

쓰기가 보고서 한 파일로 제한되어 있어 기존 검사기를 그대로 실행하여 임시파일을 만들지 않았다. 설치된 `tools/world/.validation/luau-0.745`만 사용했고 다운로드·Studio 호출은 없었다. Python/Node는 소스 조합과 실행 전달에만 사용했다.

| 검사 | 이번 검토의 실제 결과 |
| --- | --- |
| 서버 컴파일 | 현재 src/server 모듈/spec를 luau-compile --null로 컴파일 성공. |
| 서버 통합 harness | Run-WarehouseChecks.py의 생성 결과를 메모리에서 구성하고 기존 `.validation/warehouse-checks.luau`와 전체 문자열 일치를 확인한 뒤 기존 파일을 읽기 실행했다. 생성/로그 쓰기는 하지 않았다. |
| Profiles·경제 회귀 | Profile29 cases/476 checks, Progression53, Commerce313, ServerCommerce179, Movement98, Delivery21/21 통과. CommerceCritical의 lease 재획득/이전 epoch·배송 긴 ID·퇴장/종료 보상 flush·축소 주문 회귀 통과. 모두 fake 저장소/시간/공간이며 실제 DataStore/네트워크 검사가 아니다. |
| 창고 서버·월드 | WarehouseServer469, WarehouseWorld163 통과. 실제 Commerce/Delivery/Adapter/OperatorContent/Truck 모듈을 사용하되 Instance/벡터/광선은 fake. |
| 클라이언트 | 현재 src/client Luau 소스/spec 컴파일 성공. CommerceState26, CommerceClient76, StateStore16, TrayView19, LoadReporter18 통과. 모듈을 메모리에서 inline하여 Luau REPL의 loadstring으로 실행했다. |
| 모바일 수학 | 기존 Run-WarehouseLayoutChecks의 harness/checks와 실제 layoutPanel을 메모리에서 추출해320×568,568×320,360×640,640×360 검사:17 assertions와4 source guards 통과. |
| 추가 결함 재현 | production render/near/itemNear에 fake UI/위치를 적용해 WR-03·WR-04 재현. 검사 코드는 파일에 저장하지 않았다. |
| 월드/트럭 정적 검사 | verify-world.cjs와 verify-truck-warehouse.cjs를 실행하고 보고서 출력 쓰기는 메모리 wrapper에서 억제했다.8점포 변환·14마커 근방 도달·우회 경로·24창고/앵커 분리·화물/선택 표면·지상 Cargo 거리 산식 통과. WR-02 보호 통로 전수검사와는 다르다. |
| 생성 mock | verify-world-mock.cjs의 만들어질 Luau 내용과 기존 world-mock.luau의 줄끝 정규화 후 일치를 확인해 기존 파일만 실행했다. 매장별103 Parts/24앵커, 월드869+광고28=897 Parts, 공식10면, 트럭13 Parts 확인. 실제 엔진 census/성능 측정은 아니다. |
| 차이/외부 로딩 검사 | git diff --check -- src tools/world 종료0(줄끝 변환 안내만 출력). 기존 변경이 많은 작업 트리를 보존했다. |

초기 REPL 다중행 전달 시 실행 결과가 출력되지 않은 시도는 테스트 통과로 세지 않았다. 이후 서버는 최신 소스와 일치한 기존 harness를 실행했고, 클라이언트는 단일 loadstring 호출로 실제 PASS 출력을 확인했다. `verify-billboards.cjs`의 개별 전체 failure suite와 Luau 정적 타입 분석은 이번에 별도 재실행하지 않았다.

현재 `CommerceConfig.Features.PersistentSave=false`, `Profile.DefaultMode=Memory`이며 Main은 이를 명시적으로 선택한다. 개인 지갑/XP/해금의 fake 저장 회귀 통과를 실제 서버 종료 후 영구 저장 성공으로 해석하면 안 된다. 기존 Profile/경제 수정이 작업 트리에 이미 존재했으므로 이번 검토자가 새로 고쳤다고 주장하지 않는다.

## 5. 통합자에게 남기는 완료 조건

1. WR-01 설치, WR-02 보호 통로 및 상품 외곽을 먼저 수정하고 소스를 고정한다. WR-03/04는 같은 UI 보완 단위로 처리한다. WR-05/06은 트럭 표현 보완으로 묶되 Cargo/경로 계약 소유자와 조율한다.
2. 메인/Integrator만 Studio에서8매장별 PC 주문→도착 Cargo→창고 보관/꺼내기→진열/판매를 실행한다. 자기/타 점포 PC, 거리/벽 시야, 정전 중 주문, 정확한 회수 시각, 부분 하역, 동일 아이템 동시 입력, 퇴장/재접속·도난 반환을 검사한다.
3. 두 사람/손수레 교행, 카메라/모바일/야간 LCD, Baseplate 실제 높이와 z-fighting, 트럭 진입/회전/퇴장, 광고판과 경보/상품 안내 가림을 검사한다. 수정한 보호 통로를 우회로 도달 결과로 대체하지 않는다.
4. 새 설치의 PresentationKind와 OperatorBindingStatus, 공식10면과 직접 면의 분리·소재 빈 설정을 확인한다. 게시·실제 판매·외부광고 송출은 이 검토 범위에 포함하지 않는다.

Moderator 결과 확인 전 단계 준비 표식은 발행하지 않는다.

## 6. 검토 소스 지문

아래는 검토 말미 파일 바이트의 SHA256이다. 병렬 변경이 있으면 이 버전과 달라지는 부분을 재검토해야 한다. 서버 검사 출력의 Truck SHA는 Python 텍스트 읽기 후 줄끝 정규화된 값이므로 아래 원시 파일 값과 구별한다.

| 파일 | SHA256 |
| --- | --- |
| src/server/Modules/CommerceService.luau | C7E268BF79D4AF11315D6FFF94E585BE0BDD39BA3708869646DAF3C1197E5774 |
| src/server/Modules/WorldAdapter.luau | DAAA6B0569EFA8A8C9D22F57ABD884B372E4CC9B444890B04287D0F478E14EE5 |
| src/server/Modules/ProfileService.luau | B85C1C6AD7B64D896CA3316445060DE76A66E741DA34CDA5A9B57D5093B3B2DC |
| src/client/Modules/CommerceClient.luau | 1A0D65A89644F8D7B3262FBC0144D8B275000ABC4553CB215F35532AF17A3772 |
| tools/world/BuildWorld.luau | 0C7260A2F8D8F968F31F4AA4B4C46FAFBA28E2A0564417A9F6A3312BC5C2A6EF |
| tools/world/BuildDeliveryTruck.luau | 12B8A8A57954CE71DE805B5973935DD5F176891AB24415C91E2D36258B7D79EA |
| tools/integration/build-loader.cjs | D07C31AE59B98ECBA99274F3D687A9BAC6A23B5EB50152657590F6D21FE87DEF |
