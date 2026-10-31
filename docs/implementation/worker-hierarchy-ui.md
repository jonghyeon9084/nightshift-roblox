# 워커 계층 UI 구현 기록

2026-10-31 · NightShift-Dashboard · 메인 통합 전 UI 변경

## 변경 파일

- `tools/mission-control/model.js`: 이름 기준 등록 에이전트·workerPool·실제 그룹 참가자 병합, 부모 검증, 트리 배치, 풀 상태 표시 함수.
- `tools/mission-control/fleet.js`: 전체 워커 소속 트리, 실제 Moderator 통신 경로 분리, 노드 속성, 전체보기·확대·워커 상세 선택.
- `tools/mission-control/app.js`: pool 변경 시 재렌더링, 관측 모델/effort와 구성 모델/effort 분리, 부모·작업·이유·실행그룹 상세, 병합 명부.
- `tools/mission-control/index.html`, `style.css`: 스크롤 지도 영역, 접근 가능한 선택/확대 컨트롤, 소속 범례, 점선 소속과 완료 임시 워커 표현.
- `tools/mission-control/hierarchy.test.cjs`: 새 계층 데이터 및 모의 DOM 통합 테스트.
- 이 문서.

## 표시 계약

`state.workerPool = {at,workers:[{name,parentName,temporary,status,taskId,taskTitle,chatId,reason,tier}],tasks:[]}`를 읽는다. 등록 에이전트의 구성 모델 정보는 유지하고 동명 pool 메타데이터를 병합한다. pool에만 있는 워커, 등록만 된 워커, 실제 그룹 참가자도 유지한다. pool이 없으면 등록/그룹 자료만으로 동작한다. 기존 별도 일반 세션 `NightShift-Main`은 중앙 Moderator로 합성하지 않는다.

`parentName`은 작업 소속이다. 알 수 없는 부모·자기 참조·순환 및 순환으로 이어지는 관계는 루트에 배치하고 상세에서 사유를 표시한다. `NightShift-PerfAudit → NightShift-Dashboard`는 pool 자료로 적용하며 하드코딩하지 않는다. 노드와 소속선에 `data-worker`, `data-parent`를 넣었다. 루트의 검증 ID는 `orchestrator`다.

소속선은 점선이고 패킷 저장소에 등록하지 않는다. 통신선은 기존 실제 그룹의 Moderator↔참가자 경로로 별도 등록한다. 자식에게 Moderator가 직접 보낸 메시지는 중앙↔자식 경로를 따른다. 이동 원은 기존 `model.routes`로 확인한 명령/응답과 실제 메시지 ID 추적에서만 발생한다. 초기 이력은 자동 이동하지 않으며 명시적인 과거 재생은 기존 동작을 유지한다. pool 상태와 도구 관측은 메시지를 생성하지 않는다.

실제 활성 그룹의 pending이 있으면 `실제 명령 수신 · 응답 대기`로 표시한다. 그 외에는 `풀 상태: queued/active/waiting/...`로 출처를 구분한다. 완료 임시 워커는 `inactive(완료) · 재사용 가능`으로 남고 비활성 외형을 갖는다. 도구 활동은 관측된 마지막 턴 자료로 따로 표시한다. 연결이 끊어지면 노드 상태를 `마지막 기록`으로 표시하고 기존 패킷 중단 동작을 유지한다.

상세에는 부모, 작업 제목 또는 ID, 이유, 실행그룹, 풀 상태, 임시 여부, tier를 넣었다. 실제 관측 모델/effort와 다음 요청용 구성 모델/effort는 별도 행이다. 관측이 없는 경우 구성값을 관측으로 대체하지 않는다.

전체보기는 트리 전체 좌표계를 화면 폭과 높이에 맞춘다. 노드가 많아 작게 보일 때 100%/150% 확대 후 지도 안에서 스크롤하거나 워커 선택 컨트롤로 바로 상세를 열 수 있다. 키보드 노드 선택 및 상세 닫기를 유지한다. 그룹 상세 모드는 기존 그룹별 지도를 유지한다.

## 실행한 확인

- `node --check tools/mission-control/app.js`, `node --check tools/mission-control/fleet.js`: 통과.
- `node tools/mission-control/hierarchy.test.cjs`: 통과. 이름 병합·pool 부재·등록/그룹/pool 전용 워커·부모 누락/순환·완료 임시 워커 유지·실제 pending 우선·직접 Moderator 경로·트리 경계 확인.
- 같은 새 테스트의 모의 DOM 통합: 통과. PerfAudit 부모 속성과 소속선, 통신 경로가 소속선과 다른 요소인지 및 실제 루트/자식 끝점, 도구/pool에서 패킷 미생성, 320px 폭/640px 높이 전체보기 계산, 확대/전체보기 전환, 노드 클릭/선택 상세, pool만 변경되어도 재렌더링, 연결 끊김 표시 확인.
- `node tools/mission-control/model.test.cjs`: 기존 6개 PASS 출력 확인. 실제 타깃·독립 pending·ID 중복 제거·관측 출처·SVG 경로·과거 재생/실시간 큐 분리·패킷 유지/중단·13 워커 모바일 계산 회귀 통과. 기존 테스트 파일은 수정하지 않았다.
- 담당 경로 `git diff --check`: 최초 공백 1건 수정 후 최종 재실행 통과(출력 없음, exit 0). 최종 `model.js`, `app.js`, `fleet.js` 구문 검사와 두 테스트 파일 재실행도 통과했다.

## Moderator 검토 반영: NightShift-Main 보존

최초 구현은 `NightShift-Main`을 워커 목록에서 제거하고 해당 부모 이름을 루트 별칭으로 취급했다. 이 동작은 등록 일반 세션과 Moderator를 구분한다는 표시 계약과 충돌했다. `model.workers()`에서 두 특수 처리를 제거했다. 이제 등록된 Main은 독립 노드로 유지되고 `parentName: 'NightShift-Main'`인 자식은 해당 노드에 연결된다. Main이 병합 자료에 없으면 일반 미등록 부모와 동일하게 루트로 대체하며 원래 부모 이름과 알 수 없는 부모 사유를 상세에 표시한다. Main이 포함된 순환 관계도 기존 순환 검증을 적용한다.

이번 수정 파일은 `model.js`, `hierarchy.test.cjs`, 이 문서뿐이다. 회귀 테스트에 등록 Main 보존·자식 부모 보존·미등록 Main 미생성/루트 대체/사유·Main 포함 순환을 추가했다. 모의 DOM에서도 Main 독립 노드와 자식 소속선의 속성, 클릭 상세, Main 제거 후 루트 대체와 사유를 확인한다.

이번 검사: `node --check tools/mission-control/model.js`, `node tools/mission-control/hierarchy.test.cjs`, `node tools/mission-control/model.test.cjs` 통과. 지정 UI 파일과 신규 테스트·보고서의 `git diff --check`도 통과(출력 없음, exit 0). 실제 브라우저·백엔드 통합 미검증 상태는 유지한다.

## 미검증 상태

실제 브라우저 검증을 시도하기 위해 `cua.getState()`로 환경을 조회했으나 `Local browser use is disabled in Work settings` 및 빈 browsers 목록이 반환됐다. 따라서 실제 브라우저/실기기에서 부모선 가독성, 모바일 렌더링, 스크롤/터치, 상세 패널 위치, 움직이는 원의 시각적 궤적은 검증하지 못했다. 위 DOM 테스트는 실제 브라우저 통과를 뜻하지 않는다.

백엔드 워커가 병렬 수정 중이므로 실제 API pool 통합과 그룹 실시간 왕복은 메인이 확인해야 한다. 이 워커는 server.cjs, model-evidence.cjs, runner, 게임 소스, 루트 파일을 수정하지 않았고 Studio·Git push·프로세스 재시작을 수행하지 않았다. 등록/후보만으로 실행 중이라고 주장하지 않으며, 재미·게임 진행 테스트와 무관한 UI 검증이다.

## 메인 브라우저 통합 확인 (2026-11-01)

메인이 고정 GitHub Pages 링크의 실제 iframe에서 workerPool 백엔드, 부모/하위 역할, 완료 임시 워커 비활성, 실제 관측 모델/effort 상세를 확인했다. 사용자 피드백으로 중앙 Moderator와 원형 워커 배치로 변경하고 가족 역할을 인접 배치했다. 같은 중앙 연결의 소속선/통신선 중복은 제거했으며 하위 워커 소속선은 별도로 남긴다. 전체보기는 역할·상태를 간결하게 표시하고 클릭/선택 상세에 모델·effort·원문·실행그룹을 제공한다. 390×844 viewport로 응답형 확인 후 원래 크기로 복원했다. 30개 노드의 320/390/1280px 경계에서 원형 배치 겹침 없음은 모의 검사로 별도 확인했다. 실제기기 손가락 터치나 장시간 애니메이션 검증을 완료했다는 뜻은 아니다.

로컬 화면 증거: .setup/radial-worker-map.png. 관측 시 20개 역할이 표시되었으며 예약·대기 역할은 실행 중으로 표시하지 않았다. 이미지/이력은 Git에 포함하지 않는다.
