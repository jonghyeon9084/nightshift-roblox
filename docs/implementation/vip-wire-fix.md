# VIP wire 소스 통합 및 오프라인 검증

NightShift-Integrator / NightShift-VipWireFix / `rc_vip_wire_fix:7df20393-8d3a-4ce0-a610-10bae7c5c521`.

**소스 통합 및 아래 오프라인 검사 완료, Moderator 산출물 검토 대기. 준비 표식은 발행하지 않았다.** 새 독립 코드검토·최종 통합·PM 인계는 이번 실행에 포함하지 않았다. `studioRun=false`, `cloudRun=false`, `warehouseAcceptanceComplete=false`, `releaseReady=false`다. 과거 solo-store-ui attention, world-source-handoff 실패 기록, Escape 저장 중단은 수정/합격 전환하지 않았다.

## 사전 소유권·사용량 확인

- 2026-11-01 02:52 KST, `./tools/Invoke-Maestro.ps1 group-chat list --json`: 유일한 활성 그룹은 `0a07a815-0544-49b7-bb3d-6381581b01b0`, 상태 agent-working, NightShift-Integrator 참가자 세션 `group-chat-0a07a815-0544-49b7-bb3d-6381581b01b0-participant-NightShift-Integrator-fc987fb0-a2e6-4da1-bb37-d1f701294c07`.
- `.setup/worker-pool/state.json`에서 유일한 active는 `rc_vip_wire_fix`의 Integrator. 이전 서버/UI/World/NPC/Traffic 작업은 inactive 또는 명시적 waiting이며 활성 소스 소유자가 없음을 변경 전에 확인했다. 02:59 KST CLI 재확인도 같은 그룹만 active였다.
- `AGENTS.md`, `tools/usage-budget-policy.json`, release-target 및 solo-store-ui/server, npc-shopping, traffic-pedestrians, world-source-handoff, release-world-polish를 대조했다. 이후 NPC/Traffic 구현과 기존 도감 serializer를 중복 구현하지 않았다.
- 공식 `UsageBudget.check()` 결과 잔량21%, reserve10%, blocked=false/stopActive=false. 시작 표본 UTC `2026-10-31T17:52:06.696Z`, 후속 `2026-10-31T17:59:14.368Z`, source=`official-codex-session`. 새 모델/워커를 배정하지 않았다. 향후 계정 전체 지연 사용량을 보장한다는 뜻은 아니다.
- 쓰기는 지정 src/shared, src/server, src/client 및 이 보고서로 한정. Studio/Computer Use/저장 UI, 유료 API·구매·리셋·게시·판매 없음. 로더/worker-pool/준비표식은 변경하지 않았다.

## 변경 파일

| 파일 | 변경 |
|---|---|
| `src/shared/SoloStoreContract.luau` | 진행 DTO 검증과 CustomerEvents 계약·20초 TTL·32개 상한·문맥 키 |
| `src/server/Main.server.luau` | 서버 전용 EndNpcVisit 라우팅, 검증된 소유자의 최신 RoundId 적용 |
| `src/server/Modules/CommerceService.luau` | 사건명 보호, CustomerKind 분리, 방문/구매/퇴장 소유자 필터와 cursor·정리 |
| `src/server/Modules/NPCShoppingService.luau` | 실제 NPC 제거 시 EndNpcVisit 큐 제출 |
| `src/server/Modules/RuntimeBridge.luau` | 서버 전용 EndNpcVisit allowlist |
| `src/server/Modules/SoloGameService.luau` | CustomerEvents 직렬화 및 큐 처리 이후 서버 시각 사용 |
| `src/server/Modules/OperatorContent.luau` | 비공개 후보 생성·검증, 실패 보존, disabled 상태 게시 후 교체 |
| `src/server/Modules/WorldAdapter.luau` | 창고 24/32칸 좌표 설명과 1..32 정수 bin 방어 |
| `src/client/Modules/CommerceState.luau` | 공유 진행/사건 DTO 검증, 원자 적용, 문맥별 cursor 중복 제거 |
| `src/client/Modules/CommerceClient.luau` | 본인 Self 확인, 실제 부자 사건 표시, 회차/소유 문맥 및 TTL 처리 |
| `src/client/tests/SoloStoreUI.spec.luau` | 확정 진행/사건 DTO fixture 및 기존 149개 회귀 |
| `src/client/tests/run-solo-ui.py` | 공유 검사 주입 순서, 현재 계약 감사와 과거 attention 분리 |
| `src/server/tests/NPCShopping.spec.luau` | EndNpcVisit 경로 및 분리된 Kind 기대값 |
| `src/server/tests/WarehouseWorld.spec.luau` | LCD·트럭 양면 실패주입, 32칸 생성/비공개 staging/게시 검사 |
| `src/server/tests/VipWire.spec.luau` | 실제 서비스→직렬화→클라이언트 159개 검증 |
| `src/server/tests/Run-VipWireChecks.py` | 원본 bytes 고정, 결합 실행, 회귀 및 전후 SHA256 비교 |
| `docs/implementation/vip-wire-fix.md` | 이 보고서 |

생성 증거는 `src/server/.validation/vip-*`, 기존 solo-server/traffic 보고서·결합 소스·로그와 `src/client/.validation/solo-ui-*`다. 기존 작업자의 변경은 되돌리지 않았다.

## 확정한 전달 계약과 해결한 UI 차단

1. `_emit`은 extra를 먼저 복사한 다음 사건명 `Kind`/`EventType`와 소유자·세대·epoch·revision·시각을 서버 인수로 덮어 확정한다. 판매 계산용 내부 `Kind=Normal/Rich`는 R-A/R-B에 그대로 사용하며, 알림에는 `CustomerKind=Normal/Rich`로 분리한다. 이벤트 Units 배열을 네트워크에 노출하지 않고 정수 수량으로 직렬화한다.
2. `CustomerEvents={Cursor,Entries}`는 기존 Commerce snapshot에 포함한다. Entries의 필드는 `EventId,Cursor,Kind,CustomerKind,OwnerUserId,StoreId,OwnerGeneration,ProfileEpoch,RoundId,ProfileRevision,At,ExpiresAt,NpcId,Units,Revenue`다. Kind는 `NpcVisited`, `NpcSaleCommitted`, `NpcDeparted`만 허용한다. 방문은 실제 NPC registry가 진열대 Browse 도착·현재 위치를 승인했을 때이며 스폰/예정 방문을 도착으로 표시하지 않는다. 품절 방문은 방문/퇴장만 생성한다. 구매는 실제 원자 판매 커밋 뒤에만 발행한다.
3. 서버가 본인 UserId+StoreId+OwnerGeneration+ProfileEpoch+RoundId로 필터링한 최대32개/20초 사건을 반복 직렬화한다. 내부 사건 버퍼는 기존256개이며 커서 high-water는 별도로 보존한다. 버퍼 절단/TTL 만료 후에도 커서가 뒤로 돌아가지 않는다. 알림은 일시적 표현이므로 오래된/누락된 사건을 재생하지 않으며 돈·도감은 권위 있는 snapshot/프로필로 유지한다.
4. 클라이언트는 Player.UserId에 맞는 Self와 전체 사건 문맥·revision·TTL·사건명·수량·단조 커서·배열 내 중복 EventId를 검증한다. 패킷 전체가 유효한 경우에만 적용하고 이미 소비한 cursor는 재알림하지 않는다. 회차·매장·세대·epoch가 바뀌면 알림 문맥을 초기화한다. 실제 NPC 퇴장과 소유자 해제 시 정리하며 새 매장 소유자는 이전 사건을 받지 않는다. Main은 spawn 시점의 오래된 RoundId 대신 현재 유효한 소유자의 회차를 내부 알림에 사용한다.
5. Heartbeat 시작 시각보다 queue 처리 중 생성된 사건 시각이 나중일 수 있어 serializer 시각을 현재 서버 시각 이상으로 보정했다. 테스트에 오래된 tick 시각을 전달하여 정상 사건이 미래 사건으로 거절되지 않는지 확인했다.
6. `Self.RareDiscoveries`(SKU 배열), `UnlockedTools`(도구 ID 배열), `EquippedTool`, `Presets`(`{Index,Slots={{SlotId,Sku}}}` 배열), `RoundId`(ID 또는 false)는 기존 서버 실제 직렬화를 유지하고 공유 검증·UI fixture를 맞췄다. 임의 Notice는 계속 무시한다. 가짜 VIP 성공/상품도감/프리셋 보상을 만들지 않는다.
7. R-A 두 회차 목표/실판매 진척과 R-B 참가·부문·동점·비교불가·자연/Rich 점수 제외는 기존 실제 서비스 검사 및 UI 149개 회귀를 유지했다. 공유 schema protocol은2이며 서버·공유·클라이언트를 같은 해시 집합으로 설치해야 한다. 구버전 서버 snapshot에 필수 CustomerEvents가 없으면 새 UI가 적용하지 않는다.

실제 오프라인 실행에서 생성·수신한 구매 payload의 주요 필드(수작업 성공 fixture가 아니라 NPC scheduler→Commerce commit→SoloGameService 결과):

```text
Kind=NpcSaleCommitted
CustomerKind=Rich
OwnerUserId=1
StoreId=Store01
Cursor=13
Units=2
Revenue=14
```

이는 fake 이동·시계·저장소 환경의 실제 Luau 함수 출력이며 Roblox Remote 수신/실제 부자 출현 증거가 아니다. 전체 snapshot/계약 검사는 `VipWire.spec.luau`와 결합 소스에 있다.

## LCD·트럭 fallback 및 창고 32칸

- OperatorContent는 새 SurfaceGui를 Parent=nil, Enabled=false로 생성하고 label과 속성을 구성·검증한다. 성공 후보만 disabled 상태로 부모에 붙인 뒤 기존 renderer를 비활성화하고 새 renderer를 활성화·교체한다. 생성/label 생성/부모 연결 실패는 RENDER_FAILED이며 기존 동일 renderer를 보존한다. 기존 외부 AdGui/Decal 점유는 FACE_OCCUPIED로 거절한다.
- LCD 1면 및 실제 BuildDeliveryTruck 생성 양면에서 SurfaceGui 실패·TextLabel 실패·Parent 실패를 각각 주입했다. 실패 전후 기존 객체가 동일하고 면당 renderer1개, 정상 반복 바인딩 후도1개임을 실행 검사했다. fake Instance 결과이며 Studio 렌더 결과가 아니다.
- 기존 4열×2행×3/4단 좌표가 24/32칸을 이미 지원했다. bin1..32 정수 방어를 추가했다. marker 기준 x는 -2.25/-0.75/0.75/2.25, z는 ±0.75, y는0.8/2.3/3.8/5.3이다. 실제 item size1.2×1.4×1.2의 좌표 중복과 기존 창고 가로/깊이 경계를 검사했다. 32개 staging 생성·비공개 폴더·게시·용량 표시 및 저장 ID32개를 유지한 Commerce restore를 실행했다. 24칸 레벨로32개 복원은 거절된다.
- **창고32칸의 실제 플레이어 접근·거리/시야·상층 선택·8매장 회전/가시성·충돌·재접속 저장은 최종 Studio 미검증**이다. 번역 좌표/fake ray 검사로 실제 접근 합격을 선언하지 않는다.

## 정확한 재현 명령 및 결과

프로젝트 루트에서 설치된 로컬 Luau0.745를 사용했다. 다운로드·외부 서비스 호출 없음.

```powershell
python src/server/tests/Run-VipWireChecks.py
git diff --check -- src/shared src/server src/client
./tools/Invoke-Node.ps1 -e "console.log(JSON.stringify(new (require('./tools/runner/usage-budget.cjs').UsageBudget)(process.cwd()).check()))"
```

전용 실행기는 고정 bytes로 실제 서비스/클라이언트 및 실제 WorldAdapter/OperatorContent/트럭 결합 소스를 만들고 compile/run한다. 같은 실행에서 아래 회귀 명령도 실행하고 전체 입력의 전후 해시를 비교한다.

```powershell
python src/client/tests/run-solo-ui.py
python src/server/tests/Run-SoloChecks.py
python src/server/tests/Run-TrafficChecks.py
```

| 검사 | 최종 결과 |
|---|---|
| VIP 결합 compile/run | exit0 / 신규159 assertions PASS (선행 서버546·NPC527 포함 실행) |
| 창고·fallback 결합 compile/run | exit0 /317 checks PASS |
| UI | exit0 /149 assertions PASS, 정적10개 true |
| 서버·공유 | exit0 /546+291 assertions PASS |
| 교통 회귀 | exit0 /서버546·NPC527·교통17341·월드2483 assertions PASS |
| git diff --check | exit0, 기존 파일 LF→CRLF 안내만 있음 |

반복 검사의 assertion 수를 별도 실플레이 시나리오 수나 고유 검사 합계로 합산하지 않는다. Main/RuntimeBridge는 컴파일·호출 연결을 대조했지만 Roblox에서 부팅하지 않았다. 실제 엔진·Remote·터치·클라우드 검사는 없다.

검사 초기 실패도 구분한다. 첫 전용 실행은 Luau에 한글 절대 경로를 전달해 실행기 stderr 디코딩이 실패하여 상대 경로로 고쳤다. 다음 창고 fixture는 이전 테스트의 실패용 pose adapter가 남아 DELIVERY_FAILED였고, 이를 초기화했다. Parent 실패주입 변수의 선언 위치가 closure 이후여서 주입되지 않는 harness 결함도 수정했다. 위 결과는 모두 수정 후 새 실행이다. 과거 World의 fallback 소실 제품 실패를 성공으로 덮어쓰지 않았으며 수정된 현재 소스만 재검증했다.

## 해시 고정 증거

- 실행 시작 UTC `2026-10-31T17:59:51.117880+00:00`, 종료 UTC `2026-10-31T17:59:53.456398+00:00`.
- 전체 입력 71개 SHA256 비교: `sourceChangedDuringRun=false`, `changedSources=[]`, 모든7개 compile/run·회귀 결과 exit0. 문서 작성 직전에도 모든 입력의 현재 bytes와 보고서 해시가 일치함을 확인했다.
- 기준: `src/server/.validation/vip-wire-report.json`의 sourceHashesBefore/After 전체 목록, bundleSha256, results. 로그: `src/server/.validation/vip-wire-checks.txt`. 실행 소스: `vip-wire.luau`, `vip-warehouse.luau` (배포 대상 아님).
- 다음은 이번 변경 소스/검사 파일의 현재 SHA256이며, 이후 변경되면 이 검사 결과를 그대로 적용하지 않는다.

| 파일 | SHA256 |
|---|---|
| `src/shared/SoloStoreContract.luau` | `0490db26bcd5c7772afa14f889377d08b1184a4617f3a2cd7e045641c2407f9b` |
| `src/server/Main.server.luau` | `2fe6dadd18205b26e1f40c09d01d98a20381a8aa63c736d057a9f6eeb0fec347` |
| `src/server/Modules/CommerceService.luau` | `14b4325617d0a30e64f3940c69f88cb80633d7d8fa44b9ac69048b0c87ec38ee` |
| `src/server/Modules/NPCShoppingService.luau` | `5835fec5061377e7afd0635f402bc8b3e53c0184804efcc356513fc7b85a17c8` |
| `src/server/Modules/RuntimeBridge.luau` | `79a71429342bfb70d2ed991ca8f8d6d90b3a273f8c45e6d018a305b6a4b7a1b0` |
| `src/server/Modules/SoloGameService.luau` | `a1bbb7e0b3cd5d92611a8bad6a1959a2548a1df108336cec91eb1b8a3fe6b425` |
| `src/server/Modules/OperatorContent.luau` | `34b73931cec65a204374b61f53aaad98d692b7e868347cbd5ce7a14245e1283b` |
| `src/server/Modules/WorldAdapter.luau` | `c55cc421ef26f78c7457512ce4ce9ddf10c4c46df33b4191219df6c80abbcc62` |
| `src/client/Modules/CommerceState.luau` | `ea346e2eb953834f6d16c625e47f545f256070fc1ea6e649b68b230e18821da0` |
| `src/client/Modules/CommerceClient.luau` | `3be5511b6b96424e17a3f3dc9fb608a2d2d6caf5be91c13bc78d981d83a7f160` |
| `src/client/tests/SoloStoreUI.spec.luau` | `ca94b49e0a22601e3be3f6016d6654cac2624af1b8e5b40aa3787378aa8ef057` |
| `src/client/tests/run-solo-ui.py` | `487ad41c331e7467e8836dc67aba5764ed5c7b8bde0e5c0b7aef0a522c766c82` |
| `src/server/tests/NPCShopping.spec.luau` | `3190e18b988755b0fea85ddf52fde0f982668bc01bbf1647847c369385dbf5a3` |
| `src/server/tests/WarehouseWorld.spec.luau` | `e0e10a99916af24e3517b31917bb995da7dce93cf82cbfd2fa17d9eec4c3b60e` |
| `src/server/tests/VipWire.spec.luau` | `b73661738bf4ea997987a87e42e15b5a709164d53ba56ad89b9631cb36839150` |
| `src/server/tests/Run-VipWireChecks.py` | `3c46b551fac5e1b506fb443b110693dfa29a218d42ec81c19167e6f0d5229166` |

## 남은 실제 인수

새 독립 코드검토, 설치 manifest와 새 공유/서버/UI 해시 집합 동시 설치, 실제 2/8인 owner privacy·마지막 재고·퇴장/재접속, VIP 보행/품절/실판매·R-A/R-B, LCD/트럭 실제 양면 렌더, 창고32칸 접근·복원, 모바일/한글, NPC/교통 부하, cloud 저장과 최종 Place 저장/재열기·해시 일치는 미검증이다. loader 옥상/새 모듈 연결은 지정 쓰기 밖으로 변경하지 않았다. 광고 공급·공개 게시·실제 판매도 실행하지 않았다. 기존 Escape 저장 중단은 우회하지 않았다.

Moderator가 보고서·현재 소스·로그를 확인하기 전 준비 표식을 만들지 않는다. 이 결과는 과거 UI attention 해제나 releaseReady 승인 자체가 아니다.
