# 월드 마감 부분 인계 — 미완료

## 최신 현황 — 이전 기록에 우선

| 요구 | 구현 상태 | 오프라인 근거 | 담당 외 연결 / Studio |
|---|---|---|---|
| 편의점·상품 | 8매장 유리·간판·계산대·냉장고·전자레인지·커피·취식대·PC·창고 생성. 냉장고에 비판매 장식 실루엣 3개씩 추가 | 현재 빌더 fake 생성에서 각 이름·실루엣 3개 및 DecorativeOnly 확인 | 실물 재고는 서버 표현; 실제 시각·동선 미검증 |
| Floor·보행 | 서로 다른 높이와 8경로 생성. 횡단 종료점을 인도까지 이동해 차도 가장자리 대각선 지름길 제거 | 생성 지면끼리 겹치는 윗면 비동일; 각 노드 사이 0.5 stud 이하 간격, 2×2 footprint 9점의 지지·장애물·차도 밖 횡단 검사 통과 | 2 stud 표본이지 연속적인 6 stud 확보나 엔진 swept collision 증명이 아님. 실제 8매장 렌더·이동 미검증 |
| LCD·트럭 fallback | 자체 안내 생성 및 정상 바인딩/재바인딩 존재 | 바인더 없음, 정상/거부, 점유면 거절 확인. **신규 표시 생성 실패 시 기존 fallback 소실 재현: 제품 FAIL** | Server의 `OperatorContent.bind`가 기존 GUI를 먼저 Destroy하는 결함 수정 필요; Studio 미검증 |
| 간판·업그레이드 | 서버 `renderOwner`가 닉네임 문자열, `setWarehouseCapacity`가 용량 숫자 갱신 | 실제 현 서버 itemCFrame 수식의 32칸 상자와 건축/상호 겹침 정적 검사 통과. 물리 창고 장식 앵커는 24개이며 별도다 | 32개 실제 생성·접근·저장복원, 업그레이드 외형 및 Studio 미검증 |
| 차량·고객·신호 | 시각 모델과 신호 표현 빌더, 경로·경계 마커 구현 | 모의 생성·속성·pose·물리 플래그와 신호 4위상 검사 | Traffic/NPC 서버 연결, 안전 위상·제동·실제 이동/구매·물리 검증 미완료 |
| 옥상·거리 광고 | 기존 R2/R3/R4 수정 소스 보존 | 현재 옥상 22 PASS 모의 묶음, 기존 거리2 포함 기존 광고 모의 | Integrator 로더 미연결; 실제 가시성·엔진·저장 미검증 |

고객 builder는 6/7개의 고정 비충돌 Part로 구성된 시각 모델이며 Humanoid·관절·자체 보행은 없다. `release-target.md`와 `solo-store-contract.md`의 NPC 요구는 실제 인도→횡단→매장→선택→계산 이동과 서버 권한 거래이지 Humanoid 사용을 명시하지 않는다. 따라서 pose 모델이 형식만으로 계약 위반이라는 근거는 없으나, 생성·pose 검사만으로 실제 보행 계약을 충족하지 않는다. 서버 NPC가 연속 보간·신호 대기·점유·도착 검증을 수행하고 실제 표시를 연결해야 하며, 이동/보행 애니메이션과 엔진 성능은 미검증이다. 가짜 순간이동이나 판매 호출만으로 합격시키지 않는다.

바인더 결함 재현 세부: `OperatorContent.luau`의 `if own then own:Destroy() end` 이후 새 `Instance.new("SurfaceGui")`를 실행한다. fake에서 해당 생성 실패를 주입하면 LCD와 트럭 좌/우 각 면의 renderer가 1→0이 되고 호출은 예외로 종료된다. 사전 거부/중복 점유는 기존 표시를 보존했으나, 점유 충돌 자체는 두 표시가 이미 존재하는 실패 상태이며 무중복을 뜻하지 않는다. 서버 담당은 새 GUI를 비공개로 구성·검증한 다음 기존 것과 안전하게 교체하고 실패 시 fallback 보존 및 회귀 검사를 추가해야 한다. World 소유 밖 서버 파일을 변경하지 않았다.

### 이번 원본 로그와 소스 해시

프로젝트 루트 기준 모두 실제 실행, 종료 코드 0. 검사 성공은 제품 결함 주입 재현을 포함한다.

| 명령 | 원본 로그 |
|---|---|
| `./tools/Invoke-Node.ps1 tools/world/verify-world-mock.cjs tools/world/.validation/luau-0.745` | `.setup/world-polish/world-mock.log` |
| `./tools/Invoke-Node.ps1 tools/world/verify-world.cjs tools/world/.validation/luau-0.745` | `.setup/world-polish/world-static.log` |
| `./tools/Invoke-Node.ps1 tools/world/verify-truck-warehouse.cjs tools/world/.validation/luau-0.745` | `.setup/world-polish/truck-static.log` |
| `python tools/advertising/tests/run-rooftop.py` | `.setup/world-polish/rooftop.log` |

대상 SHA-256: `BuildWorld.luau` 3318B19F8C7AE204CB23F705B98E1810B15B02C7EA9C21E0BEF1CC329C7C0F33; `BuildDeliveryTruck.luau` 4C2D2E6B91481F103905B70DE03916642D8A63B22A7F05C10841301D031D5DCE; `BuildCustomerRig.luau` E8D9EB88A538223CF3D8580B6C069B6273F1D687E8E5CF21D009CF955A2C9BF4; `BuildRoadVehicle.luau` EB66820B7C6C7646D1C66F604046E121940A251073D1CB84DAB4987DE3D0ABBB; `BuildTrafficSignals.luau` F167DD079A5193CE7FACC495801153252F843DDC4000376432B4B0CA2B7A616B; `BuildRooftopBillboards.luau` B3435A6B3239BD888E907DAB7945443AF0DB485964BB8576F1714658AE3B2892; `OperatorContent.luau` 8F62094FFDD358BDBC716541F56883CEF11BCEE3664CD4423454C1E3CDD9716D; `WorldAdapter.luau` 9321902A660BFCDBFE81CD002DC5A8C46180DD4E535BCDA3812FCB0E5714CA19; `Config.luau` D17008220D7BC9220FEA5477E5981F90102B58171DB26D2DD7B09D6FA47B56CA; `CommerceConfig.luau` D16BE8C734E90E2A7D20B2F89747B8C2511472DA11591225743789180AFC4189; `verify-world-mock.cjs` BCACD52138357B3CF9267ABCE5D06BBDA9374158A9EB35B04B4F593A80A8CB27; `verify-world.cjs` 050DC3BC4FD8763B28B3EEBCB2ED5E82CA305E75D03CA9CC86F39124489B5EC4; `verify-truck-warehouse.cjs` 357230B81E0AB05253B9404506A0ED27F73456C8B3E28D6878B749439502EE16; `run-rooftop.py` 04F3D0D894B22093D670C1AA48698E250149DA560175B5A358AD94A731116039. 로컬 로그는 Git 제외 `.setup/`에 있으며, 이후 파일 변경 시 해시 재확인이 필요하다.

이번 추가 에셋은 직접 작성한 Roblox 기본 Part·색상으로 외부 모델/이미지·유료 라이선스를 사용하지 않았다. 기본 플랫폼 사용 조건은 Roblox에 따른다. 중단된 저장·Studio·Computer Use는 재개하지 않았다. 이전 섹션의 구버전 해시·개수 및 당시 실패/통과는 이 최신 결과를 덮어쓰지 않는다.

## 최신 후속: 신호 표현 및 모델 모의 검사

변경 파일: `tools/world/BuildWorld.luau`는 차량/보행 표식에 빨간 초기 시각 표시를 두고 11-stud 차량의 중심 정지점을 ±16으로 이동했다(정지선 ±10에서 앞면 0.5 stud 여유). `tools/world/BuildTrafficSignals.luau`는 `apply(world, phase, endsAt) -> boolean` 표현 인터페이스다. VehicleGreen은 차량만 녹색, Walk는 보행만 녹색, 두 all-red는 모두 빨간색이다. 소유 월드에서 잘못된 phase/시간 또는 누락된 표식은 가능한 표식을 빨간색으로 전환하며 false를 반환한다. 비소유 월드는 수정하지 않는다. 이 함수는 표현만 담당하고 스스로 주기를 돌리거나 차량·보행을 허용하지 않는다. `tools/world/verify-world-mock.cjs`는 모델 생성·속성·회전 pose·충돌 플래그, 두 정지점과 네 신호 위상/오류를 추가 검사한다.

**작동 신호의 남은 연결:** Traffic 담당이 교차로 점유·차량 제동과 all-red 연장을 검증한 서버 위상에만 `apply`를 호출하고, 표식 누락·호출 실패 시 실제 차량 정지/보행 대기를 유지해야 한다. `solo-store-contract.md` 196~207행 및 `RuntimeBridge.registerTraffic`이 경계다. 신호 표현은 통행 안전 자체를 보장하지 않는다. NPC 담당은 표식 순서와 횡단 대기/점유를 준수하는 실제 이동·진열 선택·계산을 구현한다. 현재 저장소에서 Traffic/NPC 구현 모듈은 확인되지 않았다. 횡단 출입·각 매장 통로의 연속 폭, 카메라 가시성, NPC와 차량의 실제 충돌/성능은 미검증이다.

**설치 인계 (Integrator 소유, 아직 미연결):**

1. manifest에 `tools/advertising/BuildRooftopBillboards.luau` → `ServerStorage.NightShift.BuildRooftopBillboards`, `tools/world/BuildRoadVehicle.luau` → `ServerStorage.NightShift.BuildRoadVehicle`, `tools/world/BuildCustomerRig.luau` → `ServerStorage.NightShift.BuildCustomerRig`, `tools/world/BuildTrafficSignals.luau` → `ServerStorage.NightShift.BuildTrafficSignals`의 ModuleScript 행을 추가하고 파일별 SHA-256 및 월드 구성 해시에 반영한다. `BuildWorld.luau`도 기존 해시 갱신한다. 설치 전 대상의 타입/소유권을 검사한다.
2. 기존 BuildWorld 후보 생성과 기존 BuildBillboards 설치를 유지한 뒤 `BuildRooftopBillboards.build(candidate, "ad" 또는 "notice")`를 호출하고 `{Ok,Code,Reason,AddedParts,PartCount,AdUnits,Reused}`를 별도 기록한다. 기존 `Advertising` 10 공식 면 중 거리 2개와 내부 8개를 보존하며 옥상 ad 4개 또는 notice 4면을 별도 계수한다. 광고 오류는 구조화해 보고하고 핵심 월드 로딩을 중단시키지 않으며 성공으로 계수하지 않는다. 후보 전체 예산·반복 설치·기존 폴더 보존을 검증한다.
3. 차량은 `BuildRoadVehicle.create("Compact"|"Van")`, 고객은 `BuildCustomerRig.create("Normal"|"Rich")`, 각각 `pose(model, frame)`이다. 생성물은 anchored/noncolliding/non-touch/non-query 시각 표현이므로 Traffic이 별도 서버 관측 기반 swept collision 및 속도/경로 권한을 제공해야 한다. 고객 모델은 Humanoid/관절 리그가 아니므로 NPC 담당이 pose 기반 이동 또는 별도 실제 보행 구현과 연결한다. 무한 반복 생성 없이 수명과 개수를 제한한다. 신호는 Traffic 담당이 위 `apply`를 안전 상태 계산 뒤 호출한다.
4. 런타임 장애를 격리하고 모델/신호 오류를 별도 보고한다. 소스 해시·설치 순서 및 최종 저장본 일치를 실제 검증하기 전 완료 표식을 발행하지 않는다. `tools/integration/build-loader.cjs`는 이번에 수정하지 않았다.

이번 확인 기준 SHA-256: BuildWorld `04797996E1FBF7315C861B34A29701B91939E45ABC0F352D29F668BEA6BF1966`, BuildRoadVehicle `EB66820B7C6C7646D1C66F604046E121940A251073D1CB84DAB4987DE3D0ABBB`, BuildCustomerRig `E8D9EB88A538223CF3D8580B6C069B6273F1D687E8E5CF21D009CF955A2C9BF4`, BuildTrafficSignals `F167DD079A5193CE7FACC495801153252F843DDC4000376432B4B0CA2B7A616B`, BuildRooftopBillboards `B3435A6B3239BD888E907DAB7945443AF0DB485964BB8576F1714658AE3B2892`. 설치 시 최신 파일 해시를 다시 계산한다.

검사: `./tools/Invoke-Node.ps1 tools/world/verify-world-mock.cjs tools/world/.validation/luau-0.745` 종료 0: 차량 7/7, 고객 6/7 Part, 속성·pose·물리 플래그, 잘못된 종류 거절, 4위상과 오류 정지 표시 모의 통과. `./tools/Invoke-Node.ps1 tools/world/verify-world.cjs tools/world/.validation/luau-0.745` 종료 0: 컴파일 및 정적 건축/거리 검사. `./tools/Invoke-Node.ps1 tools/world/verify-truck-warehouse.cjs tools/world/.validation/luau-0.745` 종료 0: 정적 검사. `python tools/advertising/tests/run-rooftop.py` 종료 0: 22개 모의 PASS 묶음. 모의 실행은 생성/호출 동작 근거이나 Roblox 엔진·Studio 렌더와 실제 NPC/교통 플레이가 아니다. 현재 기초 월드 979 + 기존 광고 28 + 옥상 28 = 1035 Part 예상, 여기에 차량 최대14·고객 최대112와 트럭/상품/기타 런타임을 별도로 더한다. 이는 프레임률 측정이 아니다.

현재 소스 대조: `BuildWorld.luau` 125~186행의 전면·설비·창고, 층별 groundHeight 34~37행, LCD 자체 문구 및 `WorldAdapter`의 선택적 바인딩, `BuildDeliveryTruck`의 양면 자체 안내, `WorldAdapter:renderOwner`/`setWarehouseCapacity`를 확인했다. 창고 업그레이드의 32칸 시각 배치와 실제 복원, 상품 실루엣의 한국 편의점 완성도는 미검증이다. 옥상 R2/R3/R4 및 기존 거리 광고 보존은 위 모의 범위이며 실제 설치·낮밤 시선·두 면의 렌더는 미검증이다. 새 신호/모델은 직접 작성한 기본 Part와 색상이며 별도 외부 에셋/유료 라이선스는 없다. Studio 렌더, 창고 최종 저장, 실제 인수는 수행하지 않았다.

## 02:xx 후속 작업 — 이전 기록보다 우선

- `tools/world/BuildWorld.luau`: 현재 공유 `Config.ContractVersion=2.0.0`과 빌더의 구식 1.0.0 단언이 충돌해 실제 빌드가 거절되는 결함을 2.0.0으로 수정했다. Traffic/Routes의 양방향 4점, Cross01·신호 표식, 8매장별 10개 보행 노드, 횡단보도·양쪽 정지선·신호 기둥을 추가했다. 서버 신호 제어, 보행의 안전한 경로 실행과 신호 표시등 제어는 연결되지 않았으며 정적 기둥은 작동하는 신호등이 아니다. 특히 교차로 출입 및 내부 경로, 반대 방향 도로 운행은 실제 경로/충돌 검증이 필요하다.
- `tools/world/BuildRoadVehicle.luau`: 직접 제작 Compact/Van 각 7개 비충돌 고정 Part와 pose 함수를 제공한다. `tools/world/BuildCustomerRig.luau`: 직접 제작 Normal 6개/Rich 7개 비충돌 고정 Part와 pose 함수를 제공한다. 이는 시각 모델이며 Humanoid/관절 애니메이션, AI, 차량 충돌 판정은 없다. 두 모듈은 아직 설치/런타임과 미연결이며 플레이어와의 물리 경계 및 최대 동시 객체 부하는 미검증이다. 기본 구성 예산은 차량 최대2×7, 고객 최대16×7 Part이며 트럭·상품·기타 런타임 개체는 별도다.
- `tools/world/verify-world.cjs`: 기존 PickCargo 검사는 폐기된 Cargo 중심 타깃 문자열을 요구했다. 현재 `CommerceService:_itemAction`은 소유자/상태/Docked를 확인한 뒤 ItemId를 전달하고, `WorldAdapter:check`는 실제 itemParts의 거리/시야를 검사한다. 검사도 해당 연결과 CargoIndex 4개 각각의 회전 좌표에 대한 거리·건축물 선분을 확인하게 변경했다. 실제 캐릭터 높이·동적 장애물·엔진 raycast를 입증하지 않는다. 공용 Part 예산 산술도 신규 마커를 포함했다.
- `tools/world/verify-world-mock.cjs`: 새 8경로·비충돌 마커·트럭 fallback 두 면과 Part 수를 검사한다. 단순 fake는 엔진과 동일하지 않다.
- 옥상 빌더 연결은 `tools/integration/build-loader.cjs`와 감사 파일 소유권이 Integrator에 있어 이번 지정 쓰기 범위 밖이다. Integrator가 manifest/source hash, 새 모듈 설치, 기존 거리 2개 보존과 실패 격리/옥상 4개를 연결해야 한다. 차량·고객 모듈도 해당 설치 경로와 서버 NPC/Traffic 호출 연결이 필요하다.
- 닉네임은 `WorldAdapter:renderOwner` 및 `SoloGameService` 호출이 존재한다. 업그레이드는 `WorldAdapter:setWarehouseCapacity`가 용량 표시를 갱신한다. 창고 레벨 증가의 공간 외형, 32칸 배치와 복원 및 실제 owner 갱신은 이번에 검증하지 않았다. LCD 초기 자체 문구와 OperatorContent 바인딩도 소스상 존재하나 실제 실패 전환을 검증하지 않았다.

### 이번 실행 (모두 오프라인)

- `./tools/Invoke-Node.ps1 tools/world/verify-world.cjs tools/world/.validation/luau-0.745`: 종료 0. 4개 상품 거리/선분, 건축물·선반·보행 폭 추정 및 빌더 컴파일. Part 추정 8매장 824 + 공용 155 = 979, 기존 광고 28 추가 1007; 런타임·옥상 28개 미포함.
- `./tools/Invoke-Node.ps1 tools/world/verify-world-mock.cjs tools/world/.validation/luau-0.745`: 종료 0. fake 인스턴스로 8매장/경로 및 기존 광고·트럭 fallback 구조 확인. 새 계약 버전 수정 전에는 실제 소스 버전 충돌로 실패했고, 수정 후 기존 고정 Part 수 단언이 실패하여 변경된 구조를 직접 검사하는 기대값으로 갱신했다.
- `./tools/Invoke-Node.ps1 tools/world/verify-truck-warehouse.cjs tools/world/.validation/luau-0.745`: 종료 0, 정적 검사 및 트럭 컴파일.
- `tools/world/.validation/luau-0.745/luau-compile.exe --null tools/world/BuildRoadVehicle.luau tools/world/BuildCustomerRig.luau`: 종료 0, 구문 컴파일만.
- `python tools/advertising/tests/run-rooftop.py`: 종료 0, 22개 PASS 묶음, 제한 모의. R2/R3/R4의 실제 엔진 기본값 및 렌더는 별도다.

위 모델과 표식은 직접 작성한 Roblox 기본 도형·색상·문구이며 외부 에셋·별도 유료 라이선스는 사용하지 않았다. Roblox 엔진 사용 조건은 플랫폼 조건을 따른다. Studio 조작, 창고 최종 저장과 실제 인수는 미실행이다. 아래 이전 기록의 정적 검사 실패·마커 미구현 설명은 당시 상태다.

2026-11-01 KST. 이 문서는 완료 표식이 아니다. 창고 최종 저장·실제 인수 및 이번 변경의 Studio 설치/렌더는 미완료이며 releaseReady 판정을 하지 않는다.

## 이번 변경과 근거

- `tools/world/BuildDeliveryTruck.luau`: 양쪽 DirectNotice에 직접 제작한 배송 안내 SurfaceGui를 추가했다. 선택적 OperatorContent가 없어도 문구를 제공하며 기존 바인더가 같은 `ContentSlotId`와 소유 속성을 인식해 교체하도록 구성했다. 바인더 결합 및 실제 표시 검사는 미실행이다. 이전 Studio 설치의 트럭 해시는 이번 수정과 다르다.
- 기존 `BuildWorld.luau`에는 전면 유리/간판, 계산대 마커, 진열 랙, 냉장고, 전자레인지, 커피·온수, 입식대, PC와 창고/후문 하역이 있다. 현재 각 구성의 완성도·상품 실루엣 및 소유자 업그레이드 표현은 실제 확인하지 못했다. 기존 `WorldAdapter:renderOwner`의 닉네임 간판 갱신은 소스상 존재하며 이번에 연결이나 실행을 검증하지 않았다.
- 기존 LCD의 자체 안내 및 트럭 바인더는 `BuildWorld.luau`, `WorldAdapter.luau`, `OperatorContent.luau`에 존재한다. 신규 트럭 fallback은 위 변경이다. 기존 거리 광고 둘의 보존은 현재 소스 오프라인 모의 검사에 한정하여 확인했다.
- 지면 높이는 기존 `BuildWorld.luau`의 층별 오프셋이다. 과거 `.setup/warehouse-verification.json`은 당시 설치본의 8매장 지면 평면 겹침 0 및 Store01 이동 화면을 기록한다. 이는 이번 소스의 8개 매장 전체 카메라/기기 검증이 아니다.
- 옥상 R2/R3/R4는 기존 `rooftop-ads-fixes.md`의 수정 및 F1 추가 수정이 현재 소스에 이미 있어 중복 구현하지 않았다. `tools/integration/build-loader.cjs`의 현재 manifest/worldSources에는 옥상 빌더가 없어 R1은 미연결이다. Integrator 소유 로더 변경과 실제 외부 6면 계수는 후속이다.
- 기존 월드는 도로·인도·차선 점선을 갖지만 횡단보도·정지선·신호등·NPC 보행 마커, 차량 2종과 일반/부자 NPC 리그 builder는 이번에 구현하지 못했다. 서버 `Traffic` 계약 이름만으로 동작이나 경로 안전을 입증할 수 없다. 교통 신호, 충돌 드롭, NPC 구매도 미완료로 인계한다.

## 옥상 실제 시선 검증 좌표 (계산값, 단위 stud)

현재 설정 지붕 상단 Y=19, 옥상 면 중심 Y=25.5, 로컬 X=-12, Z=24.65. 예상 중심: Store01 (-132,25.5,-27.35), Store03 (28,25.5,-27.35), Store06 (-28,25.5,27.35), Store08 (132,25.5,27.35). 각각 같은 로컬 X에서 카메라 Y=5, 로컬 Z=30/40/52/64/72를 사용해 가까운 인도·도로·반대편 시점을 검증한다. 남쪽 두 매장은 yaw 180도로 변환한다. 기존 기하 검사는 지붕만 다루며 간판·차양·다른 객체 차폐, 모바일·밤 렌더는 실제 Studio에서 확인해야 한다.

## 실행 검사

- `python tools/advertising/tests/run-rooftop.py`: 종료 0, 현재 소스 컴파일과 22개 PASS 묶음. yaw 전용 CFrame/단순 Instance 모의 및 기하 계산이며 엔진 렌더/광고 공급 증거가 아니다.
- `./tools/Invoke-Node.ps1 tools/world/verify-truck-warehouse.cjs tools/world/.validation/luau-0.745`: 종료 0, 트럭 컴파일과 기존 구조·층 높이 정적 검사. 신규 SurfaceGui 생성·교체 실행을 검증하지 않는다.
- `./tools/Invoke-Node.ps1 tools/world/verify-world.cjs tools/world/.validation/luau-0.745`: 종료 1. `CommerceService`에서 기존 `target={OrderId=item.OrderId,Cargo=true}` 문자열을 찾는 155행 단언 실패. 그 이전 선택된 공유 평면 검사는 출력됐으나 전체 검사 실패이며 원인 조사/계약 갱신은 후속이다.
- 과거 실제 창고 검증은 `warehouse-integration.md`와 `.setup/warehouse-verification.json` 참조: 당시 Store01 실제 주문→트럭→창고→진열→기존 판매, 제한된 바닥 관찰 및 2클라이언트 시작만 확인. 실제 최종 저장, 24개 적재, 다인 경합 및 최신 solo/NPC/교통은 검증되지 않았다.

## 에셋과 후속

이번 추가 안내는 직접 작성한 한국어 문구와 Roblox 기본 Part/SurfaceGui/TextLabel 및 기본 색상을 사용한다. 외부 이미지·모델·브랜드·유료 에셋은 추가하지 않았다. 기존 월드도 소스상 직접 제작 기본 도형을 사용하며 외부 에셋의 별도 라이선스를 새로 취득하지 않았다.

World 담당: 안전한 교통/보행 마커 계약을 서버 담당과 확정하고 신호·왕복 경로, 차량 2종/NPC 리그, 성능·충돌 경계 및 남은 매장 시각 요소를 구현·검사한다. 트럭 fallback의 바인더 유무/면별 단일 renderer를 검증하고 실패한 정적 검사와 현재 서버 계약을 대조한다. Integrator: 옥상 로더·실패 격리·기존 광고 보존, 8매장 경로/시야/성능 및 낮·밤·모바일을 실제 검증한다. 사용자 Escape로 중단된 창고 최종 저장을 우회하지 않는다. 최종 Place 저장·해시 및 실제 인수 전까지 모든 관련 항목을 PENDING으로 둔다.
