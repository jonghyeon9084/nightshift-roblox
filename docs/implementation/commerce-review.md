# 상거래 확장 독립 검토

2026-10-31 · NightShift-Review · 검토 완료, 발견 이슈 수정은 다음 통합 단계 담당. 이 문서는 게임·Studio 통과 판정이 아니다. 변경 파일은 이 문서뿐이다.

## 검증 범위와 실제 실행

- 읽은 기준: `AGENTS.md`, `docs/game-brief.md`, `docs/commerce-expansion-brief.md`, `docs/implementation/commerce-contract.md`, `docs/design/retention-plan.md`.
- 읽은 인계: `.setup/handoffs/{profiles,economy,delivery,world-commerce,server-commerce,ui-commerce}.json`. 인계자의 실행 기록과 이번 검토자의 실행을 구분했다.
- 실제 소스 대조: 서버 Main·Protocol·GameService·ProfileService·ProgressionService·CommerceService·DeliveryService·RankingService·WorldAdapter, 클라이언트 Main·CommerceClient·CommerceState·TrayView·LoadReporter, 공유 Config/CommerceConfig, BuildWorld/BuildBillboards, build-loader, advertising 문서와 관련 spec.
- **이번에 실제 실행:** 로컬 Luau 0.745로 `src/**/*.luau`와 두 월드 빌더 총 33파일 컴파일 성공. 현재 소스를 메모리에서 묶어 stdin/loadstring으로 실행하여 Profiles 29사례/476검사, Progression 53검사, Commerce 313검사, 서버 모듈 통합 179검사, Delivery 21사례, CommerceState 21검사, CommerceClient 15+36검사 통과. 별도 파일 생성이나 소스 수정 없이 require만 로컬 주입으로 대체했다. 최초 통합 하네스의 문장 연결 구문 오류는 하네스에서 바로잡은 뒤 위 완료 출력을 확인했다. `git diff --check -- src tools/world tools/integration` 통과.
- **실제 실행의 한계:** 위 검사는 가짜 저장소·시각·공간·엔진·UI를 이용한다. Main 이벤트 연결, 실제 Instance/raycast, Studio 플레이, 광고 렌더링, 실제 재접속/DataStore, 음성 연결, 모바일·스트리밍·16인 부하는 실행하지 않았다. 아래 추가 재현도 명시한 실제 함수와 모의 환경의 결과다.

## 수정 필요 문제

### CR-01 — 이동 허용 오차가 매 프레임 재충전되어 운반·도난 이동 검증 우회

- **severity:** P1 / 높음.
- **file:** `src/server/Modules/WorldAdapter.luau:172` (`sample`), `:202` (`check`), `:152` (`move`); 호출부 `src/server/Main.server.luau`의 drain.
- **재현:** `MaxSpeed=28`, `MovementSlack=4`에서 1/60초마다 3스터드씩 60회 이동하고 `sample` 호출 후 도착 PC에 `check`한다. 실제 함수 실행 결과 `distance=180 elapsed=1 configuredMax=28 result=OK`. 매 프레임 기준 위치를 갱신하고 오차 4를 새로 더하므로 지속적인 초과속도를 승인한다. 큰 순간이동도 새 위치를 기준으로 저장하여 직후에는 `INVALID_MOVEMENT`지만 2.1초 정지 후 `OK`가 됐다. 현재 경로에는 일반/도난 운반을 무효화하거나 마지막 정상 위치로 복구하는 처리가 없어 운반·도주 비용을 우회할 수 있다. 별도로 서버 `move`는 `invalidUntil=0`으로 초기화하여 계약의 재배치 후 2초 경제 입력 제한도 적용하지 않는다.
- **최소수정:** 정상 이동 기준을 유지하는 누적 시간창 또는 속도 예산으로 허용 오차가 매 프레임 증식하지 않게 한다. 비정상 이동은 단순 대기 후 새 위치를 승인하지 말고 메인 직렬 큐에서 운반/도난 반환과 정상 위치 복구를 처리한다. 승인된 서버 이동에는 `now + RecoveryGraceSeconds`를 설정한다.
- **검증:** 실제 `sample/check` + 가짜 벡터·Players·시각·raycast로 위 두 우회를 재현했다. 수정 후 30/60Hz 지속 초과속도, 단일 순간이동, 정상 이동/지연, 일반 운반·도난품·서버 재배치를 검사하고 Studio 다인 환경에서 확인한다. 실제 클라이언트 익스플로잇 실행은 하지 않았다.

### CR-02 — 저장 해제 응답 유실 뒤 같은 서버 재접속이 영구적으로 LeaseLost에 갇힘

- **severity:** P1 / 높음.
- **file:** `src/server/Modules/ProfileService.luau:220`, 특히 `:226`; `save` 실패 상태 전이 `:349`.
- **재현:** `load(1)` 후 `save(1,true)`에서 저장소는 데이터와 `Session=false`를 커밋하되 응답만 오류로 만든다. 재시도는 해제된 Session을 보고 `LEASE_LOST`를 반환한다. 이후 같은 ProfileService에서 `load(1)`을 호출하면 기존 `profile`이 있고 Released가 아니라는 이유로 저장소 재획득 없이 `get()`으로 빠진다. 실제 출력은 `persistedSession=false`, `SAME_SERVER_REJOIN result=LEASE_LOST`; 시각을 1000→2000으로 전진해도 동일했다. 안전한 덮어쓰기 거부는 유지되지만 이 사용자에게 같은 서버에서 영업 재진입 경로가 없다. 저장 데이터가 삭제된다는 주장은 아니다.
- **최소수정:** 기존 writer가 끝난 상태의 새 접속 load에서 LeaseLost 엔트리는 낡은 메모리 내용을 저장하지 않고 저장소 `UpdateAsync`를 통한 정상 획득 경로로 보낸다. 현재 저장 데이터·타 세션 잠금·새 epoch를 다시 검증하고, 로드 실패 시 기본값 대체는 계속 금지한다.
- **검증:** 실제 ProfileService + 커밋 후 응답 유실을 주입한 Memory 어댑터로 재현했다. 수정 후 응답 유실 release→동일 서버 재접속→지갑/XP 보존·새 epoch 획득, 타 세션 점유 시 거절, 오래된 writer 차단을 검사한다. 실제 클라우드 장애는 미실행이다.

### CR-03 — 재고가 적어 축소 생성된 주문이 인원 감소 때 오히려 커짐

- **severity:** P2 / 중간.
- **file:** `src/server/Modules/GameService.luau:156` (`newOrder`), `:351`/`:357` (`reduce`), `:271` (`completeOrder`).
- **재현:** 4인 점포에 진열 상품이 1개뿐이면 새 주문은 `required=1`, Line도 1개다. 이 주문 진행 중 1명이 떠나 3인이 되면 `reduce`가 새 target 2를 그대로 사용하여 `required=2`로 올린다. 유일한 Line을 판매해도 accepted 최대값은 1이어서 정상 완료할 수 없고 시간초과를 기다려야 한다. 실제 `reduce` 실행에서 `required=2 availableLines=1`을 확인했다.
- **최소수정:** 인원 감소가 기존 주문의 required를 증가시키지 않도록 `max(accepted, min(existingRequired, newTarget))` 등으로 제한한다. 이미 접수한 Line은 유지하고 불필요해진 미완료 Line만 기존 규칙대로 반환·취소한다.
- **검증:** 실제 `reduce`와 가짜 touch/completeOrder 후속 훅으로 불변식 위반을 재현했다. 수정 후 4→3인·재고 1개 조건에서 그 1개 접수로 주문 완료됨을 실제 GameService 통합 spec으로 확인하고, 기존 운반/Tray 반환·인원 감소 회귀를 검사한다. Studio 이탈 시나리오는 미실행이다.

## 요청 항목별 검토 경계

- 저장 원본 보존·cursor/epoch·보상 중복, 개인 Wallet과 OperatingCash 분리, 8점포 마지막 재고 경쟁, 취소/회수 환급, 도난 양쪽 보호·동일 상품 경쟁·기한·이탈 반환은 현재 모의 검사와 소스로 확인했다. 추가 확인된 수정 사항은 위 세 건이다. 이 결과가 모든 장애·실제 동시성을 보증하지 않는다.
- 8개 점포 설정/빌더/서버 초기화와 클라이언트 점포 목록 연결을 대조했다. 실제 8점포 로드·16명 성능을 통과로 처리하지 않는다. 장시간 누적 원장의 순회 비용도 실제 부하 측정 전 수치 판정하지 않았다.
- 무료 레벨 해금·손수레·프리셋, 결제 비활성·빈 상품 ID, 유료 능력치 우위 경로 부재를 소스에서 확인했다. 음성 없이 기존 Signal/정전 구간 공유·화면 상품/배송/도난 안내를 이용하는 경로가 있으며, 실제 무음 협동 완주는 통합 단계 검증 대상이다. 유지율·재미·수익은 retention-plan대로 가설이다.
- 광고: 생성된 각 AdSurface의 자식은 AdGui 1개이며 검증기가 추가 자식/SurfaceGui를 거절한다. BuildWorld의 SurfaceGui는 별도 안내 Part에 붙는다. 현재 생성 소스에서 같은 면 중복은 발견하지 않았다. 거리 16×9, 내부 8×4.5는 공식 범위이며 `EnableVideoAds=false`, 기본 fallback 유지, 비충돌·경로 분리, 외부 구매/보상/영상 실행 부재를 정적으로 확인했다. [공식 이미지 광고 규격·같은 면 제한](https://create.roblox.com/docs/production/monetization/immersive-ads#image-ads), [AdGui API](https://create.roblox.com/docs/reference/engine/classes/AdGui)를 이번 검토에서 직접 조회했다.
- 광고 빌더는 소유 Advertising 폴더를, 로더는 소유 namespace/월드 루트를 검사한 후 교체한다. 현재 소스에서 비소유 루트 삭제 경로는 발견하지 않았다. advertising 문서는 설치 수량과 실제 송출·수익을 구분하며 허위 수익 검증 주장은 없다. 게시자 조건도 [공식 자격 안내](https://create.roblox.com/docs/production/monetization/immersive-ads#publisher-eligibility)와 대조했다. 이번에는 광고 모의 검증기를 재실행하지 않았으며 해당 통과 기록은 작성자의 인계 기록이다. 실제 AdGui 상태·카메라 가림·외부 콘텐츠와 겹침·통행은 Studio 통합에서 확인해야 한다.

검토 작업은 완료했다. CR-01~03 수정과 관련 회귀/Studio 확인을 다음 통합 단계에 인계한다. 코드·Studio·구매·게시 변경은 수행하지 않았다.
