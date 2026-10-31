# 옥상 광고 독립 검토 후 수정

루트가 `rooftop-ads-review.md`의 R2/R3/R4를 수정했다. World/Studio 통합 이전의 코드 결과다.

- R2: 광고 구조를 매장 Pivot 중심에서 **지붕의 도로 쪽 끝에서 0.35 stud 안쪽**으로 이동했다. 실제 지붕 경계로 위치와 검사 footprint를 함께 산출한다. 50 stud 깊이 지붕에서는 로컬 Z=24.65, 40 깊이에서는 19.65다. 양쪽 매장 모두 로컬 +Z 도로 방향을 유지한다. 최저 이미지 점에서 대표 보행 시점 Z=30/40/52/64/72로 향하는 직선의 지붕 간섭 검사도 추가했다.
- R3: NightShiftOwned=true 및 CommerceLayoutVersion=2 확인을 추가했다. 외부·누락 소유권, 다른 배치 버전, 중복/비소유 광고 폴더는 기존 객체를 보존하고 거절한다.
- R4: 이미지 광고의 Enabled/AdShape/영상 비활성, 새 AdGui의 기본 FallbackImage/FallbackImageContent 일치 여부를 검사한다. 자체 안내는 유일한 Message 라벨의 문구·Visible·투명도·TextScaled를 검사하고 AlwaysOnTop=false를 유지한다. 손상된 표시는 새 후보를 검증한 뒤 교체한다.
- 기존 생성 실패/검증 실패 시 이전 폴더 보존과 4면/28부품, 기존 Advertising 폴더 보존은 유지했다.

수정 파일은 `tools/advertising/BuildRooftopBillboards.luau`와 `tools/advertising/tests/`다. 검사 자료를 Git 제외 임시 폴더에만 두지 않고 현재 소스를 매번 읽는 독립 실행 가능한 오프라인 검사로 보존했다.

실제 실행: `python tools/advertising/tests/run-rooftop.py` — Luau 컴파일 exit0, **21개 PASS 묶음**, exit0. 제한된 Instance/CFrame fake 및 기하 계산이며 실제 Studio 렌더/광고 공급 검사가 아니다. 한글 절대 경로를 Luau 컴파일러 인수로 넘길 때 파일 열기 실패가 있어, 루트 cwd와 상대 소스 경로로 실행하도록 수정한 뒤 위 성공을 확인했다. 테스트의 앞면 벡터 부호 오류도 수정 후 재실행했다.

근거: [Roblox AdGui API](https://create.roblox.com/docs/reference/engine/classes/AdGui)를 실제 열어 현재 속성을 대조했다. 실제 엔진의 기본 Content 비교, 시야·야간·모바일 가독성, 새 World의 간섭, R1 로더 설치 및 외부 총6면은 **미검증**이다. Integrator가 확인한다. 실제 광고 노출·수익을 확인했다는 뜻이 아니다.

후속: 독립 rooftop-fix-review.md의 크기 0/동일 색상 안내 재사용 지적을 수용해 Size·Position·전경/배경색 검사를 추가했다. 세 변조 회귀를 포함한 현재소스 검사 22개 PASS 묶음, exit0을 확인했다. 최종 World/코드 검토/Studio에 연결하며 동일 사항만 재확인하는 추가 모델 호출은 하지 않는다.
