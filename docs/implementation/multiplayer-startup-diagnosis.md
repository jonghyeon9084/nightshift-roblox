# 실제 다인 접속 실패 재진단 — 2026-11-01

메인이 기존 테스트와 Roblox Studio 로컬 로그의 시간만 대조했다. 인증·토큰 정보는 읽거나 기록하지 않았다.

- 서버 로그 `...20261031T145315Z_Studio_D5D1D_last.log`: 14:54:14.873 UTC에 NightShift 서버 준비, 14:54:59.790에 결과 전송, 같은 초에 테스트 3개 인스턴스 종료. 기존 probe의 45초 제한과 일치한다.
- 두 클라이언트 로그 `...20261031T145423Z_Studio_3E8F0_last.log`, `...20261031T145424Z_Studio_06282_last.log`: 그래픽 초기화가 각각 14:55:01.902, 14:54:58.181 UTC. 첫 클라이언트의 기본 플러그인 초기화는 14:55:09까지 이어졌다.
- 따라서 **클라이언트 초기화가 끝나기 전에 테스트 하네스가 서버를 종료했을 가능성이 높다.** 접속 실패 원인이 확정되거나 해결된 결과는 아니다. 보안/계정/방화벽 설정은 변경하지 않았다.

`tools/integration/multiplayer-probe.luau`의 실제 클라이언트 응답 대기를 최대 180초로 늘리고 플레이어별 접속 경과 시간·총 경과 시간을 기록한다. 2개 응답이 오면 즉시 끝난다. 클라이언트 Remote 준비를 명시적으로 기다린다. 이 변경을 컴파일 성공이나 다인 테스트 통과로 기록하지 않는다.

Integrator가 단독 Studio 쓰기 소유권을 얻은 다음 공식 `ExecuteMultiplayerTestAsync(2,...)`로 한 번 재검증한다. Players=2와 서로 다른 두 실제 LocalScript 응답이 필요하다. 성공하면 실제 소유권·경합/도난 검사로 확장하며, 실패하면 새 시간 증거와 오류를 수집하고 반복 무한 재시도하지 않는다. probe는 저장 전에 모두 제거한다.

공식 근거: [StudioTestService](https://create.roblox.com/docs/reference/engine/classes/StudioTestService), [Studio 테스트 모드](https://create.roblox.com/docs/studio/testing-modes). 메서드의 반환 성공만으로 클라이언트 접속이나 게임 검증을 통과로 판단하지 않는다.
