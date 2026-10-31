# 자동 배정 독립 검토 반영

2026-10-31 · 메인 통합. `worker-pool-review.md`의 R1–R8을 수용했다. 기존 검토 보고서는 발견 당시 증거로 보존한다.

| 항목 | 반영 |
| --- | --- |
| R1 경로 별칭 | 슬래시·대소문자·점 요소를 공통 정규화, 루트 범위 충돌도 확인 |
| R2 대화 재사용 범위 | 작업별 chatName 중복 거부. 같은 워커는 새 그룹으로 재사용. 예상 외 참가자는 보수적 잠금 |
| R3 한도 오류 유실 | 한도/인증 오류를 durable halt로 보존, 새 요청과 일반 resume 차단 |
| R4 참가자 초과 | 기존 대화 참가자 집합을 배정과 정확히 대조 |
| R5 idle 활성 표시 | 완료 표식 유예는 waiting, observedState와 사유 유지 |
| R6 발행 직전 경합 | 등록 준비와 읽기 전용 guard 분리. 모델 설정 뒤 참가자·용량·파일·메모리 재확인 |
| R7 동적 정원 | 작업 manifest와 별개로 현재 capacityLimit을 매번 읽음 |
| R8 관측 순서 | 풀과 메인의 기존 진행 작업을 먼저 관측하고 한도를 확인한 뒤 신규 발행 |

검증: `Invoke-Node.ps1 --test tools/model-routing.test.cjs tools/runner/pool.test.cjs tools/runner/pipeline.test.cjs tools/runner/io.test.cjs tools/runner/append.test.cjs` **100/100 통과**. 실제 사용 한도를 발생시킨 검사는 아니며 격리된 mock 회귀와 로컬 체크포인트/소켓 검사다. 실제 Maestro 임시 PoolReview 등록·model/effort 배정·응답·완료 후 비활성은 로컬 실행기 기록으로 별도 확인했다.

작업 정의/완료 이력은 유지한다. 운영 중 새 작업은 새 ID/chatName으로 추가한다. 외부 수동 실행과 완전한 분산 트랜잭션 잠금은 아니며 발행 직전 확인과 Maestro의 busy 거절을 사용한다.
