# 공개 소스 재현 환경

이 저장소는 개발 소스와 도구입니다. 원래 개발 PC의 개인 경로·Maestro 역할/그룹 ID·Studio 인스턴스 ID가 일부 스크립트, 요청 JSON, 과거 보고서와 프롬프트에 남아 있으므로 다른 PC에서 즉시 실행된다고 보장하지 않습니다. 로컬 인증·실행 기록·다운로드 바이너리·실제 Place는 포함하지 않습니다.

1. Windows에서 Node.js, 공식 Codex, Maestro, Roblox Studio를 준비합니다. Codex는 본인의 **ChatGPT 구독 로그인**을 사용합니다. OpenAI API 키·별도 유료 API·추가 크레딧은 이 프로젝트의 실행 경로가 아닙니다. 구독 한도에 도달하면 멈춥니다.
2. `AGENTS.md`, `docs/commerce-expansion-brief.md`, `tools/model-policy.json`을 읽고 본인 환경의 프로젝트 절대 경로와 기존 역할을 확인합니다. `tools/Get-NightShiftNode.ps1`, Maestro 설치 경로, 시작/정지 스크립트와 `tools/studio-mcp.cjs`의 경로 가정을 점검합니다. Node가 PATH에 없을 때 `tools/Invoke-Node.ps1`은 설치된 Codex 런타임을 찾아 사용합니다.
3. Maestro 역할·그룹은 본인 환경에 맞게 등록/연결하고, 매니페스트·프롬프트·`tools/integration/*.json`의 개인 경로와 세션/인스턴스 ID를 검토합니다. 단순 역할 등록과 실제 AI 실행은 별개입니다. 초기 설정 상태를 검토하기 전 상주 실행기를 시작하지 않습니다.
4. Roblox Studio는 본인 계정으로 로그인하고 공식 MCP 연결을 준비합니다. Edit 상태와 대상 인스턴스를 직접 확인한 뒤 `tools/integration/README.md`의 소스 로더 절차를 따릅니다. 소스 설치와 Play는 Studio를 변경하는 작업입니다. 클라우드 저장·음성·다인원·게시 설정은 로컬 단위 검사만으로 검증되지 않습니다.

AI 호출 없이 실행할 수 있는 러너 검사:

```powershell
./tools/Invoke-Node.ps1 --test tools/runner/pipeline.test.cjs tools/runner/io.test.cjs tools/runner/append.test.cjs
```

게임 코드는 확장 개발 중입니다. 기존 실제 1인 완주 결과의 범위는 `docs/implementation/integration-report.md`에 한정되며 최신 확장 전체의 플레이 통과를 보장하지 않습니다. Roblox 게임 공개 게시·실제 판매 설정은 별도 작업입니다.
