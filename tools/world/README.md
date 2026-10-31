# 8매장 상거래 월드 인계

`BuildWorld.luau`를 `ServerStorage.NightShift.BuildWorld` ModuleScript로 설치한다. `ReplicatedStorage.NightShift.Shared`의 `Config`, `CommerceConfig`를 통합자가 먼저 로드해야 한다. 생성기는 원본을 변경하지 않고 기존 Config의 월드 배치·Hub·Capacity·Budget에 CommerceConfig 값을 합성한다. 공유 파일과 서버·로더는 수정하지 않았다.

`build(parent): Model`은 yield 없이 완성·검증한 모델을 마지막에 parent에 붙인다. require 자체는 생성하지 않는다. 소유 루트의 `CommerceLayoutVersion=2`를 확인하여 재사용하고 구버전은 `COMMERCE_LAYOUT_MISMATCH` 오류로 거부한다. `validate(candidate)`는 신규 모델의 점포 수, 중복/누락 마커, 좌표·크기·속성·슬롯·경로·알람 초기 상태와 Part/Light 예산을 검사한다. 개별 기존 점포의 Unavailable 처리는 서버 담당이다.

```text
NightShiftWorld [Model, NightShiftOwned=true, CommerceLayoutVersion=2]
  Hub [Model: Spawn, StoreSelect, Plaza, Directory]
  Stores [Folder]
    Store01 .. Store08 [Model, StoreId/DisplayName]
      Counter, Shelf1..3, SignalPanel, Breaker, Entry, Spawn
      OfficePC, WarehouseDrop, Unload, TruckDock, Alarm, TheftReturn
      ShelfSlots [Folder: Slot01..Slot12, Capacity=4]
      TruckRoute [Folder: Approach, Dock, Exit; Order=1..3]
      Architecture [Folder: 입구·후문·열린 선반·PC 책상·창고·하역장·옆길]
      Lights [Folder: Fixture1..3 > WorkLight]
  Streets [Model: MainRoad, Sidewalk, ServiceLane, HubWalk, 가로등]
  CommerceRuntime [Folder: 비어 있음; 서버가 Trucks/Items 생성]
```

도로는 X축 400×24, 점포는 x=-120/-40/40/120, z=-52/+52로 4+4 배치한다. 남쪽 점포 yaw=180으로 로컬 +Z 입구가 도로를 향한다. Hub는 (-190,0,52)에 위치한다. 앞 인도는 폭10, 양옆길은 폭8, 후문은 폭10·높이13, 뒤 보행로는 폭8, 서비스 차로는 폭12다. 기본 마커 타입·크기·로컬 좌표는 기존 Config와 같다. Shelf1..3은 투명·비충돌 논리 마커로 바꾸고, 별도 열린 선반 판을 제작하여 하단 진열 슬롯이 기존 단단한 덩어리 안에 묻히지 않게 했다. 서버가 기존 Shelf 마커 자체를 상품 시각물로 사용하지 않도록 통합 시 확인해야 한다.

추가 마커·슬롯·트럭 경로는 CommerceConfig의 좌표와 크기를 사용한다. 모든 논리 마커는 Anchored, 비충돌·CanTouch=false·CanQuery=false·CastShadow=false다. OfficePC와 Alarm만 보이며 다른 신규 마커는 투명하다. Alarm의 PointLight는 Enabled=false이고 OutageControlled 속성이 없다. 정전 제어는 `Lights`의 OutageControlled=true 광원만 수집하도록 서버 어댑터에서 구분해야 한다. 상품·트럭·Prompt·Remote·스크립트·SoundId·외부 에셋은 생성하지 않는다.

## 배치 교체 경로 — 통합자 전용, 이번 작업에서는 미실행

Studio Edit 상태에서 최신 Config와 CommerceConfig 및 생성기를 설치한 후 실행한다. Play 세션이 열려 있으면 교체 함수는 거부한다.

```lua
local builder = require(game.ServerStorage.NightShift.BuildWorld)
local staging = Instance.new("Folder") -- Workspace 밖에서 후보 생성
staging.Name = "NightShiftWorldStaging"
local candidate = builder.build(staging)
builder.validate(candidate)
builder.replaceInEdit(workspace, candidate)
staging:Destroy()
```

`replaceInEdit`는 후보를 검증한 뒤 `NightShiftOwned=true`인 기존 동명 Model만 교체한다. 외부 소유 모델·동명 중복은 거부한다. 후보 parent 변경 실패 시 구모델 이름을 복원하며, 성공한 뒤 구모델을 제거한다. 사용자 Baseplate·Spawn·Lighting은 변경하지 않는다. 후보 확인 후 작업 파일을 저장하는 것은 통합자 몫이다.

## 실제 수행한 오프라인 검사

```powershell
.\tools\Invoke-Node.ps1 tools/world/verify-world.cjs tools/world/.validation/luau-0.745
```

기존 설치된 Luau 0.745 compiler/AST 도구 사용, 새 다운로드·패키지 설치 없음. 검사기는 Roblox 모듈을 실행하지 않고 실제 소스 AST와 두 Config 상수를 읽는다. `luau-compile --null` 통과, 점포 충돌 상자 39개 대상으로 반경3·1스터드 격자 탐색으로 14종 마커 접근 및 후문·양옆길 연결 통과, 폭8 트럭 이동 구간 충돌 없음, 12개 슬롯과 건축물 교차 없음, Spawn/Entry 목적지 여유 공간 통과. 8개 점포 배치/방향, Dock 일치, 설정 마커 중복, Hub/앞 인도 바닥 연결과 금지 호출 부재도 확인한다. 결과는 `.validation/static-report.json`에 기록한다.

전체 Part·Light 예산은 생성 시 `checkBudget`으로 강제하고 모델의 BuildPartCount/BuildLightCount에 기록한다. 모든 형상은 Anchored, CastShadow=false이며 Light.Shadows=false다. 이 비용 제한은 16명 목표 성능의 실측값이 아니다.

Studio require/build/validate/replace의 실제 Instance 동작, 실제 census, 아바타·카메라·글자·야간 조도, 서버 정전/도난 알람 분리, 멀티플레이·모바일·16인 부하는 미검증이다. 평면 AABB 검사는 Roblox 충돌·Pathfinding·이동 보안 검증을 대체하지 않는다. Studio 실행·게시·실제 판매는 수행하지 않았다.
