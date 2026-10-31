# 모바일 개발 상황실

2026-10-31: 접근 키 없는 외부 HTTPS 루트 주소에서 실제 Maestro 상태와 이력 조회를 확인했다. 현재 설정은 **공개·무키·읽기 전용**이다.

- 로컬 지도: [이 PC의 개발 상황실](http://127.0.0.1:43821/).
- 고정 모바일 링크: [GitHub Pages 상황실](https://jonghyeon9084.github.io/nightshift-roblox/). Pages의 고정 화면 안에서 현재 Cloudflare Quick Tunnel 지도를 표시한다. 로그인이나 쿠키 없이 누구나 공개 지시·응답과 이력을 읽을 수 있다.
- 실제 PC 연결은 Cloudflare Quick Tunnel이다. Pages는 접속 화면과 최신 연결 주소만 호스팅하며 AI 실행이나 로그 저장을 담당하지 않는다. 직접 연결 주소는 로컬 `.setup/mobile-link.txt`, 고정 주소는 `.setup/mobile-stable-link.txt`에 있다.
- 게이트웨이는 별도 loopback 포트 43822에서 실행되며 `publicAccess=true`다. 허용된 화면·상태·이력 GET 경로만 제공하고 그 외 경로는 404, GET 이외는 405다. Maestro 제어 API·러너 정지 API·임의 파일 경로는 외부에 제공하지 않는다.
- 사용 중인 PC, 지도 서버, Maestro와 터널이 실행되어 있어야 최신 상태가 보인다. PC 종료·절전·네트워크 중단 중에는 모바일 접속도 끊긴다.
- 터널 재생성 시 내부 연결 주소는 바뀔 수 있지만 모바일 즐겨찾기 주소는 유지된다. `Start-NightShiftMobile.ps1`이 공개 터널 주소를 `codex/mobile-monitor` 배포 브랜치에 갱신한다. Pages 배포·캐시 갱신에는 시간이 걸릴 수 있으며 화면은 60초마다 주소 변경을 확인한다. PC 종료 후 클라우드 기록 조회는 미구현이다.
- 지도 화면은 2초마다 조회한다. 서버의 Maestro 조회는 조회 완료 후 5초, 화면을 60초 이상 보지 않으면 15초 간격이다. 실제 반영 시간에는 CLI 조회 시간도 포함된다. AI 요청은 발생하지 않는다.

## 전체 워커 지도

- 기본 화면은 메인 오케스트레이터 중심에서 등록된 전체 워커로 뻗는 지도다. 화면을 크게 보는 모드와 통신·기록을 함께 보는 모드를 전환할 수 있다.
- 중심 노드는 실제 그룹별 Moderator 세션을 통합 표시한다. 세션이 하나로 합쳐졌다는 뜻은 아니며 실제 그룹·발신자·수신자·시각은 메시지 상세에 남긴다.
- 워커 노드에는 관찰된 모델과 출처, 등록 대기·명령 수신·응답 상태를 표시한다. 등록만 된 워커를 실행 중으로 표시하지 않는다.
- 새로 확인된 실제 메시지만 이동 애니메이션으로 보여 준다. 과거 기록 재생과 실시간 관찰을 구분하고 연결이 끊기면 마지막 기록임을 표시한다. 내부 추론이나 가짜 통신을 생성하지 않는다.

## 기록 범위
- 기존 Maestro `chat.log`와 `history.jsonl`을 해당 NightShift 그룹별로 `.setup/history/maestro/<chatId>/`에 복사 보관한다.
- `.setup/history/activity.jsonl`: 실제 지시·응답 전문, 관찰한 작업 상태 변경, `src/`, `docs/`, `tools/`의 코드·문서 내용 해시 변경을 누적한다.
- 상주 실행기의 `.setup/runner/events.jsonl`과 실제 모델 배정 `.setup/model-routing.jsonl`도 이력의 상태 이벤트로 가져온다. `.setup/runner/state.json`은 진행 단계와 발행 체크포인트이며 실행 로그는 같은 폴더의 `stdout.log`, `stderr.log`다.
- 기존 대화는 원본에서 가져온다. 과거 상태 전환이나 기록 도입 전 파일 변경 이력은 복원했다고 주장하지 않는다.
- 최초 파일 확인은 기준점이다. mtime은 파일 수정 시각이며 실제 관찰 시각과 구분한다. 파일 변경이 워커 성공·테스트 통과를 증명하지 않는다.
- 개별 도구 호출/키 입력/내부 추론 전체를 수집하는 감사 시스템은 아니다. 관찰 사이의 매우 짧은 상태 변화와 파일 삭제는 이 기록에 포함되지 않을 수 있다.
- 지도에는 관찰 가능한 현재/최근 턴의 도구 호출 수·최근 시각·허용된 도구 이름을 별도 활동 메타데이터로 표시한다. 도구 인수·출력 전문·내부 추론을 표시하지 않으며, 이 수치를 워커 간 메시지 수로 해석하지 않는다.
- 화면을 닫아도 서버가 켜져 있으면 수집한다. 재시작 시 이벤트 ID와 마지막 상태를 읽어 중복을 억제한다.
- 화면에서 종류별 필터, 내용 검색, 전문 펼치기, 이전 기록, 전체 JSONL 다운로드를 지원한다.
- 저장은 이 PC에만 한다. 클라우드 영구 백업은 아직 없다. `.setup/`은 Git에서 제외되어 있다.

## 상주 개발 파이프라인

- `tools/runner/resident.cjs`는 로컬 그룹 기록의 `fs.watch` 이벤트와 2.5초 안전 상태 조회로 진행을 감시한다. 분 단위 예약 자동화가 아니다. 상태 조회는 AI 요청을 만들지 않고, 검증된 다음 단계 발행만 실제 Maestro 작업을 시작한다.
- [개발 매니페스트](../tools/development-pipeline.json)는 첫 버전 5단계에 **성장·유통 계약 → 저장·경제·배송·8매장 병렬 구현 → 서버·화면 연결 → 독립 검토 → Studio 통합** 5단계를 추가한 유한 10단계다. 작업 완료가 확인되면 같은 관찰 회차에서 다음 단계를 발행한다. 전체 역할과 흐름은 [README 구조도](../README.md#오케스트레이터-전체-구조)에 있다.
- 완료에는 현재 요청 뒤의 Moderator 완료 표식, 그룹 idle, 필수 산출물 파일이 필요하다. 새 발행 단계는 파일 해시·수정 시각도 검증한다. idle이나 문서 저장만으로 완료를 판정하지 않는다.
- 전송 전 체크포인트와 실제 사용자 메시지 해시를 남겨 재시작 중복 발행을 막는다. 발행 여부가 불명확하거나 제한·인증·오류가 관찰되면 `attention`으로 멈춘다. 다른 활성 그룹까지 합산한 참가자 수가 현재 정원 4명을 넘으면 `waiting-capacity`로 대기한다. Moderator는 이 참가자 정원에 포함하지 않는다.
- 2026-10-31 확인 시 실제 PID 18980이 `resident/running/scale` 상태로 기존 NightShift-Design 작업을 채택했고 `adopted` 이벤트가 기록됐다. 이때 새 작업 중복 발행은 없었다. 후속 구현·검토·Studio 테스트나 16인 성능 테스트가 완료됐다는 뜻은 아니다.
- 모든 단계가 끝나면 `awaiting-review`, `completed=false`로 남는다. 메인이 실제 통합·테스트 증거와 미검증 사항을 검토해야 한다. 로컬 1~2클라이언트 검사와 실제 16인·4점포 부하 검증은 별개이며, `MaxPlayers=16` 설정 자체를 통과로 표시하지 않는다.

## 운영
- 고정 주소 배포 설정: GitHub Pages → Deploy from a branch → `codex/mobile-monitor` → `/ (root)`. `tools/mobile-site/`의 화면 소스와 `tools/publish-mobile-site.cjs`를 사용한다. 생성 전용 체크아웃은 `.setup/mobile-site-publisher/`이며 게임 개발 체크아웃·main 브랜치를 변경하지 않는다.
- 로컬 `.setup/mobile-pages-enabled`가 있을 때 시작 스크립트의 자동 주소 갱신이 활성화된다. 기존 Git 로그인만 사용하며 새 API 키를 생성하지 않는다. 갱신 실패는 경고로 남기고 현재 직접 링크와 로컬 개발은 유지한다.
- `tools/Start-NightShiftMobile.ps1`: 기존 연결이 있으면 재사용하고 없으면 숨김 프로세스로 게이트웨이·터널 실행.
- `tools/Stop-NightShiftMobile.ps1`: 이 프로젝트 소유의 게이트웨이·터널만 종료. 로컬 지도·Maestro·Studio 유지.
- `tools/Start-NightShiftRunner.ps1`: 숨김 상주 러너 실행, singleton 확인. `tools/Stop-NightShiftRunner.ps1`은 정확한 프로세스를 검증한 뒤 정상 종료하며 Maestro와 진행 중 작업은 유지한다. 원인 해결 후 attention 상태를 재개할 때만 정지 후 `Start-NightShiftRunner.ps1 -Resume`을 사용한다.
- `Open-NightShift.cmd`: 기존 모바일 설정이 있을 때 함께 시작. 새 링크는 `.setup/mobile-link.txt`에서 확인.
- 재부팅 자동 시작·운영체제 절전 설정은 변경하지 않았다.
- 별도 유료 서비스·OpenAI API·유료 크레딧은 사용하지 않는다.

## 검증
- 모델 상태/라우팅 및 로그 중복 방지·필터·페이지네이션·게이트웨이 접근 범위 테스트와 러너 격리 테스트 16개가 통과했다. 이는 코드 검증이며 Studio 플레이 테스트와 구분한다.
- 실제 외부 HTTPS `/api/state`를 쿠키나 접근 키 없이 조회해 HTTP 200, `ok=true`, 실제 등록 에이전트·그룹과 `development.mode=resident`, `development.status=running` 응답을 확인했다.
- 러너 `/health`와 저장된 state에서 PID 18980·기존 Design chatId·채택 체크포인트를 확인했다. 로그에는 resident-started와 adopted가 있고, 해당 초기 확인 시점에 dispatch-prepared 이벤트는 없었다.
- 브라우저 390px 화면에서 가로 넘침 없음 확인. 실제 사용자의 모바일 기기에서의 접속은 아직 확인하지 않았다.

공식 자료: [Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).
