# 옥상 광고판 검증 기록 — 2026-11-01

구현 파일: `tools/advertising/BuildRooftopBillboards.luau`. Store01/03/06/08의 StoreId 및 Pivot을 사용한다. 모드 ad는 영상 비활성 AdGui와 플랫폼 기본 fallback, notice는 단독 SurfaceGui다. 소유 `RooftopAdvertising`만 교체한다. 광고면 4개, 부품 28개는 모의 실행의 집계다.

지붕은 충돌 가능한 불투명 정렬 `Part`의 `Block` 형상만 인정하고, 단일 지붕의 투영 영역이 광고판 전체 받침 폭을 덮어야 한다. Pivot은 수직이어야 한다. 해당 영역에서 더 높은 가시 형상은 충돌 가능 여부에 관계없이 거절한다. MeshPart, WedgePart, 공 등은 지붕으로 인정하지 않는다. 조건 미충족 시 실패를 반환한다. 투영 영역 검사는 보수적 경계상자 검사이며 다른 월드 객체와 시야는 검사하지 않는다. 기대 위치는 매장 Pivot과 지붕에서 계산하며 공유 배치의 로컬 +Z가 도로 방향이라는 가정이 있다. 크기와 정확한 부품 구성, 좌우 지지대 각각 하나를 검사한다.

## 재현 절차와 결과

프로젝트 루트의 PowerShell에서:

```powershell
python -u .setup/handoffs/verify-rooftop-ads.py
python .setup/handoffs/build-rooftop-mock.py
& tools/world/.validation/luau-0.745/luau.exe .setup/handoffs/rooftop-mock-bundle.luau
```

첫 명령은 정적 검사 9개, Luau 실제 소스 컴파일, Stores 누락·잘못된 모드 오류 모의 검사를 실행했다. 전체 코드 `.setup/handoffs/verify-rooftop-ads.py`와 출력 `.setup/handoffs/rooftop-ads-validation-output.txt`에 기록했다. 나머지 명령은 prefix 모의 객체 및 실제 빌더 소스와 테스트를 결합해 Luau로 실행한다. 재현 코드 `.setup/handoffs/build-rooftop-mock.py`, `.setup/handoffs/rooftop-mock-prefix.luau`, `.setup/handoffs/rooftop-mock-tests.luau`, 전체 출력 `.setup/handoffs/rooftop-mock-output.txt`.

성공 경로 모의 검사 결과: 최초 설치 4개/28 Parts 및 기존 광고 10개 보존, 재호출 재사용, pivot·지붕·광고면 이동 및 프레임·지지대 크기 변경에 따른 재설치, 지지대 중복 위치 거절, 두 모드 왕복, 후보 생성 도중 오류 및 후보 검증 실패 시 기존 폴더 보존, 비직육면체 지붕 및 가시 비충돌 장애물 거절, 기존 광고 보존 모두 PASS. 기존 광고는 모의 Part 10개이므로 실제 거리 2개/실내 8개의 엔진 구조를 검사한 것은 아니다.

모의 객체는 yaw 회전만 구현한 CFrame과 간략한 Instance, Parent, 파괴 및 속성 모델이다. 렌더링, 실제 물리·메시·엔진 오류, 병행 실행, 실제 World 구조와 Roblox 엔진 동작을 입증하지 않는다. Studio는 조작하지 않았다. 컴파일러와 실행기는 기존 문서가 명시한 로컬 `tools/world/.validation/luau-0.745/` 실행 파일을 사용했다. world 소스나 검증 의존 파일은 읽거나 수정하지 않았다.

## Integrator 연결

ModuleScript로 설치해 Stores 준비 후 `build(world)`를 호출하고 실패 결과를 기록하며 핵심 로딩을 계속한다. `build`, `rebuild`, `validate`는 mode 생략/ad 또는 notice를 받으며 Ok/Code/Reason 및 성공 시 Folder/PartCount/AdUnits를 반환한다. build/rebuild는 Reused/AddedParts도 반환한다. 실제 월드에서 지붕 형상이 안전 조건을 만족하는지와 28개 부품, 기존 도로 2개·내부 8개 보존, 배치 변경·실패 복원, 지붕 지지와 도로 방향·입구·하역·간판·다른 객체 간섭, 조명·모바일·실제 광고/안내 렌더를 Studio에서 확인한다. 지붕 조건을 만족하지 않으면 실패하며 높이를 추측하지 않는다.

Studio 배치·렌더링·플레이, 실제 광고 자격·공급·노출·수익은 미검증이다. 공개 게시 및 실제 판매는 하지 않았다.

## 메인 인계 정리
원본은 RooftopAds 워커가 .setup/handoffs에 남겼고 메인이 정해진 문서 경로로 복사했다. 메인이 현재 소스를 결합한 모의 실행 14개를 다시 통과 확인했다. 실제 Studio 결과가 아니며 독립 Review와 World/Integrator의 실제 설치 검증이 남는다.
