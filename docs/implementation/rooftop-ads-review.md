# 옥상광고 4개 독립 검토

검토자: NightShift-Review / NightShift-RooftopAdsReview. 검토일: 2026-11-01 00:52~00:55 KST. 기준은 `AGENTS.md`, `docs/design/release-target.md`, `docs/implementation/release-acceptance-matrix.md`의 ADS·SHOP·FLOOR·DELIVER다. 8명·1인 1매장을 적용하며 폐기된 직원/공동 소유 기획을 승인하지 않는다.

**결론: 검토 산출물은 준비됐지만 ADS 실플레이 합격은 보류한다.** 통합 로더 누락과 지붕에 의한 시야 차폐를 먼저 해결해야 한다. 소유 월드 확인 및 재사용 시 표시 상태 검증도 보강이 필요하다. 코드는 수정하지 않았다. Studio 조작·게임 게시·실제 판매·외부 에셋 구매·유료 API 호출은 수행하지 않았다.

## 1. 검토한 소스와 증거 범위

줄 번호는 아래 스냅샷 기준이며 병렬 작업 이후에는 해시와 함께 대조한다. 최종 재확인 중 다른 작업자의 로더 트럭 모듈 연결과 월드 변경을 발견하여 00:55 소스를 다시 읽었다. 옥상 모듈 누락과 지붕/간판 좌표는 그대로이며 아래 해시는 재확인한 버전이다.

| 파일 | SHA-256 |
|---|---|
| `tools/advertising/BuildRooftopBillboards.luau` | `BE680A0A382FA44FE73BCC6CDE5B78BA6D7D19665BFB19FC0F6171DA333DBC8A` |
| `tools/integration/build-loader.cjs` | `85E0BF38043B8C0F19CD7D5790EFAE132799117EFA4CE46FD754183F2D730B04` |
| `tools/world/BuildWorld.luau` | `985D742177423BA4C5A0D633207A5AA9F5BF231A947D728F27F64014936A2379` |
| `src/shared/CommerceConfig.luau` | `978206B511D2FFF206BE5F9FF85F3928C64E78FABAFEEBF617046AE96D05B349` |

추가로 `tools/world/BuildBillboards.luau`, `tools/integration/advertising-audit.luau`, `docs/implementation/rooftop-ads.md`, `docs/implementation/advertising.md`, `docs/design/advertiser-content.md` 및 기존 모의 prefix/tests/bundle을 읽었다. 기존 보고서의 PASS를 Studio 결과로 전환하지 않았다.

## 2. 항목별 판정

| 항목 | 정적·모의 확인 | 판정과 남은 확인 |
|---|---|---|
| 좌표 | 빌더 7, 70~75행은 Store01/03/06/08 Pivot의 로컬 (-12,0,0), 지붕 상단+6.5로 면 중심을 계산한다. BuildWorld 131행 Roof 상단은 Y=19. CommerceConfig 34~41행의 양쪽 행에 2개씩 배치된다. | 계산 일치. 실제 설치는 R1로 미확인. 아래 좌표표 참조. |
| 방향 | 빌더 75, 92, 97, 100행: Pivot yaw에 180도를 더하고 Front면을 사용하므로 매장 로컬 +Z를 향한다. CommerceConfig 북쪽 yaw=0, 남쪽 yaw=180과 일치한다. | 도로 방향은 정적으로 맞음. Studio 앞/뒤 렌더 미검증. |
| 가독성 | 빌더 95~103행: 16×9 면, 영상 false, notice 흰 글자/짙은 배경/TextScaled. 지붕 중앙 배치 때문에 지상 시선 차폐가 계산됨(R2). | 문제 발견. 화면 가독성·야간·모바일·카메라 거리 미검증. 비충돌/무그림자는 시각 차폐 해소 증거가 아님. |
| 입구·하역·표지 간섭 | 빌더 86행 전 부품 Anchored, CanCollide/CanTouch/CanQuery=false. 로컬 광고 구조 범위 X=-20.4~-3.6, Z=-0.3~0.3, Y=19~30.4. BuildWorld 132~150행 입구 Z=24, 간판 중심 Y=15.5/Z=24.8, 사무실 표지 Y=7/Z=-23; CommerceConfig 47~48행 하역 X=23/Z=-30, 도킹 Z=-39. | 정적 부피상 직접 겹침 없음. 실제 보행·운반·카메라·새 월드 객체와의 간섭은 미검증. |
| 소유권 | 빌더 12~13, 116~119, 184~186행은 별도 소유 RooftopAdvertising 폴더와 중복을 검사한다. 기존 Advertising은 교체 대상이 아니다. 그러나 getStores 15~29행은 월드 이름/타입만 확인한다(R3). | 폴더 보호 모의 통과, 월드 소유권 보호 부족. StoreId는 배치 식별자이며 플레이어 매장 소유 권한을 부여하지 않는다. |
| 반복 설치 | 빌더 113~170, 206~209행: 면/프레임/지지대 좌표·개수·물리 설정·모드를 검증하고 정상 시 AddedParts=0/Reused=true. 이동·크기 변경·모드 변경 모의 통과. | 구조 재사용 통과, 표시 내용/Enabled/fallback 변조 검사는 부족(R4). |
| 기본 fallback | 빌더 96~103행은 ad와 notice를 분리하고 ad의 fallback 값을 지정하지 않는다. notice는 자체 문구만 사용한다. 외부 이미지 ID/가짜 협찬/영상 재생 로직 없음. | 초기 생성 의도 확인. 실제 기본 이미지/빈 소재 렌더 미검증. 변경된 fallback이 재사용되는 문제는 R4. notice 전환은 명시적 모드 전환이며 ad 실패 시 자동 전환 기능은 없음. |
| 실패 격리 | 빌더 172~204행: pcall→Ok=false/ROOFTOP_ADS_ERROR, 후보 생성 실패 파괴, commit 검증 실패 후보 파괴·기존 이름 복원. 기존 광고 보존 및 두 실패 주입 모의 통과. | 모듈 수준 격리 확인. 호출부의 핵심 게임 로딩 지속·예산·저장본 반영은 R1 및 Studio 재검증 필요. |

### 계산된 네 면 중심

| 매장 | 월드 중심 (X,Y,Z) | Front 법선 | 기준 지붕 상단 |
|---|---|---|---|
| Store01 | (-132,25.5,-52) | +Z | 19 |
| Store03 | (28,25.5,-52) | +Z | 19 |
| Store06 | (-28,25.5,52) | -Z | 19 |
| Store08 | (132,25.5,52) | -Z | 19 |

이 값은 현재 CommerceConfig와 BuildWorld에서 도출한 기대값이며 Studio 측정값이 아니다. BuildWorld 336~347행은 legacy Config의 배치를 CommerceConfig로 덮어쓰므로 폐기된 4매장 좌표를 사용하지 않았다. CommerceConfig의 기존 TargetPlayers=16/SeatsPerStore=4 잔존은 최신 요구와 불일치하므로 별도 solo-store 계약 통합에서 해소해야 하며 이 광고 검토가 해당 값을 승인하지 않는다.

## 3. World/Integrator 후속 수정

### R1 — P1: 통합 경로에 옥상광고가 없음

- 대상: Integrator 소유 `tools/integration/build-loader.cjs:7~25,74~93`, `tools/integration/advertising-audit.luau:6~27`.
- 근거: manifest와 worldSources에 BuildRooftopBillboards가 없다. 후보 빌드는 BuildBillboards만 호출하고 BuildAdUnitCount는 그 결과만 저장한다. 감사 스크립트는 `w.Advertising`만 순회하고 10면을 assert한다. `rg -n 'BuildRooftop|RooftopAdvertising' tools/integration src`도 매칭 없음. 별도 수동 Studio 설치 유무는 확인하지 않았다.
- 수정 방향: 모듈 manifest·소스 해시·후보 설치 및 동일 해시 재설치 경로에 연결한다. 실패 결과를 구조화하여 기록하고 옥상광고 실패로 주문/재고/이동 로딩을 중단하지 않는다. 실패한 광고를 완료로 집계하지 않는다. 설치 후 전체 부품 예산을 재검증한다. 기존 감사 10면 검사는 유지하고 옥상4를 별도로 감사한다.
- 재검증: ad 성공 시 거리2+옥상4=외부6, 내부 공식8, 총 AdGui14를 구분하여 기록한다. notice는 옥상 안내면4/옥상 AdGui0으로 구분한다. 기존 공식10면 보존, 28 Parts 추가, 두 번째 설치 AddedParts=0, 실패 주입 시 핵심 로딩 유지와 오류 보고, 최종 저장본 소스 해시 일치를 실제 Studio에서 확인한다.

### R2 — P1: 옥상 중앙 배치가 지상 시선에서 지붕에 가려짐

- 대상: World 소유로 조율할 `tools/advertising/BuildRooftopBillboards.luau:34~75,95~110`; 필요 시 `tools/world/BuildWorld.luau:131~142`.
- 근거: 광고 앞면은 매장 로컬 Z≈0.2이고 지붕 전단은 Z=25, 상단 Y=19다. 광고 상단 Y=30을 향한 중앙 시선을 계산하면 카메라 (X=-12,Y=5,Z=52)에서 지붕 전단의 시선 Y≈17.98로 지붕보다 낮다. 인접 인도 Z=30~40에서는 더 낮다. 따라서 해당 지상 시점에서 위쪽까지 막히는 배치다. 두께를 생략한 중앙면 근사이며 실제 카메라/엔진 결과는 아니다. 반대쪽 인도 Z=64~72에서 윗부분 시선은 지붕을 넘지만 전체 면 가독성을 보장하지 않는다.
- 수정 방향: 광고와 지지대를 도로 쪽 지붕 가장자리 안으로 옮기거나 필요한 시선 여유를 확보한다. 과도한 높이보다 보행 시점에서 읽히는 배치를 우선한다. 하드코딩된 footprint 판정(58,64행)도 새 위치/크기에서 유도하여 좌표와 검증값이 분리되지 않게 한다. 입구 간판·차양·다른 광고와의 간섭도 재검토한다.
- 재검증: 네 매장 각각 가까운 인도·도로 중앙·반대 인도·입구에서 서 있는 캐릭터의 실제 카메라로 앞면 전체와 문구를 확인한다. 낮/밤·PC/모바일·기본/축소 카메라 거리의 스크린샷 및 가림 객체를 기록한다. 강제 시청이나 AlwaysOnTop으로 건물 위에 광고를 덧그려 문제를 숨기지 않는다.

### R3 — P2: 소유하지 않은 같은 이름의 월드에도 설치 가능

- 대상: `tools/advertising/BuildRooftopBillboards.luau:15~29`.
- 근거: getStores는 `NightShiftWorld`라는 이름과 Model만 요구한다. 보조 모의 검사에서 `NightShiftOwned=false`인 월드에 build가 Ok=true를 반환했다. 기존 BuildBillboards 57~60행은 NightShiftOwned 및 CommerceLayoutVersion=2를 검사한다.
- 수정 방향: 동일한 월드 소유권/지원 배치 버전 전제를 명시하고 검사한다. 기존 폴더의 Owner 속성 검사를 유지한다. 실제 클라이언트 권한 취약점을 입증한 것은 아니며 편집 설치기의 외부 월드 오수정 방지 문제다.
- 재검증: 소유권 false/누락·잘못된 버전·같은 이름 외부 폴더·중복 폴더에서 Ok=false, 원본 객체·이름·자식 불변. 올바른 8매장 소유 월드에서는 최초/반복 설치 성공.

### R4 — P2: 재사용 검사가 빈 안내/비활성 광고/변경 fallback을 허용

- 대상: `tools/advertising/BuildRooftopBillboards.luau:96~103,156~165,206~209`.
- 근거: notice는 SurfaceGui 클래스만 확인하여 TextLabel을 지워도 Reused=true다. ad는 클래스/Face/EnableVideoAds만 확인하여 Enabled=false 및 변경된 FallbackImage를 그대로 재사용한다. 세 경로를 모의 실행으로 재현했다. 초기 생성에서 실제 광고 이미지를 설정하는 코드는 없다.
- 수정 방향: 허용된 표시 상태와 자체 안내 문구를 명시적으로 생성·검증한다. 프로젝트가 기본 fallback만 허용한다면 새 AdGui의 기본값을 기준으로 검사하거나 오염된 GUI를 재생성한다. 임의 운영자 이미지를 공식 fallback으로 채택하지 않는다. AdShape/Enabled 등 중요한 설정도 엔진 기본값에만 의존하지 않도록 명시하고 실제 엔진에서 대조한다.
- 재검증: notice 문구 삭제/빈 문자열, GUI 비활성, fallback 변조 후 build가 복구 또는 명시적 오류를 반환한다. 새 생성과 모드 왕복 모두 한 면에 하나의 renderer만 존재하고 기본 콘텐츠가 보인다. 광고 공급 성공과 안내 렌더 성공을 별도 기록한다.

## 4. 이번에 실행한 검사

모든 실행은 로컬 오프라인이다. 지정 문서 외 파일을 생성·갱신하는 기존 Python 생성기는 실행하지 않았다. 아래 명령의 출력과 보조 재현을 이 문서에 보존한다.

1. 현재 빌더 소스+기존 prefix/tests 조합과 기존 bundle 내용의 완전 일치 검사: PASS.
2. 현재 빌더의 `luau-compile.exe` 컴파일: 종료코드 0.
3. 일치 확인한 기존 bundle을 `luau.exe`로 실행: 14개 PASS, 종료코드 0.
4. 같은 bundle에 메모리상 보조 검사를 붙여 REPL stdin 실행: 중복/비소유 동일 이름 폴더 거절 PASS; R3 1건과 R4 3건의 검증 누락 재현. 이는 결함 재현 성공이며 제품 합격이 아니다.
5. Python 시선 직선 계산: R2 차폐 근거 확인. Roblox raycast나 스크린샷이 아니다.
6. 완성 문서에서 재현 코드를 추출해 실행: 컴파일·기존14개·보조 재현·기하 계산이 동일하게 완료됐다. 최종 소스 해시 재검사에서 병렬 변경을 감지해 로더/월드를 다시 읽고 근거를 갱신했다.

bundle SHA-256: `ac09f3cc105eac94fcf578787c5563de5fde558af265c5cfc1505a4627087af1`.

14개 PASS: 최초4면/28부품/기존 모의10개 보존; 반복 재사용; Pivot 이동; 지붕 높이 변경; 면 이동; 프레임 크기 변경; 지지대 크기 변경; 지지대 중복 위치; notice/ad 왕복; 생성 중 오류 복원; commit 검증 실패 복원; 비직육면체 지붕 거절; 가시 비충돌 장애물 거절; 전 과정 기존 광고 보존.

모의 환경의 매장은 4개 대상만 존재하며 실제 BuildWorld로 생성하지 않았다. 지붕 크기/높이와 배치도 실제 월드와 다르다. 기존 광고는 Part10개뿐이다. yaw-only CFrame, 간략한 Instance/Parent/Destroy는 엔진 렌더·실제 AdGui 속성·전체8매장·동시 실행·성능을 입증하지 않는다.

### 쓰기 없는 재현 명령

프로젝트 루트 PowerShell에서 실행한다. 기존 bundle이 현재 소스와 다르면 assert에서 중단하며 오래된 bundle을 새 소스의 검사 결과로 사용하지 않는다.

```powershell
@'
from pathlib import Path
import subprocess, json
p = Path('.setup/handoffs')
s = Path('tools/advertising/BuildRooftopBillboards.luau').read_text(encoding='utf-8-sig')
expected = (p/'rooftop-mock-prefix.luau').read_text(encoding='utf-8-sig') + '\nlocal module=(function()\n' + s + '\nend)()\n' + (p/'rooftop-mock-tests.luau').read_text(encoding='utf-8-sig')
bundle = (p/'rooftop-mock-bundle.luau').read_text(encoding='utf-8-sig')
assert expected == bundle, 'STALE BUNDLE'
subprocess.run(['tools/world/.validation/luau-0.745/luau-compile.exe', 'tools/advertising/BuildRooftopBillboards.luau'], stdout=subprocess.DEVNULL, check=True)
subprocess.run(['tools/world/.validation/luau-0.745/luau.exe', str(p/'rooftop-mock-bundle.luau')], check=True)
extra = '''
world:SetAttribute("NightShiftOwned",false)
local r=module.build(world); assert(r.Ok)
print("REPRO R3: unowned world accepted (mock)")
world:SetAttribute("NightShiftOwned",true)
local old=r.Folder
local stranger=Instance.new("Folder"); stranger.Name="RooftopAdvertising"; stranger.Parent=world
r=module.build(world); assert(not r.Ok and old.Parent==world and stranger.Parent==world)
stranger:Destroy(); print("PASS duplicate/unowned same-name folder rejected and retained (mock)")
r=check(module.build(world,"notice"))
local panel=r.Folder:FindFirstChild("Store01"):FindFirstChild("AdSurface")
local notice=panel:GetChildren()[1]; notice:GetChildren()[1]:Destroy()
r=module.build(world,"notice"); assert(r.Ok and r.Reused)
print("REPRO R4: missing notice label accepted as reusable (mock)")
r=check(module.build(world,"ad"))
local gui=r.Folder:FindFirstChild("Store01"):FindFirstChild("AdSurface"):GetChildren()[1]
gui.Enabled=false
r=module.build(world,"ad"); assert(r.Ok and r.Reused)
print("REPRO R4: disabled AdGui accepted as reusable (mock)")
gui.FallbackImage="REVIEW_SENTINEL_NO_ASSET"
r=module.build(world,"ad"); assert(r.Ok and r.Reused)
print("REPRO R4: modified fallback accepted as reusable (mock; no asset fetched)")
'''
r = subprocess.run(['tools/world/.validation/luau-0.745/luau.exe'], input='assert(loadstring(' + json.dumps(bundle+extra, ensure_ascii=False) + '))()\n', text=True, encoding='utf-8', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
print(r.stdout); print(r.stderr)
assert r.returncode == 0
assert all(t in r.stdout for t in ['unowned world accepted','missing notice label accepted','disabled AdGui accepted','modified fallback accepted','duplicate/unowned same-name folder rejected'])
for z in [30,40,52,64,72]:
    y = 30 + (5-30)*25/z
    print('GEOMETRY_ONLY camera Z=',z,'roof-edge ray Y=',round(y,4),'top blocked=',y<19)
'@ | python -
```

실행한 기하 계산 결과: Z=30→Y=9.1667, 40→14.3750, 52→17.9808, 64→20.2344, 72→21.3194. 앞의 세 지점은 지붕 상단19보다 낮다.

## 5. 공식 자료 대조와 실제 검증 인계

2026-11-01 공식 [Immersive ads](https://create.roblox.com/docs/production/monetization/immersive-ads)와 [AdGui API](https://create.roblox.com/docs/reference/engine/classes/AdGui)를 직접 열어 대조했다. 16×9 크기는 문서의 8×4.5~32×18 범위 안이며 EnableVideoAds=false는 이미지 전용 설정이다. 부적격 사용자에게 기본 로고/fallback이 표시될 수 있고, 설치가 실제 광고 공급·수익을 보장하지 않는다. AdGui.Status는 읽기 전용·비복제 상태이므로 서버의 면 개수만으로 클라이언트 렌더를 판정하지 않는다. 이는 문서 대조이며 현재 계정/게임의 자격 확인이 아니다.

Integrator만 다음 실제 검증을 수행한다. 현재 전부 **미실행/PENDING**이다.

- ADS: R1~R4 수정본 설치 후 외부6/내부8/안내면을 분리 계수, 네 좌표·Front 방향·기본 fallback/notice/빈 소재·허용 콘텐츠 경계 확인.
- SHOP/FLOOR: 네 입구 및 후문 하역/PC 표지에서 보행·운반·카메라 검사, 광고 가독성과 시야 차폐를 낮/밤/모바일에서 확인.
- 반복/격리: 두 번 설치, 모드 왕복, 좌표 변경, 소유권 충돌, 후보 생성/검증 실패 시 기존 객체 보존 및 게임 루프 지속 확인.
- DELIVER: Edit 상태 로컬 rbxl 저장, 저장본 및 설치 소스 해시, 임시 오류 주입/관측 코드 제거 확인.
- 실제 광고 공급·노출·수익, 8인 부하, 클라우드 저장은 이번 광고 검토 범위에서 미검증이다. 기존 다른 단계 결과를 대신 합격 처리하지 않는다.

후속 순서는 World의 R2/R3/R4 수정 → 독립 재검토 → Integrator의 R1 연결 및 실제 플레이·저장 검증이다. 파일 소유권은 Moderator가 배정한다. 본 문서 작성 완료는 검토 단계 준비만 의미하며 Moderator 완료 표식이나 releaseReady=true를 대신하지 않는다.
