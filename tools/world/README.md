# 월드 구현 인계

`BuildWorld.luau`를 `ServerStorage.NightShift.BuildWorld` ModuleScript로 배치한다. 서버 Main이 Config를 먼저 로드한 후 `require(...BuildWorld).build(workspace)`를 한 번 호출한다. require 시 Instance 생성은 없다. `build(parent: Instance): Model`은 대기 호출 없이 완성된 모델을 마지막에 parent에 붙인다. Config 원본은 `ReplicatedStorage.NightShift.Shared.Config`이며 공유 파일은 수정하지 않았다.

반환 구조:

```text
NightShiftWorld [Model, NightShiftOwned=true]
  Hub [Model]
    Spawn [SpawnLocation]
    StoreSelect [Part]
    Plaza / Directory / 벤치
  Stores [Folder]
    Store01 .. Store04 [Model, StoreId/DisplayName attributes]
      Counter / Shelf1 / Shelf2 / Shelf3 / SignalPanel / Breaker / Entry [Part]
      Spawn [SpawnLocation]
      Architecture [Folder: 건물, 창고, 메모, 안내문]
      Lights [Folder: Fixture1..3 Part > WorkLight PointLight]
  Streets [Model]
    Street1 .. Street4 [Model: 도로, 인도, 방향판, 가로등, 골목, 벤치]
```

필수 마커는 Config의 이름·로컬 좌표·크기에서 생성한다. 점포 모델 pivot도 Config 좌표/회전과 일치한다. 모델과 모든 필수 마커의 StoreId는 문자열 Attribute다. Hub는 StoreId가 없다. 모든 마커의 Anchored/CanTouch/CastShadow, Entry의 투명·비충돌, Spawn의 Neutral/Enabled/Duration 설정은 계약을 따른다. 기존 루트가 있으면 소유권과 루트/Hub 필수 구조를 검사하여 재사용하고, 충돌 시 덮어쓰지 않는다. 개별 점포 오류의 Unavailable 처리는 서버 담당이다.

네 입구는 Hub를 향하고 폭 14·높이 13 studs가 항상 열려 있다. 점포 내부는 56×48, 광장은 64×64, 각 도로는 폭 18×길이 84다. 양쪽 인도와 진입 마당이 이어지고 각 거리의 휴식 골목에 벤치가 있다. 창고 문은 로컬 x=20..28, z=-12의 폭 8이며 차단기는 그 안에 있다. 번호·이름·도형·색·차양 깊이로 점포를 구분한다. 상품 진열/트레이 내용과 ProximityPrompt는 만들지 않는다. 서버/UI가 해당 상태와 상호작용을 소유한다.

점포별 정전 제어는 `Stores[StoreId].Lights` 아래 Light의 Enabled를 변경한다. Fixture와 Light에 StoreId 및 OutageControlled=true를 붙였다. 서버 WorldAdapter가 점포 모델 하위 Light만 수집하는 기존 방식과 맞는다. 가로등은 Streets에 있으므로 점포 정전과 분리된다. 조명 껍데기의 Neon은 길 찾기를 위해 남으며 실제 동적 광원만 꺼진다. 정답 도형은 장식에 넣지 않는다. 전역 Lighting·시간·스트리밍 설정은 변경하지 않았다. 실제 야간 시간/조도와 정전의 시각적 구분은 Studio 통합에서 확인해야 한다.

소스 할당 수식으로 산정한 예상 규모는 점포당 BasePart 33·PointLight 3, 공통 BasePart 88·PointLight 8, 전체 BasePart 220·PointLight 20이다. SurfaceGui 30 + TextLabel 30이다. 이는 엔진 생성 후 실측값이 아니다. 모든 Part는 Anchored=true/CastShadow=false, 모든 Light는 Shadows=false다. 빌드 시 자체 census가 점포/공통/전체 Part·Light 예산을 검사하고 BuildPartCount/BuildLightCount를 모델 Attribute에 기록한다. 루트의 BuildWorldGuiObjectCount는 TextLabel 등 GuiObject만 집계한다. 엔진과 아바타 성능은 포함하지 않는다.

## 실제 수행한 정적 검사

2026-10-31, 공식 [Luau 0.745 릴리스](https://github.com/luau-lang/luau/releases/tag/0.745)의 Windows compiler/AST 도구 사용. 다운로드 파일은 `.validation/`에만 두고 Git에서 제외했다. 추가 패키지·유료 API는 사용하지 않았다.

```powershell
.\tools\Invoke-Node.ps1 tools/world/verify-world.cjs tools/world/.validation/luau-0.745
```

결과: exit 0. `luau-compile --null` 구문 컴파일 통과. 검사기는 BuildWorld를 실행하지 않고 compiler AST와 Config의 상수만 읽었다. 점포 충돌 상자 30개를 읽어 폭 4 studs의 평면 경로에서 필수 마커 8개 모두 6 studs 이내 접근 가능한지 확인했다. Spawn/Entry의 서버 목적지 기준 4×5.5×4 공간 충돌 없음, 도로 끝과 Hub 경계 연결, 금지 서비스/전역 삭제/대기 호출 부재를 확인했다. 결과 JSON은 `.validation/static-report.json`이다.

이 검사는 단순한 수치/AABB 격자 검사이며 Roblox 충돌·캐릭터 이동·계단·카메라·조도·글자 가독성의 실행 검증을 대체하지 않는다. 독립 Roblox 타입 분석, Studio 배치/require/build 재호출, 실제 Instance census, 서버 이동 안전 Raycast, 2~4인 통행, 점포별 정전, 스트리밍, 16인 및 모바일 성능은 미실행이다. Studio 조작·게임 실행·게시·판매는 하지 않았다.

API 확인: [Model.WorldPivot](https://create.roblox.com/docs/reference/engine/classes/Model#WorldPivot), [PointLight](https://create.roblox.com/docs/reference/engine/classes/PointLight) 공식 문서를 참조했다.
