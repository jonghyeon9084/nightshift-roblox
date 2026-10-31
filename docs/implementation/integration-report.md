# 로컬 Studio 통합 검증 보고

2026-10-31 / NightShift-Integrator / NightShift-Integration  
추적 ID: `1983ffc0-ec8e-4f43-ae24-52a456d7152d`

**판정: `[STAGE_READY:INTEGRATION]` — 로컬 게임 통합, 실제 1클라이언트 완주, 발견한 치명 오류 수정·재검증을 완료했다.** 2인 협동·16인 성능·모바일·재미·매출 검증 완료를 뜻하지 않는다. 최종 Studio는 **Edit**, 로컬 Place는 `.setup/NightShift-local.rbxl`에 저장했다. 게시하지 않았고 Studio는 열어 두었다.

## 선행 확인과 설치

AGENTS.md, game-brief, contract, 독립 code-review, build-report와 실제 서버·클라이언트·공유·월드 소스를 읽었다. Maestro 그룹 상태와 Build/Review 기록에서 다른 게임 워커 완료 및 유휴 상태를 먼저 확인했다. 이 단계의 Studio 쓰기는 Integrator만 수행했다.

`.setup/studio-connection.json` 메타데이터와 실제 `tools/list`를 읽고, 현재 단일 Studio **Place1**(ID `70507f96-7854-4fff-bbbd-38855a438646`, PlaceId 0)을 선택·확인한 뒤 Edit를 확인하고 설치했다.

초기 `%LOCALAPPDATA%\Roblox\mcp.bat` 실행은 경로 부재로 실패했다. 실행 중 Studio의 MSIX 가상화 경로에서 공식 `StudioMCP.exe`를 확인해 **기존 tools/studio-mcp.cjs 클라이언트의 시작 명령만 메모리에서** 교체했다. 원본 파일·RPC 프로토콜을 변경하지 않았다. 연결 차단은 해소됐다.

재실행 가능한 `tools/integration/build-loader.cjs`는 계약의 10개 소스와 신규 `StarterPlayer.StarterPlayerScripts.NightShift.Modules.LoadReporter`를 설치한다. Edit 전용이며 소유권·타입·동명 충돌을 변경 전에 검사한다. 변경된 ModuleScript는 캐시가 남지 않게 교체하고, 월드 변경은 별도 모델에서 생성 성공 후 소유한 `Workspace.NightShiftWorld`만 교체한다. 테스트 도구는 게임에 설치하지 않았다.

최종 로더 결과는 **Installed=11, Changed=0**이고 실제 서비스 경로·Script/LocalScript/ModuleScript 타입·소스 해시가 파일과 일치했다. 실제 엔진 census는 **4점포, 220 BasePart, 20 Light**다. 중앙 Hub, 네 방향 거리·인도, 네 점포와 내부 창고를 설치했다. 기존 **Baseplate와 SpawnLocation은 유지**했다. 최종 조감 이미지는 `.setup/integration/1793443138366.jpg`다.

## 중요 검토 이슈별 대응

| 이슈 | 결정과 수정 | 확인 범위 |
| --- | --- | --- |
| CR-001 / P1 버튼 재생성 | 수용. 페이지·점포·근무·동작 식별자로 행과 버튼을 재사용한다. 단일 Activated 연결이 최신 콜백을 읽고 제거된 행은 요청하지 않는다. | 실제 마우스를 1.6초 누른 채 상태 갱신을 통과한 뒤 놓았다. 같은 버튼 유지·성공 Ack 정확히 1건. 실기 터치와 동료 동시 요청은 미검증. |
| CR-002 / P2 로드 보고 경계 | 수용. LoadReporter에서 pending과 서버 Loaded를 분리한다. StoreId/RoundId/SeatGeneration/목표 Loaded를 문맥으로 삼고 원요청을 보존한다. 문맥당 최대 2회, 2초 간격, pending 10초 제한과 F5 초기화를 적용했다. 오래된 Ack는 새 pending을 지우지 않는다. | 실제 모듈의 순수 검사 18개 통과. 합성 마커 해제/복원에서 Loaded false→true와 트레이 3개 복원이 F5 없이 확인됐다. **자연 발생 Result→Lobby 지연 RemoteEvent 경계 자체는 엔진 미검증.** |
| CR-003 / P2 Hub 선택 동작 | 수용. 클라이언트가 StoreSelect에 E/클릭 가능한 ProximityPrompt를 하나 소유하고 해제 시 정리한다. | 도움말에서 Hub 안내판에 접근해 실제 E로 점포 화면 열림 확인. 점포 이동 후 Hub 복귀에도 PromptCount=1. 실제 모바일 터치·streaming eviction은 미검증. |

세 이슈 모두 수용했으며 보류한 수정안은 없다. 독립 검토 문서는 검토 당시 기록으로 보존했다.

## 실제 실패와 원인 수정

1. **INT-001 / 서버 시작 차단:** 첫 Play에서 `Hub Spawn is obstructed or has no floor`. 원래 SpawnLocation과 자체 바닥이 같은 높이라 Raycast가 비소유 SpawnLocation을 먼저 맞혔다. 바닥 검사는 자체 월드만 Include하고, 서 있는 공간의 Overlap은 외부 충돌물을 계속 검사하도록 WorldAdapter를 수정했다. 기존 SpawnLocation을 삭제하지 않았다. 이후 시작과 네 점포 이동 성공.
2. **INT-002 / 첫 정전 서버 오류:** 빈 역할의 `owner=false`에서 `role.owner and users[role.owner]`가 false가 됐고 nil만 검사한 코드가 boolean의 storeId를 읽었다. GameService에서 false도 거절하도록 수정하고 1~4인 빈 역할 Snapshot·타이머 회귀 검사를 추가했다. 이후 정전 해결·완주·최종 콘솔 무오류 확인.
3. **INT-003 / 즉시 역할 갱신:** 새 역할 직후 이전 갱신 시각을 사용하여 COOLDOWN이 발생할 수 있었다. 역할 세대가 새로 부여되면 갱신 시각을 초기화했다. 최종 요청 응답 25건 모두 OK.
4. **INT-004 / UI 행 순서:** 기본 이름 정렬로 실제 행 배치가 어긋났다. UIListLayout.SortOrder를 LayoutOrder로 명시했다.

초기 공식 `character_navigation`은 도착하지 않았는데 Success를 반환했다. 이동 통과로 세지 않고 테스트를 정상 속도 `Humanoid:MoveTo`와 도착 거리·7초 제한 검사로 바꾸고 창고 문 경유점을 추가했다. 초기 이동 정체·주문 시간초과, 중간 복구 완주, 최종 깨끗한 실행을 별도 기록했다. 한 번의 Stop RPC 시간초과는 다음 상태 조회로 Edit 복귀를 확인했다.

## 실제 1클라이언트 최종 실행

공식 `start_stop_play`, `get_console_output`, `execute_luau`의 Edit/Server/Client 기능과 실제 키/마우스를 사용했다. 공개 State 패킷을 읽는 클라이언트 관찰기와 캐릭터 물리 이동을 사용했으며 **서버 게임 상태를 주입해서 완주 결과를 만들지 않았다.**

| 시각 (2026-10-31 KST) | 실제 관측 |
| --- | --- |
| 19:34:02 | 실제 Play 시작. 19:34:27 자동 사용자 흐름 시작. |
| 19:34:27~38 | Hub E → Store01 입장·Loaded=true. 준비 버튼 1.6초 유지 → 동일 인스턴스·Ack 1건. P로 혼자 연습 시작. |
| 근무 중 | 선반 이동·E 집기, 계산대 E 내려놓기·접수. 주문 2개 후 정전에서 창고 문 통과·차단기 역할 획득·실제 1/2/3 도형 입력으로 Solo 해결. |
| 19:35:30 | `AdjustedClose`, SuccessCount=5, FailureReason=false, OutageResolution=Solo, HadSolo=true, HadSupport=false, HadReduction=false. |
| 19:35:31 | 결과 E → Lobby, Loaded=true, Ready=false, Carry=false, Role=false. 전체 Ack **25건 모두 OK**. |
| 19:35:47~56 | Store02/03/04 실제 키 입장, 각 Lobby·Loaded=true와 Entry 위치 확인. |
| 19:36:00 | Store04 클라이언트 마커 잠시 해제·복원. Unloaded=true, ReloadedWithoutF5=true, Trays=3. **합성 재바인딩이며 실제 스트리밍·자연 지연 재현이 아님.** |
| 19:36:04 | Hub 복귀 StoreId=false, PromptCount=1. 최종 플레이 콘솔은 서버 ready 메시지뿐이며 오류 없음. 이전 실패 로그는 보존. |
| 19:36:18 | Stop 후 Edit. 로컬 저장 뒤 19:38:57 Edit·Installed=11·Changed=0 다시 확인. |

약 52초 근무 완주는 자동화 입력 기준이며 사람의 플레이 시간·난이도·재미 지표가 아니다. 전체 주문 물리 동선은 Store01에서 검증했다. 나머지 회전된 점포는 입장/로드와 Store04 합성 재바인딩까지 확인했다.

## 오프라인 검사와 증거

- 서버: Luau 0.745 구문 검사 6개, **5,192 assertions / 72 schedule-layout-team loops** 통과. 1~4인은 순수 상태 모의 검사 수치다.
- 클라이언트: 소스/명세 7개 컴파일, 순수 모듈 3개 분석, StateStore 16 + TrayView 19 + LoadReporter 18 = **53 assertions** 통과. 22개 계약 동작·중앙 송신·트레이 연결 정적 검사 통과.
- 월드: AST/AABB 30개 상자, 8개 마커 접근, 폭 4 studs 경로, Spawn/Entry 여유 공간과 도로 연결 통과. 실제 엔진 물리 검사로 확대하지 않는다.
- 로그 저장 재실행 중 상대 Tee 경로가 테스트 내부 디렉터리 변경으로 실패했고 월드 CLI의 필수 bin 인수를 한 번 누락했다. 절대 로그 경로·올바른 인수로 재실행하여 통과 기록을 남겼다. 게임 코드 실패와 구분한다.

원본 근거는 `.setup/integration/events.jsonl`(도구·초기 실패·최종 상태), `play-flow.jsonl`(실패·중간·최종 입력/관측), `postplay.jsonl`(다른 점포·합성 검사·최종 콘솔)이다. `manifest.json`과 `tools.json`은 설치 소스와 실제 기능 메타데이터다. 이번 오프라인 출력은 `server-offline.txt`, `client-offline.txt`, `world-offline.txt`다.

`.setup/studio-verification.json`에 검증 분류·남은 항목·소스/저장 파일 SHA-256을 기록했다. `collect-verification.cjs`는 이미 실행된 증거와 현재 파일을 대조해 조립할 뿐 Studio 플레이를 새로 수행하지 않는다. 기존 `.validation/verification.json`과 validation-report는 빌드 당시 역사적 결과이며 최신 통합 결과로 읽지 않는다.

## 남은 문제·미검증과 재개

| 항목 | 현재 사실과 다음 확인 |
| --- | --- |
| 2클라이언트 | 공식 start_stop_play는 is_start만 제공하고 다중 로컬 서버/인원 수 기능이 노출되지 않아 미실행. 지원 환경에서 역할 읽기·공유·동시 요청 검증 필요. |
| 3~4인·16인 | 실제 협동·네 점포 동시 정전·팀 격리·부하·전체 S1/S2 동시성 시나리오 미검증. |
| 정원 | Config 목표 16, 실제 Players.MaxPlayers **30**. Place 설정 적용 완료가 아님. |
| 연출 | 기존 전역 Lighting을 보존하여 ClockTime **14.5**. 점포 광원 제어와 별개로 야간 분위기·정전 가독성 조정/검수 미완료. |
| 모바일·화면 | 작은 뷰포트의 긴 HUD 스크롤, 실제 터치·글자 크기·화면 가림·무음 이해도·기기 FPS/메모리/통신량 미검증. |
| 로드·네트워크 | 실제 streaming eviction·지연/역전 RemoteEvent·Result→Lobby 자연 발생 CR-002 경계 미검증. |
| 사용자 평가 | 재미·이탈률·수익 미측정. |

현재 연결·승인·한도 차단은 없다. 예약·재승인 대기를 만들지 않았다. 재개 지점은 저장한 로컬 Place의 Edit 상태다. 명령은 `tools/integration/README.md`에 있다. 수동 경로는 **Play → Hub 안내판 E → 1번 점포 → P → 주문 집기/내려놓기/접수 → 정전 차단기·도형 → 주문 5개 → 결과 E**다. 테스트 뒤 Stop → Edit를 확인한다.

## 변경 파일과 최종 저장

- 게임: `src/client/Main.client.luau`, 신규 `src/client/Modules/LoadReporter.luau`, `src/server/Modules/WorldAdapter.luau`, `src/server/Modules/GameService.luau`.
- 검사: 신규 `src/client/tests/LoadReporter.spec.luau`, `src/client/tests/Run-StaticChecks.ps1`, `src/server/tests/Service.spec.luau`.
- 통합: `tools/integration/`의 공식 MCP 래퍼·로더·요청 JSON·플레이/관찰/합성 검사·증거 조립기·README.
- 문서: contract의 LoadReporter 설치·의미, 본 보고서, build-report의 후속 결과 연결. code-review 원문 보존.
- 산출물: `.setup/integration/`, `.setup/studio-verification.json`, `.setup/NightShift-local.rbxl`, 제외된 검사 `.validation/` 산출물. Config와 BuildWorld 소스는 변경하지 않았다.

금지된 지도/mission-control·`tools/runner/`는 수정하지 않았다. 공개 게시·판매·유료 API·구매·외부 메시지·계정/보안 설정 변경·Studio 종료를 하지 않았다.

**최종 Studio: Edit.** 로컬 저장은 Studio의 File → Save to File As로 수행했다.

`C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\NightShift-local.rbxl`

파일 존재·크기 **143,395 bytes**, 저장 시각 **2026-10-31 19:38:27 KST**를 확인했다. 저장 후 Edit와 소스 일치를 재확인했으며 파일 재열기 검증은 하지 않았다. 최종 해시는 JSON에 기록했다.
