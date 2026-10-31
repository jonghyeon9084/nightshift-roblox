# 오늘도 정상영업 — 구현 빌드 보고서

> 후속 기록: 이 문서는 빌드 당시 결과다. 2026-10-31 Integrator의 실제 Studio 통합·플레이·수정 결과와 추가 필수 LoadReporter 모듈은 [통합 검증 보고서](integration-report.md)와 최신 [계약](contract.md)을 따른다.

- 작성: NightShift-UI / 2026-10-31. Moderator가 이 보고서 작성을 명시적으로 위임했다.
- 프로젝트: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발`.
- 기준: [공유 계약 1.0.0](contract.md), [scale-plan v0.3.2](../design/scale-plan.md), 유지된 [plan v0.2](../design/plan.md), [story](../design/story.md), [Config](../../src/shared/Config.luau). ProtocolVersion=1.
- 현재 상태: 소스 구현·오프라인 검사 및 트레이 보완을 완료하여 **보고서 검토 대기**. 빌드 준비 완료 여부는 Moderator가 보고서 검토 후 판정한다. Studio 통합·게임 실행·실제 플레이 통과를 뜻하지 않는다.
- 이번 보고서 작성 작업은 이 파일만 변경했다. 다른 담당 소스·검증 기록은 읽기만 했다. 검증 산출물을 쓰는 검사 명령은 이번 문서 작업에서 재실행하지 않았다.
- 작업 전 Maestro 조회에서 실행 중인 그룹은 NightShift-Build(World·Server·UI, 참가자 3명) 하나였으며, 다른 5개 그룹과 일반 AI 세션은 idle이었다. 추가 워커를 생성하지 않았다.

## 1. 전체 변경 파일과 구현

아래 목록은 이번 구현 단계 전체의 인계 대상이다. 공유 Config와 contract는 기존 기준이며 이번 구현 워커들이 변경하지 않았다. `.validation/` 산출물과 도구는 개발용 로컬 파일로 별도 구분한다.

### 월드 — NightShift-World

- [tools/world/BuildWorld.luau](../../tools/world/BuildWorld.luau): 중앙광장, 연결된 야간거리 4개, 편의점 4개, 창고, 인도·벤치·가로등·안내판을 직접 Part와 텍스트로 제작. 열린 입구, 보이는 실내, 점포별 번호·이름·도형·색 간판을 제공한다.
- [tools/world/verify-world.cjs](../../tools/world/verify-world.cjs): 공식 Luau compiler/AST와 Config를 읽는 오프라인 구문·통로·금지 동작 검사기.
- [tools/world/README.md](../../tools/world/README.md): 월드 구조·로더·정전 제어·규모 산정·검사 한계 인계.
- `tools/world/.gitignore`: 개발용 `.validation/` 제외.

루트는 `NightShiftWorld` Model이며 `Hub`, `Stores.Store01~Store04`, `Streets`를 갖는다. 점포 입구는 폭 14·높이 13 studs로 열려 있고 Hub를 향한다. 내부 외곽은 56×48, 광장은 64×64, 연결 도로는 폭 18이다. 창고의 차단기까지 접근하는 통로를 포함한다. 상품 상태와 가상 트레이 내용은 월드가 생성하지 않고 서버/UI에 맡긴다.

점포별 `Lights` 폴더에 광원을 분리했다. 서버는 자기 점포 모델 하위 Light만 제어하며, `Streets`의 공용 가로등은 점포 정전과 분리된다. 전역 Lighting·야간 시각·스트리밍 설정은 변경하지 않았다. 조명 껍데기의 Neon이 남으므로 실제 야간 조도와 정전 구분은 엔진에서 확인해야 한다.

### 서버 — NightShift-Server

- [src/server/Main.server.luau](../../src/server/Main.server.luau): 유한 부트스트랩, 월드 빌드 1회 호출, 원격 생성·검증·연결, 이벤트 수신 순서/같은 시각 우선순위 처리, 상태 전송, 캐릭터·접속 정리.
- [Modules/GameService.luau](../../src/server/Modules/GameService.luau): 4점포 독립 좌석·명단, 준비·시작 확인, 혼자 연습, 주문 묶음·운반·놓기·무료 반납·접수, 일정 A/B/C·진열 변경·정전, 역할 선점·공유·갱신, 인원 감소·복귀 예산·혼자 전환, 결과·재준비.
- [Modules/Protocol.luau](../../src/server/Modules/Protocol.luau): 요청/페이로드 허용 목록, 타입·유한 정수·길이 검사, 속도 제한, 요청 동일성·결과 캐시, 스냅샷 요청 검사.
- [Modules/Timer.luau](../../src/server/Modules/Timer.luau): 기한·정지·재개·전송용 타이머 계산.
- [Modules/WorldAdapter.luau](../../src/server/Modules/WorldAdapter.luau): 월드/마커 구조·좌표·속성 검사, 점포별 이용 불가 처리, 생존·거리·점포 내부·이동 안전 검사, 점포 조명과 진열 속성 반영.
- [tests/Service.spec.luau](../../src/server/tests/Service.spec.luau): 실제 상태 모듈에 결정적 모의 월드·플레이어·시계를 제공하는 회귀 검사.
- [tests/Verify-Server.ps1](../../src/server/tests/Verify-Server.ps1): Luau 구문 컴파일과 순수 상태 모의 검증 실행기.
- `src/server/.gitignore`: 개발용 `.validation/` 제외.

기본 상태 흐름은 `Lobby → Starting → Running → Result → Lobby`이며, 인원 감소 시 `Recovery`를 거쳐 재개 또는 단독 확정한다. 오류 점포는 `Unavailable`이다. 도중 합류자는 현재 근무 진행권 없이 다음 근무를 기다린다. 서버가 점포·좌석 세대·참가 권한·phase·근무/주문/품목/정전 ID·Revision·Token·역할 소유권·로드·생존·거리·호출 속도를 검사한다. 구현된 검증과 실제 네트워크 환경에서의 검증은 구분한다.

### 클라이언트/UI — NightShift-UI

- [src/client/Main.client.luau](../../src/client/Main.client.luau): 단일 HUD, 점포 선택·준비·혼자 연습·주문·상호작용·역할·공유·정전 입력·복귀·결과·재준비·도움말, 키보드/터치 입력, 유한 로딩 복구, 위치별 로컬 표지, 준비 상태 전용 무료 앞치마 색 미리보기, 계산대 트레이 표시.
- [Modules/StateStore.luau](../../src/client/Modules/StateStore.luau): Sequence·점포 Revision 검사, 최상위 slice 교체, 점포 상세 제거, Store slice 수신 시각에 고정한 타이머 보간.
- [Modules/TrayView.luau](../../src/client/Modules/TrayView.luau): 서버 주문을 고정 번호 트레이 3칸으로 변환하는 순수 표시 모듈.
- [tests/StateStore.spec.luau](../../src/client/tests/StateStore.spec.luau): 순수 상태 적용·타이머 검증 16개.
- [tests/TrayView.spec.luau](../../src/client/tests/TrayView.spec.luau): 순수 트레이 상태·표시 검증 19개.
- [tests/Run-StaticChecks.ps1](../../src/client/tests/Run-StaticChecks.ps1): 구문·순수 모듈 분석·35개 검증 및 원격/정리 연결 소스 검사.
- [tests/validation-report.txt](../../src/client/tests/validation-report.txt): UI 실행 기록·배치·검증 범위와 한계.
- `src/client/.validation/.gitignore`: 로컬 임시 도구와 산출물 제외.

화면은 이름·도형·번호·문구로 무음 협동을 지원한다. E 상호작용/준비/공유, R 반납, G 위치 신호, 1/2/3 도형, M 점포, H 도움말, B 무료 재배치, X 퇴장 등의 입력에 화면 버튼을 제공한다. 실제 터치 사용성 통과를 의미하지 않는다. 미리보기는 준비 상태에서만 로컬로 표시하며 무료·판매하지 않음·소유권 미부여를 명시한다. 구매·외부 에셋·영구 저장 기능은 없다.

## 2. 검증 명령·결과·근거와 한계

명령은 프로젝트 루트의 PowerShell에서 실행하는 기준이다. 사용 도구는 공식 Luau 0.745 Windows CLI다. 아래 결과는 각 담당의 실제 실행 기록 및 Moderator의 재검토 보고를 정리한 것이며, 이번 문서 작성 중 새 엔진 검증을 수행한 것은 아니다.

### 월드: 구문·정적 통로 검사

```powershell
.\tools\Invoke-Node.ps1 tools/world/verify-world.cjs tools/world/.validation/luau-0.745
```

- 기록 결과: exit 0, `luau-compile --null` 통과. 근거는 [인계 README](../../tools/world/README.md), 검사기 소스, `tools/world/.validation/static-report.json`, `world.ast.json`, `config.ast.json`이다.
- 방식: BuildWorld를 실행하지 않고 AST에서 점포의 로컬 충돌 상자 30개를 읽어 평면 격자 경로를 검사한다. 폭 4 studs의 접근 경로에서 필수 마커 8개 각각의 수평 6 studs 이내 접근, Spawn/Entry 목적지의 4×5.5×4 공간, 도로와 Hub 경계 연결, 금지 동작·대기 호출 부재를 확인했다.
- 한계: 단순 수치/AABB·평면 격자 검사다. Roblox의 실제 충돌, 캐릭터 이동, Raycast/Overlap 판정, 카메라, 네 점포 동시 통행, 조도·글자 가독성을 검증하지 않았다.

| 월드 요소 | 점포당 소스 산정 | 공통 소스 산정 | 전체 소스 산정 |
| --- | ---: | ---: | ---: |
| BasePart | 33 | 88 | 220 |
| 동적 Light | 3 | 8 | 20 |
| 월드 표시 | — | — | SurfaceGui 30 + TextLabel 30 |

이는 엔진 생성 후 실측값이 아니다. 모든 월드 Part는 Anchored=true/CastShadow=false, Light는 Shadows=false로 작성했다. 빌드의 자체 census·예산 검사와 `BuildPartCount`/`BuildLightCount`/`BuildWorldGuiObjectCount` 기록 코드가 있으나 실행은 미검증이다. UI·아바타·엔진 객체를 합친 전체 예산이나 성능의 통과로 보지 않는다.

### 서버: 구문 및 순수 상태 모의 검사

```powershell
.\src\server\tests\Verify-Server.ps1 -CompilerDirectory tools/world/.validation/luau-0.745
```

- 기록 결과: Luau 파일 6개 구문 컴파일 통과, `PURE STATE SIMULATION PASS: 5127 assertions; 72 full schedule/layout/team loops`.
- 근거: `src/server/.validation/last-run.txt`, `verification.json`, `combined-state-tests.luau`와 [검사 소스](../../src/server/tests/Service.spec.luau). verification.json의 확인 시각은 `2026-10-31T18:53:20.5366081+09:00`이다.
- 이번 보고서 작성 중 읽기 전용 SHA-256 대조를 수행했고, verification.json의 소스 해시 6개가 현재 Main·모듈 4개·검사 소스와 모두 일치했다. 이는 기록과 현재 파일의 대응 확인이며 검증 재실행은 아니다.
- 방식: 실제 Config·Timer·Protocol·GameService 소스를 결합하고 Random·월드·플레이어·거리·이동을 결정적 테스트 어댑터로 대체한다. 인원 1/2/3/4 × 일정 A/B/C × 초기 진열 6개인 72개 조합, 품목 회수·축소·기한, 정전·역할·단독/복귀, ID/Token·점포 격리·허용 필드·속도/캐시 등의 회귀를 검사한다.
- 한계: 5,127은 assertion 실행 횟수이며 실제 플레이 세션·사람·클라이언트 수가 아니다. 실제 Main의 이벤트 큐·Remote 전달 순서, WorldAdapter의 엔진 물리·이동, 서버/클라이언트 동시성·이탈, 16인 부하를 실행한 결과가 아니다. 같은 시각 경계 규칙의 모의 검사가 실제 네트워크 경합 검증을 대체하지 않는다.

### UI: 구문·순수 모듈 분석·35개 상태 검사

```powershell
.\src\client\tests\Run-StaticChecks.ps1 -LuauBin (Resolve-Path src/client/.validation/bin).Path
```

- 기록 결과: Luau 파일 5개 구문 컴파일, StateStore·TrayView 순수 모듈 2개 분석 통과. 상태 적용 16개 + 트레이 19개 = **35개 순수 검증 통과**.
- 근거: [validation-report.txt](../../src/client/tests/validation-report.txt), 두 spec와 실행기 소스, NightShift-Build의 UI 완료 응답 및 실행 도구 출력. 그룹 기록은 로컬 `C:\Users\HP\AppData\Roaming\maestro\group-chats\96a2ad59-f9ba-45fe-a1fa-a9097447cf8d\history.jsonl`/`chat.log`에 있다. UI의 별도 JSON 실행 로그는 없으며 도구 출력과 인계 기록이 근거다.
- Moderator도 트레이 수정 소스 대조 후 Luau 5개 구문 검사와 순수 모듈 2개 분석을 재실행해 통과했다고 이번 위임에서 보고했다. 이를 35개 검증 전체의 독립 재실행으로 확대하지 않는다.
- 16개: 오래된/중복 Sequence, 간격 복구 신호, 낮은 Revision, 새 근무, Self-only delta의 타이머 기준 보존, 실행/정지/만료/시계 조정 타이머, 버전·snapshot slice·점포 불일치·false 제거·첫 delta 처리.
- 19개: 빈칸 3개, 접수·취소 후 고정 번호, 정렬되지 않거나 빠진 LineId, 상품 이름·도형·상태 문구, 미수집/운반의 빈칸 표현, TrayIndex 불일치, 점포·근무·주문 식별 변경, 현재 상태 재구성, 새 주문/종료 시 이전 상태 제거, 입력 상태 불변성.
- 추가 소스 검사: Config의 22개 행동 참조, 중앙 FireServer/InvokeServer 각각 1곳, 유한 WaitForChild, UTF-8·후행 공백·금지 API, TrayOffsets 위치·상태 갱신·마커 해제 시 정리 연결.
- 한계: 실제 GUI Instance 생성·파괴, 화면 배치·터치 입력·스트리밍·서버 연동을 실행하지 않았다. 코드의 정리 연결 검사와 현재 상태 재구성 검증은 실제 스트리밍 재바인딩 통과가 아니다. Main의 전체 Roblox 엔진 형식/API 분석도 미완료다.

검사 도구·AST·결합 테스트·로그는 각 `.validation/` 안의 개발 산출물이며 게임 의존성이나 Studio 배치 대상이 아니다. UI 임시 도구 삭제는 앞선 작업에서 자동 승인 검토가 `blocked by policy`로 차단하여 로컬에 남아 있고 Git 제외를 확인했다. 이번 문서 작성에서는 삭제·다운로드·다른 파일 변경을 시도하지 않았다.

## 3. 계약 일치 사항

### 원격과 요청

서버가 `ReplicatedStorage.NightShift.Remotes` 아래 다음 네 객체를 생성하고 UI가 같은 이름·타입을 사용한다.

| 원격 | 타입·방향 | 형식 |
| --- | --- | --- |
| Action | RemoteEvent, C→S | 요청 table 하나 |
| ActionResult | RemoteEvent, S→해당 C | Ack table 하나 |
| State | RemoteEvent, S→해당 C | 수신자별 Packet 하나 |
| GetSnapshot | RemoteFunction, C→S | `{ProtocolVersion}` → `{Ok,Code,RetryAfter,Snapshot}` |

Action 요청은 정확히 **`ProtocolVersion, RequestId, Action, StoreId, RoundId, SeatGeneration, Payload` 7개 필드**다. 빈 Payload도 `{}`로 보낸다. Ack는 `ProtocolVersion,RequestId,Ok,Code,StoreId,RoundId,Revision,RetryAfter,MoveCode`다. Packet은 `ProtocolVersion,Kind,Sequence,ServerTime`과 `Self,Stores,Store` slice를 사용한다. snapshot은 전체 slice, delta는 누락 slice 유지·포함 slice 전체 교체이며 `Store=false`는 상세 제거다.

팀 식별자는 `StoreId`(`Store01`~`Store04`)다. 임의 `teamID` 필드를 추가하지 않았고 서버 허용 목록 밖 입력으로 거부한다. 모델과 필수 마커도 문자열 StoreId Attribute를 사용한다. 상태는 자기 점포 상세와 타 점포 요약으로 구분하며, UI는 서버 발급 ID·Revision·Token·역할 세대를 요청에 사용한다.

### 월드 로더와 정전

`ServerStorage.NightShift.BuildWorld`의 `build(parent: Instance): Model` 인터페이스와 서버 Main의 `builder.build(workspace)` 단일 호출을 확인했다. require 자체에서 월드를 만들지 않고, 완성된 `NightShiftWorld`를 parent에 붙인다. 기존 루트는 `NightShiftOwned=true`와 구조를 검사해 재사용하고 소유권 충돌은 덮어쓰지 않는다. 개별 점포 마커 오류는 서버가 해당 점포만 이용 불가로 처리한다. 루트·Hub 안전 조건 실패는 시작 중단 대상이다. 실제 require/build 재호출 및 엔진 생성 결과는 미검증이다.

점포별 광원 하위 구조와 WorldAdapter의 점포별 Light 제어가 맞으며, 공용 가로등은 점포 밖 `Streets`에 있다. 다른 팀 조명 분리가 소스에서 확인된 상태이고 실제 정전 시각 효과는 미검증이다.

### 트레이 보완

초기 구현에 없던 계산대 가상 트레이를 Moderator 지적으로 추가했다. UI가 Counter 기준 Config의 오프셋 **(-4,2.5,0), (0,2.5,0), (4,2.5,0)**에 로컬 Attachment·BillboardGui·TextLabel을 각각 3개 만든다. BasePart·Light·물리 assembly는 추가하지 않는다.

`LineId=1~3`에 칸 번호를 고정하며 `Tray` 상태는 동일 번호의 `TrayIndex`를 확인한다. 취소·배열 순서·빠진 품목 때문에 재번호하지 않는다. 빈칸·미수집/운반 중·계산대 대기·접수 완료·취소를 번호·이름·도형·문구로 구분한다. 불일치는 다른 칸으로 옮기지 않고 상태 확인 문구로 표시한다.

점포/근무/주문 식별 변경 시 이전 GUI와 anchor를 정리하고 새 상태로 만든다. 스트리밍 해제·캐릭터 제거 시 마커 정리 경로가 트레이도 제거하고, 성공한 재바인딩과 Store packet 수신 시 현재 상태를 반영한다. 새 원격·공유 필드는 추가하지 않았다. Moderator가 좌표·고정 번호·TrayIndex·정리/복원 연결을 실제 소스에서 확인했다. 실제 회전된 계산대의 화면 위치와 스트리밍 동작은 미검증이다.

## 4. Studio 배치 인계

아래는 **후속 통합 시 필요한 배치 목록**이며 지금 배치되었음을 뜻하지 않는다. 중간 namespace와 Modules는 Folder다. 자동 동기화 도구가 있다고 가정하지 않는다.

| 소스 | Studio 경로 | 타입 |
| --- | --- | --- |
| src/shared/Config.luau | ReplicatedStorage.NightShift.Shared.Config | ModuleScript |
| tools/world/BuildWorld.luau | ServerStorage.NightShift.BuildWorld | ModuleScript |
| src/server/Main.server.luau | ServerScriptService.NightShift.Main | Script |
| src/server/Modules/GameService.luau | ServerScriptService.NightShift.Modules.GameService | ModuleScript |
| src/server/Modules/Protocol.luau | ServerScriptService.NightShift.Modules.Protocol | ModuleScript |
| src/server/Modules/Timer.luau | ServerScriptService.NightShift.Modules.Timer | ModuleScript |
| src/server/Modules/WorldAdapter.luau | ServerScriptService.NightShift.Modules.WorldAdapter | ModuleScript |
| src/client/Main.client.luau | StarterPlayer.StarterPlayerScripts.NightShift.Main | LocalScript |
| src/client/Modules/StateStore.luau | StarterPlayer.StarterPlayerScripts.NightShift.Modules.StateStore | ModuleScript |
| src/client/Modules/TrayView.luau | StarterPlayer.StarterPlayerScripts.NightShift.Modules.TrayView | ModuleScript |

**UI에는 StateStore와 TrayView가 모두 필수다.** Main만 또는 예전 StateStore만 배치하지 않는다. GameService는 Timer가 필요하다. 클라이언트는 실행 시 PlayerScripts로 복제되어 `PlayerGui.NightShiftHUD`를 생성한다. Remotes와 Workspace의 생성 결과 모델을 정적으로 별도 복제하는 운영은 이 로더의 전제가 아니다.

`tests/`, `.validation/`, `.gitignore`, README, 검사 스크립트·로그·AST·CLI 실행 파일·결합 테스트·본 보고서는 Studio에 배치하지 않는다. BuildWorld를 Workspace Script로 실행하거나 클라이언트에서 require하지 않는다.

## 5. 미검증·잔여사항과 다음 단계의 조건

| 항목 | 현재 범위와 남은 확인 |
| --- | --- |
| 엔진 형식·API·로더 | CLI 구문 검사와 UI 순수 모듈 분석까지 완료했다. Roblox 형식 정의를 사용한 전체 분석, Script 종류·부모 구조, require/build 실행, 중복 시작·기존 모델 재사용은 후속 확인이 필요하다. |
| 최대 인원 설정 | Config.Capacity.TargetPlayers=16은 설계값이다. 실제 Place의 최대 플레이어 수 16 설정은 미실행·미확인이다. 서버 소스도 설정을 변경하지 않으므로 Studio/Place 설정에서 통합 담당이 확인한다. |
| 실제 통신·경합·팀 격리 | RemoteEvent/RemoteFunction 실통신, 동시 요청, 지연·순서 역전·재송신, 접속/캐릭터 상실, 타이머 경계, 다른 점포에 대한 조작 거부를 실제 클라이언트로 확인한다. |
| 충돌·이동 안전 | AST 평면 검사를 넘어 실제 캐릭터의 출입구·선반·창고·Spawn/Entry 이동, Raycast/Overlap, 여러 명의 통행, 시야·카메라를 확인한다. |
| 스트리밍 | 실제 로드 해제와 최대 2회 탐색, SetLoaded·역할 실효, GUI/anchor/연결 삭제, 현재 상태 재바인딩, 지연 snapshot을 확인한다. StreamingEnabled/반경은 변경하지 않았다. |
| 트레이·화면 | 회전된 4개 점포의 정확한 위치, 세 칸의 겹침·문자/도형 가독성, 주문 갱신·취소·접수·재바인딩, 터치 버튼·스크롤과 이동 UI의 간섭을 확인한다. |
| 정원·여러 인원 | 혼자·실제 2인, 실제 3/4인 역할 분담, 실제 16인/4점포의 동시 주문·정전·재시작을 별도 단계로 검증한다. 모의 인원을 실제 인원으로 환산하지 않는다. |
| 성능·규모 | 생성 후 Instance census, GUI 수, 점포/공통 광원, 통신량, 메모리, 프레임·서버 처리 시간을 측정한다. 16인·모바일 목표 달성 여부는 미확인이며 코드의 예산값을 실측 결과로 취급하지 않는다. |
| 연출·접근성 | 야간 조명·점포별 정전 구분, 무음 협동, 첫 목표 이해, 실패 이유·무료 재준비 발견, R6/R15 앞치마 미리보기를 확인한다. 재미·이탈률·수익은 측정하지 않았다. |

다음 순서를 지킨다.

1. Moderator가 본 보고서를 검토하고 수정이 필요하면 해당 담당에게 돌려보낸다. 작성자는 빌드 준비 완료를 스스로 판정하지 않는다.
2. **다음 독립 검토를 마친 뒤에만 Studio 통합과 게임 실행을 진행한다.** 본 보고서는 Studio 조작·게임 실행의 승인이나 실행 기록이 아니다.
3. 통합 시 메인/지정 Integrator가 Studio 쓰기와 테스트 시작·종료를 단독으로 소유한다. 여러 워커가 동시에 Studio를 변경하지 않는다.
4. scale-plan의 V1 로컬 1~2클라이언트, V2 실제 3~4인 역할, V3 실제 16인/4점포, V4 모바일을 실행 환경·증거와 함께 단계별로 기록한다. S1-A~H·S2-A~B도 모의 검사와 실기 검사의 구분을 유지한다.

지금까지의 구현·검사에서 Studio 직접 조작, 게임 실행, 공개, 판매, 외부 메시지 전송, 외부 에셋, 유료 생성/API·유료 구매는 실행하지 않았다. 공개·실제 판매 설정은 별도 승인 범위다.
