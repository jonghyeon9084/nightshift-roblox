# 로컬 Studio 통합·재현

NightShift-Integrator만 Studio 쓰기를 수행한다. 실행 기록과 범위는 `docs/implementation/integration-report.md`, `.setup/studio-verification.json`을 따른다. 테스트 코드는 게시용 게임에 설치하지 않는다.

## 설치

프로젝트 루트 PowerShell에서 실행한다. Studio 대상이 하나뿐이어야 한다. 먼저 `preflight` 출력의 Place와 Edit 모드를 확인한다. 대상이 다르거나 Play 중이면 설치하지 않는다.

```powershell
./tools/integration/Invoke-Studio.ps1 tools/integration/preflight.json
./tools/Invoke-Node.ps1 tools/integration/build-loader.cjs
./tools/integration/Invoke-Studio.ps1 tools/integration/install.json
```

`studio.cjs`는 기존 `tools/studio-mcp.cjs`의 공식 클라이언트를 재사용한다. 일반 LocalAppData의 `mcp.bat`가 없을 때만 `NIGHTSHIFT_STUDIO_MCP`의 설치된 공식 `StudioMCP.exe`를 실행하도록 프로세스 시작 부분을 메모리에서 바꾼다. 기존 파일·프로토콜은 변경하지 않는다. `Invoke-Studio.ps1`의 버전 경로는 이번 PC에서 확인한 경로이며 Studio 업데이트 후 없으면 설치된 공식 경로를 다시 확인해야 한다. 외부 서버/API를 대체 사용하지 않는다.

로더는 `.setup/integration/install.luau`와 소스 해시·타입·경로 manifest를 생성한다. Edit에서만 실행되며 소유권·중복 이름·타입 충돌을 변경 전에 검사한다. Lua 11개를 실제 서비스에 설치하고 변경 없는 소스는 유지한다. 변경된 ModuleScript는 require 캐시가 남지 않게 교체한다. 월드 변경은 분리된 모델에서 먼저 생성한 뒤 소유한 `Workspace.NightShiftWorld`만 교체한다. 기존 Baseplate·SpawnLocation·비소유 콘텐츠를 삭제하지 않는다. 충돌은 수동 검토 대상으로 중단한다.

## 실제 플레이

```powershell
./tools/integration/Invoke-Studio.ps1 tools/integration/start.json
./tools/Invoke-Node.ps1 tools/integration/play-flow.cjs
./tools/Invoke-Node.ps1 tools/integration/postplay.cjs
./tools/integration/Invoke-Studio.ps1 tools/integration/stop.json
./tools/integration/Invoke-Studio.ps1 tools/integration/final.json
```

이 명령은 같은 PowerShell 세션에서 실행해야 MCP 경로 환경변수가 유지된다. `start.json`은 설치 재실행 후 공식 `start_stop_play`로 시작한다. Play 직후 Hub에서 `play-flow.cjs`를 실행한다. 공개 상태 패킷을 읽는 클라이언트 관찰기를 연결하고 실제 키/마우스와 `Humanoid:MoveTo`로 Store01의 주문 5개, 정전, 결과, 무료 로비 복귀를 수행한다. 이동은 거리와 제한 시간을 검사하며 캐릭터 순간이동·서버 상태 주입을 하지 않는다. `--resume`은 같은 관찰기가 있는 진행 중인 Store01 근무만 이어간다. 테스트 도중 별도 입력을 섞지 않는다.

`postplay.cjs`는 Lobby에서 시작하여 다른 세 점포 입장/로드와 Hub 복귀를 확인한다. 이 안의 마커 제거·복원은 **합성 클라이언트 재바인딩 검사**이며 실제 스트리밍 검사가 아니다. 실패하더라도 종료 명령을 별도로 실행하고 Edit 복귀를 확인한다. `.setup/integration/*jsonl`은 실패를 포함한 누적 원본 기록이다.

수동 재현은 Play → Hub 안내판 E → 1번 점포 → P 혼자 연습 → E 집기/내려놓기/접수 → 정전 시 차단기 E와 화면의 1/2/3 도형 순서 → 주문 5개 → 결과 E 순이다. 창고는 문을 통과해 이동한다. 준비 버튼을 1.6초 누른 채 상태 갱신 후 놓으면 같은 버튼에서 요청 1회가 발생해야 한다.

## 검사와 증거

```powershell
./src/server/tests/Verify-Server.ps1
./src/client/tests/Run-StaticChecks.ps1 -LuauBin "$PWD/tools/world/.validation/luau-0.745"
./tools/Invoke-Node.ps1 tools/world/verify-world.cjs tools/world/.validation/luau-0.745
```

위 검사는 오프라인이다. 실제 플레이와 구분한다. `collect-verification.cjs`는 이번 실행 로그·현재 소스 해시·저장 파일을 검증하고 JSON을 조립할 뿐 테스트를 실행하지 않는다. 기존 오프라인 `.validation/verification.json`은 빌드 단계의 역사적 기록이므로 최신 통합 결과로 읽지 않는다. 이번 오프라인 로그는 `.setup/integration/*-offline.txt`다.

로컬 저장은 Studio File → Save to File As로 `.setup/NightShift-local.rbxl`에 수행했다. 자동 스크립트는 저장·게시하지 않는다. 최종 상태는 Edit이며 Studio를 닫지 않는다.
