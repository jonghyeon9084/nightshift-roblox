# 단독 매장 서버 v2 소스 인계

NightShift-StoreOwner / NightShift-SoloStoreServer-RC / 2026-11-01 KST.

**로컬 서버 소스와 오프라인 검사를 제출한다. 단계 완료 표식은 Moderator 검토 대기다. `releaseReady=false`, `warehouseAcceptanceComplete=false`를 유지한다. 최종 Place 저장·Studio 실플레이 인수는 미완료다.**

`warehouse-source-handoff.md`를 먼저 확인하고 release-target, solo-store-contract 2.0.0, release-task-decisions, release-acceptance-matrix를 적용했다. 기존 창고의 저장 중단을 성공으로 바꾸지 않았다. Computer Use/Studio를 호출하지 않았으며 Escape 이후 UI 재개·저장 우회도 하지 않았다. 공개 게시·실제 판매·유료 API·유료 에셋 실행은 없다. 09:00 KST 기한 전 소스 인계이며, 기한 도래가 실플레이 합격을 뜻하지 않는다.

## 이번에 변경한 파일

| 파일 | 변경 |
| --- | --- |
| `src/server/Main.server.luau` | v2 bootstrap, 단일 yield 금지 경제 큐, 프로필 IO 작업 분리, 연결별 rate/replay 캐시, 소유권/스냅샷/종료 연결 |
| `src/server/Modules/CommerceService.luau` | 개인 Wallet·단위 상품 ledger, 발주/취소/배송/하역/창고/진열, NPC 원자 판매, 임시 도난·회수·드롭, 복원/퇴장 장벽, R-A/R-B 실제 거래 연결 |
| `src/server/Modules/ProfileService.luau` | 기존 v1 normalize 보존·공개, 검증된 v2 migration, 세 커서 epoch 재설정, Store 확장 저장, 장벽/ErrorCode, 기존 lease/UpdateAsync 보존 |
| `src/server/Modules/Protocol.luau` | Commerce 요청을 공유 validateAction에 위임, OwnerGeneration, v1 명시 거절, 야간 액션 allowlist |
| `src/server/Modules/WorldAdapter.luau` | 복원 표현의 숨긴 staging/폐기/게시, 현재 DisplayName 간판 메타데이터, Recoverable 위치 표현, 창고 업그레이드 용량 표시 |
| `src/server/Modules/OwnershipService.luau` (신규) | 8자리 1:1 배정, 복원 성공 전 비공개, generation/epoch 검증, 해제 |
| `src/server/Modules/DemandGoalService.luau` (신규) | 기존 도매 재고에서 실제 유보·차감·환원, 고정 목표, 검증 판매 진행 후보 |
| `src/server/Modules/ContestService.luau` (신규) | 자발적 참가, 고정 4기회·도착 증거, 부문별 점수, 비교가능/개인/비교불가 결과 |
| `src/server/Modules/SoloGameService.luau` (신규) | 자동 배정/대기, 본인 야간 영업·정전·차단기 입력·완료·무료 재시작, v2 상태/다음 행동 |
| `src/server/Modules/ServerUtil.luau` (신규) | 복사·동등성·결과와 yield/예외를 거절하는 adapter 호출 |
| `src/server/Modules/RuntimeBridge.luau` (신규) | 서버 전용 NPC/Traffic 등록·계획 읽기·큐 명령 인터페이스 |
| `src/server/tests/SoloServer.spec.luau` (신규) | 실제 서비스에 fake 저장소/월드/NPC/교통/시계를 주입하는 오프라인 검사 |
| `src/server/tests/Run-SoloChecks.py` (신규) | 실제 모듈 bundle, Luau compile/run, 결과와 소스 SHA256 기록 |

`GameService.luau`, `ProfileService.spec.luau`, 기존 창고 검사·다른 담당의 변경은 작업 시작 때 이미 존재했다. 이번 작성 변경 목록에 포함하지 않으며 되돌리지 않았다. Main의 활성 야간 경로는 **SoloGameService**다. 기존 GameService/ProgressionService/RankingService/DeliveryService의 v1 기능을 Main에서 병행 실행하지 않는다. 직원·공동 소유·SecureTheft·수동 legacy line 판매 경로를 새 경제 흐름에 우회 연결하지 않는다.

공유 소스, 클라이언트, 월드 빌더, 설치 manifest, worker-pool은 수정하지 않았다. 산출물·검증 파일은 배정된 `src/server/`와 이 문서 안에 작성했다.

## 구현한 보존·권한 경계

- 프로필 lease가 유효하고 전체 저장 재고가 검증·staging된 다음에만 슬롯을 공개한다. 같은 사용자 재배정은 같은 슬롯, 9번째는 STORE_FULL이고 자리가 비면 대기자 재배정을 시도한다. StoreId는 영속 소유권이 아니다. DisplayName은 현재 서버 Player 값으로 갱신한다.
- 네트워크 가격/보상/소유자/좌표를 받지 않는다. v2의 7필드·정확한 payload를 검증하고 Player 기반 context에서 매장/세대/epoch/로드·거리·시야·이동 유효성을 추가 검사한다. RequestId 캐시는 128개, 오래된 ID high-water는 유지한다.
- 새 프로필만 240을 받는다. 기존 Wallet에 보조금을 더하지 않는다. 발주 즉시 유료 상품 ID를 단위별 한 번 생성하며, 저장용 canonical view에도 같은 ID를 담는다. 배송 실패·종료 시 인도와 환불을 동시에 하지 않는다. 명시 취소는 미출발 주문만 실제 결제액을 한 번 환불한다.
- 모든 경제 변경은 소유 매장의 copy-on-write 후보와 전체 프로필을 함께 검증한다. 프로필 mutate가 실패하면 라이브 ledger·공용 공급·유보·점수는 커밋하지 않는다. 판매가 성공한 뒤에만 수요/대회 후보를 교체한다. 복원·회수 왕복에서 XP/점수를 만들지 않는다.
- 자동 저장은 커밋마다 갱신된 canonical 전체 프로필 사본을 저장한다. 저장 IO 중 새 거래를 허용하는 경로는 더 최신 메모리 revision/dirty를 보존한다. 퇴장은 큐에서 유료 transit·운반·도난·바닥 상품을 원소유자로 정산하고 장벽을 닫는다. Shelf slot을 유지하며 나머지는 창고/초과 안전 보관이다. 저장 실패 후 장벽을 열어 기본값으로 덮지 않는다.
- UpdateAsync는 기존 키 `NightShiftProfiles_v1` / `u:`를 유지한다. 실제 부재를 확인한 경우만 defaults를 생성한다. 다른 lease, 미래 스키마, 손상, stale epoch를 거절한다. v1의 4인 Coop/Support Best는 이전 검증 설정으로 보관한다. 클라우드 활성화는 하지 않았고 기본 Memory 모드는 영속 저장 성공 표시가 아니다.
- NPC 판매는 신뢰된 registry의 Browse/Checkout 증거, 선택 토큰/만료, 상품 revision, 현재 소유권을 검사한다. 한 선택의 전체 수량을 모두 판매하거나 모두 거절한다. 잔고 상한 초과면 상품을 소비하지 않는다. 매출·부채 상환·XP·도감·R-A 실적은 같은 프로필 revision이다. 원 영수증 replay는 재지급하지 않는다.
- 도난은 일시 보유일 뿐 OwnerUserId를 바꾸지 않는다. 보호·hold·피해 cooldown·carry 한도·만료·원소유 회수를 적용한다. 도난품을 자기 창고/지갑으로 편입하지 않는다. 다른 소유자의 상품과 자기 cart 상품을 동시에 들 수 없다.
- ForceDrop은 서버 전용이다. 본체에서 ID, 관측 freshness 0.25초, 최소속도, 쌍별 2초 cooldown, replay를 검사하고, 추가 기하 증거는 Traffic authority가 검증한다. 현재 운반품만 같은 ID로 Recoverable로 이동한다. 안전 바닥 좌표가 없으면 자산 보존 반환과 `SafeStorage=true`를 알리며 실제 바닥 드롭 성공으로 간주하지 않는다.

## 성장·R-A/R-B·야간 흐름

현재 확정 공유 계약은 **창고 0→1, 게임머니120, 용량24→32**다. 일반 요청의 “약 3단계/전문화 조합”은 공유 계약·DR12의 1단계 및 전문화 보류와 다르다. 지정 소유권 밖의 shared 스키마를 임의로 늘리지 않았다. 3단계 업그레이드나 전문화를 구현했다고 보고하지 않는다. 무료 회복은 공용 Water1 외상 배송과 RecoveryDebt4이며 재접속 현금 지급이 아니다.

R-A는 기존 공급의 소유자별 두 SKU×2 유보, AllocationId 소유권·만료, 공용 마지막 수량, 취소/퇴장/만료의 단 한 번 반환을 구현했다. 성공한 실제 판매 후보만 목표를 올린다. 2회차는 Milk/Snack으로 회전한다. 공급/자금 부족은 시작하지 않는다. `Demand.Phase="Waiting"`, `Reason`, 시작/종료/유보시각 `false`로 대기 원인을 전달한다. 준비 실패는 생성된 상품이나 성공 회차가 아니다.

R-B는 준비 중 자발적 참가, 두 기본 SKU·새 유료품 최대4개·HandCarry·Slot01/02·실제 일반 손님 4기회를 사용한다. 자연/부자 판매는 대회 점수0이며 R-A에는 실제 적격 단위 수량을 반영한다. 대회 상품을 지정 기회 전에 자연 방문이 소모하지 못하게 보류하고 기회 실패/종료 후 해제한다. 다양한 판매20/계획40/물류30 상한과 단위/기회 중복 방지를 적용했다. 물류는 본인 하역→창고→직접 진열 계보를 확인한다. 연습·도난·외상은 제외한다.

실제 offeredAt/arrivedAt/결과를 요구하고 ±5초 또는 누락/장애를 검사한다. 2명 이상 정상 동일 기회일 때만 Comparable, 정상 1명은 PersonalOnly, 누락·이탈·장애는 NotComparable이다. 비교불가 회차의 우승자/영구 대회 실적을 만들지 않는다. 기록 실패가 남은 정상 종료 회차를 다음 회차로 덮지 않는다. 실제 위치별 공정성은 아직 검증되지 않았다.

SoloGameService는 첫 판매 전 야간 제한시간/정전 강제를 시작하지 않는다. 실제 NPC 매출로 야간 진행을 계산하고, 혼자 화면 모양 순서를 자기 차단기에 입력하거나 무료 자동 복구한다. 5단위 판매와 정전 해결 후 무료 완료/재시작, 실패 후에도 지갑·재고·업그레이드를 유지한다. 직원 역할/공동 근무가 필요하지 않다. 기존 v1의 전체 연출·UI가 자동으로 호환된다는 의미는 아니다.

## 실행 명령과 실제 결과

```powershell
python src/server/tests/Run-SoloChecks.py
git diff --check -- src/server docs/implementation/solo-store-server.md
```

최종 Luau compile exit=0, 서비스 모의검사 **546 assertions PASS**, 기존 공유 계약 순수 검사 **291 assertions PASS**, test exit=0. 합계 837 assertion이며 837개의 서로 다른 실플레이 시나리오라는 뜻이 아니다. whitespace 검사에서 오류는 없었으며 기존 파일의 Git LF→CRLF 안내만 있었다. 소스 최종 해시/UTC 실행시각은 보고서에 기록했다.

| 근거 | 내용 |
| --- | --- |
| `src/server/.validation/solo-server-checks.txt` | 최종 compiler와 Luau 실행 stdout/stderr |
| `src/server/.validation/solo-server-report.json` | 실행 종류, UTC 시각, compile/test 종료코드, 입력 소스 SHA256, studioRun=false/cloudRun=false/releaseReady=false |
| `src/server/.validation/solo-server-tests.luau` | 실제 모듈 코드와 fake adapter 검사를 조합한 재현 bundle |
| `src/server/tests/SoloServer.spec.luau` | 입력/주장/assertion이 있는 검사 원본 |

실제로 실행한 것은 **standalone Luau에서 실제 서비스 로직을 fake adapter로 실행한 검사**와 공유 순수 함수 검사다. Main/WorldAdapter/RuntimeBridge는 컴파일했지만 Roblox 엔진에서 실행하지 않았다. fake world의 staging·거리·NPC 경로·충돌 증거는 실제 지형/보행/기하 검증을 대신하지 않는다.

검사 범위: 8배정/9번째/퇴장 후 대기자, v1·직원·서버전용 Remote 거절, 권한·거리 거절, 결제 transit 재접속 동일 ID 복원, 취소·공용 마지막1개, 실제 서비스 물류·판매·selection 경합·잔고상한, upgrade 저장 CAS, 외상 상환, load/save 실패, 손상/미래 스키마, v1 돈/4인 기록 migration, lease·negative Studio ID, 저장 중 새 거래, 8명 유보 보존/부족/중복 prepare, 두 참여자 R-A/R-B 판매·동점·중복 실적, 두 번째 회전, PersonalOnly/NotComparable, 도난·드롭·만료, 야간 무료 완결, 복원 publish 실패/yield 거절을 확인했다.

첫 검사에서 test helper가 다중 반환을 label/인덱스로 받는 오류가 있어 harness를 수정했다. 연속 배송 검사에서는 `pairs` 순서에 따라 두 번째 SKU가 먼저 배차되는 문제를 발견하여 주문 serial FIFO와 현재 매장 상태 재조회로 수정했다. 실제 WorldAdapter가 받는 segment 이름과 출차3초 대기도 연결했다. 대회 판매 후 점수 상태 복사 때문에 `Released` 표식이 소실되어 다음 단위를 조기에 풀 수 있는 경로를 추가 점검해 수정하고, 자연/부자 판매 차단 회귀 검사를 실행했다. 최초 실패를 통과 기록으로 바꾸지 않으며 위 결과는 수정 후 실행 결과다.

## NPC·Traffic 담당 연결

서버 전용 `RuntimeBridge`를 사용한다. Main이 `configure`한 뒤 전문 서비스가 등록한다. 새 Remote를 만들거나 CommerceService를 별도 인스턴스로 생성하지 않는다.

```lua
local Bridge = require(ServerScriptService.NightShift.Modules.RuntimeBridge)
Bridge.registerNPC(npcAuthority, npcTick)
Bridge.registerTraffic(trafficAuthority, trafficTick, trafficSnapshot)
local owners = Bridge.contexts()
local plan = Bridge.activityPlan(ownerUserId) -- {Contest, Demand} 또는 false
Bridge.submit(kind, context, payload, function(result) ... end)
```

| kind | payload / 의미 |
| --- | --- |
| `SelectNpcItems` | `{NpcId,Kind="Normal"|"Rich",OpportunityId=false|id}` → 선택 DTO의 SelectionId/Items 사용 |
| `CommitNpcSale` | 계약 sale `{TransactionId,NpcId,SelectionId,Kind,Items,OpportunityId}`; 실제 Checkout 이후 호출 |
| `OfferOpportunity` | `{Index=1..4}` → 동일 기회 ID/Sku/DueAt; 경로 길이로 사전 출발 보정 |
| `ObserveOpportunity` | `{OpportunityId,ArrivedAt,Outcome="Arrived"|"Miss"|"Blocked",Reason=false|code}`; 실제 도착/미판매/장애 기록 |
| `ForceDrop` | 계약 collision `{CollisionId,VehicleId,ObservedAt,ServerPosition,SafeDropCFrame,Speed}` |

`npcAuthority:validate(context,npcId,kind,"Browse"|"Checkout",opportunityId)`는 `{Ok,Code,Value}`를 반환한다. 서버 NPC registry의 소유 세대·종류·경로 순서·현재 위치·실제 계산대 도착을 검증해야 한다. 부자 RNG는 전문 서비스가 공유 확률 함수를 사용한다. 선택은 만료10초이며 실패 시 새 선택을 한다. `removeOwner(storeId,generation)`을 제공하면 Main이 퇴장 때 호출한다.

`trafficAuthority:validate(context,collision)`은 서버 소유 차량, RoadZone, 접촉/swept collision, 위치·거리8·이동속도, 안전 보도 raycast/바닥을 검증해야 한다. core의 시간/속도/cooldown만으로 실제 충돌이 입증되지 않는다. 모든 registry/tick/validator/callback은 yield 금지다. tick에서 submit한 경제 명령은 다음 큐 drain에서 실행되므로 관측시각 freshness를 보존한다. authority 미등록이면 판매/드롭은 fail closed다. `trafficSnapshot()`은 계약 Traffic DTO를 반환해야 한다.

## UI·World·Integrator·Review 후속

1. Integrator가 새 서버 ModuleScript 6개(OwnershipService, DemandGoalService, ContestService, SoloGameService, ServerUtil, RuntimeBridge)와 shared SoloStoreContract/SoloStoreProfile을 **실제 설치 manifest**에 추가하고 Main을 교체해야 한다. 이 작업에서는 manifest나 Studio를 수정하지 않았다. 기존 v1 GameService 기반 설치만으로는 새 Main이 부팅되지 않는다.
2. NPC/Traffic 전문 소스·authority 등록을 연결해야 자연 판매/실제 차량 드롭이 시작된다. 현재 소스 인계가 NPC 이동·신호·충돌 구현 완료를 뜻하지 않는다. 위 API와 파일 소유권을 기준으로 후속 담당이 연결한다.
3. UI는 CommerceState의 전체 v2 snapshot과 OwnerGeneration/ProfileEpoch/ProfileRevision을 사용한다. 개인 정보는 Self/Store, 다른 매장은 공개 Stores/공개 item만 있다. Items에 OrderId도 제공해 이미 materialize된 transit 주문을 중복 합산하지 않는다. Demand Waiting/false 시각, 오류/저장 상태, 대회 부문/비교불가를 처리해야 한다.
4. 야간 Action도 OwnerGeneration을 사용한다. SetReady의 RosterVersion은 해당 OwnerGeneration이다. InputShape는 OutageId와 Generation=OwnerGeneration이며 직원 role claim이 없다. 야간 snapshot은 SoloGameService:packet의 실제 형태를 UI가 대조해야 한다. Commerce Self에 현재 RoundId를 제공한다.
5. World는 기존 marker/경로 계약을 유지하고 실제 간판 글꼴/닉네임, 창고32칸 표현, 숨긴 staging 실패 정리, 안전 보관/드롭, truck 출차, Alarm을 엔진에서 확인해야 한다. 실제 신호/보행 지오메트리는 전문 월드 작업이다.
6. Review는 원자성·저장 실패·세대 재사용·R-A/R-B 기회 증거와 위 경계를 독립 검토한다. 시간에 쫓겨 미실행 검사를 통과로 바꾸지 않는다. 단계 완료 표식은 Moderator가 실제 파일·근거를 확인한 뒤에만 발행한다.

## 남은 실제 검증과 운영 상태

**미검증:** Main의 Roblox 실행/Remote 왕복, 실제 두 클라이언트·8인/9인 서버, NPC 보행·부자 출현·계산대 구매, 교통 신호·거리/raycast·실물 드롭, 실제 마지막 재고 경합, 실제 도난/경보, 모바일 UI, 실제 재접속/종료, 클라우드 저장·lease 장애, Source/Place 일치, 최종 rbxl 저장·해시·재열기. 기존 창고의 24개 실제 적재/경합/저장 미완료도 이월한다. 운영 Place MaxPlayers=8 확인도 별도다.

실제 광고 공급·수익·음성·상품 판매는 이번 서버 검사 범위가 아니다. 재미·기회 공정성·재방문 개선은 실측 전 가설이다. 승인되지 않은 공개 게시/실제 판매를 수행하지 않았다.

구독 확인: 공식 Codex 세션 rate_limits 기반 2026-11-01 02:10:55 KST 잔량24%, stopNew=false/stopActive=false. 새 모델·하위 워커를 배정하지 않았고 외부 API/계정 전환을 하지 않았다. 이것은 확인 시점의 관측이며 이후 계정 전체 지연 사용량까지 보장하지 않는다.
