# 지도 백엔드 poll 캐시 검증

검증일: 2026-10-31. 담당: NightShift-PerfAudit, 중앙 배정 소속 NightShift-Dashboard.

## 변경 범위와 동작

- `tools/mission-control/server.cjs`: 모든 대상 그룹을 처리한다. 기존 `slice(0, 20)`을 제거했으며 등록 에이전트 목록에도 개수 제한을 두지 않는다. 그룹 목록에서 제거된 그룹은 캐시와 다음 정상 수집 결과에서 제외한다.
- `tools/mission-control/poll-cache.cjs`: 종료/비활성 그룹의 CLI 응답 및 로그 수집을 캐시한다. 키는 group-list 항목 전체의 JSON signature와 `metadata.json`, `history.jsonl`, `chat.log` 각각의 mtimeMs·size다. 새 메시지, 파일 생성/삭제, 상태/참가자 변화가 키를 바꾼다.
- `isActive === true`인 그룹이나 busy 등 미정착 상태는 매 poll 조회한다. 캐시 hit는 비활성인 idle/inactive/completed/stopped/archived에만 허용하며 상태 필드가 없는 비활성 그룹은 idle로 취급한다. 활성 여부가 애매하면 최신 조회를 우선한다.
- 모든 CLI subprocess에 공통 동시 실행 상한 **3**을 적용한다. 기본 목록 3개 조회와 그룹 상태 조회 모두 같은 limiter를 통과한다. 실패한 슬롯도 반환한다. 모든 결과가 settle된 뒤 다음 poll을 예약하며 내부 즉시 재시도 루프는 없다. 기존 subprocess timeout 12초를 유지한다.
- 로그 파일은 signature가 바뀔 때만 복사·파싱한다. 변경 없는 활성 그룹에서도 CLI 메시지는 공통 MessageIngestor를 통해 journal에 수집한다. 로그·CLI를 독립적인 ID 경로로 저장하지 않는다. 소스 파일 삭제는 기존 보관본을 지우지 않는다. 복사/파싱/조회 실패 전에 캐시를 제거하여 실패를 cache hit나 성공으로 확정하지 않는다.
- 프로젝트 파일 해시는 mtimeMs·size별로 재사용한다. 파일 트리 탐색/stat은 계속 수행한다.
- 실패 poll은 `ok:false`로 표시한다. 일부 그룹만 실패하면 기존 결과 또는 목록 기반 최소 정보에 `stale:true`, `lookupFailed:true`, 공개 오류를 붙여 보존한다. 이전 snapshot이 없어도 목록에서 확인한 그룹과 참가자를 유지하며, 삭제된 그룹은 제외한다. 공개 오류는 조회/보관 실패를 알리는 고정 문구로 내보내 subprocess 명령·경로·원문 오류가 노출되지 않게 한다. 기존 **30초 stale 기준**과 5초/유휴 15초 poll 간격을 유지한다.

## workerPool과 관측 정보

루트가 atomic write하는 `.setup/worker-pool/state.json`을 poll마다 읽어 `state.workerPool`에 제공한다. 파일이 없으면 `{workers:[],tasks:[]}`다. JSON 파싱 실패나 읽기 오류는 성공으로 간주하지 않는다. 시작 시 저장된 snapshot의 workerPool도 현재 파일의 허용 필드로 다시 읽는다.

공개 필드는 다음으로 제한한다.

- 최상위: `at`, `workers`, `tasks`
- worker: `name,parentName,temporary,status,taskId,taskTitle,chatId,reason,tier`
- task: `id,title,status,chatId,reason`

parentName은 null 또는 NightShift-Dashboard, status는 queued/active/completed/inactive/attention/waiting만 허용한다. 잘못된 status는 attention으로 표시한다. 경로·명령 등 별도 필드는 전달하지 않는다. 허용된 title/reason 문자열 자체는 생산자인 루트가 작성한 공개 설명으로 취급한다.

`events.jsonl`의 완료된 각 행은 기존 journal에 안정적인 해시 ID와 `kind:status`로 보존한다. 이벤트의 kind·worker·배정·상태·작업 공개 필드만 남기고 중복은 journal이 제거한다. 미완성 마지막 행은 다음 poll에서 재확인한다. 실행기 이벤트를 채팅 메시지로 만들지 않는다. 잘못된 완성 JSON 행은 수집 오류로 표시한다.

모델 관측은 기존 `model-evidence.cjs`의 실제 `turn_context` 파서를 그대로 사용한다. 캐시된 그룹도 매 poll 관측을 다시 요청하며, 구성값을 실제 관측으로 승격하지 않는다. 해당 모듈은 수정하지 않았다. 내부 추론·도구 인수·결과·비밀 원문 제외 회귀 테스트를 실행했다.

## 실제 실행한 검증

```powershell
./tools/Invoke-Node.ps1 --test tools/mission-control/poll-cache.test.cjs tools/mission-control/model-evidence.test.cjs tools/mission-control/history.test.cjs
./tools/Invoke-Node.ps1 --check tools/mission-control/server.cjs
git diff --check -- tools/mission-control/server.cjs tools/mission-control/poll-cache.cjs tools/mission-control/poll-cache.test.cjs
```

결과: **10 tests, 10 pass, 0 fail**, 총 7715.2ms. 문법 검사와 diff 공백 검사도 종료 코드 0.

신규 테스트 8개는 idle cache hit와 로그 미복사, busy 최신 조회, 비활성→활성 전환, group-list 메시지 수 변경, 세 소스 파일 각각의 변경/삭제, 전체 소스 삭제, 삭제 그룹 prune, CLI 예외/negative 응답과 복구, 실제 archive IO 오류와 복구, journal 실패 시 재시도, limiter 실패 슬롯 반환을 검증한다. pool 허용 필드·부재/손상 파일·status 이벤트 중복 제거 및 디스크 보존도 검증한다. 서버 소스를 VM에서 실행하는 통합 테스트는 첫 poll 전체 상태 조회 실패에도 26개 그룹 전부 노출, 명시적 실패·stale 필드, 초기 실패에서 복구, warm cache, 기존 그룹 실패 시 stale 보존, 복구, 삭제, 기존 30초 stale 판정을 확인한다. 실제 서버를 시작하거나 재시작하지 않는다.

## 성능 측정: mock 실행 실측

아래는 테스트 프로세스에서 측정한 시간이며 **실제 Maestro CLI의 운영 성능 측정이 아니다**. CLI 비용은 요청당 `delay(10)`으로 가정하고 실제 임시 파일 읽기·복사 비용 및 호스트 스케줄링은 포함한다. 타이머 실제 경과는 정확히 10ms로 고정되지 않는다. 비교는 각 1회이며 속도 비율을 운영 성능 보장으로 해석하지 않는다.

조건: 비활성 24개 + busy 2개 = 26개, 그룹별 소스 파일 3개, 빈 보관 폴더에서 cold poll 후 warm poll. 기존 방식 비교는 같은 지연으로 기본 목록 3개를 병렬 처리한 뒤 상태 20개를 순차 처리하는 기존 상한을 재현했다.

| 측정 경로 | CLI 호출 수 | 경과 시간 | 최대 동시 CLI |
|---|---:|---:|---:|
| 기존 순차 방식 mock, 20개 상한 | 23 | 401.7ms | 3 (기본 목록 단계), 상태 단계 1 |
| 신규 cold, 26개 모두 수집 | 29 | 375.2ms | 3 |
| 신규 warm, busy 2개만 재조회 | 5 | 77.4ms | 3 |

warm 호출 수는 기존 상한 방식보다 23→5로 감소하면서 전체 26개 그룹을 유지했다. cold에는 처음 수행하는 78개 로그 파일 보관 비용 등이 포함된다. 이전 측정에서는 기존 mock보다 느렸으며 최신 1회 측정에서는 더 빨랐다. cold 최적화나 OS별 복사 비용 개선까지 검증한 결과는 아니다. CLI 카운터·동시 실행 수·그룹 개수는 assertion으로 검증하며 시간 수치 자체에 flaky한 통과 기준을 두지 않았다.

## 남은 한계와 미검증

- 실제 실행 중인 지도 서버/CLI의 전후 성능, 실시간 활동 UI와 연결된 운영 확인은 미실행이다. 프로세스 재시작은 메인 담당이다.
- Studio 조작·플레이 테스트·게임 소스 검증은 수행하지 않았다. 이 변경의 검증 범위는 지도 백엔드다.
- 파일 내용이 바뀌면서 mtime·size가 정확히 모두 유지되는 비정상 수정은 감지하지 못한다. 변경 가능한 그룹 파일의 stat 및 group-list signature가 올바르게 갱신된다는 가정이다.
- 파일 복사·트리 stat과 journal 이벤트 파일 전체 스캔은 여전히 동기 처리다. 큰 최초 수집 또는 로그 증가 시 poll이 오래 걸릴 수 있으며 30초 stale 표시가 유지된다.
- 전체 Maestro 목록 조회 실패 때는 마지막 snapshot을 오류 상태로 보존하므로 그 시점에 삭제된 그룹을 확정할 수 없다. 다음 목록 조회 성공 때 제외한다.
- event reason/title은 허용 문자열을 그대로 보존하므로 생산자가 민감한 원문을 해당 필드에 넣지 않아야 한다. 임의의 비공개 추가 필드는 whitelist로 차단한다.


## 검토 후 보완: 메시지 동일성 및 최초 실패 노드

Moderator 검토에서 지적한 기존 `source/...`와 `message/...` 중복 경로를 제거했다. `MessageIngestor`가 로그와 CLI를 함께 받아 정규화한 시각(ISO/epoch milliseconds), actor, 내용과 동일 메시지의 발생 순번으로 공통 `observed-message/...` ID를 만든다. 서로 다른 CLI ID로 확인된 반복 메시지도 발생 횟수만큼 보존한다. 로그가 바뀌지 않은 활성 poll은 이전에 파싱한 로그와 최신 CLI를 대조하며, 로그에 아직 없는 CLI 메시지도 즉시 기록한다. 로그가 뒤늦게 반영되어도 같은 발생 순번을 재기록하지 않는다. 저장된 journal로부터 중복 방지 상태를 복원한다. 기존 legacy source/message 행도 참고하며, 이미 저장되어 있던 중복 행을 삭제하거나 기록을 다시 쓰지는 않는다.

회귀 테스트는 `ISO timestamp|participantName|escaped content` 형태의 실제 로그 구조와 `{id,timestamp,participantName,content}` CLI 메시지 구조를 사용한다. epoch timestamp, 개행 escape, 내용의 `|`, CLI tail 밖 과거 메시지, 동일 시각·동일 내용의 서로 다른 두 메시지, CLI 선도착→로그 반영, 소스 로그 삭제→복원, journal 재생성을 검증했다. 실제 서비스 기록을 테스트 입력으로 읽지 않았으며 생성한 fixture다.

로그에는 원본 메시지 ID가 없으므로 두 소스는 시각·actor·내용이 보존된다는 가정으로 대조한다. 이 세 값까지 같은 메시지들이 서로 겹치지 않는 CLI tail에서 등장하는 극단적 경우에는 원본 ID를 포함한 로그 없이 완전한 동일성 판정을 보장할 수 없다. 현재 테스트는 두 소스의 겹치는 메시지와 반복 횟수 보존을 검증한다.

최초 조회 실패 시 목록에서 확인한 `id/topic/state/isActive/participants`와 빈 messages를 남기고 명시적인 실패·stale 필드를 제공한다. 기존 메시지가 있으면 그대로 보존한다. 정상 조회로 복구하면 실패 필드가 사라지고, 다음 목록에서 삭제된 그룹은 결과와 캐시에서 빠진다. 서버 VM 통합 테스트는 초기 snapshot 없는 전체 조회 실패→전체 복구→추가 실패/복구→목록 삭제 순서로 이를 검증한다.

보완 후에도 20개 상한 제거, CLI 동시 실행 최대 3개, warm 호출 5회(기본 목록 3 + busy 2), workerPool 허용 필드 및 status journal 규약은 유지된다. 서버 재시작·Studio 조작·Git push는 수행하지 않았다.


## 재시작 후 늦게 관측한 CLI ID 연결 보완

이전 구현은 로그에서 이미 기록한 occurrence에 CLI ID가 나중에 연결되는 경우 그 연결을 메모리에만 남겼다. Moderator가 제시한 겹치는 CLI tail의 재현은 문서의 비중첩 tail 한계가 아니라 이 영속화 누락에 의한 구현 결함이었다.

수정한 `MessageIngestor`는 `.setup/history/message-links.jsonl`에 `{key,id,occurrence}`만 append한다. key는 메시지 fingerprint 해시이며 내용·명령·경로·도구 인수는 인덱스에 포함하지 않는다. 이 파일은 `activity.jsonl`과 분리된 내부 인덱스다. 채팅 메시지나 실행기 status 이벤트를 합성하지 않으며 기존 HTTP 정적 파일 허용 목록에도 추가하지 않는다.

새 CLI ID는 기존 메시지에 해당하더라도 연결을 파일에 기록한 뒤 메모리에 확정한다. 동일 ID를 다시 관측할 때는 추가 쓰기를 하지 않는다. 새 ingestor는 인덱스의 정확한 occurrence부터 복원하고, 기존 journal의 messageId/occurrence도 참고한다. 따라서 `b→1,c→2` 연결이 재시작 뒤에도 유지되어 새 `d`를 occurrence 3으로 기록한다. 연결 기록 실패는 상위 poll에 전파하며 성공으로 처리하지 않는다.

추가한 디스크 기반 회귀 테스트는 다음을 검증한다.

1. 동일 시각·작성자·내용의 로그 메시지 2개를 CLI ID 없이 먼저 기록한다.
2. CLI `b,c`를 관측하고 journal은 2개를 유지하며, 연결 인덱스에 `b→1,c→2`가 저장된다.
3. Journal과 MessageIngestor 모두 디스크에서 재생성한 뒤 CLI `c,d`를 받으면 메시지는 3개가 된다.
4. 로그에 세 번째 메시지를 반영해도 3개이며, 다시 재생성해도 중복되지 않는다.
5. 연결 인덱스 쓰기를 실제 파일 경로 충돌로 실패시키면 새 메시지를 성공으로 기록하지 않는다. 충돌 해소 후 재시도하면 4개가 되고 후속 로그 반영 후에도 4개다.
6. activity journal에는 실제 메시지 행만 있으며 연결 메타데이터는 없다. 중단된 마지막 인덱스 append는 유효한 접두부를 보존해 복구한다. 완성된 손상 행은 조용히 무시하지 않고 오류를 발생시킨다.

검증 명령은 위 세 테스트 파일 실행 명령과 동일하다. 추가로 `./tools/Invoke-Node.ps1 --check tools/mission-control/poll-cache.cjs`를 실행했다. 최종 결과는 10/10 통과, 서버와 캐시 모듈 문법 검사 및 diff 공백 검사 통과다. 기존 비중첩 tail의 원본 ID 부재에 따른 판정 한계는 남지만, 이번에 재현된 겹치는 tail의 재시작 누락은 회귀 테스트로 해결을 확인했다. 실제 서버 재시작·Studio 조작·Git push는 수행하지 않았다.
