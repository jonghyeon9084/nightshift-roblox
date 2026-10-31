# Worker pool 독립 검토

검토자: NightShift-PoolReview (NightShift-Dashboard 소속 임시 검토 역할)  
검토일: 2026-10-31  
판정: **수정 필요 — P1 6건, P2 2건을 격리된 mock에서 재현했다.** 현재 운영에서 해당 장애가 실제 발생했다는 의미는 아니다.

## 범위와 검증 방법

- AGENTS.md를 먼저 읽고 요청된 `tools/runner/{pool.cjs,pool.test.cjs,resident.cjs,pipeline.cjs,io.cjs}`, `tools/model-routing.cjs`, `tools/model-routing.test.cjs`, `tools/set-worker-model.cjs`, `tools/model-policy.json`, `tools/worker-pool.json`을 검토했다. 기존 회귀 검사 확인을 위해 `pipeline.test.cjs`, `io.test.cjs`도 읽었다.
- 프로젝트 쓰기는 이 보고서 하나뿐이다. 코드·설정·Studio·실행 중 프로세스를 변경하지 않았다. Maestro CLI 실행, 실제 AI 호출, 모델 변경, 그룹 발행을 하지 않았다. mock의 dispatch/setModel은 메모리 배열 변경뿐이다.
- 기존 검사: `./tools/Invoke-Node.ps1 --test tools/runner/pool.test.cjs tools/runner/pipeline.test.cjs tools/model-routing.test.cjs` → **66/66 통과**. singleton 검사는 테스트 자체의 임시 localhost 포트를 사용한다.
- 추가 재현: 복사본에서 **R1–R8 8/8 현행 결함 재현**, 안전성 확인 **S1–S2 2/2 통과**. R 테스트의 통과는 잘못된 동작이 재현되었다는 뜻이며 제품 정상 판정이 아니다.
- 격리 디렉터리: `C:/Users/HP/AppData/Local/Temp/nightshift-pool-review-5623c61c575c4996a9801d4047594994/`. 이 안의 `repro.cjs`가 실행 가능한 전체 재현 코드이고 `tools/`는 검토 대상 복사본이다. 임시 산출물은 후속 확인을 위해 남겨 두었다.
- 재현 명령: `./tools/Invoke-Node.ps1 --test C:/Users/HP/AppData/Local/Temp/nightshift-pool-review-5623c61c575c4996a9801d4047594994/repro.cjs`. 개별 확인은 `--test-name-pattern=R3` 등을 추가한다. 최초 R 8건 실행 뒤 S 2건은 `--test-name-pattern=^S`로 별도 실행했다.
- `source-hashes.json`에 복사 시점 SHA-256을 보존했다. 재현 후 요청 대상 10개 파일 모두 프로젝트 원본과 복사 시점 해시가 같음을 확인했다. 아래 라인은 이 버전 기준이다.

## 재현된 결함

### R1 — P1: 동일 경로의 표기 차이로 파일 소유권 검사를 우회한다

**위치:** `tools/runner/pool.cjs:21–23,32–34`.

`normalize()`는 역슬래시·끝 슬래시·대소문자만 처리한다. `validatePool()`은 `.` 경로 요소와 중복 슬래시를 허용한다. 따라서 `./src/server`와 `src/server/x.luau`는 실제 포함 관계인데 `conflicts()`는 false를 반환한다. `within()`이 해결한 경로는 충돌 비교에 사용되지 않는다.

**재현/증거:** R1은 writes가 각각 위 두 경로인 작업을 구성한다. `validatePool(config, root)`가 성공하고 `conflicts(a,b) === false`이며, `path.resolve(root,'./src/server') === path.resolve(root,'src/server')`임을 검증했다.

**영향:** 승인된 작업 정의만 사용해도 같은 파일을 두 워커가 동시에 수정할 수 있다. 현재 worker-pool.json의 경로에서 이미 충돌이 발생했다고 확인한 것은 아니다.

**수정안:** 검증 시 모든 scope를 workspace 기준 정규화한 상대 경로로 바꾸거나 비정규 표기를 거부한다. 충돌 계산도 같은 정규형을 사용한다. Windows 경로 처리와 `@studio` 같은 논리 자원은 별도 규칙으로 구분한다.

### R2 — P1: 같은 대화를 후속 작업에 재사용하면 첫 작업의 파일 범위가 계속 적용된다

**위치:** `tools/runner/pool.cjs:28–44,65–68`.

작업 검증은 동일 chatName의 후속 작업을 허용하지만 `scopes(chat)`는 `find()`로 첫 번째 정의만 반환한다. 완료 기록이나 현재 task/checkpoint를 조회하지 않는다.

**재현/증거:** R2는 같은 worker/chatName으로 A(writes=`old.md`)와 B(writes=`new.md`, dependsOn=[A])를 등록한다. 구성이 수락되며 해당 대화의 scope는 계속 `old.md`다. B가 실행 중인 형태의 chat에 대해 `new.md`를 쓰는 다른 작업의 `guard()` 결과가 null이다.

**영향:** 완료 역할을 재사용하는 정상적인 확장 시 현재 파일 소유권을 놓친다. 동일 이름의 대화에 추가 참가자가 있어도 task만 반환하므로 추가 참가자 범위도 누락할 수 있다.

**수정안:** 실제 chatId와 현재 진행 중 checkpoint/task를 연결하여 scope를 결정한다. 연결이 불분명하면 관련 범위를 합쳐 보수적으로 잠근다. 대화 재사용을 지원하지 않을 의도라면 chatName 중복을 명시적으로 거부한다.

### R3 — P1: dispatch에서 보고된 사용 한도가 소실되어 다음 작업을 발행한다

**위치:** `tools/runner/pipeline.cjs:95–99,128–129`; `tools/runner/pool.cjs:79–80,102–103`.

dispatch 예외는 이벤트에만 기록하고 재조정으로 진행한다. 대화가 생성되지 않았으면 attention 사유는 `Dispatch result cannot be reconciled: chat missing`으로 덮인다. 전역 중단 판단은 attention.reason의 limit/authentication 문자열에 의존하므로 이미 확인된 한도를 놓친다.

**재현/증거:** R3에서 A의 mock dispatch가 `Error('usage limit reached')`를 던지게 하고 독립 작업 B를 뒤에 둔다. 한 번의 pool.tick에서 호출 기록은 `['a','b']`이고 A.reason에는 `chat missing`만 남는다. 실제 한도 요청은 하지 않았다.

**영향:** A를 중복 발행하지 않는 안전장치는 유지되지만, 한도 도달 후 다른 AI 요청을 중단해야 한다는 규칙을 위반한다. 인증 실패 예외도 같은 사유 소실 경로를 가진다(인증 문자열의 별도 실행 재현은 하지 않음).

**수정안:** dispatch 오류의 분류를 durable 상태에 별도 보존하고 한도/인증 오류는 pool과 main에 전역 중단 원인으로 전달한다. 전송 성공 여부가 불명확하면 기존대로 재조정하되, 새로운 요청은 차단한다. 사람이 읽는 reason 문자열만으로 중단 여부를 판단하지 않는다.

### R4 — P1: 기존 대화에 추가 참가자가 있으면 워커 4명 제한을 초과한다

**위치:** `tools/runner/pipeline.cjs:61–65,94,110,120`; `tools/runner/io.cjs:97–98`.

기존 대화 참가자는 stage.participants의 부분집합 조건만 확인한다. capacityAvailable은 대상 대화를 합계에서 빼고 stage.participants.length만 더한다. 실제 send는 기존 대화 전체에 수행한다.

**재현/증거:** R4는 stage 참가자를 A 1명으로 지정하고, 같은 이름의 idle 기존 대화에는 A를 포함한 참가자 4명을 둔다. 다른 대화에서 UI 1명이 실행 중이다. maxWorkers=4임에도 dispatch가 허용되고 활성 대화 참가자 합계가 **5명**이 된다.

**수정안:** 기존 대화의 참가자 집합이 stage와 정확히 일치하는지 확인하거나, 실제 대상 대화의 전체 참가자 수와 소유권을 capacity/guard에 반영한다. 발행 전 재검사도 같은 실제 집합을 사용한다.

### R5 — P2: idle 상태를 관측한 워커도 active로 게시한다

**위치:** `tools/runner/pipeline.cjs:155–160`; `tools/runner/pool.cjs:112–124`.

pipeline은 완료 표식 없는 idle 대화에 유예 시간을 주고 observedState='idle'을 저장한다. pool.publish는 observedState를 무시하고 checkpoint가 있으면 active로 게시한다.

**재현/증거:** R5에서 작업 발행 후 대화를 isActive=false/state='idle'로 바꾸고 tick한다. runner.state.observedState는 idle인데 snapshot.workers[0].status는 active다.

**영향:** 최소 유예 시간 동안 완료 응답 대기와 실제 실행을 지도 소비자가 구분할 수 없다. active를 단순히 '배정이 미완료'라는 의미로 쓸 수는 있으나, 요청된 실제 도구 활동 표시와는 별도 정보가 필요하다. 이 검토는 지도 UI의 최종 렌더링까지 검증하지 않았다.

**수정안:** 배정 상태와 실행 관측 상태를 분리하고 observedState, 관측 시각, evidence/chatId를 함께 게시한다. idle 유예는 awaiting-completion 같은 별도 상태로 표현한다. parentName은 소속 선언으로 유지하고 실제 명령 송신자로 해석하지 않는다.

### R6 — P1: 모델 설정 중 새 충돌이 생겨도 발행 직전에는 동시수만 재검사한다

**위치:** `tools/runner/pipeline.cjs:111–120`; `tools/runner/pool.cjs:70–86`.

파일 소유권과 메모리는 모델 설정 이전 canDispatch에서 확인한다. 비동기 setModel 이후에는 대상 대화 busy 및 capacity만 확인하며 파일·메모리·참가자 중복 guard는 다시 수행하지 않는다.

**재현/증거:** R6에서 A.writes=`src/client`로 설정하고 setModel mock 도중 다른 대화의 NightShift-UI를 active로 만든다. 두 작업 합계는 2명이므로 capacity 검사가 통과하고, 동일 파일 범위를 소유한 대화가 생겼음에도 A가 발행된다.

**영향:** 상주 실행기 자체가 단일 tick을 직렬 처리해도 수동 그룹 실행 등 외부 상태 변경과 경합할 수 있다. 메모리 감소도 같은 검사 공백에 있지만 별도 재현은 하지 않았다.

**수정안:** 발행 직전 새 list를 얻어 참가자 중복·실제 참가자 수·파일 소유권·메모리를 모두 다시 확인한다. ensureWorker처럼 부작용이 있는 준비 단계와 재실행 가능한 읽기 전용 dispatch guard를 분리한다. 서로 다른 실행 주체 간 완전한 원자성이 필요하면 공통 예약/잠금도 필요하다.

### R7 — P2: maxWorkers를 낮춰도 이미 생성된 runner는 이전 제한을 사용한다

**위치:** `tools/runner/pool.cjs:55–63,83–88`; `tools/runner/pipeline.cjs:61–65`.

refresh는 최상위 maxWorkers 변경을 수락하지만 getRunner는 기존 객체를 반환한다. 객체의 manifest.maxWorkers는 생성 시 값에 고정된다.

**재현/증거:** R7은 maxWorkers=4에서 A/B runner를 생성한 뒤 설정을 1로 바꾸고 tick한다. pool.config.maxWorkers는 1인데 dispatch 기록은 `['a','b']`로 두 작업이 시작된다.

**수정안:** 실행 용량 정책을 runner의 immutable 작업 manifest와 분리하여 매번 현재 값을 전달한다. 또는 동적 변경을 지원하지 않는다면 명시적으로 거부한다. 제한 변경 때문에 진행 중 dispatch의 정체성·체크포인트를 재작성하지 않는다.

### R8 — P1: 전체 진행 작업을 먼저 재조정하지 않아 뒤쪽 작업의 한도를 확인하기 전에 새 작업을 발행한다

**위치:** `tools/runner/pool.cjs:93–108`; `tools/runner/resident.cjs:67`.

주석은 모든 기존 작업을 먼저 reconcile한다고 설명하지만 실제 첫 순회는 runner 생성뿐이다. 다음 순회에서 새 발행과 기존 작업 관측이 배열 순서대로 섞인다. resident도 main.tick을 pool.tick보다 먼저 실행한다.

**재현/증거:** R8은 앞에 신규 A, 뒤에 adoptExisting B를 배치하고 B의 기존 대화에 `usage limit reached` 응답을 둔다. tick에서 A가 먼저 발행된 뒤 B가 Limit attention으로 바뀐다. 현재 파일 순서에서 이 정확한 상황이 발생했다고 확인한 것은 아니다. append-only 운용에서도 앞쪽 대기 작업이 풀리는 순간 뒤쪽 진행 작업에 한도가 발생하면 같은 순서 문제가 가능하다.

**수정안:** 관측/재조정과 신규 발행을 별도 단계로 나눈다. main 및 모든 pool의 진행 작업을 먼저 관측해 전역 한도/인증 중단을 확정한 다음 신규 작업을 선택한다. 완료 처리로 다음 단계까지 즉시 발행하는 runner 경로도 관측 단계에서는 발행을 억제해야 한다.

## 정상 확인한 범위

- 재시작/완료 후 재발행: 기존 66개 검사에서 완료 작업 재시작, prepared checkpoint의 수신 증거 재조정, timeout 뒤 정확한 user-message 확인, 불명확한 전송의 자동 재발행 금지, stop/resume 보존을 확인했다.
- immutable dispatch: `createFiles.writePrompt()`는 `wx`를 사용한다. S2에서 같은 ID의 파일 덮어쓰기가 EEXIST로 거부되고 원문이 유지됨을 확인했다. wire hash/dispatchId는 checkpoint에 저장된다. 모델 정책 전체를 같은 snapshot으로 고정하는지까지의 종단 검증은 하지 않았다.
- task 추가/변경: S1에서 새 ID 추가는 수락하고, 기존 정의 변경과 삭제는 `definitions.json` 해시 비교로 거부함을 확인했다. maxWorkers 예외는 R7이다.
- 선행 의존성: 기존 검사에서 미완료 선행 작업 대기, 완료 후 해제, 순환·없는 의존성 거부를 확인했다. parent 순환과 worker별 부모 변경도 코드에서 거부한다. parent 존재 자체를 실제 Maestro 실행 근거로 확인하는 구조는 아니다.
- 메모리: 기존 검사에서 400 MiB에서 발행 0건, 900 MiB로 회복 후 발행을 확인했다. 실제 PC 메모리 압박을 일으키지는 않았다. 실행 중 작업을 메모리 부족만으로 중단시키지 않는 구조다.
- 모델·추론 지원: model-routing 검사 4개가 모델 slug 및 supported_reasoning_levels 거부, workload/risk 선택, legacy tier 호환, busy/불명 상태 참가자 모델 변경 거부를 확인했다. set-worker-model은 catalog 확인 후 설정하고 configured-next-dispatch로 기록한다. 실제 실행 모델을 확정하는 turn_context 증거는 이 코드 검토만으로 확보하지 않았다.
- 완료/inactive: 현재 요청 뒤의 moderator 독립 행 완료 표식, idle 상태, 비어 있지 않은 변경 산출물을 요구한다(adoption은 이전 파일과 변경 여부 비교 예외). 완료 이후 inactive는 완료 기록에 근거한다. 실행 중 active의 의미 문제는 R5다.

## 미검증과 인계

실제 Maestro IPC·구독 한도·인증 실패·모델 catalog 현황·update-agent 설정 반영·turn_context·UI 렌더링·Studio는 테스트하지 않았다. 별도 테스트로 프로세스를 시작하거나 기존 그룹을 재호출하지 않았다. io.test.cjs는 읽었지만 이번 66개 실행 목록에는 포함하지 않았다.

검토 대상 해시는 추가 재현 후 모두 동일했다. 보고서 인계 이후 다른 워커가 수정한 버전에는 라인과 판정이 달라질 수 있다. 수정은 메인이 담당한다. 우선 R3/R8의 전역 중단과 R4의 실제 참가자 수, 이어 R1/R2/R6의 파일 소유권을 수정하고 해당 재현을 기대 정상 동작의 회귀 검사로 전환하는 것이 필요하다. 준비 완료 표식은 요청대로 Moderator의 보고서 확인 뒤 출력한다.
