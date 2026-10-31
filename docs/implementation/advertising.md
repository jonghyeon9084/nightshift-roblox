# 거리·매장 내부 이미지 광고판

2026-10-31 사용자 요청에 따라 Roblox 공식 `AdGui`를 사용하는 광고판 생성기를 구현했다. **광고 면 설치 코드이며 실제 광고 송출·수익 발생은 아직 검증하지 않았다.**

## 배치와 플레이 경험

- 도로변 간판 2개: 서쪽 `(-180,18,-32)`, 동쪽 `(180,18,32)`. 면은 16×9스터드이며 도로를 향한다.
- 각 매장 오른쪽 내벽의 포스터형 광고 1개: 해당 매장 `GetPivot()` 기준 `(27.75,10,6)`, yaw -90도, 면 8×4.5스터드. `Stores`의 실제 매장 Model에서 위치를 계산한다. 현재 8매장이면 거리 포함 **광고 면 10개, Part 28개**다.
- 계산대·진열대·출입구·사무실 및 트럭 경로와 분리한다. 광고판은 비충돌이며 게임 진행에 필요한 안내를 덮지 않는다. 실제 카메라와 야간 조명에서의 자연스러운 배치는 Studio 통합 때 확인한다.
- 이미지 광고만 사용한다(`EnableVideoAds=false`). 강제 시청, 광고 시청 보상, 영상 자동재생, 광고 포털·외부 이동은 없다. 상품 선점·도난 성공률·랭킹에 영향을 주지 않는다.
- 외부 에셋을 내려받지 않고 Part로 직접 만든다. 광고 미배정·비대상 이용자는 Roblox의 기본 대체 이미지를 사용한다. 별도 광고 추적·외부 API·유료 에셋을 사용하지 않는다.

## 설치와 소유권

`tools/world/BuildBillboards.luau`를 `ServerStorage.NightShift.BuildBillboards` ModuleScript로 설치한다. require 자체는 월드를 변경하지 않는다.

```lua
local ads = require(game.ServerStorage.NightShift.BuildBillboards)
local result = ads.build(candidateWorld)
assert(result.Ok, result.Reason or result.Code)
-- result: Ok, Code, Folder, AddedParts, PartCount, AdUnits, Reused
```

`build(worldModel)`은 정상 설치된 소유 폴더를 재사용한다. `rebuild(worldModel)`은 검증한 새 광고 폴더로 교체하고, `validate(worldModel)`은 기존 광고 구조를 확인한다. 실패는 `Ok=false`와 이유를 반환한다. 소유권과 `CommerceLayoutVersion=2`를 확인한 `NightShiftWorld` 안의 `Advertising` 폴더만 다루며 매장·사용자 콘텐츠는 변경하지 않는다.

`tools/integration/build-loader.cjs`는 Config·CommerceConfig·BuildWorld·BuildBillboards를 설치하고 후보 월드에 광고판을 추가한다. 광고 부품까지 전체 예산을 재검증한 뒤 Edit 모드에서 월드를 교체한다. 생성 실패 시 이전 월드는 유지하며 설치 오류를 보고한다. 로더 결과 `AdUnits`는 광고 면 수이며 광고 노출·매출 집계가 아니다.

## 확인한 검사와 남은 검증

```powershell
./tools/Invoke-Node.ps1 tools/world/verify-billboards.cjs tools/world/.validation/luau-0.745
```

2026-10-31 실제 로컬 실행 결과: Luau 컴파일, 광고 면 규격, 도로·트럭 경로 분리, 내부 작업 마커 간격, 외부 서비스 부재, 모의 Instance 기반 멱등성·재생성·소유권·API/parent 실패 처리·기본 대체 이미지·이미지 전용·매장 변환 검사 통과. 출력은 `OFFLINE_COMPILE_GEOMETRY_AND_MOCK_NOT_STUDIO`, `10 ad units / 28 parts`였다.

Roblox 실제 Instance 생성, AdGui 상태·렌더링, 카메라·조명·스트리밍, 모바일·다인 성능, 게시자/플레이어 적격성, 광고 수요와 실제 수익은 미검증이다. 후속 `commerce_review`와 `commerce_integration` 프롬프트에 검토·설치·플레이 검증을 연결했다.

## 수익화 활성 조건

공식 문서 확인일은 2026-10-31이다. 실제 송출에는 공개 경험, 제작자 13세 이상·ID 인증·2FA, 연령/콘텐츠 설문 승인, 월 고유 방문자 2,000명 등 Roblox의 자격 조건이 필요하다. 조건 충족도 광고 배정이나 수익을 보장하지 않는다. 현재 개발 단계에서 게임 게시, 계정 설정, 광고 송출 승인이나 판매 설정을 수행하지 않았다.

공식 근거: [Immersive ads](https://create.roblox.com/docs/production/monetization/immersive-ads), [AdGui API](https://create.roblox.com/docs/reference/engine/classes/AdGui).
