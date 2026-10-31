# 사무실 주문·직접 물류·창고 UI

2026-11-01 / 담당 NightShift-WarehouseUI / Moderator 검토 대기.

## 변경 파일

- `src/client/Main.client.luau`: 기존 OfficePC ProximityPrompt 재사용, Q·터치로 주문 탭 진입. 상시 HUD는 재고 조회와 사무실 이동 안내. 줄바꿈된 라벨·버튼의 높이 자동 확장.
- `src/client/Modules/CommerceClient.luau`: PC 근처·활성 상태에서만 주문 수량/주문/취소 조작 표시. 멀어지면 조회 전용으로 전환. 전송 직전에도 자기 PC 거리와 근무 상태를 검사해 이전 버튼 콜백 차단. 기존 프리셋 PC 동작에도 같은 검사 적용. 서버 거절 사유 한국어 보완. 직접 물류 단계·상품별 창고 수량·빈 창고·공유 용량 안내.
- `src/client/Modules/CommerceState.luau`: 서버 Store DTO만 읽는 `storage` 요약 함수 추가.
- `src/client/tests/CommerceState.spec.luau`: 창고 SKU 합계·소유권·예약량·빈 상태·남은 용량 검사 5개 추가.
- `src/client/tests/CommerceClient.spec.luau`: PC 이탈 후 이전 콜백, HUD/탭 접근, 비활성 단계, 빈 재고, 서버 거리 거절 등 10개 검사와 Moderator 보완 근거 13개 추가.
- `src/client/tests/Run-WarehouseLayoutChecks.ps1`: 실제 Main의 layoutPanel 소스를 추출해 작은 화면에서 실행하고 스크롤·자동 높이·PC 키보드/터치 연결을 확인.
- 이 문서.

기존 작업 트리의 변경은 보존했다. Studio·서버·공유 계약·world·runner 파일은 수정하지 않았다. 신규 리모트·자동입고·자동진열·클라이언트 경제 권한·판매 기능은 추가하지 않았다.

## 사용 흐름과 계약 대응

HUD의 재고 V는 어디서든 조회를 제공한다. 자기 사무실 PC의 기존 Prompt에 접근해 Q 또는 모바일 Prompt를 터치하면 도매 탭이 열린다. Q는 전역 V 페이지 토글 및 상품 E 동작과 충돌하지 않도록 선택했다. 주문 가능 조건은 기존 활성 근무·프로필·자기 Store/Round 일치 및 공유 Interaction.Distance(현재 10 studs) 이내다. 근처라도 시야·이동·실제 예산/회차 한도 등 최종 판정은 서버가 한다. PC를 벗어나면 다음 UI 갱신(기존 0.25초 주기)에 주문·취소 조작이 사라진다. 그 전에 이전 콜백이 실행되어도 send에서 다시 검사한다.

주문 후 배송 상태와 도착/회수 시간을 기존 Orders DTO로 표시한다. 상품 탭은 트럭 짐칸에서 집기 → 창고 앞 내려놓기 → 창고에서 꺼내기 → 선반 앞 직접 진열을 안내한다. 기존 PickCargo/PickWarehouse/DropWarehouse/PlaceShelf만 사용하고 기존 ItemRevision·CarryToken·SlotId를 그대로 보낸다. E는 가까운 활성 동작에 배정되고 터치 버튼도 유지한다. 진열 이후 손님 주문 집기·계산은 기존 근무 화면을 사용한다.

별도 창고 용량 필드는 없다. `CommerceService:_size`와 실제 view를 읽고, 자기 점포의 비종료 Items 수량 + Reserved 주문 수량을 점포 전체 사용량으로 요약한다. 배송 중 주문은 이미 Truck Items로 표현되므로 예약량에 다시 더하지 않는다. 타 점포 소유 상품과 Sold/Recalled/Expired는 제외한다. 상품별 Warehouse만 창고 보관 수량에 합산한다. 추가 보관 가능은 `Wholesale.MaxItemsPerStore`(현재 24)에서 전체 사용량을 뺀 값이며 창고 전용 빈칸 수가 아님을 명시한다. 이미 운반 중인 상품을 창고로 이동할 때에는 추가 공간을 쓰지 않는다. Store 미수신을 빈 창고로 표시하지 않는다.

OrderStock은 기존 Wholesale.Revision을 사용한다. 요청 및 ack는 재고·자금·보관량을 수정하지 않으며, 기존 CommerceState 서버 패킷 수신 후만 반영한다. ack 성공은 ‘서버 승인·상태 갱신 대기’, 실패는 거절 이유를 표시한다.

## 실제 실행한 검증

프로젝트 루트 PowerShell, 기존 `src/client/.validation/bin` Luau 도구 사용. 외부 API/다운로드 없음.

```powershell
$warehouseLuauBin = (Resolve-Path src/client/.validation/bin).Path
./src/client/tests/Run-CommerceChecks.ps1 -LuauBin $warehouseLuauBin
./src/client/tests/Run-StaticChecks.ps1 -LuauBin $warehouseLuauBin
./src/client/tests/Run-WarehouseLayoutChecks.ps1 -LuauBin $warehouseLuauBin
git diff --check -- src/client
```

| 검사 | 실제 결과 | 범위 |
| --- | --- | --- |
| Commerce 컴파일·reducer 분석 | 통과 | Main/Commerce 모듈/spec 구문, CommerceState 정적 타입 |
| CommerceState | 26개 통과 | 신규 창고 합계 5개 포함 |
| CommerceClient | 15 + 36 + 2 + 10 + 13 = 76개 통과 | 기존 transport/도난 회귀/거리·손수레 + 신규 창고 UI + Moderator 근거. 마지막 13개는 실제 near 함수·reducer에 fake 월드/전송을 적용 |
| Commerce 소스 계약 검사 | 통과 | 기존 14 actions, 중앙 Remote 전송, 런타임 연결, 구매/음성 API 제한 |
| 기존 UI 검사 | 16 + 19 + 18 = 53개 통과 | StateStore/TrayView/LoadReporter, 컴파일·순수 모듈 분석·기존 22 action 계약 검사 |
| 작은 화면 | 17개 assertion + 4개 소스 guard 통과 | 실제 layoutPanel 함수에 fake 화면/UDim2 적용. 320×568, 568×320, 360×640, 640×360에서 패널 범위·최소 터치 행 공간·본문 폭·가로 화면 notice 접기·접힌 패널 확인 |
| diff 공백 검사 | 종료 코드 0 | 기존 TrayView CRLF 안내만 출력, 해당 파일은 이 작업에서 수정하지 않음 |

첫 Commerce 검사에서 신규 요약 함수의 strict 타입 추론 오류를 확인해 DTO 배열에 `{any}` 타입을 명시한 뒤 위 검사 전체를 통과했다. 레이아웃 검사 첫 실행의 Luau 한글 절대 경로 열기 오류는 기존 검사기처럼 작업 디렉터리 내 상대 경로 실행으로 수정한 뒤 통과했다.

## Moderator 요청 보완 근거

후속 요청에 따라 위 세 PowerShell 검사 명령을 전부 다시 실행했다. 최종 결과는 CommerceState 26개 + CommerceClient 76개 = 102개, 기존 UI 53개, 작은 화면 17개 및 소스 guard 4개 모두 통과다. 최초 보고의 89개에서 실제 공간 판별·확정 응답 근거 13개를 보완했다. 후속 작업은 `src/client/tests/CommerceClient.spec.luau`와 이 문서만 수정했다. 이 작업 전체 수정 파일은 앞 절의 7개가 전부이며, `TrayView.luau`와 `Run-CommerceChecks.ps1` 등 작업 트리에 이미 있던 변경/미추적 파일은 이 워커의 수정 목록에 포함하지 않는다.

### 자기 PC·이탈·조회 우회 검사

실제 판별은 `CommerceClient.luau:29`의 LegacySelf.StoreId 문맥, `:117`의 `NightShiftWorld/Stores/<StoreId>/OfficePC` 조회와 HumanoidRootPart 거리 비교, `:126`의 StoreId/RoundId 활성 일치, `:187`의 자기 점포 ID 전달로 연결된다. `:90` send에서도 자기 문맥 StoreId로 다시 검사한다. 클라이언트 안내 제한이며 악의적인 클라이언트에 대한 최종 권한 검증은 기존 서버 소유다.

`CommerceClient.spec.luau`의 다음 assertion 이름으로 실행했고 모두 통과했다.

| assertion 이름 | 확인 내용 |
| --- | --- |
| `OwnPC.NamedStoreLookup` | 실제 near 함수에 자기 PC x=0, 타 점포 PC x=100, 플레이어 x=100인 fake 월드 트리 적용. 타 점포만 가까운 경우 구별 |
| `OwnPC.ForeignPCDispatch` | 위 위치에서 주문·취소를 send에 직접 호출해도 Remote 전송 수 증가 없음 |
| `OwnPC.ForeignPCView` | 위 위치에서 도매 탭을 직접 렌더해도 주문·취소 컨트롤 없음 |
| `OwnPC.DistanceInclusive` / `OwnPC.DistanceOutside` | 공유 거리 10은 허용, 10.01은 차단. 실제 near 함수 실행 |
| `OwnPC.AtOwnPC` | 자기 PC 위치로 이동하면 근접 판별 참 |
| `OwnPC.MissingMarker` / `OwnPC.NoCharacter` / `OwnPC.NoMembership` | PC·캐릭터·소속이 없으면 근접 판별 거짓 |
| `leaving PC blocks stale order and cancel callbacks before next render` | 근접 렌더 때 저장한 주문·취소 콜백을 거리 이탈 후 실행해도 전송 없음 |
| `distant HUD/tab view contains no ordering controls` | 열린 도매 화면 재렌더에서 주문·취소·수량 조작 제거 |
| `distant view clearly directs player to office PC` | 조회 전용 이동 안내 표시 |
| `keyboard/touch tab navigation cannot expose distant order controls` | 상품 탭에서 도매 탭 콜백으로 돌아와도 원거리 주문 조작 없음 |
| `server distance refusal stays readable without spending` | TOO_FAR 실패 ack를 기존 연결 이벤트에 전달, 한국어 사유 표시·자금 유지 |

‘화면 닫기’ 대신 ‘열린 화면을 조회 전용으로 전환하고 조작 제거’를 채택했다. 첫 9개 OwnPC 검사는 near를 스텁하지 않고 실제 함수를 실행한다. 이탈/탭 검사는 fake 거리와 실제 render/send를 사용한다. 실제 Main의 HUD 클릭·키보드 이벤트·Prompt 엔진 동작은 Studio 미검증이며 탭 콜백 단위 결과와 구별한다.

### 서버 DTO·확정 반영 위치

- `CommerceClient.luau:38` receive → `CommerceState.luau:12` apply: Snapshot/Delta의 기존 Self/Wholesale/Store 등을 Sequence·Revision 검사 후 처리. `CommerceState.luau:37`에서 전달된 slice만 교체하며 Delta 누락 slice는 유지한다.
- `CommerceClient.luau:64` ActionResult 수신: ProtocolVersion·pending RequestId를 확인한 뒤 pending 해제, 성공/거절 안내와 상태 조회 예약만 수행한다. 재고·운영자금·아이템 수량은 변경하지 않는다. 오류 한국어 매핑은 같은 모듈 상단 `errors`이며 미등록 코드는 `요청 거부: <Code>`로 표시한다.
- `CommerceClient.luau:90` send: 기존 DTO 봉투 생성·pending 기록·단일 FireServer만 수행한다. `OrderStock`은 Wholesale.Revision, 물류는 ItemRevision·서버 CarryToken을 전달한다. 주문 수량 선택 값은 요청 입력이며 확정 재고가 아니다.
- `CommerceState.luau:57` storage: 현재 서버 Store.Items/Orders만 읽어 수량을 계산한다. ack나 주문 입력값으로 보관 수량을 증감하지 않는다.
- 신규 `Authority.Pending`, `Authority.SuccessAck`, `Authority.SuccessAckMoney`, `Authority.StatePacket` 4개 모두 통과: 창고 집기 요청 후 Item Quantity/State 유지 → 성공 ack 후에도 유지, 자금·도매 재고 유지 → 이후 새 서버 Delta Store가 왔을 때에만 창고 Items 교체를 확인했다.

작은 화면 결과는 실제 레이아웃 함수의 수학적 배치와 소스 연결 확인에 한정된다. Roblox 글꼴 측정·자동 높이 실제 렌더링·터치 조작·기기 안전 영역 통과로 해석하지 않는다. 관련 명령·화면 크기·확인 범위는 위 실행 표에 기록했다.

## Studio 미검증 및 통합 확인 항목

Studio 조작은 Moderator/Integrator 소유이므로 이 워커는 실행하지 않았다. 위 결과는 Roblox 엔진 렌더링이나 실제 서버 플레이 통과를 뜻하지 않는다.

- 자기 PC Q/터치로 도매 탭 열기, 타 점포 PC에서 자기 주문 불가, PC 밖 조회 전환 및 이탈 직후 클릭 차단.
- 실제 트럭 Docked Cargo 접근 → 집기 → WarehouseDrop 보관 → 꺼내기 → 진열 → 손님 판매 전체 흐름과 서버 ack/상태 지연.
- 벽 뒤 시야 거절, 출발 직전 취소 경쟁, 동시 주문으로 재고/용량이 바뀌는 경우 서버 거절 안내.
- 실제 모바일 에뮬레이터에서 한국어 글꼴의 AutomaticSize 높이·긴 상품명·스크롤·터치 Prompt·조이스틱 가림·안전 영역. 수학적 레이아웃 검사로 글꼴/실기기 터치를 확인하지는 못한다.
- 실제 네트워크·다인원·저장·음성은 미실행.

Moderator가 변경과 검증 기록을 검토하고 Studio 통합 확인을 이어가야 한다. `[STAGE_READY:WAREHOUSE_UI]` 표식은 워커가 발행하지 않는다.
