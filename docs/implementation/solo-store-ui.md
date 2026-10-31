# 단독 매장 UI 소스 인계 — 서버 계약 대조 후속

NightShift-UI / NightShift-SoloStoreUi-RC. 최신 검사 UTC: 2026-10-31T17:02:10.941512+00:00 (2026-11-01 02:02 KST 무렵, 09:00 기한 전).
**UI 소스·오프라인 준비 상태이며 단계 완료 표식은 보류한다.** Studio·실제 네트워크·실기기·cloud·최종 인수는 실행하지 않았다. 기존 창고 저장과 최종 인수는 계속 `warehouseAcceptanceComplete=false`, `releaseReady=false`다. 중단된 Computer Use·저장 재개 및 우회 없음.

입력은 적용 AGENTS.md, warehouse-source-handoff.md, docs/game-brief.md, docs/design/release-target.md, release-task-decisions.md(DR01~12), release-scope-review.md, release-acceptance-matrix.md, solo-store-contract.md, 현재 실제 서버 Main/관련 모듈이다. 지정 UI·검사·인계 파일만 수정했으며 서버·공유 계약은 읽기 전용으로 대조했다.

## 최신 소스 재검사 및 실행 중 변경 확인

Moderator의 해시 불일치 지적을 반영해 실행기를 보완하고 **현재 파일로 재실행**했다. 이 절의 실행/해시 근거가 이전 실행 시각과 해시를 대체한다. 기능 구현 범위·VIP 미연결·Kind 충돌·공유 DTO 미확정·실제 인수 보류는 그대로 유지한다.

- 시작 UTC: `2026-10-31T17:05:11.927657+00:00`.
- 종료 UTC: `2026-10-31T17:05:12.035727+00:00` (KST `2026-11-01T02:05:12.035727+09:00`, 09:00 기한 전).
- compile exit0 / test exit0 / **149 assertions PASS / 정적 검사10개 true**.
- 실행 전 소스14개를 원본 bytes로 고정하고, 동일 bytes로 Luau 결합 소스를 생성했다. 실행 직후 같은14개 경로의 SHA256을 다시 읽어 대조했다. **변경0개, sourceChangedDuringRun=false, changedSources=[]**. 보고서 `sources`는 실행 전 값이며, `sourceHashesBefore`/`sourceHashesAfter` 양쪽을 함께 보존한다. 변경이 감지되면 성공 종료하지 않으며 자동 재시도하지 않는다.
- `Main.server.luau`와 `CommerceService.luau`는 실행 경로/계약 **소스 대조용**이다. 이를 실제 서버 실행으로 표시하지 않는다. 실제 실행한 SoloGameService/DemandGoalService/ContestService와 의존성 모의, 클라이언트 Main의 compile/정적검사 범위는 보고서 `sourceUse`에 나눠 기록했다. bundle SHA256도 함께 남겼다.
- 계약 대조 JSON도 **같은 실행에서 같은14개 입력 해시**로 갱신했다. 별도의 나중 시점 해시를 이번 통과 근거인 것처럼 합치지 않았다. 현재 소스에서 SoloGameService 진입점/v2/도감 배열/Notice 미발행/extra.Kind 복사 가능성을 다시 읽어 확인했다. 단순 문자열 확인은 런타임 이벤트 동작 검사와 구별한다.
- 이번 수정 파일은 `src/client/tests/run-solo-ui.py`, `docs/implementation/solo-store-ui.md`와 생성 근거4개(JSON2/로그/결합 Luau)다. UI 런타임·서버·공통 계약은 변경하지 않았다.
- 공식 Codex 세션 rate_limits 기준 잔량25% 확인, 새 워커 배정 없음. Studio·실제 네트워크·실기기·중단된 창고 저장·최종 인수는 실행하지 않았으며 계속 미완료다.

담당별 미완료: 공유 계약 담당은 Self.RareDiscoveries/UnlockedTools/EquippedTool/Presets/RoundId 확장과 VIP wire schema/cursor를 확정하고, Server는 `_emit`의 사건명 Kind와 손님 Normal/Rich 종류 충돌을 해결하고 본인에게만 전달해야 한다. NPC 담당은 실제 부자 방문/판매 사건을 연결한다. UI는 확정 전의 Notice를 수용하지 않으며 임의 성공 알림을 만들지 않는다. Review/Integrator 실제 검증과 최종 파일 인수는 별도다. **VIP 미완료이므로 단계 완료 표식 보류를 유지한다.**

## 이전 보고 정정과 현재 실행 경로

첫 인계는 133 assertions/정적8개를 통과했고 당시 조회한 GameService의 v1을 연결 차단으로 보고했다. 후속 조사 중 서버 파일이 갱신되었다. 현재 `src/server/Main.server.luau:17`은 `modules.SoloGameService`를 require하며 `service:commercePacket`과 `service:ack`를 호출한다. 이 서비스는 **ProtocolVersion=2**다. 남아 있는 옛 `GameService.luau`의 v1 함수가 현 Main의 실행 서비스라는 주장은 더 이상 적용하지 않는다.

이 사실은 실제 서버 Remote 플레이 성공을 뜻하지 않는다. 이번 검사는 현재 실제 직렬화 함수의 출력만 의존성 모의 객체를 통해 실행했다. 서버가 작업 중이므로 검증 JSON·계약 대조 JSON에 기록한 SHA256 버전으로만 판단한다.

## 변경 파일

| 경로 | 현재 구현 / 이번 후속 수정 |
| --- | --- |
| `src/client/Main.client.luau` | 직원·공동입장 제거한 단독 HUD. 자동배정 대기/닉네임/돈/레벨/저장/다음행동, 한글 메뉴·back·48px 버튼·PC Q/터치 prompt·키보드·스크롤. **후속:** 야간 요청 RoundId도 최신 Commerce Self에서 읽고, 새 SoloGameService에 없는 ClaimRole/ShareSegment/ReleaseRole/RenewRole를 제거. SharedShapes/Generation/CanInput을 사용해 표시판 근처 순서 확인→차단기 직접 InputShape로 교체. |
| `src/client/Modules/CommerceState.luau` | v2 스냅샷/revision/소유권 일치 검증, 세대 전환 private reset, 7필드 요청, 물류 용량 집계, 순수 화면 크기 계산. 이번 후속에서는 변경 없음. |
| `src/client/Modules/CommerceClient.luau` | 개인 지갑 발주/유보·직접 물류·성장·R-A/R-B·저장·경보·교통. **후속:** context.RoundId를 Self.RoundId로 수정해 독립 야간 스트림 지연에 의한 STALE_ROUND 방지. RareDiscoveries를 실제 서버 SKU 배열로 한정하고 유효 SKU 중복 제거. 장착은 실제 UnlockedTools와 레벨 둘 다 확인. 프로필 미준비의 빈 Achievements도 오류 없이 표시. Departed/Pending 한글 안내. 소유 문맥 변경 시 과거 매출 알림 초기화. 미확정 packet.Notice 처리를 제거하고 VIP 이벤트 연결 대기 표시. |
| `src/client/tests/SoloStoreUI.spec.luau` | 현재 **149 assertions**. 실제 SoloGameService:commercePacket/ack, Demand:view/prepare, Contest:view/finalize를 실행하는 오프라인 연동 사례 추가. |
| `src/client/tests/run-solo-ui.py` | 실제 서버 직렬화 모듈 결합·실행, 사용 서버 소스 SHA256 추가, 폐기 역할 제거·최신 회차 사용 정적 검사 추가. |
| `src/client/tests/Run-CommerceChecks.ps1` | v2 suite 진입점. 이번 후속에서는 변경 없음. 선택 LuauBin 인수 유지. |
| `docs/implementation/solo-store-ui.md` | 이 문서로 기존 인계를 갱신. |

새 런타임 ModuleScript는 추가하지 않았다. 기존 CommerceClient/CommerceState 설치 경로를 그대로 사용한다. 과거 v1 Commerce*.spec 및 기존 레이아웃 검사를 모두 통과한 것으로 주장하지 않으며 v2 suite가 현재 commerce 검사다. 타 워커 소스/Studio/로더는 수정하지 않았다.

## 파일·함수·필드 대조

| 기능 | 실제 서버 소스 → UI | 현재 상태와 담당 후속 |
| --- | --- | --- |
| v2 Snapshot/Ack | Main의 SoloGameService require → `SoloGameService:commercePacket` / `:ack` → `CommerceClient:receive/bind`·`CommerceState.apply` | 실제 함수 출력의 오프라인 적용 PASS. Self.OwnerGeneration/ProfileEpoch/ProfileRevision/RoundId, ProfileStatus, Store, Carry/Theft, Wholesale, Demand/Contest, Traffic가 해당 경로다. 실제 Remote 미검증. |
| R-A | `DemandGoalService:prepare/view` → `CommerceService:view`의 Demand → `SoloGameService:commercePacket` → `CommerceClient:render` goals | CycleId/Phase/Eligible/Reason/Targets[].Sku,Required,Sold/Completed/ReserveUntil/EndsAt/NextTargets 사용. 실제 view는 **NextTargets=SKU 문자열 배열**이며 UI가 이를 표시한다. 실제 prepare→view 두 회차 회전/진행 출력 오프라인 PASS. 실제 판매·유보 ledger의 경제 보존·기한 경합은 서버/Review/Integrator 담당. |
| R-B | `ContestService:setParticipation/view/finalize` → CommerceService:view.Contest → SoloGameService:commercePacket → goals | Prepare 참가만 활성, Scores 3부문, Rows, Results.Comparable/Reason/Winners, NextOpportunityAt 사용. 종합점수·경제 보상 없음. 개인/비교불가는 순위 없음, 비교가능 공동1위 모두 표시. 실제 serializer 출력·참가·finalize 오프라인 PASS. 실제 동등기회/NPC/결제/영구 실적은 미검증. |
| 상품도감 | `CommerceService:commitNpcSale`가 p.RareDiscoveries에 SKU 삽입 → `SoloGameService:commercePacket` Self.RareDiscoveries → profile 탭 | 현재 소스에는 SKU 배열 전달 경로가 존재하며 실제 serializer→UI 오프라인 PASS. 예전 “서버 도감 미전달”은 현 경로에 적용하지 않는다. 단 **공유 문서 필수 Self DTO에는 이 확장이 미기재**다. 계약 담당이 기존 구현의 RareDiscoveries/UnlockedTools/EquippedTool/Presets/RoundId를 공식 DTO로 기록할 필요가 있다. UI가 공유 계약을 임의 변경하지 않았다. |
| 매출 | `SoloGameService:commercePacket` Stores[].Sales/Revenue → Client:receive | 본인 매장 확정 누계 증가만 일반 매출 갱신으로 표시. NPC 종류는 누계로 추론하지 않음. 세대/프로필 문맥 전환 시 이전 누계 초기화. |
| 부자 손님/VIP | `CommerceService:commitNpcSale` → `Service:_emit` → 내부 events[] | **미연결.** SoloGameService:commercePacket에는 Notice/Events/VIP/NpcKind 필드가 없고 Main에도 해당 이벤트 전달 경로를 확인하지 못했다. UI는 연결 대기만 표시한다. 공유 담당이 owner-scoped wire 필드/이벤트·cursor·TTL·중복 정책을 확정하고 Server/NPC가 실제 방문/구매 사건을 발행해야 한다. |
| VIP 이벤트 타입 충돌 | CommerceService:_emit의 `Kind=kind` 초기화 후 `for k,v in pairs(extra)` 덮어쓰기; commitNpcSale이 `event.Kind=sale.Kind`를 extra로 전달 | **서버 수정 필요.** 현재 `_emit("NpcSaleCommitted",...,event)`의 최종 Kind가 Normal/Rich로 덮일 수 있다. 내부 사건명과 손님 종류 필드를 구분하고 wire allowlist를 확정할 것. `event.Units`는 배열이나 commit 결과 Value.Units는 수량이므로 네트워크 표현도 담당자가 명시해야 한다. UI는 임의 스키마/변환을 확정하지 않는다. |
| 야간 | `SoloGameService:packet/action`의 Outage.SharedShapes/Generation/Progress/CanInput → Main renderNight / InputShape | 예전 역할 분배 Remote는 삭제. 현재 서버 출력과 맞춰 직접 입력하도록 수정했다. 컴파일·정적 연결만 검증, 실제 복구 동선·안전한 근접 안내·SetLoaded·재시작은 Studio 미검증. |
| 신호/경보 | Stores[].Alarm.ItemId/RecoverUntil, Traffic.Signals → Client render | 필수 DTO 표시 경로 유지. Main의 host.trafficSnapshot 연결과 실제 월드/안전 드롭은 전문 담당·Integrator 검증 필요. |

VIP에 대해 이전에 제안한 packet.Notice는 확정 계약이 아니었다. 이번에는 처리 코드를 제거했고, 그 임의 필드를 넣은 모의 패킷이 VIP 구매로 표시되지 않는 회귀검사를 추가했다. 현재 실제 도감 배열은 명확한 소스 근거가 있으므로 유지했다. 전문화는 DR12대로 보류 표시이며 새 보너스/저장 기능을 추가하지 않았다.

## 실행 검사와 증거

재현: `python src/client/tests/run-solo-ui.py` 또는 `powershell -NoProfile -ExecutionPolicy Bypass -File src/client/tests/Run-CommerceChecks.ps1`.

- 최종 compile exit0, test exit0, **149 assertions PASS**, 정적 검사 **10개 true**. UTF8/중앙 Remote/구매 호출 없음/PC prompt/직원·폐기 역할 제거/키보드/back/회차 근거 포함.
- 실행 종류: `OFFLINE_PURE_LUAU_AND_CONTROLLER_MOCKS_WITH_REAL_SERVER_SERIALIZERS`. 실제 서버 Luau 함수(직렬화/수요·대회 계산)를 실행하되 Profiles/Ownership/Commerce 상태·월드·Remote·UI는 모의 객체다. 경제 서비스 통합이나 Roblox 실행이 아니다.
- 기존 133개 검사 범위에 실제 현 서버 DTO 적용, 실제 Ack 필드, 독립 야간 스트림보다 최신 Commerce RoundId, 실제 NextTargets 문자열 배열·두 회차 교체, 실제 도감 배열·미준비 빈 상태, 미확정 VIP Notice 무시를 추가했다. 전액 지갑/재고·pending·거리·소유권·동점·비교불가 회귀 유지.
- 390×844/390×300/320×568/800×360/1920×1080 화면 크기 계산과 48px 버튼 검사를 유지했다. 패널 계산 결과는 각각366×760/366×276/296×544/440×336/440×760. 한글 실제 렌더·safe inset·터치·포커스는 실기기 미검증.
- 후속 첫 실행은 프로필 실패 fixture에서 이전 정상 revision을 유지한 상태로 새 Revision0 패킷을 넣어 마지막 assertion이 실패했다. reducer의 stale-profile 거절을 확인하고 **새 접속의 빈 UI 상태·미배정 Store=false**로 fixture를 수정했다. 이후 최종149 PASS. 실패를 숨기거나 reducer 검증을 약화하지 않았다.
- `git diff --check -- src/client/Main.client.luau src/client/Modules/CommerceClient.luau src/client/tests` exit0.

정확한 근거:

1. `C:/Users/HP/Documents/ChatGPT/로블록스 게임 개발/src/client/.validation/solo-ui-report.json` — 실행 종류·149 검사 exit·정적10개·클라이언트/공유/실제 서버 소스 해시.
2. `C:/Users/HP/Documents/ChatGPT/로블록스 게임 개발/src/client/.validation/solo-ui-checks.txt` — 최종 compile/검사 로그.
3. `C:/Users/HP/Documents/ChatGPT/로블록스 게임 개발/src/client/.validation/solo-ui-bundle.luau` — 실제 실행한 오프라인 결합 소스, 배포 대상 아님.
4. `C:/Users/HP/Documents/ChatGPT/로블록스 게임 개발/src/client/.validation/solo-ui-contract-audit.json` — 읽기 전용 소스 계약 대조·필드/함수·미연결 소유자·관측 소스 해시.

## 미완료 및 인계

- **공유/Server/NPC:** 위 VIP transport·Kind 충돌·Units 표현·중복 정책 확정 및 실제 owner 사건 전달. 기존 도감/도구/회차 확장을 공유 DTO에 기록. 이 작업에서 서버/공유 파일은 수정하지 않았다.
- **Review:** UI와 현 v2 서버 계약, 소유권·개인정보·저장·대회/수요의 실제 경제 연결·부자 추가량/공정성 검토. 자체 검사로 독립 검토를 대신하지 않는다.
- **Integrator:** 최종 모듈 설치 후 실제 2인/8인·PC 권한·발주→하역→창고→진열→NPC→돈·도감·목표 두 회차·대회 동등기회·VIP·교통/도난/회수·단독 정전·저장실패/재접속·실제 한글/터치/해상도 검사를 수행해야 한다. 현 소스 출력 연동 PASS만으로 실제 플레이/저장/출시 완료라 하지 않는다.
- **이전 저장/최종 인수:** 중단된 창고 Place 저장, 실제 적재/경합 잔여, 최종 rbxl 저장·해시·재열기는 계속 미완료. Studio/Computer Use/저장 우회를 실행하지 않았다. 게시·상품판매·유료 API/에셋도 실행하지 않았다.

공식 usage-budget checker의 공식 Codex 세션 rate_limits 기준 01:59 KST 잔량25%, 추가 워커/모델 배정 없음. 잔량20/15/10 보호 규칙을 유지한다. 이 보고는 파일/근거 확인을 요청하는 인계이며 완료 표식을 발행하지 않는다.
