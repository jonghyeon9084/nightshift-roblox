# 창고 통합·실제 검증 인계

NightShift-Integrator / 2026-11-01 KST. **로컬 창고 루프 검증 완료, 새 Place 저장 차단·전체 인수 미완료.** `warehouseAcceptanceComplete=false`, `releaseReady=false`. 완료 표식은 발행하지 않는다.

## 저장본과 정확한 증거 경로

- 새 Place 저장: **미완료**. 사용자 물리 Escape 입력으로 Computer Use가 중단되어 Save As를 실행하지 않았다. 예정 경로 `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\NightShift-warehouse-20261101-v1.rbxl`는 저장된 파일 경로가 아니다. 기존 Place는 보존했지만 최신 수정이 디스크에 저장되었다고 주장하지 않는다.
- 저장 UI 차단 전 마지막 검증 상태는 Edit다. Studio를 닫지 않았다.
- 종료 상태: **Edit**, 임시 probe 0개, Edit CommerceRuntime 자식 0개.
- 필수 JSON: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-verification.json`.
- 실제 플레이 원문: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\play.jsonl`.
- Studio 설치·다인·최종 Edit 원문: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\integration\events.jsonl`.
- 소스/설치 해시: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\integration\manifest.json`. 22개 Script/ModuleScript의 최종 파일 해시 일치. 설치 재실행 Changed=0 증거는 최종 이벤트에 별도 기록.
- 오프라인 결과: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\tools\integration\warehouse-server-offline.txt`, `warehouse-client-offline.txt`, `warehouse-world-offline.txt`, `warehouse-world-mock.txt` (동일 디렉터리).
- 단독 소유 확인: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\tools\integration\warehouse-ownership.txt`. 시작 당시 다른 게임 수정 그룹은 idle, 독립 읽기 검토만 활동. 종료 전 확인도 Integrator만 게임 통합 실행. runner/mission-control 수정 없음.

## 수정과 검토 반영

WR-01: BuildDeliveryTruck 설치 행·소스 hash·worldHash 연결. 실제 runtime PresentationKind=BuildDeliveryTruck, 두 안내면 OK 확인.

WR-02: 선반 폭12→8, 뒤판 Z=-9.7, 네 상품을 안쪽 2×2로 배열. 고정 Slot/마커 계약 유지. 8매장 엔진 assertion으로 왼쪽·중앙·후방 보호 통로 확인. 2인/손수레 실제 교행은 미검증.

WR-03/04: 집기 거리를 WarehouseDrop/Cargo/ShelfSlot 서버 기준과 통일, 창고 내려놓기 E 우선 동작 추가. 9.99/10/10.01 모의 경계9개와 E 회귀1개 통과, 실제 E 보관/꺼내기 수행.

WR-05/06: 트럭의 진행 방향 +X와 앞면 일치(실제 내적1), 정차 중에도 같은 방향. Cargo 중심 보존. 직접 안내면을 적재함 양측으로 이동. 차량은 비충돌 지상 하역 모델이며 탑승형 램프를 구현했다고 주장하지 않는다.

Baseplate/Spawn 보존. 지면 상단: 도로0.08, 광장0.16, 보도/서비스차로0.24, 연결0.32, 실내0.40, 창고표식0.46, 전면0.48, 측면0.56, RearWalk0.64, LoadingPad0.72. 원래 Baseplate 상단0·Spawn 상단1 유지. 내부 진열 뒤판/상품 외곽도 재배치. 실플레이 창고 수량 라벨과 표지 겹침을 발견하여 라벨 높이6→2.8, 크기·노출거리 축소.

공간/광고 독립검토 R1/R3는 자체 안내·빈 allowlist·협찬/영상 비활성으로 수용, 실제 협찬은 보류. R2는 마커 보존·안쪽 조작 지점·중앙 통로로 구현/검증 범위를 제한. 사무실 랙 옆 좁은 틈 및 냉장고가 있는 벽 쪽으로 향하던 기존 테스트 경로가 막혀, PC(-16,-14), 중앙 x=8 및 z=-14 통로로 수정했다. 이 경로 수정은 두 사람 교행 통과 증거가 아니다.

다인에서 새로 발견된 음수 Studio UserId: ProfileService, CommerceService 근무 명단, RankingService 검증을 **IsStudio + Memory** 조건에서만 허용. ID를 양수로 바꿔 사용자끼리 충돌시키지 않는다. DataStore 모드와 일반 실행에서는 계속 거절. 실제 클라우드 설정은 켜지 않았다.

## 실제 검사 결과

| 검사 | 결과·한계 | 근거 |
|---|---|---|
| 소스 설치 | 22개, 월드897 Parts/40 Lights, 8매장, 공식10면 | events.jsonl / manifest |
| 주문→트럭→창고→진열→판매 | Store01 실제 키·Humanoid 보행으로 성공. 상품/서버 상태 주입 없음 | play.jsonl의 warehouse cargo pickup/deposit/withdrawal/direct shelf placement/sale |
| 수량 보존 | 첫 주문4개: 1개 판매, 남은3개 트럭 회수 및12 환불. 최초240→224→231→243. 이후 최종 회차5개 직접 진열·5판매 | ordered/sale/floor physical traversal complete 및 최종 state |
| 입력/권한 | 수량0·5 BAD_REQUEST, 타 매장 NOT_MEMBER, 자기 PC 원거리 TOO_FAR, 거절 전후 재고/자금 동일 | actual boundary rejections |
| 성공 주문 중복 | 원래 요청의 캐시 OK만 반환, 같은 ID 변경 수량 REQUEST_ID_REUSED, 닫힌 근무/상품 재생성 없음 | successful order replay exact original generation |
| 용량24·다른 창고/마지막 재고 경쟁 | **모의 검사만**. 실제 24개 적재/2인 경쟁은 미완료 | WarehouseServer469 / 기존 Commerce 회귀 |
| 바닥 | 8매장 엔진 지면 겹침0. Store01 이동 프레임·실내·창고·후면·하역패드 관찰에서 깜박임 재현 안 됨 | floor-* PNG / runtime warehouse audit |
| 광고 | 공식 AdGui10, 런타임 managed LCD8+트럭2=10. 같은 Part/Face 중복0, 빈 허용이미지/소재, 자체 안내 | runtime warehouse audit / truck-live PNG |
| 정전/완주 | 직접 차단기 역할·도형 입력, 5판매, AdjustedClose, OutageResolution=Solo, 무료 Lobby 복귀. 지갑10/XP35 | outage role/outage resolved 및 마지막 state.LastResult |
| 최초180초 다인 프로브 | 실제2명·서로 다른2응답. 접속 {'-1': 26.860536399995908, '-2': 30.350211800076067}, 종료 46.905초. **프로필 LoadFailed였으므로 게임 진행 실패** | warehouse 180s actual multiplayer final |
| 새 오류 수정 후 제한 회귀 | PASS_ACTUAL_TWO_CLIENT_START. 실제2클라이언트 프로필·별도 매장 근무 시작만 검사. 초기 부팅 프로브 반복이 아니라 발견 오류에 대한 별도1회 회귀 | warehouse negative-user actual regression final |
| 저장/음성 | PlaceId0. DataStore handle 요청이 미게시 제한으로 실패. Memory 저장, 진짜 영속/음성통화 미확인 | platform limits |

오프라인은 엔진/네트워크 결과와 분리한다. Profile30 cases/487 checks, Studio ID12, WarehouseServer469, WarehouseWorld163, Commerce313, ServerCommerce179, Movement98, Delivery21/21, Progression53 통과. 클라이언트 기존76+신규10 검사를 수행했다. 월드 컴파일·AST·mock도 별도 통과. 초기 랙 통로 assertion의 회전 float 오차를0.001 허용하도록 수정했다. 루프 검사기의 너무 이른 snapshot·주문 종료/정전 전환 시점 때문에 실패한 시도는 JSON failedAttemptsPreserved에 그대로 남겼다. 도구 스크린샷이 오래된 검은 화면을 반환한 최초1장은 시각 통과 근거에서 제외하고, 실제 Studio 창을 활성화해 후속 화면과 대조했다.

## 미완료·미확인

전체 출시 기준은 충족하지 않는다. 현재 공유설정 TargetPlayers=16, SeatsPerStore=4, 실제 Place MaxPlayers=30. 최신1인1매장/8인 요구와 다르다. 직원/공동 소유 제거, 걷는 NPC 실제 구매, 창고·진열·업그레이드 영속저장, 교통/보행신호/차량 충돌 드롭, 재방문 경쟁 기능은 이 통합본에서 완료하지 않았다. 기존 상거래 주문·계산 판매를 자율 NPC 구현으로 표시하지 않는다. 옥상4개 모듈은 별도 산출물이며 이번 요청의 기존 공식10면 보존 범위에서 설치하지 않았다.

실제8인 부하, 모든8매장 물류 플레이, 모바일 터치, 2인 손수레 교행, 타인 창고/마지막1개 경쟁·도난 회수, 실제 클라우드 재접속·광고 공급/수익·음성통화 미검증. 공개 게시·실제 판매·유료 에셋/생성API·결제는 실행하지 않았다. 로컬 정상 루프 확인과 출시/경제/다인 모든 조건 합격을 구분한다.

## 후속 기획 3개 (독립 검토 전 제안)

1. **초보 물류 동선 표시** — 실제 보행이 사무실 랙 틈과 냉장고에 막혔다. PC 접근→중앙 통로→후문→창고 조작 지점의 얇은 비충돌 화살표/안내를 제안. 기대효과는 첫 배송 길 찾기 감소 가설. 완료조건: 고정마커/거리10 보존, 8매장 남북회전·손수레 동선 검증, 신규 플레이어5명 모두 끼임 없이 첫 입고 완료.
2. **가까운 물류 동작을 상단에 표시** — 트럭 앞 화면에 안내·재시도 버튼이 먼저 보이고 집기/진열이 아래 스크롤에 위치한 실제 PNG가 있다. 필요한 현재1동작과 배송 잔량/회수시간을 작은 고정 영역에 표시. 기대효과는 터치 조작 발견성 및 회수 전 하역률 향상 가설. 완료조건:320×568/568×320 실제 에뮬레이터에서 집기·보관·진열·오류가 가려지지 않고 기존 서버 권한 유지.
3. **초기 진열과 주문 시작 시점 검토** — 첫1개 진열 후 주문 타이머가 시작되어 나머지4개 운반 중 주문 만료가 발생했다. 운영자가 초기 진열을 마친 뒤 무료 영업 시작을 누르거나 첫 배송 중 완화하는 작은 안을 독립 비교. 기대효과는 첫 세션 실패/혼란 감소 가설. 완료조건: 결제/광고 없이5판매·정전·재시작 가능, 초회 준비 시간과 주문 만료 횟수 실측, 무한 무위험 수익/재고 복제 없음.

## 별도 스크린샷

- capture: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\1793462219959.png`
- capture: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\1793462287434.png`
- visual floor-interior-moving-a: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\floor-interior-moving-a-1793462351193.png`
- visual floor-interior-moving-b: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\floor-interior-moving-b-1793462351846.png`
- visual floor-warehouse-low: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\floor-warehouse-low-1793462353231.png`
- visual floor-rearwalk: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\floor-rearwalk-1793462356865.png`
- visual floor-loadingpad: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\floor-loadingpad-1793462358393.png`
- visual live delivery truck: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\truck-live-1793462675783.png`
- visual live delivery truck: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\truck-live-1793462835631.png`
- visual live delivery truck: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\truck-live-1793462916360.png`
- capture: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발\.setup\warehouse-integration\1793463187838.png`

공식 API 대조: https://create.roblox.com/docs/reference/engine/classes/StudioTestService (ExecuteMultiplayerTestAsync/EndTest). API 반환 성공과 실제 클라이언트 결과는 위에서 구분했다.
