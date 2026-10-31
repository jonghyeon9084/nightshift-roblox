# 오늘도 정상영업 — 공유 구현 계약 1.0.0

기준: `scale-plan.md v0.3.2` > 유지된 `plan.md v0.2`, `scale-decisions.md`, `story.md`. 이 문서는 경로·데이터 형식을 확정하며 기획의 SP2~SP7 전환 규칙을 대체하지 않는다. 상수 원본은 `src/shared/Config.luau`; ProtocolVersion=1. 서버 16명·4점포·2~4인 협동은 목표이며 실제 검증 완료가 아니다. 이번 산출물은 이 문서와 Config뿐이며 아래 배치·로더·서버·UI·월드 구현은 다음 단계다.

## 1. 소유권과 실제 배치

| 담당/소스 | Studio 인스턴스 경로·타입 |
| --- | --- |
| 공유 `src/shared/Config.luau` | `ReplicatedStorage.NightShift.Shared.Config` ModuleScript |
| 월드 `tools/world/BuildWorld.luau` | `ServerStorage.NightShift.BuildWorld` ModuleScript |
| 서버 `src/server/Main.server.luau` | `ServerScriptService.NightShift.Main` Script, 서버 실행 |
| 서버 `src/server/Modules/<Name>.luau` (필요할 때만) | `ServerScriptService.NightShift.Modules.<Name>` ModuleScript |
| UI `src/client/Main.client.luau` | `StarterPlayer.StarterPlayerScripts.NightShift.Main` LocalScript |
| UI `src/client/Modules/<Name>.luau` (필요할 때만) | `StarterPlayer.StarterPlayerScripts.NightShift.Modules.<Name>` ModuleScript |

통합 보완(2026-10-31): UI 필수 모듈은 `StateStore`, `TrayView`, `LoadReporter`다. `LoadReporter`는 로컬 마커 로드 상태와 서버 확인 상태를 조정하며 점포·RoundId·SeatGeneration·목표 Loaded별로 최대 2회 보고하고 2초 간격을 둔다. 요청 응답 대기는 10초로 제한하며 이후 같은 한도 안에서 재시도한다. 상태 재시도 버튼은 한도를 초기화한다. 원격 형식과 서버의 옛 RoundId 거절 규칙은 변경하지 않는다.

중간 경로는 Folder다. Main의 선택 모듈 로더는 `require(script.Parent.Modules.<Name>)`; 모듈 이름은 담당 영역 내부 사항이며 다른 워커가 참조하지 않는다. 클라이언트 실행 시 위 StarterPlayerScripts 내용은 `Players.LocalPlayer.PlayerScripts.NightShift`로 복제된다. `PlayerGui.NightShiftHUD` ScreenGui는 클라이언트가 하나만 만들고 ResetOnSpawn=false로 재사용한다. GUI/프롬프트 생성은 UI 담당, 월드 구조·표지 생성은 월드 담당, 상태·상품 진열 변경·Remote 생성은 서버 담당이다.

자동 파일 동기화/배포 스크립트가 이미 있다고 가정하지 않는다. 이후 통합 담당이 위 표대로 소스를 배치한다. BuildWorld를 Workspace Script로 실행하거나 클라이언트에서 require하지 않는다. 서버 Main의 시작 순서는 다음과 같다.

1. 공유 Config와 BuildWorld의 존재/ModuleScript 타입을 최대 `Network.BootstrapTimeout=10`초 확인하고 실패 시 명시적 오류로 시작 중단한다. 각 단계 무한 WaitForChild 금지.
2. `local builder = require(game:GetService("ServerStorage").NightShift.BuildWorld)` 후 `local world = builder.build(workspace)`를 서버 세션당 **한 번** 호출한다. `build(parent: Instance): Model`은 yield 없이 완성된 `NightShiftWorld` Model을 parent에 붙이고 반환한다. require 자체에는 월드 생성 부작용이 없다.
3. 이미 parent에 NightShiftWorld가 있으면 `NightShiftOwned=true`와 필수 구조를 검사해 반환하며 중복 생성하지 않는다. 소유 표식이 없거나 루트 구조가 잘못되면 덮어쓰지 말고 오류를 반환한다. 개별 점포 불량은 서버에서 해당 점포만 Unavailable로 처리한다.
4. 아래 Remote들을 서버에서 생성/타입 검사하고 콜백을 연결한 뒤 상태 서비스를 준비한다. 초기화 중 GetSnapshot은 NOT_READY를 반환한다. 준비 후 플레이어를 안전한 Hub Spawn에 배치한다.

월드/서버/UI는 자기 NightShift namespace만 수정한다. Workspace:ClearAllChildren(), 전체 Lighting/StarterGui 삭제, 타인 모델·스크립트 삭제 금지. 월드는 전역 Lighting을 바꾸지 않고 자체 Part/Light만 사용한다. 이번 단계에는 Studio 쓰기·테스트·게시·실제 판매·유료 API가 없다.

## 2. 월드와 마커

`Workspace.NightShiftWorld` Model (`NightShiftOwned=true`) 아래 `Hub` Model, `Stores` Folder, 선택 장식 `Streets` Model을 둔다. Stores의 직접 자식은 Store01~Store04 Model이며 각각 문자열 Attribute `StoreId`=모델명, `DisplayName`=Config 점포명이다. `StoreId`라는 Value 인스턴스를 만들지 않는다.

좌표 단위 studs. 각 점포 pivot은 `CFrame.new(Position)*CFrame.Angles(0, math.rad(YawDegrees), 0)`. 마커는 pivot 기준 로컬 Position/회전 0으로 생성한다. 로컬 +Z가 출입구 방향이며 네 입구 모두 Hub를 향한다. Config의 숫자 배열 `{x,y,z}`를 Vector3/CFrame으로 변환한다.

| 점포 | 표시 이름/도형 | Position | YawDegrees |
| --- | --- | --- | --- |
| Store01 | 01 달빛점 ○ | (0,0,-140) | 0 |
| Store02 | 02 골목점 △ | (140,0,0) | -90 |
| Store03 | 03 새벽점 □ | (0,0,140) | 180 |
| Store04 | 04 별빛점 ◇ | (-140,0,0) | 90 |

Hub 중심 (0,0,0), 바닥 크기 (64,1,64), 바닥 윗면 y=0. 점포 바닥 윗면도 로컬 y=0, 내부 외곽 크기 (56,18,48), 연결 도로 폭 18. 건물 장식은 필수 지점까지의 통로와 안전 재배치 영역을 막지 않는다.

| 점포의 직접 자식 마커 | 정확한 타입 | 로컬 Position | Size |
| --- | --- | --- | --- |
| Counter | Part | (-12,3,10) | (12,4,4) |
| Shelf1 | Part | (-16,3,-8) | (8,4,4) |
| Shelf2 | Part | (0,3,-8) | (8,4,4) |
| Shelf3 | Part | (16,3,-8) | (8,4,4) |
| SignalPanel | Part | (-22,4,-18) | (4,4,1) |
| Breaker | Part | (22,4,-18) | (4,4,1) |
| Entry | Part | (0,1,20) | (8,0.2,4) |
| Spawn | SpawnLocation | (0,0.5,14) | (8,1,6) |

모든 마커 Anchored=true, CanTouch=false, CastShadow=false. Entry는 Transparency=1, CanCollide=false; 나머지는 CanCollide=true. Spawn은 Neutral=true, Enabled=false, Duration=0으로 기본 무작위 스폰 대상에서 제외하고 서버가 위치만 사용한다. 모든 마커에 같은 StoreId 문자열 Attribute를 붙인다. 마커 이름은 각 점포에서 유일하며 장식에 재사용하지 않는다.

Hub에는 `Spawn` SpawnLocation (0,0.5,0), 크기 (8,1,8), 위 Spawn과 같은 설정 및 `StoreSelect` Part (0,3,-12), 크기 (12,4,2)를 직접 자식으로 둔다. Hub는 StoreId 속성을 갖지 않는다. 선택 UI는 Hub StoreSelect에서 열 수 있고 HUD에서도 열 수 있다. JoinStore/무료 이동은 거리 검사가 없는 명시적 UI 동작이다.

Counter 기준 트레이 오프셋은 (-4,2.5,0)/(0,2.5,0)/(4,2.5,0), SignalPanel의 가상 자리 오프셋은 (-3,0,4)/(0,0,4)/(3,0,4)이다. 별도 필수 마커를 추가하지 않는다. 트레이는 LineId 1~3과 대응하고 취소 후 재번호하지 않는다. 슬롯은 역할 안내용이며 역할 거리 검사는 SignalPanel 중심을 사용한다.

서버는 네 모델/StoreId/마커 개수·타입·위치와 Spawn 위 캐릭터 공간·바닥을 검사한다. 오류 점포는 선택 불가 요약으로 남기고 정상 점포는 계속한다. 안전 위치는 Entry/Spawn의 CFrame에 로컬 y+`World.SpawnLift=4`; 장애물·바닥 안전 검사를 통과한 서버 목적지만 사용한다. 실패 시 MOVE_FAILED, 좌표 추측 이동 금지. JoinStore는 좌석 배정과 Entry 이동을 별도로 보고하며 이동 실패가 좌석을 다시 배정하게 만들지 않는다.

## 3. 상수와 실행 규칙

Config의 공개 키는 `ProtocolVersion, ContractVersion, DesignVersion, Namespace, Paths, Sources, Network, Capacity, Round, Order, Anxiety, Outage, Interaction, Loading, Products, ShapeLabels, ProductOrder, InitialLayouts, Schedules, World, Enums, Actions, ErrorCodes, Budget, Text, Features`다. 읽기 전용으로 취급하며 런타임 상태/정답/Token을 쓰지 않는다.

| Config 키 | 확정 값/의미 |
| --- | --- |
| Capacity | TargetPlayers=16, StoreCount=4, SeatsPerStore=4, MinCoopPlayers=2 |
| Round | SuccessOrders=5, MaxSeconds=300, StartConfirmSeconds=3, RecoveryBudgetSeconds=20, SoloRequestSeconds=10, BoundarySeconds=3, ResultSeconds=8 |
| Order / Anxiety | Seconds=45, TimeoutAnxiety=15, MaxCarryPerPlayer=1, MaxLines=3 / Initial=0, Warning=70, Maximum=100 |
| Outage | AutoRestoreSeconds=45, PenaltySeconds={15,30,45}, PenaltyAnxiety=10, RoleRenewSeconds=2, RoleLeaseSeconds=5 |
| Interaction | Distance=10, SignalCooldown=1, SignalSeconds=5, RepositionCooldown=10 |
| Loading | MarkerTimeout=5, RetryDelay=2, AutomaticAttempts=2(최초 포함) |
| Network | StateInterval=0.2, TimerSyncInterval=1, SnapshotCooldown=2, ActionRate=10/s, ActionBurst=20, RequestCacheSize=128, MaxRequestId=2147483647, MaxStringBytes=96, MaxPayloadFields=4, BootstrapTimeout=10 |

결과는 최대 8초 보여준 뒤 온라인 좌석자를 Lobby/Waiting/준비=false로 전환한다. 결과 화면의 무료 재도전(AcknowledgeResult)은 더 일찍 같은 로비 전환을 요청할 수 있다. 다른 사람의 결과는 Self.LastResult로 계속 열람 가능하다. 재도전은 새 근무 자동 시작이 아니며 새 명단 버전에 전원 준비가 필요하다. 이 8초는 이번 구현의 표시 기본값이다.

상품 ID는 Water=물/○, Bread=빵/△, Milk=우유/□. 진열 배열은 Shelf1~3 순으로 Config.InitialLayouts의 6개 순열 중 선택하며 변경 시 `{a,b,c}→{c,a,b}`. 새 근무 일정은 A/B/C 중 직전과 다르게, 초기 배치도 가능한 직전과 다르게 고른다. 일정별 첫 품목 배열은 Config.Schedules.FirstProducts대로 고정한다. 추가 품목은 ProductOrder 순서에서 첫 상품을 제외해 채우며 서로 다른 종류만 사용한다. Q=max(1,N-1); 만료 재주문은 같은 단계/품목을 새 OrderId로 만든다.

A: 2성공→진열 변경, 3성공→정전. B: 2성공→정전→진열 변경. C: 1성공→진열 변경, 4성공→정전. 변경 예고와 주문 경계는 최대 3초이며 중첩 대기하지 않는다. 단계3 주문 첫 생성 시 호출벨 표지를 한 번만 표시한다. 시각 표지 우선, 외부 음원 필수 아님. 주문/정전 중 예외 사건·인원 감소·재개는 SP2.1~SP6 그대로 따른다.

표시판 구간은 N=2에서 {1,2,3}, N=3에서 {1,2}/{3}, N=4에서 {1}/{2}/{3}; 단독은 구간 0개/순서 직접 공개다. Shapes는 Circle/Triangle/Square이며 실제 정답 순열은 서버 전용이다. 한 명은 Panel 구간 하나 또는 Breaker 하나만 소유한다. 감소 재분할은 정답·정전 ID·경과·벌점을 보존하고 소유권/공유/진도를 초기화한다.

## 4. Remote 계약과 전달 주기

`ReplicatedStorage.NightShift.Remotes` Folder 아래 정확히 다음 네 객체를 사용한다. Shared 아래 필수 공개 모듈은 Config 하나다.

| 이름 | 타입·방향 | 인자/반환 |
| --- | --- | --- |
| Action | RemoteEvent C→S | Request 한 table |
| ActionResult | RemoteEvent S→해당 C | Ack 한 table |
| State | RemoteEvent S→각 C | 수신자별 Packet 한 table |
| GetSnapshot | RemoteFunction C→S | `{ProtocolVersion=1}` → `{Ok:boolean, Code:ErrorCode, RetryAfter:number, Snapshot:Packet 또는 false}` |

GetSnapshot은 yield 없이 준비된 상태 복사만 반환한다. 클라이언트는 이벤트를 먼저 연결한 뒤 최초 호출하고 동시에 한 호출만 유지한다. 실패/NOT_READY는 2초 이상 간격으로 자동 재시도 한 번 후 수동 재시도 UI를 둔다. 서버 버전 불일치는 재시도 대신 업데이트 안내다. 비정상 Invoke 지연은 10초 뒤 UI 실패로 표시하며 뒤늦은 응답도 Sequence로 검사한다.

변경을 합쳐 State는 점포당 최대 5Hz/다음 200ms 이내 전송한다. 타이머 기준만 변할 때는 1Hz. 자기 점포 상세만 보내며 타 점포는 4행 요약뿐이다. 최초/재요청은 Snapshot, 이후 Delta는 변경된 최상위 slice 전체 교체 방식이다. 타이머는 매 프레임 송신하지 않는다. 위치 신호 1Hz/인·5초 수명, 소유 역할 갱신 2초/5초 만료, 스냅샷 요청 2초/인, 입력 토큰 버킷 10/s·버스트20을 서버에서 검사한다. 역할 갱신도 총 입력량에 포함한다. 거부 요청을 무제한 로그/응답 증폭하지 않는다.

## 5. Packet와 클라이언트에 필요한 전체 상태

아래는 wire 필드명/타입이다. `int`는 유한 정수, `number`는 유한 수, UserId는 int, ID는 1~96바이트 문자열이다. 부재 값은 명시적 `false`를 사용한다(배열 구멍/nil 금지). `T|false`는 그 의미이며 배열은 순서 있는 연속 배열이다. 표에 없는 내부 서버 필드는 보내지 않는다.

`Packet={ProtocolVersion:int, Kind:"Snapshot"|"Delta", Sequence:int, ServerTime:number, Self?:SelfState, Stores?:{Summary}, Store?:StoreState|false}`.

- ServerTime은 서버 `workspace:GetServerTimeNow()` 초 단위. Sequence는 수신자 연결별 단조 증가, Snapshot 응답도 증가시킨다. Snapshot에는 세 slice가 모두 필수, Delta의 누락 slice는 유지, Store=false는 상세 삭제다. `Sequence<=마지막 적용값`은 폐기한다. Delta 공백은 일단 최신 slice 적용 후 제한된 GetSnapshot으로 복구한다. Snapshot은 더 새 Sequence면 전체 교체한다.
- Store 변경 시 Self와 Store를 같은 packet에 넣는다. 점포 Revision은 로비부터 서버 세션 끝까지 단조 증가하며 새 RoundId에도 리셋하지 않는다. 오래된 점포 Revision은 폐기한다. RoundId 변경은 내부 주문/역할/시각 효과를 폐기한다.
- `Timer={Remaining:number, Running:boolean}`. Remaining은 Packet.ServerTime 시점 값이다. UI는 Running일 때만 서버 현재 시간 차를 빼고 0에서 멈춘다. 종료/권한 판정은 서버만 한다.

| 타입 | 필드·타입 |
| --- | --- |
| SelfState | UserId:int, StoreId:ID\|false, Seat:int\|false(1~4), SeatGeneration:int, Participant:Participant enum, Loaded:boolean, Carry:Carry\|false, Role:RoleRef\|false, ReadShapes:{IndexedShape}, LastResult:Result\|false |
| Carry | RoundId:ID, OrderId:ID, LineId:int(1~3), LineRevision:int, ProductId:product enum, CarryToken:ID |
| RoleRef | OutageId:ID, RoleId:"Panel1"\|"Panel2"\|"Panel3"\|"Breaker", Generation:int |
| IndexedShape | Index:int(1~3), Shape:shape enum |
| Summary | StoreId:ID, DisplayName:string, SignShape:string, Phase:Phase enum, Available:boolean, UnavailableReason:string\|false, OccupiedSeats:int, OnlineCount:int, FreeSeats:int |
| StoreState | StoreId:ID, RoundId:ID\|false, Revision:int, RosterVersion:int, Phase:Phase enum, Seats:{SeatState}, StartTimer:Timer, Round:RoundState\|false, Result:Result\|false, ResultTimer:Timer, Signals:{SignalState} |
| SeatState | Seat:int, UserId:int, DisplayName:string, Participant:Participant enum, Online:boolean, Ready:boolean, Loaded:boolean, ResumeReady:boolean |
| RoundState | RoundId:ID, Schedule:"A"\|"B"\|"C", Mode:"Coop"\|"Solo", InitialUserIds:{int}, ActiveUserIds:{int}, ActiveCount:int, TargetLines:int, SuccessCount:int, Anxiety:number, AnxietyCause:"None"\|"OrderTimeout"\|"OutageDelay", ShiftTimer:Timer, BoundaryTimer:Timer, BoundaryKind:"None"\|"NextOrder"\|"Shuffle", ShelfProducts:{product enum}, ShuffleStatus:EventStatus enum, OutageStatus:EventStatus enum, BellShown:boolean, Order:OrderState\|false, Outage:OutageState\|false, Recovery:RecoveryState\|false, SoloRequest:SoloRequestState\|false, SoloRequestUsed:boolean, HadReduction:boolean, HadSolo:boolean, HadSupport:boolean |
| OrderState | OrderId:ID, Stage:int(1~5), RequiredCount:int, AcceptedCount:int, Timer:Timer, Lines:{LineState} |
| LineState | LineId:int(1~3), ProductId:product enum, Status:LineStatus enum, LineRevision:int, CarrierUserId:int\|false, TrayIndex:int\|false, AcceptedByUserId:int\|false |
| OutageState | OutageId:ID, Revision:int, Timer:Timer, PenaltiesApplied:int(0~3), RequiredPanelCount:int, ConnectedPanelCount:int, RequiredBreakerCount:int(항상1), Roles:{RoleState}, SharedShapes:{shape enum\|false}(항상3칸), Progress:int(0~3), MissingSegments:{int}, CanInput:boolean, InputBlockReason:InputBlockReason enum, Resolution:OutageResolution enum\|false |
| RoleState | RoleId:role enum, Indices:{int}(Breaker는 빈 배열), OwnerUserId:int\|false, Generation:int, Connected:boolean, Shared:boolean(Breaker는 false) |
| RecoveryState | Timer:Timer, BudgetRemaining:number, SurvivorUserId:int, ReservedUserIds:{int} |
| SoloRequestState | RequesterUserId:int, Timer:Timer |
| SignalState | SignalId:ID, SenderUserId:int, Target:"Counter"\|"Shelf1"\|"Shelf2"\|"Shelf3"\|"SignalPanel"\|"Breaker", Message:"Here"\|"PanelHelp"\|"BreakerHelp", ExpiresAt:number(서버 절대시각) |
| Result | StoreId:ID, RoundId:ID, Code:ResultCode enum, FailureReason:FailureReason enum\|false, SuccessCount:int, OutageResolution:OutageResolution enum\|false, HadReduction:boolean, HadSolo:boolean, HadSupport:boolean, FinishedAt:number |

SeatGeneration은 사용자별 서버 세션 단조 증가값이다. 좌석 획득/상실/본인의 권한 전환 때 증가하고 Hub에서도 유지한다. 다른 사람 퇴장이나 로비 RosterVersion 변화만으로 생존자의 세대·유지된 Token을 바꾸지 않는다. Seats에는 점유 좌석만 좌석번호 순서로 전송하고 Reserved도 점유로 센다.

Enum의 허용 문자열은 Config.Enums가 정본이다. Lobby/Starting/Unavailable에서 RoundId=false, Result에서는 종료한 RoundId를 유지하고 Round=false로 보낸다. 없는 타이머는 `{Remaining=0,Running=false}`, 일시 정지한 타이머는 실제 남은 값과 Running=false다. Recovery에서는 진행 타이머를 멈추지만 Recovery.Timer는 흐른다. Outage 동안 Order/Boundary만 멈추고 Shift는 흐른다. Outage.Timer는 자동복구까지 남은 시간이다. Result는 Round 제거 후에도 표시 가능하며 LastResult는 그 라운드 참가자/대기자의 개인 마지막 결과를 다음 결과까지 보존한다(영구 저장 아님).

ReadShapes는 현재 본인이 소유한 표시판 구간 정답만 보낸다. 공유 전 다른 플레이어에게 정답·CarryToken을 보내지 않는다. SharedShapes는 직접 공유한 인덱스만 공개하며 단독 확정 시 3칸 모두 공개한다. Role 공유/진도는 같은 N의 연결 해제에도 유지하고, Generation은 소유권 해제/재할당 때 증가한다. MissingSegments는 미연결 또는 미공유 Panel 번호다. CanInput/InputBlockReason은 수신자별 서버 판정이다(거리/로드/자기 역할 포함). Roles와 요구 인원·도움말을 같은 Revision으로 갱신한다.

HUD는 Stores 4행, 내 Seats/준비, 성공 수/불안 원인/시간, Lines의 모든 상태, ShelfProducts, Carry, 표시판 담당/연결/공유/누락, SharedShapes/ReadShapes/진도/중지 이유, 복귀/혼자 요청, Result를 표시한다. 숫자·이름·도형을 함께 쓰고 색/소리만 사용하지 않는다. 안내 텍스트는 Config.Text, 상품 이름/도형은 Config.Products에서 가져온다.

## 6. Action 요청·응답

`Request={ProtocolVersion=1, RequestId:int, Action:Config.Actions 원소, StoreId:ID|false, RoundId:ID|false, SeatGeneration:int, Payload:table}`. 이 7개 필드는 항상 보낸다. Payload={}도 명시한다. 클라이언트 시각·UserId·Position·Instance·임의 정답·보상 값은 받지 않는다.

RequestId는 연결당 1부터 단조 증가, 재전송은 같은 ID/같은 본문이다. 서버는 사용자별 최근 128개 결과+요청 본문과 처리 high-water mark를 유지한다. 캐시 내 동일 재전송은 과거 Ack만 반환하고 상태를 재처리하지 않는다. 같은 ID의 다른 본문은 REQUEST_ID_REUSED, 캐시에서 밀린 ID 이하의 요청은 STALE_REQUEST. 진행 허용 기간을 넘긴 Token/ID를 재사용할 수 없다. 신규 연결은 새 요청 스트림이며 서버 좌석 세대는 복귀 권한을 따로 검증한다.

`Ack={ProtocolVersion=1, RequestId:int, Ok:boolean, Code:ErrorCode, StoreId:ID|false, RoundId:ID|false, Revision:int, RetryAfter:number, MoveCode:"OK"|"MOVE_FAILED"|false}`. Ack에 상태 delta를 섞지 않는다. 결과 상태는 State/GetSnapshot으로 받는다. Ok=true라도 JoinStore의 MoveCode=MOVE_FAILED면 좌석은 유지되고 무료 재배치 안내를 한다. 그 밖의 실패는 Ok=false. 파싱 불가능 RequestId는 Ack를 생략하고 경량 집계한다.

아래 `현재`는 서버 사용자 매핑의 점포·근무 ID·SeatGeneration과 일치한다는 뜻이다. 로비/Starting에는 RoundId=false. 대상 점포 선택 이외에는 다른 StoreId로 권한을 얻을 수 없다.

| Action | Payload의 정확한 필드 | 권한/효과 |
| --- | --- | --- |
| JoinStore | `{}` | StoreId는 목적 점포, RoundId=false, SeatGeneration은 현재 본인 값. Hub/원점포 Lobby·Result에서 가능. 목표 정원 확인+기존 좌석 해제+신규 배정 원자 처리. 진행 중에는 먼저 LeaveStore 필요. 예약 복귀자가 다른 점포 선택하면 SP5대로 원예약부터 해제. 합류 뒤 Entry 이동 시도 |
| LeaveStore | `{}` | 현재 점포/근무. 좌석·예약 해제 후 Hub 안전 이동; 이동 실패해도 퇴장 확정. Hub라면 NOT_MEMBER |
| TravelToEntry / Reposition | `{}` | 현재 점포/근무, 온라인 좌석자. 각각 자기 Entry / Spawn으로 무료 이동. 두 행동이 같은 10초 이동 쿨다운 공유, 역할 해제, 타이머·목표·상품 상태 유지 |
| SetLoaded | `{Loaded:boolean}` | 현재 점포/근무. false면 준비 취소 및 자기 역할 해제, 팀 시간/상품 권한은 유지. true는 클라이언트 마커 재바인딩 보고이며 거리/생존 검사를 대신하지 않음 |
| SetReady | `{Ready:boolean,RosterVersion:int}` | 현재 로비/Starting 명단 버전, Loaded=true일 때 준비 가능. 2~4명 전원 준비→3초 확인. 취소/명단 변경 시 전원 준비 무효화 |
| SoloPractice | `{RosterVersion:int}` | Lobby의 유일 온라인 좌석자, 다른 예약/대기자 없음, Loaded=true. 즉시 새 단독 근무 |
| ResumeReady | `{Ready:boolean}` | Recovery의 생존자/예약 복귀 준비자, 현재 RoundId, Loaded=true. 연결된 대상 전원 준비·2명 이상·기한 전이면 재개 |
| FinishSolo | `{}` | Recovery의 Survivor만 즉시 단독 확정 |
| RequestSolo / CancelSolo | `{}` | Running Coop 활성2명만 요청, 근무당1회. 취소는 상대만 10초 기한 전에 가능 |
| AcknowledgeResult | `{}` | 현재 Result 좌석자, 결과 RoundId. 전체 점포를 Lobby로 옮기고 전원 준비 초기화, 개인 LastResult 유지 |
| PickUp | `{OrderId:ID,LineId:int,LineRevision:int,Shelf:string}` | Running 활성, 정전 아님, 미수집/빈손, 현재 상품이 있는 Shelf1~3까지 10 studs 이내 |
| PutDown / ReturnItem | `{OrderId:ID,LineId:int,LineRevision:int,CarryToken:ID}` | Running 활성·정전 아님·현재 운반자. 놓기는 Counter 10 studs, 무료 반납은 거리 제한 없음. 상태/Token 폐기 원자 처리 |
| AcceptLine | `{OrderId:ID,LineId:int,LineRevision:int}` | Running 활성·정전 아님·Counter 10 studs·Tray 상태. 본인 운반품 접수도 가능 |
| ClaimRole | `{OutageId:ID,RoleId:role enum,Generation:int}` | Running 활성 정전, 빈 역할의 현재 세대·빈 개인 역할, Panel은 SignalPanel/Breaker는 Breaker 10 studs. 단독은 Breaker만 |
| ReleaseRole / RenewRole / ShareSegment | `{OutageId:ID,RoleId:role enum,Generation:int}` | 현재 소유자/세대. 해제는 거리 무관, 갱신·공유는 살아 있음/Loaded/해당 지점10 studs. 공유는 Panel만, 갱신 성공 후5초 lease |
| InputShape | `{OutageId:ID,Generation:int,Shape:shape enum}` | 현재 Breaker 소유자/세대·10 studs·서버 CanInput 조건. 오답은 진도만0, 벌점 없음 |
| Signal | `{Target:marker enum,Message:message enum}` | Running 활성, Loaded=true, 점포 안에서 자기 마커까지 10 studs. 메시지는 위 SignalState enum만, 자유 텍스트 없음 |

플레이 중 ReturnItem을 포함한 진행 입력은 Recovery에서 중지된다. 서버 이탈 회수는 사용자 반납과 별개다. Role 해제/Loaded=false/LeaveStore는 정지 상태에서도 필요한 정리가 가능하다. 시작확인 정각에는 시작이 우선이며 SetLoaded=false가 늦게 도착해도 입력 차단/역할 해제를 적용하되 자동 팀 중단은 하지 않는다.

예시(테스트 결과가 아닌 메시지 형식):

```lua
-- 내 점포의 현재 Shelf2에 있는 물(Line1)을 집기
{ProtocolVersion=1, RequestId=12, Action="PickUp", StoreId="Store01",
 RoundId="r-17", SeatGeneration=3,
 Payload={OrderId="o-8", LineId=1, LineRevision=0, Shelf="Shelf2"}}
-- 첫 성공 Ack. Token은 이후 본인 Self.Carry에만 들어온다.
{ProtocolVersion=1, RequestId=12, Ok=true, Code="OK", StoreId="Store01",
 RoundId="r-17", Revision=28, RetryAfter=0, MoveCode=false}
-- Hub의 초기 full snapshot (summary 네 행은 같은 형식)
{ProtocolVersion=1, Kind="Snapshot", Sequence=1, ServerTime=1000,
 Self={UserId=101, StoreId=false, Seat=false, SeatGeneration=0,
 Participant="Hub", Loaded=false, Carry=false, Role=false, ReadShapes={}, LastResult=false},
 Stores={
  {StoreId="Store01",DisplayName="01 달빛점",SignShape="○",Phase="Lobby",Available=true,UnavailableReason=false,OccupiedSeats=0,OnlineCount=0,FreeSeats=4},
  {StoreId="Store02",DisplayName="02 골목점",SignShape="△",Phase="Lobby",Available=true,UnavailableReason=false,OccupiedSeats=0,OnlineCount=0,FreeSeats=4},
  {StoreId="Store03",DisplayName="03 새벽점",SignShape="□",Phase="Lobby",Available=true,UnavailableReason=false,OccupiedSeats=0,OnlineCount=0,FreeSeats=4},
  {StoreId="Store04",DisplayName="04 별빛점",SignShape="◇",Phase="Lobby",Available=true,UnavailableReason=false,OccupiedSeats=0,OnlineCount=0,FreeSeats=4}},
 Store=false}
```

## 7. 검증·경계·복구 불변조건

서버 검증 순서: 형식/버전/허용 키·길이·유한수 → 속도 제한/재전송 → 현재 좌석 세대/StoreId/RoundId/참가 권한 → 대상 ID·Revision·Token·소유권 → 상태/생존/서버 거리 → 원자 상태 변경. Payload는 위 표의 키만 허용, 최대4필드, 중첩 table/Instance/function 금지. 문자열 한도96은 요청에 적용하며 서버의 한국어 문구·표시명 출력 한도가 아니다. 상태 변경 처리 중 yield 금지; 점포별 직렬 큐, 좌석 이동은 전역 직렬 큐를 사용한다.

동일 수신 시각 우선순위: 이탈/퇴장/캐릭터 제거 전체 반영 → 300초 기한 → 시작확인/복구/혼자전환 기한 → 정전/주문 기한 → 과제 축소 → 일반 입력(접수 순번). 이미 도달한 기한을 정지로 소급 취소하지 않는다. 이탈자의 운반만 먼저 미수집 복원하고 접수/트레이는 보존한다. 유지 선택은 접수 전부 + 필요한 미접수(Tray→Carried→Uncollected, 동률 LineId). 생존자의 같은 시각 일반 반납은 축소 뒤 검사하며 유지된 Token/Revision을 보존한다. SP9.1 S1-G/H의 결과가 달라야 한다.

Round/Order/Outage ID는 서버 발급·세션 내 재사용 금지. LineId는 주문 안1~3이며 각 상태 변경에 LineRevision 증가. 손·운반자·Token·트레이 변경은 한 처리 단위다. 주문 성공은 묶음 전체 완료당1, 만료 벌점은 묶음당1. 정각45초 정전 입력보다 마지막 벌점/지원복구가 우선. 같은 판정의 결과는 불안도100 실패→필수목표 완료→상한 미완료 순이며 상한 정각의 새 입력은 받지 않는다.

4→3→2 감소는 즉시 계속, 1명은 SP5의 예약 자격이 있는 경우에만 누적20초 복구, 예약 없으면 즉시 단독 확정. 복구 중 강제 상품 회수는 즉시, 과제 축소는 재개/단독 확정 때 수행한다. 대기자를 현재 근무로 승격하지 않는다. 로비 준비 버전과 품목 권한 세대는 분리한다. 결과는 Config.Enums.ResultCode로 분류하며 지원/혼자 이력을 지우지 않는다.

클라이언트는 경로 재탐색 최대5초, 2초 후 자동1회만 재시도한다. 마커 해제 시 로컬 프롬프트/시각 효과를 제거하고 SetLoaded=false, 스냅샷/좌석은 유지한다. 재바인딩 성공 후 SetLoaded=true와 제한된 GetSnapshot을 수행한다. 실패 UI에는 재시도/무료 재배치/퇴장 후 Hub가 있다. 서버 타이머는 허위 미로드 보고로 멈추지 않는다. 이동/죽음/거리 위반 또는5초 lease 만료 시 자기 역할 연결을 해제한다. StreamingEnabled/반경은 이번 계약에서 변경하지 않고 이후 실제 측정으로 정한다.

Budget은 점포180/공통400/전체1120 BasePart, 조명4/8/24, 그림자80, 자유물리0, 표시 GUI160, 게임 상태12000 bytes/s/인·192000 bytes/s/전체 목표다. 코드·아바타 포함 실제 성능은 별도 측정한다. 초과 시 장식·광원·효과부터 줄이고 필수 단서/무료 기능은 유지한다. Features의 Monetization/ExternalAssets/PersistentSave는 모두 false.

## 8. 인계·현재 검증 범위

서버 워커는 경로/Remote/상태/액션/기한을, UI 워커는 snapshot·slice 교체/무음 조작/재바인딩을, 월드 워커는 build(parent)와 고정 마커·안전 통로를 구현한다. 공유 계약 변경은 통합 담당에게 요청하고 각자 다른 담당 파일을 수정하지 않는다. 조용한 공포·친구 협동·무료 완결을 유지하며 큰 비명·섬광·판매 유도·추격·저장 시스템을 추가하지 않는다.

이번 확인 대상은 두 파일의 존재·UTF-8·상수/이름/경로/형식 일치다. Studio 배치·require 실행·플레이·네트워크 동시성·S1/S2 실행·16인/모바일 검증은 모두 미실행이다. 후속 검증은 scale-plan SP9의 V1~V4와 S1-A~H/S2-A~B를 구분하여 실제 증거와 함께 기록한다.
