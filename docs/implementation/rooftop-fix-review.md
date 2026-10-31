# 옥상광고 R2/R3/R4 수정 독립 재검토

검토자: NightShift-Review / NightShift-RooftopFixReview. 검토일: 2026-11-01 01:04 KST 기준. 작업 디렉터리: `C:\Users\HP\Documents\ChatGPT\로블록스 게임 개발`.

**검토 산출물 준비: R2는 코드·제한 기하 범위에서 충족, R3는 정적·모의 범위에서 충족, R4는 부분 해결이며 잔여 P2 결함이 있다. 게임·ADS 실플레이 합격 판정은 하지 않는다.** 현재 소스를 읽는 공식 오프라인 검사 21개 PASS 묶음을 독립 실행해 종료 코드 0을 확인했다. 추가 모의 검사에서는 크기 0 안내문과 글자/배경 동일 색상 안내문을 그대로 재사용하는 두 경로를 재현했다.

## 범위와 변경 파일

- AGENTS.md 및 지정된 두 보고서, `tools/advertising/`의 빌더·검사 파일만 읽고 검토했다. 기존 보고서에 인용된 다른 월드·공유 규약·통합 파일은 이번에 열어 현재 상태를 확인하지 않았다.
- 지속적으로 생성·수정한 프로젝트 파일은 이 문서 `docs/implementation/rooftop-fix-review.md` 하나다. 소스·테스트·Studio·`src/world/integration`은 변경하지 않았다.
- 요청받은 검사 실행기는 운영체제 임시 디렉터리에 bundle을 생성하고 종료 시 삭제한다. 추가 재현은 stdin과 메모리에서만 수행했다. 기존 Luau 실행 파일만 실행했으며 설치·다운로드를 하지 않았다.
- R1 로더는 다른 Integrator의 후속 범위다. 이번에 로더를 읽거나 설치·검증하지 않았다. 유료 API·게시·판매·외부 메시지 전송은 실행하지 않았다. 완료 표식 발행은 Moderator에게 남긴다.

## 검토 입력과 SHA-256

모든 경로는 위 작업 디렉터리 기준이다. 최초 읽기 때와 검사 후 01:04:18 KST 재확인 때 아래 여섯 해시가 동일했다. 아래 소스 행 번호는 이 해시 기준이다.

| 경로 | SHA-256 |
|---|---|
| `tools/advertising/BuildRooftopBillboards.luau` | `7F15904F1ADB2B788DEE45B9897C41B6795E760C87AF3A64DD751E15E77A6E0E` |
| `tools/advertising/tests/run-rooftop.py` | `04F3D0D894B22093D670C1AA48698E250149DA560175B5A358AD94A731116039` |
| `tools/advertising/tests/rooftop-fake.luau` | `E462E9AC6405C0A04E20F8E819F215AB442539CB355EF0BB8A6955AFED18929B` |
| `tools/advertising/tests/rooftop.spec.luau` | `E3612D9BF7F53A489FE925B56DB7F31B73D1100FFC69E1F15EA64D9AB4CCAF45` |
| `docs/implementation/rooftop-ads-review.md` | `A3ACD13B4297A80085927B67AE0C0DEFE5A9C256A91D8BDDA17CA6C46BC45840` |
| `docs/implementation/rooftop-ads-fixes.md` | `8BAA2096C31CED394567AE0467B35CE3150D65F4E7EDDC11A1931CEA099D6AE6` |

## 항목별 판정

| 항목 | 실제 소스 및 실행 근거 | 판정 |
|---|---|---|
| R2 지붕 차폐 | 빌더 8, 55~76, 78~83행: 실제 지붕 경계 `hiZ`에서 프레임 반깊이 0.3+여유 0.05를 뺀 위치를 사용하고 동일 boardZ로 footprint를 검사한다. 50 깊이는 24.65, 40 깊이는 19.65. 검사 74~91행에서 네 면 방향·위치, 대표 시점의 지붕 경계 직선, 지붕 깊이 변경을 확인했다. | 기존 지붕 중앙 배치 문제를 코드·제한 기하 범위에서 해결. 실제 렌더 합격은 보류. |
| R3 월드 소유권 | 18~20행의 이름/Model·NightShiftOwned=true·CommerceLayoutVersion=2 검사와 127~129, 211~215행의 광고 폴더 소유권/중복 검사를 확인했다. 공식 검사와 추가 구조 스냅샷 검사에서 잘못된/누락 속성 및 외부·중복 폴더를 거절했다. | 정적·모의 범위 충족. 실제 8매장 월드/엔진 검증은 별도. |
| R4 ad | 105~107행에서 Face/AdShape/Enabled/EnableVideoAds를 명시하고, 167~178행에서 유일 GUI, 클래스·설정·자식 없음과 새 AdGui의 두 fallback 속성을 비교한다. 비활성·두 fallback 변조·잘못된 shape의 재생성 검사가 통과했다. | 원래 ad 재현 사례를 모의 범위에서 해결. 실제 엔진 Content 비교와 렌더는 미검증. |
| R4 notice | 109~114행에서 안내를 생성하고 181~187행에서 유일 Message·문구·Visible·Enabled·투명도·TextScaled·AlwaysOnTop 등을 검사한다. 라벨 삭제/빈 문자열/숨김과 GUI 비활성/AlwaysOnTop 변경은 재생성된다. 그러나 Size 및 두 색상은 검사하지 않는다. | 부분 해결. 아래 F1의 두 재현 때문에 표시 상태 검증을 충분하다고 판정할 수 없다. |
| 재사용·실패 격리 | 208~237행의 후보 생성/commit 실패 시 후보 제거와 기존 이름 복원 흐름을 확인했다. 공식 검사에서 최초 4면/28부품, 반복 0 추가, 모드 왕복, 두 실패 주입, 모의 기존 광고10개 보존이 통과했다. | 이 범위에서 새 실패 회귀를 발견하지 못했다. 핵심 게임 로딩 지속을 검증한 결과는 아니다. |

R2 수정 보고서의 “시선 검사 추가”는 빌더의 런타임 raycast를 뜻하지 않는다. `rooftop.spec.luau:81~84`의 지붕 전단 Z=25, 카메라 Y=5 및 로컬 Z=30/40/52/64/72를 사용하는 오프라인 직선 계산이다. 변경된 40 깊이 지붕에 대해서는 위치만 검사하며 그 지붕의 시선을 다시 검사하지 않는다. 광고 프레임, 입구 간판·차양, 다른 매장/월드 객체의 가림은 이 계산이 포괄하지 않는다. 빌더의 장애물 검사도 선택한 매장 descendants의 광고 footprint 교차만 다룬다.

## F1 — P2: notice의 크기·대비 손상을 정상 재사용함

대상: `tools/advertising/BuildRooftopBillboards.luau:111~114,181~187,234~237`.

원래 R4의 삭제·빈 문구·Enabled/fallback 사례는 해결됐지만, 생성 시 지정한 Size·TextColor3·BackgroundColor3가 검증 계약에는 없다. 현재 소스와 기존 fake/spec를 메모리에서 조합한 추가 실행으로 다음을 각각 재현했다.

1. 정상 notice의 Message에 `Size=UDim2.fromScale(0,0)`을 대입한 뒤 build → `Ok=true`, `Reused=true`, 같은 폴더 및 0 크기 보존.
2. 새로 rebuild한 notice의 Message에 `TextColor3=BackgroundColor3`를 대입한 뒤 build → `Ok=true`, `Reused=true`, 같은 폴더 및 동일 색상 보존.

이는 모의 상태 검증 우회 재현이다. 실제 엔진에서 화면이 어떻게 보이는지 직접 관찰했다는 뜻은 아니다. 새로 정상 생성한 안내가 처음부터 손상됐다는 증거도 아니며, 이전 R4와 같은 표시 상태 검사 누락이 남은 것이다.

수정 제안: 생성값과 검증값을 공유해 전체 면 Size 및 배경/글자색을 검사하고, 표시 영역에 영향을 주는 Position/AnchorPoint 등도 생성·검증 계약에 포함할지 정한다. 손상 시 기존 후보 검증·교체 경로를 사용한다. 같은 두 변조를 독립 회귀 검사로 추가하고, 수리 후 실제 표시 속성과 단일 renderer까지 확인한다. 이 문서에서는 소스나 테스트를 수정하지 않았다.

## 실제 실행과 PASS/FAIL 근거

작업 디렉터리에서 실행:

```powershell
python tools/advertising/tests/run-rooftop.py
```

관측된 외부 종료 코드: **0**. 실행기 10행의 `luau-compile.exe` 호출과 17행의 `luau.exe` 호출 모두 `check=True`이며 완료됐으므로 두 하위 명령도 종료 코드 0이다. 컴파일 stdout은 실행기에서 폐기한다. 실행기는 매번 위 빌더 소스를 읽으므로 예전 정적 bundle을 검사한 결과가 아니다.

실제 stdout의 PASS 21개 묶음과 범위 고지:

```text
PASS first build: four boards, 28 parts, legacy 10 preserved
PASS repeated build reuses folder
PASS pivot movement rebuild
PASS roof height change rebuild
PASS board movement rebuild
PASS frame size change rebuild
PASS support size change rebuild
PASS duplicate support position rebuild
PASS mode switching notice and ad
PASS mid-creation failure retains old folder
PASS failed candidate validation restores old folder
PASS non-block roof rejected, old folder retained
PASS visible noncolliding obstruction rejected
PASS legacy advertising unchanged throughout
PASS foreign/missing ownership and unsupported layout rejected without mutation
PASS unowned duplicate folder retained and rejected
PASS deleted, blank and hidden notice repaired
PASS disabled and through-wall notice repaired
PASS disabled ad, custom fallback and wrong shape repaired with engine defaults
PASS all four front faces at roof edge and geometric sightlines clear roof (not rendering proof)
PASS roof depth change derives board and footprint from current roof
MOCK ONLY: yaw-only CFrame, simplified Instance; not Roblox or Studio
```

공식 묶음의 FAIL은 0이다. 여러 assert가 한 PASS 줄에 묶여 있으므로 “21개의 독립 엔진 테스트”로 표현하지 않는다. 공식 R3 검사 중 “without mutation” 줄은 주로 기존 폴더 Parent를 검사한다. 추가 검사에서는 이름·부모·전체 자식 identity/순서·destroyed 여부를 비교해 구조 보존 근거를 보강했다. 모든 속성/이벤트까지 무변경이라고 주장하지 않는다.

추가 검사는 PowerShell `@'…'@ | python -`로 실행했다. Python이 위 fake + 현재 builder + spec + 아래 Luau 보조 코드를 조합하고, `subprocess.run(['tools/world/.validation/luau-0.745/luau.exe'], input='assert(loadstring('+json.dumps(bundle+extra,ensure_ascii=False)+'))()\n', text=True, encoding='utf-8', stdout=subprocess.PIPE, stderr=subprocess.PIPE)`로 stdin 실행했다. 파일을 추가 생성하지 않았다. Python과 Luau 종료 코드 모두 **0**, stderr는 비어 있었다. REPL 종료 코드만 신뢰하지 않고 아래 네 출력 문자열도 Python assert로 확인했다. 21개 기존 PASS가 앞서 다시 출력된 후 다음이 출력됐다.

```text
REPRO R4 residual: zero-size notice reused unchanged
REPRO R4 residual: equal text/background colors reused unchanged
PASS EXTRA R3 ownership/layout rejection preserves all object names, parents, child identities
PASS EXTRA R3 standalone foreign folder and owned duplicate rejected without structural mutation
LUAU_PROCESS_EXIT 0
```

REPRO 두 줄은 **결함 재현 성공**, 해당 제품 요구에 대해서는 **FAIL/잔여 결함**을 의미한다. 추가 실행에 사용한 Luau 코드:

```lua
local function getLabel(folder)
 return folder:FindFirstChild("Store01"):FindFirstChild("AdSurface"):GetChildren()[1]:GetChildren()[1]
end
local r=check(module.build(world,"notice"))
local label=getLabel(r.Folder); label.Size=UDim2.fromScale(0,0)
local old=r.Folder
r=module.build(world,"notice"); assert(r.Ok and r.Reused and r.Folder==old)
assert(getLabel(r.Folder).Size[1]==0 and getLabel(r.Folder).Size[2]==0)
print("REPRO R4 residual: zero-size notice reused unchanged")
r=check(module.rebuild(world,"notice")); label=getLabel(r.Folder)
label.TextColor3=label.BackgroundColor3; old=r.Folder
r=module.build(world,"notice"); assert(r.Ok and r.Reused and r.Folder==old)
assert(getLabel(r.Folder).TextColor3==getLabel(r.Folder).BackgroundColor3)
print("REPRO R4 residual: equal text/background colors reused unchanged")
local function snapshot(x)
 local result={}
 local function visit(y)
  table.insert(result,{object=y,name=y.Name,parent=y.Parent,children=y:GetChildren()})
  for _,c in ipairs(y:GetChildren()) do visit(c) end
 end
 visit(x); return result
end
local function unchanged(s)
 for _,v in ipairs(s) do
  assert(v.object.Name==v.name and v.object.Parent==v.parent and not v.object.destroyed)
  local c=v.object:GetChildren(); assert(#c==#v.children)
  for i,old in ipairs(v.children) do assert(c[i]==old) end
 end
end
for _,case in ipairs({"ownership-false","ownership-missing","layout-missing","layout-wrong"}) do
 if case=="ownership-false" then world:SetAttribute("NightShiftOwned",false)
 elseif case=="ownership-missing" then world:SetAttribute("NightShiftOwned",nil)
 elseif case=="layout-missing" then world:SetAttribute("CommerceLayoutVersion",nil)
 else world:SetAttribute("CommerceLayoutVersion",3) end
 local s=snapshot(world); r=module.build(world); assert(not r.Ok); unchanged(s)
 world:SetAttribute("NightShiftOwned",true); world:SetAttribute("CommerceLayoutVersion",2)
end
print("PASS EXTRA R3 ownership/layout rejection preserves all object names, parents, child identities")
local folder=world:FindFirstChild("RooftopAdvertising")
folder:SetAttribute("Owner","foreign")
local s=snapshot(world); r=module.build(world); assert(not r.Ok); unchanged(s)
folder:SetAttribute("Owner","NightShiftRooftopAdvertisingV1")
local duplicate=Instance.new("Folder"); duplicate.Name="RooftopAdvertising"
duplicate:SetAttribute("Owner","NightShiftRooftopAdvertisingV1"); duplicate.Parent=world
s=snapshot(world); r=module.build(world); assert(not r.Ok); unchanged(s); duplicate:Destroy()
print("PASS EXTRA R3 standalone foreign folder and owned duplicate rejected without structural mutation")
```

## 미검증 범위와 후속 완료 조건

- fake는 대상 매장 4개만 만들고 실제 8매장 BuildWorld를 실행하지 않는다. 기존 광고는 AdGui10개가 아닌 Part10개다. CFrame은 yaw만 처리하고 Instance·Color3·UDim2를 단순화한다. 실제 속성 타입·기본값·Content 값 동등성·렌더·이벤트·동시성·성능을 증명하지 않는다.
- 특히 fallback 비교는 fake의 두 고정 문자열 비교다. 새 엔진 AdGui의 FallbackImageContent 비교가 실제 설치와 반복 재사용에서 통과하는지는 미확인이다. API 문서의 현재 사실을 새로 대조한 검토도 아니다.
- 실제 네 매장의 가까운 인도·도로 중앙·반대 인도·입구, 낮/밤, PC/모바일, 카메라 거리별 화면과 간판·차양·프레임 간섭, 보행·운반 동선은 미검증이다.
- R1 로더 연결/실패 격리/외부6·내부8·총14 광고 계수, Studio 설치·두 번째 설치·모드 왕복, 실제 광고 공급·노출·수익·자격, 로컬 저장본과 설치 소스 해시, 핵심 게임 루프·8인 부하는 이번에 검증하지 않았다.
- 후속은 Root가 F1 수정과 회귀 검사를 배정하고 독립 검토 후 Integrator가 엔진·렌더·R1 검증을 수행하는 것이다. 현재 문서 준비를 게임 합격이나 Moderator 완료 표식으로 전환하지 않는다.
