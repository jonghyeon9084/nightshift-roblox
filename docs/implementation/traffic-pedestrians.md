# 교통·보행자 소스 및 오프라인 검사 인계

NightShift-Traffic / NightShift-TrafficPedestrians-RC / 2026-11-01 KST.

**소스와 오프라인 검사 결과를 Moderator 검토에 인계한다. Studio 설치·실플레이·최종 Place 저장은 미실행이며 `studioRun=false`, `releaseReady=false`, `warehouseAcceptanceComplete=false`다. 완료 표식은 발행하지 않는다.** 실제 소스를 실행한 모의 검사를 Roblox 플레이 성공으로 해석하지 않는다.

`warehouse-source-handoff.md`를 먼저 읽고 루트 AGENTS.md, 최신 release-target, game-brief, release-task-decisions의 DR01~12, 독립 release-scope-review, solo-store-contract, NPC/World 인계와 release-acceptance-matrix를 적용했다. 이전 2인 직원/16인 공동 매장 설계는 사용하지 않았다. `warehouse-integration.md`와 `.setup/warehouse-verification.json`의 이전 실제 창고 루프 증거·실패 기록 및 새 Place 저장 미완료를 확인했다. 해당 증거는 이번 교통 소스의 실플레이 증거가 아니다.

Computer Use/Studio/MCP 저장은 호출하지 않았고 Escape로 중단한 작업을 재개하거나 우회하지 않았다. 공개 게시·실제 판매·외부 메시지·유료 에셋·유료 API·추가 모델 작업 배정은 실행하지 않았다. 기존 공식 Codex 세션 rate_limits를 프로젝트 UsageBudget으로 확인했고 작업 중 확인값은 잔량22%, reserve10%, blocked=false/stopActive=false였다. 이는 조회 시점의 공식 집계이며 계정 전체 향후 사용량 보장은 아니다.

## 변경 파일과 소유권

배정된 `src/server/`와 이 문서만 수정했다. 다른 담당자의 선행 변경을 되돌리지 않았다.

| 파일 | 변경 |
|---|---|
| `src/server/Modules/TrafficGeometry.luau` 신규 | 유한 좌표·도로 영역 검사, 차량/플레이어 상대 이동의 연속 slab sweep |
| `src/server/Modules/TrafficService.luau` 신규 | 양방향 2대, 서버 위상·정지·횡단 점유, 충돌 증거/쿨다운, Bridge 연결, cleanup |
| `src/server/Modules/TrafficWorldAdapter.luau` 신규 | 실제 월드 마커/차량/신호 빌더, 서버 캐릭터 관측, 바닥 ray 및 상자 공간 검사 |
| `src/server/Main.server.luau` | Bridge.configure 다음 교통 생성/등록, NPC보다 먼저 tick, 종료 시 교통 cleanup |
| `src/server/Modules/CommerceService.luau` | 충돌 응답에 시각 기록, 60초 지난 응답 및 만료 쿨다운 정리. 기존 forceDrop 거래 경계 유지 |
| `src/server/tests/Traffic.spec.luau` 신규 | 실제 교통/NPC/경제 상태 머신을 fake 시간·월드로 실행 |
| `src/server/tests/TrafficWorld.spec.luau` 신규 | 실제 BuildWorld/BuildRoadVehicle/BuildTrafficSignals/adapter 실행, fake ray·yaw/AABB |
| `src/server/tests/Run-TrafficChecks.py` 신규 | 구문 컴파일·두 테스트 bundle 실행·원문 로그/입력 SHA256 기록 |
| `docs/implementation/traffic-pedestrians.md` 신규 | 이 인계 |

`src/server/.validation/traffic-*`는 생성된 로컬 검사 근거다. 기존 Run-SoloChecks를 재실행하여 그 기존 `.validation/solo-server-*` 결과도 갱신했다. shared/client/world/설치 manifest/worker-pool은 수정하지 않았다. 신규 모듈을 Studio에 설치하는 로더 작업은 Integrator 소유다.

## 구현된 흐름

### 서버 신호와 실제 모델 연결

- 공유 상한2에 맞춰 Compact/Van 각1대가 Route01/Route02를 반대 방향으로 움직인다. `BuildRoadVehicle.create/pose`를 실제 호출하며 별도 가짜 차량 표현으로 대체하지 않는다. 7파트 anchored/noncolliding/non-touch/non-query 모델이고 서버가 pose한다. 배송 트럭 모델을 교통 차량으로 등록하거나 물리적으로 밀지 않는다.
- 최대18 stud/s, 가속12, 제동 계산16, 갱신 최대20Hz다. 위치는 정지 중심 ±16에서 제한되어 11-stud Van 앞면도 정지선 ±10보다 0.5 stud 뒤다. 녹색 종료5초 전부터 신규 진입을 제한한다. 이미 정지점을 넘은 차량은 횡단 구간을 끝까지 빠져나간다. 실제 물리 차량 시뮬레이션이 아니라 서버 경로 이동이며, 최종 정지점 clamp가 안전 경계다.
- 경로 끝 ±195에서 모델을 제거하고 2초 후 같은 경로 시작에 재생성한다. 끝→시작을 충돌 sweep으로 연결하지 않으며 생성 tick에는 피격을 만들지 않는다. 길 위를 순간이동해 통과한 것으로 검사하지 않는다.
- 안전한 시작은 AllRedToVehicle3초다. 이후 VehicleGreen20→AllRedToWalk3→Walk12→AllRedToVehicle3 순환이다. 진입한 차량이 남으면 Walk 전 적색을 연장하고, 횡단 점유가 남으면 VehicleGreen 전 적색을 연장한다. 연장된 PhaseEndsAt도 신호 표현에 반영한다.
- 동일 서버 상태만 `BuildTrafficSignals.apply`와 공유 Traffic DTO `{Revision,Signals={{CrossingId,Phase,VehicleGo,PedestrianGo,PhaseEndsAt}}}`에 사용한다. 동시 녹색은 없다. 누락 빌더·마커 이동/교체·신호 속성 변조·차량 소실/물리 플래그 변경·표현 실패는 적색/차량 정지/새 보행 진입 거절로 고정한다. 자동 재시도 루프는 없다.

### NPC 보행

Main이 `registerPedestrianTraffic(traffic)`을 연결한다. 기존 실제 NPCShoppingService/NPCWorldAdapter의 인도→대기→횡단보도→매장 경로를 유지했다. Traffic이 NPC를 임의 직선으로 옮기거나 구매를 직접 호출하지 않는다.

`requestCrossing`은 현재 서버 시각, Cross01, Walk, 남은 시간(요청 이동시간+0.25초), 차량 구간 비점유, 월드 정상 상태를 확인하고 **반환 전에** NPC ID 점유를 등록한다. 중복 요청은 같은 점유 하나다. 점유 상한16, 잘못된 교차로/NaN/시간 부족은 거절한다. 점유를 시간만으로 만료시키지 않으므로 느려진 NPC 아래로 차량 녹색이 켜지지 않는다. NPC의 실제 도착/제거 경로가 releaseCrossing을 호출한다. 고장으로 점유 해제가 누락되면 차량 적색이 계속되는 안전 실패이며 통과로 숨기지 않는다.

기존 NPC 모듈의 보도/횡단 경로 검사와 장애 시 cleanup을 그대로 사용한다. 이번 서비스 결합 검사에서 빨간불 보도 대기→실제 Traffic 점유→횡단 완료 해제→실제 경제 모듈 구매까지 실행했지만, 이동 엔진은 fake다. 이전 NPCWorld 기하 검사 결과는 `npc-shopping.md`의 별도 근거이며 이번 실행으로 재검증했다고 주장하지 않는다.

### 충돌과 운반품

서버가 관측한 살아 있는 캐릭터와 기존 WorldAdapter 이동 예산 검사만 사용한다. 새 클라이언트 Remote/Touch 입력은 없다. 같은 캐릭터·최근 두 샘플·둘 다 RoadZone 내부·최소 이동속도2·차량/플레이어 상대 sweep·접촉 거리8 이하를 확인한다. 점프 높이/매장/보도 등 도로 영역 밖은 피격하지 않는다. 차량 최대속도와 dt 제한으로 긴 서버 지연을 순간이동으로 보상하지 않는다.

검증된 CollisionId/VehicleId/관측 시각/서버 위치/속도/안전 드롭 좌표를 짧은 서버 증거로 보관한 뒤 `Bridge.submit("ForceDrop",...)`를 통해 기존 CommerceForceDrop 서버 경계(`CommerceService:forceDrop`)로만 보낸다. Main의 단일 경제 큐에서 소유 세대·프로필 상태를 확인하고, authority가 전체 본문/현재 캐릭터/현재 도로 위치/0.25초 신선도를 다시 확인한다. 지갑·XP·업그레이드·진열/창고를 Traffic이 직접 쓰지 않는다.

2초 쿨다운은 차량 쌍 검사 외에 플레이어별로도 적용하여 다른 차의 연속 피격을 제한한다. 빈손은 무보상 no-op이다. 같은 CollisionId는 경제 모듈의 원 응답을 반환하고 다른 본문 재사용은 거절한다. 최근 응답은60초 보존 후 제거하며 그 뒤 옛 요청은 신선도/사라진 증거 때문에 재승인되지 않는다. Traffic 증거는0.25초 후, 플레이어 캐시는 현재 관측 집합으로, 만료 쿨다운은 tick에서 정리한다.

운반 중 Carried/TheftCarried만 기존 Recoverable 상태로 이동한다. 원소유권은 바뀌지 않으며 기존 회수·25초 만료 반환·퇴장/저장 장벽 정책을 사용한다. 현재 DropSafe 표식은 높이가 다른 가게 측 보도 끝에 있어, 표식에서 넓은 보도 방향으로1 stud 이동한 z=±16 위치를 raycast한다. 차도 경계±12 밖이고 실제 보도 지지면·정상 법선·상자 공간을 검사한다. 안전 바닥을 못 찾으면 기존 안전 보관 경로로 보존하며, 이는 실제 바닥 드롭 성공이 아니다.

## 실행한 명령과 결과

로컬에 이미 준비된 `tools/world/.validation/luau-0.745`를 사용했다. 다운로드·추가 설치·API 요청은 없다.

```powershell
python src/server/tests/Run-TrafficChecks.py
python src/server/tests/Run-SoloChecks.py
git diff --check -- src/server/Main.server.luau src/server/Modules/CommerceService.luau
./tools/Invoke-Node.ps1 -e "console.log(JSON.stringify(new (require('./tools/runner/usage-budget.cjs').UsageBudget)(process.cwd()).check()))"
```

| 검사 | 실제 실행 결과 | 근거 경로 |
|---|---|---|
| 교통 관련 소스 구문 컴파일 | exit0 | `src/server/.validation/traffic-checks.txt`, `traffic-report.json` |
| 기존 서버/NPC 회귀 + 실제 Traffic 서비스 | exit0, 서버546·NPC527·Traffic17341 assertions PASS | `traffic-services-tests.luau`, `traffic-checks.txt` |
| 실제 월드·차량·신호·adapter fake-engine 실행 | exit0, 2483 assertions PASS | `traffic-world-tests.luau`, `traffic-checks.txt` |
| 기존 서버·공유 회귀 | exit0, 서버546·공유291 assertions PASS | `src/server/.validation/solo-server-checks.txt`, `solo-server-report.json` |
| 변경 tracked 소스 whitespace | exit0, 오류 없음 | 위 git 명령으로 재현 가능 |

assertion 수에는 매 tick 반복 검사가 포함되며 실제 플레이 시나리오 수가 아니다. `traffic-report.json`에 실행 UTC, 각 입력 파일 SHA256, compile/test 종료 코드와 `studioRun=false`를 남겼다. Main은 컴파일했으며 Roblox에서 부팅하지 않았다.

주요 검사: 양방향 2대·3주기 이상·정지선/차로/속도·출입/재생성에 걸친 sweep 금지·두 녹색 불가·보행 점유 적색 연장·차량 점유 적색 연장·서버 지연 dt 제한·신호 실패·마커 이동·물리 플래그 변경·빌더 부재·바닥 공간 실패·서버 위치 위조/NaN·상점/새 캐릭터/잘못된 이동/정지 차량·쿨다운·빈손·운반품1회 이동·지갑/XP/업그레이드/개수 보존·도난품 원소유 보존·저장 장벽 경합·25초 반환·60초 receipt 정리·실제 NPC/Traffic 허가 연결·종료 반복 cleanup. 실제 월드의 트럭 경로는 z=±91, 교통 차로는 z=±6으로 분리됨을 생성 좌표로 검사했다.

초기 실패도 보존해 설명한다. 첫 월드 검사는 DropSafe ray가 일반 `Sidewalk` 대신 높은 `SideWalk`를 맞아 실패했다. 두 보도 종류를 허용한 뒤에도 남쪽 경계의 지지면/공간 문제가 남아, 경계에서1 stud 벗어나 실제 공간을 검사하도록 수정했다. fake 기하에도 회전 AABB를 적용했다. NPC+Traffic 결합 검사의 첫25초 관측은 시작 적색 후 첫 Walk/계산 완료까지 충분하지 않아 판매0으로 실패했고, 테스트 관측을40초로 늘려 실제 상태 전이를 끝까지 검사했다. 판매 상태나 시각을 강제하지 않았다. 위 PASS는 수정 후 재실행 결과다.

## 미검증과 후속 연결

**ROAD/DROP 실제 인수는 PENDING이다.** fake Instance/벡터/yaw/AABB와 fake Raycast/overlap은 Roblox 엔진 물리·복제·렌더·터치 성능을 증명하지 않는다. 기존 창고 저장 미완료와 최종 게임 인수 조건도 그대로다. 독립 코드 리뷰는 아직 받지 않았다.

Integrator 소유 후속:

1. 설치 manifest에 새 `TrafficGeometry`, `TrafficService`, `TrafficWorldAdapter`를 ServerScriptService.NightShift.Modules로 추가하고 변경 Main/Commerce 및 선행 RuntimeBridge/NPC 모듈의 소스 해시를 맞춘다. `BuildRoadVehicle`, `BuildTrafficSignals`, `BuildCustomerRig`를 ServerStorage.NightShift에 설치한다. world/설치 manifest 자체는 이번에 변경하지 않았다. 빌더 미설치 시 fail-closed로 NPC 판매도 횡단 전에 대기하므로 이를 명시적으로 확인한다.
2. 허용된 Studio 환경에서 신호3주기 이상, 두 방향 정지선·보행 점유/느린 횡단·차량 clear·신호 누락/모델 소실을 검증한다. 실제 NPC가 횡단보도/매장 동선을 걷고 진열 선택→계산→판매→퇴장을 하는지 화면/로그로 확인한다.
3. 실제 플레이어의 빈손/상품 운반/손수레2개/도난품, 매장·보도·점프·연속 접촉·캐릭터 재생성·저장/퇴장 경합을 확인한다. 바닥 상품이 보이고 회수 가능하며 지갑·업그레이드·총량이 보존되는지 대조한다. 여러 상품/여러 플레이어가 같은 안전 드롭 지점에 몰릴 때 표현 겹침과 회수 조작은 미검증이다.
4. 정상 트럭 배송 중 교통/보행, 8명·NPC최대16·차량2·트럭/상품 최대 부하의 실제 FPS/서버 시간/복제량/메모리와 모바일을 측정한다. 최대20Hz/소수 모델 설정만으로 모바일 성능 합격을 주장하지 않는다.
5. 허용 범위의 최종 저장·재열기·소스 해시·Edit 상태를 확인하고 release-verification에 실제 ROAD/DROP/SALE/TRUCK 결과를 기록한다. 이 목록은 Escape로 중단된 Computer Use/저장 재개 승인이 아니다.

Moderator/Review는 위 파일과 입력 해시·검사 원문을 확인한 뒤 소스 단계 표식 여부를 판단한다. 실플레이 이후 개선은 실제 발견 근거에 한정한다. 현재 확인된 후속 후보는 다중 드롭 지점의 회수 가시성과 지연 시 보행 대기 안내이며, 구현/게임 재미 효과를 검증했다고 표시하지 않는다.
