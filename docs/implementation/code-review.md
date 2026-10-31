# REVIEW_1 — 독립 코드 검토

2026-10-31 / NightShift-Review / NightShift-CodeReview

검토 결과는 **문제 발견, 통합 수정 및 실행 재검증 필요**다. 아래 CR-001~003을 다음 통합 단계에서 수정해야 한다. 구문 검사와 순수 상태 모의 검사는 통과했지만, Studio 플레이·실제 원격 통신·모바일 사용성을 통과한 것은 아니다.

## 범위와 작업 제한

- 프로젝트: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발`.
- 읽은 기준: `AGENTS.md`, `docs/game-brief.md`, `docs/implementation/contract.md` 1.0.0, `docs/design/scale-plan.md` v0.3.2. 확장 규칙은 contract/scale-plan을 기준으로 대조했다.
- 실제 읽은 구현: `src/shared/Config.luau`, `src/server/Main.server.luau`, 서버 Modules의 GameService/Protocol/Timer/WorldAdapter, `src/client/Main.client.luau`, 클라이언트 Modules의 StateStore/TrayView, `tools/world/BuildWorld.luau` 전부.
- 보조 소스: 서버 Service.spec/Verify-Server, 클라이언트 StateStore.spec/TrayView.spec/Run-StaticChecks, 월드 README/verify-world. 기존 검증 결과 파일을 이번 실행의 증거로 대신 사용하지 않았다.
- 변경 파일은 **이 문서 하나**다. 게임 코드·테스트 파일·기존 검증 산출물은 수정하지 않았다. Studio 조회/편집/테스트 시작·종료, 게시, 외부 메시지 발송, 결제, 구매, 에셋 반입을 하지 않았다.
- 아래 줄 번호는 검토 시점의 실제 파일 기준이며, 수정 후에는 달라질 수 있다.

## 발견 이슈

### CR-001 / P1 — 상태 수신 때 조작 중인 모바일 버튼을 파괴한다

- 위치: `src/client/Main.client.luau:384-386`(상태 수신마다 dirty), `:542-548`(기존 콘텐츠 전부 Destroy), `:507-520`(새 버튼 생성과 Activated 연결), `:783-786`, `:868`(0.25초 주기 렌더). 송신 원인: `src/server/Modules/GameService.luau:904-916`(타이머만 변해도 1초마다 Store 전송).
- 확인한 문제: 정상 근무 중 상태 패킷을 받으면 내용이 사실상 같은 타이머 갱신이어도 화면의 모든 작업 버튼과 연결을 제거하고 다시 만든다. 따라서 누르기와 떼기 사이에 수신/렌더가 일어나면 같은 버튼 인스턴스가 유지되지 않는다. 위치 변화·다른 팀원의 동작 때는 더 자주 발생할 수 있다.
- 재현 조건: 모바일 또는 마우스로 집기/접수/역할 공유/도형 버튼을 누른 채 다음 Store 패킷과 렌더를 통과한 뒤 같은 화면 위치에서 뗀다. 1초 이상 누르면 정상 1Hz 타이머 갱신도 이 경계를 만들 수 있다. 실제 입력 누락률은 Studio/기기에서 확인해야 한다.
- 영향: 핵심 터치 조작이 간헐적으로 무시될 위험이 있으며, 스크롤 중 버튼과 콘텐츠도 교체된다. 모바일에서 키보드 우회가 없으므로 통합 우선 수정 대상으로 판단했다.
- 근거 구분: **버튼 파괴·재생성 경로는 소스 확인**, 입력 손실은 소스와 API 수명에서 도출한 결함 판단이며 **엔진 재현은 미실행**. Roblox의 Activated는 누른 후 놓는 입력으로 발생한다. [공식 GuiButton 설명](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/GuiButton.yaml).
- 수정 방향: 화면/품목/역할의 안정된 ID로 버튼을 유지하고 Text/활성 조건만 갱신한다. 타이머 패킷은 기존 timerLabel만 갱신한다. 콜백은 클릭 시 최신 상태를 조회해 이전 LineRevision/Role Generation을 제출하지 않게 한다. 페이지 전환 등 실제 구조 변경 때만 필요한 객체를 정리한다.
- 수정 후 검증: 실제 터치/마우스로 누르기→상태 갱신→떼기, 다른 플레이어의 동시 접수, 정전 공유/도형 입력, 긴 콘텐츠 스크롤을 수행한다. 유효 탭 1회당 요청 1회, 중복 요청 0회, 기존 버튼 인스턴스 유지 여부를 기록한다.

### CR-002 / P2 — 결과→로비 경계의 로드 보고 거절 뒤 자동 복구가 멈춘다

- 위치: `src/client/Main.client.luau:249-253`(요청 RoundId 캡처), `:825-827`(성공 응답 전에 reportedLoaded/reportGeneration 확정), `:469-478`(거절 시 스냅샷만 예약), `:739`(수동 재시도에서만 reportedLoaded 초기화). 서버: `src/server/Modules/GameService.luau:116-120`, `:295-299`, `:516`, `:650-658`.
- 재현 조건:
  1. Result 상태의 온라인 사용자가 마커 해제/재로딩으로 SetLoaded(false)를 성공시킨다.
  2. 마커를 다시 찾은 클라이언트가 결과 RoundId와 현재 SeatGeneration으로 SetLoaded(true)를 보낸다.
  3. 그 요청 처리 전에 결과 8초 만료 또는 동료의 AcknowledgeResult로 toLobby가 실행된다. RoundId는 false가 되고 Participant는 이미 Waiting이므로 SeatGeneration은 그대로다.
  4. 늦은 보고는 STALE_ROUND로 거절된다. 클라이언트는 이미 reportedLoaded=true로 기록했고, 로비 스냅샷의 Loaded=false를 받아도 재보고 조건에 사용하지 않는다.
- 영향: 맵은 준비됐는데 서버 Loaded는 false로 남아 팀 준비/혼자 연습이 비활성화된다. F5/상태 재시도 버튼으로 회복할 수 있으므로 영구 교착은 아니지만, 정상 재바인딩의 자동 복구가 중단된다.
- 실행 확인: 실제 GameService/Config/Protocol/Timer를 메모리에 적재한 **순수 상태 모의 검사**에서 Result의 Loaded=false → toLobby 주입 → 이전 RoundId의 Loaded=true 요청을 실행했다. 결과는 다음과 같다.

```text
REVIEW_LOAD_RACE STALE_ROUND generationUnchanged true serverLoaded false phase Lobby
```

- 서버 거절과 세대 불변은 모의 실행으로 확인했다. 이후 클라이언트 재전송 부재는 위 소스의 조건을 대조한 결과다. 실제 지연 RemoteEvent와 전체 UI 재현은 **미실행**이다.
- 수정 방향: 전송 상태와 서버 확인 상태를 분리한다. SetLoaded 응답에 해당하는 원래 Loaded/StoreId/RoundId/SeatGeneration을 pending에 보관하고, 최신 문맥에서 거절된 보고만 유한 재시도 대상으로 되돌린다. RoundId가 바뀐 경우도 보고 문맥 변경으로 취급하고, 최신 서버 Loaded와 로컬 로드 상태의 불일치를 제한된 횟수로 조정한다. 임의의 옛 요청을 서버에서 허용하는 방식은 피한다.
- 수정 후 검증: 위 경계에서 F5 없이 Loaded=true와 준비 버튼이 회복되는지, 서버의 옛 RoundId 거절은 유지되는지 확인한다. 반복 거절 시에는 재시도 한도를 지키고 수동 복구를 제공한다.

### CR-003 / P2 — Hub StoreSelect 마커에서 선택 화면을 여는 동작이 없다

- 위치: `tools/world/BuildWorld.luau:283-284`(StoreSelect 생성), `src/client/Main.client.luau:289-300`(Hub 마커 탐색), `:303-329`(Billboard 텍스트만 설치), `:765-774`(선택 화면은 nav/M으로만 연결), `:834-841`(근접 검사에서 StoreSelect 제외).
- 요구 근거: `docs/implementation/contract.md:55`의 Hub StoreSelect/HUD 양쪽 진입 경로. 현재 HUD/M 경로 자체는 있다.
- 재현 조건: Hub에서 도움말 탭을 연 뒤 StoreSelect 앞에 서서 마커를 터치/클릭하거나 E를 누른다. 마커에는 Prompt/ClickDetector/터치 버튼이나 해당 근접 E 콜백이 연결되어 있지 않아 점포 화면을 열지 않는다.
- 영향: 월드 안내판이 상호작용 지점처럼 표시되지만 계약상 동작이 누락됐다. HUD의 점포 버튼/M으로는 계속 진행할 수 있다.
- 확인 상태: **소스에서 연결 부재 확인**, Studio 입력 재현 **미실행**.
- 수정 방향: UI 소유 범위에서 StoreSelect의 근접 E/터치 조작을 연결한다. 작동 시 `setPage("stores")`를 호출하고, 마커 해제/재등장 때 연결을 한 번만 정리·재설치한다. 월드 빌더에 클라이언트 입력 로직을 섞지 않는다.
- 수정 후 검증: Hub의 두 진입 경로, 스트리밍 해제/복귀 뒤 중복 연결 0개, 모바일에서 키보드 없이 선택 화면 열기를 확인한다.

## 점검 영역별 판정

여기서 정적 통과는 적힌 소스 항목만을, 모의 통과는 적힌 오프라인 검사만을 뜻한다. 영역 전체의 Studio 통과로 확대하지 않는다.

| 점검 | 소스/모의 결과 | 실제 실행 검증 |
| --- | --- | --- |
| 팀 간 권한·상태 격리 | 정적 및 일부 모의 통과. GameService:116-128, 614-640에서 세대/점포/근무/참가 권한 확인. :840-917에서 자기 점포 상세와 전체 요약 분리. :826-838의 정답 구간/Carry는 본인 Self로 제한. 다른 StoreId Signal 요청은 NOT_MEMBER 확인 | 실제 두 점포 및 16인 교차 Remote 요청 미실행 |
| 2~4인·1인 연습 | 순수 상태 모의 통과. N=1/2/3/4 × A/B/C × 초기 배치 6개의 72개 완주/로비 복귀/새 근무 경로. :659-683에서 단독 조건/전원 준비, :184-202에서 정전 구간 분할 | 실제 1~4인 플레이, 각 참가자 기여·대기 시간 미실행 |
| 동시 주문·지연 요청 | revision/token/요청 ID 방어는 소스 확인 및 일부 순차 모의 통과. Protocol:34-66, 88-94; Main:163-177; GameService:740-776. CR-002 문제 발견 | 실제 동시 접수·재전송·패킷 지연/누락 미실행. Main의 수신 큐는 순수 Service 테스트 대상이 아님 |
| 타이머·기한 경계 | Timer 전체, Main:55-118, GameService:511-599 확인. 기존 모의 검사의 주문 만료 우선/정전 지원복구/재시작 통과 | Heartbeat 지연·정각 원격 입력·동일 시각 여러 사건의 엔진 실행 미실행 |
| 이탈·복귀·재시작·정전 교착 | GameService:394-485의 일괄 감소/복귀, :340-392의 단독·협동 재개, :486-510/778-810의 역할 입력 차단 확인. 기존 모의 복귀 예산/단독/4인 정전 통과. CR-002는 클라이언트 준비 복구 문제 | 실제 죽음/재접속/전원 이탈, 4→3→2→1, 역할 lease 만료 및 거리 이탈 미실행 |
| 모듈 경로·API | 정적 대조 및 구문 컴파일 통과. Main.server:15-26의 Config/Builder/서버 Modules, Main.client:441-481의 Config/StateStore/TrayView/네 Remote가 계약과 대응. 공개 필드·액션명 대조에서 추가 불일치 미발견 | Studio 실제 인스턴스 배치·require/build·API 호출 미실행 |
| 모바일 버튼·무음 단서 | **CR-001 문제 발견**. Activated 버튼, 텍스트/상품명/도형/역할 수/미공유 구간/입력 중지 이유는 소스에 있음(Main.client:507-520, 643-683). 무음 안내 존재는 정적 통과 | 실제 모바일 터치·화면 가림·글자 크기·무음 이해도·성능 미실행 |
| 맵 통로·마커·기본 시각 | 오프라인 AABB/격자 검사 통과. 8개 마커 접근, Spawn/Entry 공간, 도로-Hub 연결. **CR-003 동작 누락**. BuildWorld:127-198의 입구/창고/번호·이름·도형 간판과 조명 확인 | 2~4인 충돌·통행, 카메라·조도·정전 구별·빌보드 겹침·실제 Raycast 안전 검사 미실행 |
| 유료 에셋·실제 결제 | 검토한 게임 소스 범위 **정적 통과**. Config:146의 Monetization/ExternalAssets/PersistentSave=false. 코드가 직접 Part/텍스트를 생성하고 외부 asset ID·LoadAsset·숫자 require·구매/receipt API 호출 미발견. 무료 미리보기(Main.client:144-165,606-611)는 로컬 장식 | 실제 place에 별도로 존재하는 외부 모델/플러그인/판매 설정은 조회하지 않음. 해당 영역 무결성을 보증하지 않음 |

정전의 정답·공유·소유권과 요청 권한을 소스로 검토한 범위에서는 확정적인 타팀 변경 결함을 추가로 찾지 못했다. 이것은 보안 또는 모든 경계의 무결성 보증이 아니다.

## 이번에 실제 수행한 오프라인 검증

### 구문 컴파일 — 통과

설치되어 있던 `tools/world/.validation/luau-0.745/luau-compile.exe --null`로 게임 Luau 10개와 테스트 Luau 3개, 합계 13개를 컴파일했다. 상대 경로 실행은 모두 exit 0이었다. 처음 절대 경로 실행은 도구의 한글 경로 해석 문제로 파일 열기에 실패했으며, 이를 구문 오류나 통과로 처리하지 않고 상대 경로로 다시 확인했다. Roblox 전역 타입 분석/엔진 실행은 아니다.

### 순수 모의 검사 — 통과 및 CR-002 재현

원본 검증 스크립트는 중간 파일을 쓰므로 그대로 실행하지 않았다. PowerShell에서 현재 실제 모듈과 spec을 읽어 메모리 안에서 결합하고, 설치된 Luau REPL의 표준입력으로 loadstring 실행했다. require 경로만 메모리에서 주입했다. Random은 기존 테스트 방식의 결정적 모의 구현, world는 테스트의 alive/near/move 어댑터다. 임시 소스 파일·로그 파일은 만들지 않았다.

```text
PURE STATE SIMULATION PASS: 5127 assertions; 72 full schedule/layout/team loops; Roblox/Studio/network/geometry not executed
PASS: 16 pure reducer assertions; Roblox/Studio not executed
PASS: 19 pure tray assertions; Roblox/Studio not executed
```

추가 CR-002 검사는 기존 fixture로 1인 근무를 만들고 `finish` → SetLoaded(false) → `toLobby` → 이전 RoundId의 SetLoaded(true) 순으로 실행했다. 상태 전환을 직접 주입한 검사이며 타이머/네트워크까지 재현한 것은 아니다. STALE_ROUND, 세대 불변, Loaded=false를 assert로 확인했다.

탐색용으로 복귀 예약자가 Unavailable 점포에 JoinStore를 요청하는 경우도 확인했다. STORE_UNAVAILABLE이고 원예약/Recovery가 유지됐다. 이 결과는 정상 이동 통과로 세지 않았으며, 위 3개 확정 수정 이슈와 구분한다. 예약 해제 정책을 추가 손볼 경우 contract의 예약 선해제 규칙과 함께 검토할 수 있다.

### 맵 수치 검사 — 통과

`tools/world/verify-world.cjs`를 읽어 **메모리에서만** 마지막 mkdir/writeFileSync 구문을 제거하고, 쓰기 구문이 남지 않았는지 확인한 뒤 설치된 Node로 실행했다. 원본 파일은 변경하지 않았다. 검사 결과:

```text
kind: OFFLINE_STATIC_INSPECTION_NOT_ROBLOX_EXECUTION
compile: PASS
inspectedStoreBoxes: 30
reachableMarkers: Counter, Shelf1, Shelf2, Shelf3, SignalPanel, Breaker, Entry, Spawn
routeWidthStuds: 4
spawnEntryClearance: PASS
hubRoadSeam: PASS
forbiddenOperations: PASS
```

이는 소스 상수를 읽는 평면 격자/AABB 검사다. 4명 아바타의 동시 통행을 시험하지 않았다. 220 BaseParts/20 Lights는 검사기의 소스 산정치이며 실제 Instance census가 아니다.

API 대조는 [BillboardGui의 Part/Attachment Adornee](https://create.roblox.com/docs/reference/engine/classes/BillboardGui), [Model.WorldPivot](https://create.roblox.com/docs/reference/engine/classes/Model#WorldPivot), [WorldRoot.GetPartBoundsInBox](https://create.roblox.com/docs/reference/engine/classes/WorldRoot#GetPartBoundsInBox)의 공식 문서에서 확인했다. API 존재/형식 확인을 실제 호출 성공으로 표시하지 않는다.

## 통합 담당의 다음 작업과 미실행 목록

1. CR-001~003을 담당 소스에서 수정하고 이슈 ID별 변경 파일·수용 여부·검증 증거를 남긴다. 이 문서의 검토 완료 표식을 코드 승인으로 해석하지 않는다.
2. Studio 실제 경로에 모듈을 배치하고 부트스트랩/월드 build 1회/개별 불량 점포 격리/안전 이동을 확인한다. 기존 Lighting, MaxPlayers, Streaming 설정은 이 검토에서 조회하지 않았으므로 야간 기본 시각과 정전 가독성도 검증한다.
3. SP9 V1: 실제 1인 연습과 2인 협동 완주·실패·무료 재시작, 두 점포 격리, CR-002 지연 보고, 마커 해제/재등장/자동 2회 한도를 실행한다.
4. S1-A~H/S2-A~B를 실제 서버 큐/클라이언트로 확인한다. 특히 동일 시각 여러 이탈, 이탈 대 일반 반납 S1-G/H, 마지막 품목 접수 대 만료, 결과 대 늦은 원격, 45초 정전 지원복구, 20초 복귀 기한, 역할 갱신 만료는 기존 순수 모의 통과만으로 종료하지 않는다.
5. V2의 실제 3~4인 무음 역할 교환/기여 관찰, V3의 실제 16인·4점포 동시 10분, V4의 기록된 모바일 기기 터치·프레임·메모리 검증은 전부 미실행이다. 실제 인원/기기·로그·화면 증거가 있어야 각각 통과로 바꿀 수 있다.

검토 시점 주요 소스 SHA-256 앞 12자리(2026-10-31 19:13 KST 조회):

| 파일 | SHA-256 접두 |
| --- | --- |
| src/shared/Config.luau | 5E12A2CEC89C |
| src/server/Main.server.luau | 6DA4691B13C6 |
| src/server/Modules/GameService.luau | 3169A9A173C0 |
| src/server/Modules/Protocol.luau | 636694661926 |
| src/server/Modules/Timer.luau | E9554E8DE9CE |
| src/server/Modules/WorldAdapter.luau | 535023ECF6AA |
| src/client/Main.client.luau | A7893B5733B3 |
| src/client/Modules/StateStore.luau | 0144E190801E |
| src/client/Modules/TrayView.luau | F35E610CA5F7 |
| tools/world/BuildWorld.luau | 9CBBBCEB411E |

독립 검토 보고 완료. 코드 수정과 Studio 검증은 다음 통합 단계의 작업으로 남는다.

[STAGE_READY:REVIEW]
