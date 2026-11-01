# NightShift 상주 개발 파이프라인

독립 작업은 같은 프로세스의 [worker-pool](../../docs/worker-pool.md)에서 병렬로 진행한다. `tools/worker-pool.json`의 구체적인 작업을 추가하면 필요 역할 등록, 난도별 모델 배정, 파일 소유권·선행 작업·메모리·정원 확인, 실제 완료 후 비활성 전환을 처리한다. 기존 항목은 변경/삭제하지 않고 새 ID와 새 chatName으로 추가하며 같은 역할 이름을 재사용할 수 있다. 먼저 주 파이프라인과 풀의 진행 작업을 모두 관측한 뒤 새 요청을 발행한다. 사용 한도/인증 중단은 별도 durable halt로 보존된다.

`resident.cjs`는 공식 로컬 Maestro CLI의 상태와 실제 그룹 기록을 읽는 유한 단계 실행기다. 새 API 키나 외부 모델 호출 경로를 만들지 않는다. 단계가 끝나면 같은 관찰 회차에 다음 단계를 발행하며 분 단위 예약 자동화는 사용하지 않는다.

```powershell
./tools/Start-NightShiftRunner.ps1
./tools/Stop-NightShiftRunner.ps1
# attention 원인을 해결한 뒤 명시적으로 재개할 때만:
./tools/Start-NightShiftRunner.ps1 -Resume
node --test tools/runner/*.test.cjs
```

매니페스트는 `tools/development-pipeline.json`이며 version=1, stages 배열을 사용한다. 각 단계에는 id, name, chatName, participants, promptFile, completionMarker, requiredFiles가 필요하다. completionMarker는 `[STAGE_READY:대문자_ID]` 형태다. 첫 단계만 adoptExisting=true를 지정할 수 있고, 기존 대화의 **최신 사용자 요청**에 해당 완료 표식이 있어야 채택한다. modelAssignments는 선택 항목이며 참가자에 해당하는 Role: simple/standard/complex를 지정한다. 실제 변경은 기존 `tools/set-worker-model.cjs`로만 처리한다.

새 작업은 전송 직전에 프롬프트·산출물 기준값과 dispatch ID를 `.setup/runner/state.json`에 원자적으로 기록한다. 전송 성공 응답도 실제 저장된 사용자 메시지 해시로 확인한다. 재시작은 같은 체크포인트에 재접속하며, 전송 여부가 불명확하면 자동 재전송하지 않고 attention으로 멈춘다. 프롬프트 자체는 `.setup/runner/dispatch-*.txt`, 실제 이벤트는 `events.jsonl`, 실행 로그는 `stdout.log`, `stderr.log`다.

완료에는 현재 작업 이후의 마지막 Moderator 응답에 독립된 완료 표식 줄, 그룹 idle, 비어 있지 않은 필수 파일이 모두 필요하다. 새로 발행한 단계는 파일 해시 변화 또는 발행 이후 수정 시각도 확인한다. 초기 채택 단계는 이미 생성된 파일을 인정하되 최신 사용자 요청 뒤 응답인지 검사한다. 표식 없이 idle이 된 경우 최근 이벤트와 idle 상태가 12초 동안 안정될 때까지 기다린다. 한도·인증·오류나 예상하지 않은 활성 작업은 attention으로 멈추며 재시도하지 않는다.

상주 감시는 로컬 그룹 디렉터리 fs.watch와 2.5초 안전 조회를 사용한다. 이 조회는 AI 요청을 생성하지 않는다. 모든 단계가 끝나면 awaiting-review가 되며 completed는 false다. 게임 전체 완성이나 Studio 테스트 통과를 의미하지 않는다. Maestro의 Studio 조작 권한은 기존 프로젝트 지침대로 메인에만 있다.

새 단계 발행 전 다른 활성 그룹의 참가자 수 합계와 새 단계 참가자 수를 보수적으로 더해 매니페스트의 maxWorkers(1~4, 기본 3)를 지킨다. 자리가 부족하면 waiting-capacity로 기다리며 실패나 완료로 표시하지 않는다. 단계 자체의 참가자 수가 정원을 넘으면 attention으로 명시 중단한다. 다른 그룹이 끝난 것이 관찰되면 즉시 다시 판단한다. 기록과 live 상태의 미세한 타임스탬프 차이는 동일 발화로 합치고, 실제 사용자 문구 해시와 시작 시각을 함께 확인한다.

## 승인된 후속 단계 추가

구체적으로 승인된 후속 작업은 `append.cjs <extension.json>`으로 기존 단계 뒤에 추가한다. 확장 파일은 `{ "version": 1, "maxWorkers": 2, "stages": [...] }` 형태이며 stages는 기존과 같은 규약을 사용한다. maxWorkers를 생략하면 기존 정원 또는 기본 3을 유지한다. 기존 단계 ID와 중복할 수 없고 새 단계는 adoptExisting을 사용할 수 없다. 이미 완료된 3인 build 기록은 정원을 2로 낮춰도 보존한다. 프롬프트는 먼저 실제 파일로 작성해야 하며, 확장 파일·프롬프트·산출물 경로가 프로젝트 밖이거나 외부 junction으로 연결되면 거부한다.

```powershell
# 모든 기존 단계가 awaiting-review에 도달한 뒤 운영자가 실행:
./tools/Stop-NightShiftRunner.ps1
./tools/Invoke-Node.ps1 tools/runner/append.cjs tools/approved-extension.json
./tools/Start-NightShiftRunner.ps1
```

추가 명령은 동일 singleton 포트를 점유해 실행 중인 러너·다른 추가 작업과 충돌을 막는다. runner.pid가 없어야 하고, 상태가 stopped/resumeStatus=awaiting-review, 모든 기존 단계가 순서대로 완료, checkpoint·현재 chat 없음, 기존 manifest hash 일치일 때만 수정한다. stage 인덱스와 기존 완료 증거를 유지하고 상태를 ready로 바꾼다. 명령 자체는 AI 발행이나 러너 시작을 하지 않는다.

원본 두 파일은 `.setup/runner/backups/append-<ID>/manifest.json`, `state.json`에 바이트 그대로 보존한다. `append.json`과 events.jsonl의 pipeline-append-prepared 이벤트에 백업 위치·이전/새 hash·추가 ID를 기록한 후 manifest, state 순서로 원자 교체하고 pipeline-appended 이벤트를 남긴다. 두 파일 사이에 프로세스가 중단되면 hash가 불일치하여 다음 러너가 attention으로 멈춘다. 자동 복구·재발행은 하지 않으며 운영자가 기록과 백업을 대조해야 한다.

singleton은 127.0.0.1:43823 바인딩으로 확보한다. 시작 스크립트는 기존 프로세스의 실행 파일·정확한 러너 명령줄·프로젝트를 확인한다. 정지 스크립트도 같은 검증 뒤 로컬 정지 요청을 보내며 프로세스를 강제 종료하거나 Maestro 작업을 중단하지 않는다. 정지 요청 뒤 새 단계는 발행하지 않는다. 정상 종료된 러너를 다시 시작하면 진행 중 단계에 재접속한다. attention은 일반 재시작으로 해제되지 않는다.

로컬 상태 인터페이스: `GET http://127.0.0.1:43823/health`에서 service, pid, root, entry, state를 읽는다. 메인 활동 지도는 같은 state.json과 events.jsonl을 읽을 수 있다. 브라우저 Origin 요청과 다른 Host는 거부한다. `POST /stop`에는 현재 PID와 같은 `X-Runner-Pid` 헤더가 필요하며 공식 정지 스크립트를 사용하는 것을 권장한다.

## 미완료 검증과 독립 작업 분리

메인이 실제 실패 증거를 검토한 뒤에만, 정지한 실행기의 `defer.cjs <검토문서> <사유>`를 사용할 수 있다. idle이며 완료 표식이 없는 비치명적 attention만 허용한다. 사용 한도/인증 정지·실행 중·매니페스트 변경은 거절한다. `deferred`는 해당 단계 미완료와 원래 체크포인트를 그대로 보존하며 재전송/다음 주 단계를 실행하지 않는다. 독립 워커 풀만 파일·모델·메모리 제한 안에서 진행한다. 검토 근거 해시와 운영자 이벤트, 전 상태 백업을 남긴다. 완료나 출시 합격을 뜻하지 않는다.

Maestro가 누락된 참가자 멘션을 자동 삽입하므로 신규 발행은 모든 참가자의 명시 멘션을 wire prompt에 먼저 넣고 해시를 기록한다. 이미 발행된 요청은 그대로 보존하고 실제 원문·배정 참가자·dispatch ID를 대조해 재접속하며 중복 요청하지 않는다.

## 구독 예비 사용량

`tools/usage-budget-policy.json`으로 계정 공유 한도 최소10%를 보호한다. 공식 사용량 도구의 로컬 snapshot 및 공식 Codex 세션 `token_count.rate_limits`에서 수치·시각·기간만 읽는다. 대화 본문·계정 ID·크레딧은 복사/노출하지 않는다. 수치는15초 캐시하며 잔량12% 이하 또는15분 이상 오래된/없는 기록이면 새 배정을 중지한다. 잔량11% 이하에서는 이 풀의 진행 중 그룹만 공식 `group-chat stop`으로 중단하고 파일·Studio를 종료하지 않는다. 같은 그룹을 반복 중단하지 않고 미완료 체크포인트를 보존한다. 사용 한도 리셋/크레딧 구매/API 호출은 실행하지 않는다. 계정의 다른 활동·진행 중 요청·지연 집계 때문에 수학적 잔량 보장을 할 수 없으므로10% 앞에 여유를 둔다. `state.json.usageBudget`에 실제 관측값과 중단 사유를 기록한다.

sourceHandoffs는 루트가 명시적으로 검토한 소스 부분 인계의 scope=source-only, file, sha256을 기록한다. 정확한 검토문서 해시가 맞을 때 후속 소스 작업의 입력 준비로만 인정한다. 원본 attention/미완료 및 completedStages는 바꾸지 않는다. 통합 이후에만 검증할 수 있는 연결을 선행 월드 작업도 요구하여 생기는 순환을 분리하며 실제 최종 검사와 수정 담당은 검토문서에 명시한다.
