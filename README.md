# 오늘도 정상영업

친구와 함께 운영하는, 조금 이상한 야간 편의점 Roblox 게임입니다. 게임 소스와 맵 생성기, 검사, Maestro 기반 개발 도구를 공개합니다. Roblox 게임 게시와 실제 상품 판매는 아직 하지 않았습니다.

## 현재 구현과 검증

2026-10-31 기준, 기존 4점포 버전을 Roblox Studio에 통합하고 **실제 1클라이언트에서 주문 5건 → 정전 Solo 해결 → 결과 → 무료 로비 복귀**를 완주했습니다. 최종 요청 응답 25건이 정상이었고 콘솔 오류가 없었습니다. 발견한 서버 시작·정전 오류를 수정하고 재검증했습니다. 상세 근거와 남은 항목은 [통합 검증 보고](docs/implementation/integration-report.md)에 있습니다.

실제 2인 협동·16인 부하·모바일·자연 발생 스트리밍/지연 경합은 미검증입니다. 오프라인 상태 모의 검사 통과를 실제 다인 플레이로 해석하지 않습니다. 당시 실제 MaxPlayers는 30, 전역 ClockTime은 14.5였으며 정원·야간 연출 검수가 남았습니다. 재미·유지율·수익도 아직 측정하지 않았습니다.

현재는 **직선 도로 양쪽 총 8매장**으로 확장하는 작업을 진행합니다. 사무실 PC 주문, 서버 공용 도매 재고, 배송 트럭·직접 운반·진열, 점포 간 경쟁·도난 알림, 개인 정보 저장/복원과 무료 성장이 대상입니다. 신규 기능의 구현·통합·실제 테스트 완료를 의미하지 않습니다. 최신 범위는 [8매장 경쟁·물류·성장 기획](docs/commerce-expansion-brief.md)을 따릅니다. [첫 버전 기획](docs/game-brief.md)과 [다인원 설계](docs/design/scale-plan.md)는 이전 단계의 기준과 기록입니다.

## 소스와 로컬 실행

| 경로 | 내용 |
| --- | --- |
| `src/server/`, `src/client/`, `src/shared/` | 서버, 화면·입력, 공유 규약 |
| `tools/world/` | 직접 제작한 맵 생성 소스 |
| `tools/integration/` | Studio 설치 로더와 플레이 검증 도구 |
| `tools/runner/` | 유한 단계 실행기·완료 판정·후속 단계 추가 |
| `tools/mission-control/` | 실제 개발 상태와 메시지를 읽는 활동 지도 |
| `docs/`, `setup-test/` | 기획·계약·검토·프롬프트와 검사 자료 |

Windows, Node.js, 공식 Codex의 ChatGPT 구독 로그인, Maestro와 Roblox Studio가 필요합니다. 개인 PC 경로·계정/그룹/Studio ID가 남아 있어 **다른 PC에서 바로 실행되는 설치 패키지는 아닙니다**. 먼저 [재현 환경과 초기 설정](docs/repository-setup.md)을 확인하세요.

```powershell
# 준비된 환경에서 로컬 상황실 열기
./Open-NightShift.cmd

# AI 요청을 생성하지 않는 실행기 단위 검사
./tools/Invoke-Node.ps1 --test tools/runner/pipeline.test.cjs tools/runner/io.test.cjs tools/runner/append.test.cjs
```

Place 파일과 다운로드한 실행 파일은 배포하지 않습니다. Studio의 소스 설치·수동 플레이 흐름은 [통합 도구 문서](tools/integration/README.md)에 있습니다. 현재 확장 중인 소스에는 기존 1인 완주 기록과 별도로 재통합 검증이 필요합니다.

## 개발 실행기와 활동 지도

상주 실행기는 실제 Maestro 기록, 최신 사용자 요청 뒤 마지막 Moderator의 완료 표식, 그룹 idle, 필수 파일 변경을 확인하고 다음 유한 단계를 발행합니다. 2026-10-31 굵은 `**[STAGE_READY:INTEGRATION]**` 표식을 인식하지 못해 멈췄던 문제를 수정했고, 기존 5단계를 `awaiting-review`까지 복구했습니다. 이제 독립된 plain·bold·inline-code 표식을 허용하고 인용·코드 블록·문장 안의 표식은 거부합니다. 승인된 후속 단계만 정상 정지 후 안전하게 추가합니다.

동시 실행 워커는 현재 **최대 4명**이며 매니페스트의 `maxWorkers`를 따릅니다(생략 시 기본 3명). 다른 활성 그룹의 참가자도 합산하고 자리가 부족하면 `waiting-capacity`로 기다립니다. 무제한 워커 생성이나 한도 우회는 하지 않습니다. 한도·인증·오류·불명확한 발행은 `attention`으로 멈춥니다. 운영과 백업·복구 절차는 [실행기 문서](tools/runner/README.md)를 따릅니다.

활동 지도는 기본 `http://127.0.0.1:43821`에서 열립니다. 확인된 명령·응답에 방향성 광점과 후광을 표시하고 원문·발신자·수신자·시각을 확인할 수 있습니다. 초기 과거 기록을 새 통신처럼 재생하지 않으며, 실행기 `attention`·실제 작업 중·대기를 구분합니다. 광점은 내부 추론을 보여 주지 않습니다. 지도 조회 자체는 AI 요청을 생성하지 않습니다. 모바일 운영 범위는 [별도 문서](docs/mobile-monitoring.md)에 있습니다.

모델 정책은 [tools/model-policy.json](tools/model-policy.json)에 있습니다. 복합 조정·검토는 `gpt-6-astra / high`, 일반 구현은 `gpt-6.1-sol / medium`, 작은 확인은 `gpt-6-luna / low`를 기본 등급으로 사용하며 역할별 예외가 있습니다. 이는 설정한 모델·추론 노력 등급이고, 실제 실행 모델은 관찰된 Codex `turn_context`와 구분합니다.

실행 상태·통신 원문·검증 로그·계정 정보는 로컬 `.setup/` 등에 보관하며 Git에서 제외합니다. 공개 저장소에는 소스·기획·검사·프롬프트를 포함합니다. API 키·다른 유료 제공자·추가 크레딧 구매를 사용하지 않는 개발 규칙과 파일 소유권은 [AGENTS.md](AGENTS.md)를 따릅니다.
