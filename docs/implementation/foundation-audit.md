# 기초 모듈 조기 데이터 무결성 감사

- 기준: `c5d3b226c28121540541e0064a2aa3500faafff5` (`c5d3b22`), 2026-10-31.
- 범위: 해당 커밋의 ProfileService, CommerceService, ProgressionService, DeliveryService 및 대응 spec, CommerceConfig, commerce-contract. `AGENTS.md` 확인 후 `git show`로 격리 추출했다. 아래 `file:line`은 모두 기준 커밋이다.
- 결과: **P1 1건, P2 2건을 로컬 재현. P0 확인 없음.** 실제 모듈·현재 서버/UI 코드는 변경하지 않았다.
- 생성 파일: 이 보고서와 `.setup/early-audit/`의 커밋 스냅샷, 재현 스크립트, 실행용 번들, 결과 로그. `.setup/`은 Git 제외 대상이므로 다른 PC에 인계할 때 재현 자료도 별도 전달해야 한다.

## 실제 수행한 확인

기존 네 모듈 spec을 로컬 Luau CLI로 실행했고 모두 통과했다(Profile 29사례/476검사, Commerce 313검사, Progression 53검사, Delivery 21사례). 이 결과는 fake 저장소·월드·엔진의 상태 검사이며 Studio/클라우드 검증이 아니다. 아래 추가 재현은 기존 spec에 없는 서비스 생명주기와 실제 모듈 간 경계를 대상으로 했다.

실행: 프로젝트 루트에서 `& .setup/early-audit/Run-Audit.ps1`.
핵심 소스: `.setup/early-audit/reproduce.luau`; 증거: `reproduce-output.txt`, `baseline-output.txt`.
설치된 `tools/world/.validation/luau-0.745/luau.exe`만 사용했다. 이 환경의 한글 절대 경로/상대 require 해석 실패를 피해 스냅샷을 함수로 감싼 단일 번들을 생성해 실행했다. 모듈 로직은 수정하지 않았다. 최종 실행 종료코드 0은 **현재 결함이 재현 조건과 일치함**을 뜻하며 수정 완료를 뜻하지 않는다.

## A1 · P1 · lease 상실 후 같은 서버 인스턴스에서 재접속 복구 불가

- **file:line:** `src/server/Modules/ProfileService.luau:226`, `:271`, `:312`, `:366`.
- **근거:** `load`는 기존 profile이 있고 Released가 아니면 저장소 재획득 없이 `get`을 반환한다. LeaseLost의 `get/save`는 모두 거절되고 `due`에서도 제외된다. 공개 API에 해당 entry를 재로드 가능한 상태로 바꾸는 경로가 없다.
- **재현:** t=1000 로드→Wallet=22 저장→t=1120 정확한 만료→같은 객체에서 load/save(release)/load. 모두 LEASE_LOST이며 저장소 호출 수가 증가하지 않는다. 새 객체 B는 같은 저장소에서 Wallet=22/Epoch=2로 정상 획득한다. 별도 사례로 release 확정 후 응답 1회 유실을 주입하면 저장소 Session=false인데도 같은 객체의 load가 계속 LEASE_LOST다.
- **영향/조건:** 일시 장애로 lease를 잃은 사용자가 같은 서버로 돌아오면 저장소가 정상이어도 이용 불가가 지속된다. 저장값 덮기나 자산 소실은 이 재현에서 발생하지 않았다. 현재 Main의 우회/서버 이동 처리는 감사 범위 밖이다.
- **최소수정:** 명시적 재접속/재획득 경로에서 busy 확인 후 만료·LeaseLost entry를 새 load 시도로 전환한다. 이전 dirty 데이터를 새 소유권에 덮지 말고 저장소 원본에서 시작하며 새 epoch로 옛 작업을 차단한다. `load` 분기 전 만료 refresh도 필요하다.
- **검증:** 같은 인스턴스에서 만료 및 응답유실 후 재획득 성공, 실제 타 소유자 존재 시 SESSION_LOCKED, 이전 epoch mutate/save 거절을 함께 검사한다. 기존 spec은 응답유실 뒤 **다른** 서비스 객체의 로드만 확인한다.

## A2 · P2 · 허용 길이 주문 ID가 배송 이벤트를 영구 거절시킴

- **file:line:** `src/server/Modules/DeliveryService.luau:66`, `:107`; `src/server/Modules/CommerceService.luau:12`, `:180`, `:458`, `:505`.
- **근거:** Delivery.register는 OrderId 최대 96바이트를 허용하지만 EventId에 `:Delivery:Dispatched` 20바이트를 추가한다. Commerce._event는 EventId에도 96바이트 상한을 적용한다. tick은 거절 결과를 처리하지 않고 Delivery도 이미 발생한 전이를 재발행하지 않는다.
- **재현:** 실제 Delivery+Commerce에 고유한 77바이트 또는 96바이트 OrderId를 생성하는 NewId를 주입한다. Water 1개 주문 후 t=5/17 tick: Delivery=Docked, Commerce=Reserved, Item=0, 운영자금=236, 공유재고=31. endShift도 INVALID_STATE로 끝난다. 76바이트 대조군은 Docked 및 endShift OK다.
- **영향/조건:** 허용 범위 입력으로 배송/정산 원장이 갈라지고 상품과 자금이 묶인다. 클라이언트 지정 ID 공격을 입증한 것은 아니다. 현재 Main의 NewId 최대 길이는 읽지 않았으므로 실게임 도달 여부는 미확인이다.
- **최소수정:** 내부 EventId를 별도 최대 길이로 검증하거나 주문 ID 상한을 접미사 길이만큼 줄여 생산·소비 계약에 동일하게 적용한다. 주문을 받은 뒤 이벤트만 거절하는 상태를 없앤다.
- **검증:** 76/77/96바이트 경계에서 주문 성공이면 출발·도착·회수·종료 정산까지 성공해야 한다. 제한하는 설계라면 처음 register/주문에서 돈·재고 변화 없이 거절해야 한다. 이벤트 중복 정산 방지도 유지한다.

## A3 · P2 · 보상 일시 실패 직후 퇴장하면 확정 판매의 개인 보상이 소실됨

- **file:line:** `src/server/Modules/CommerceService.luau:241`, `:426`, `:438`, `:442`, `:451`.
- **근거:** sellLine은 판매/거래 소비를 먼저 확정한다. award 실패 시 pending을 남기지만, depart로 context가 사라진 뒤 tick은 보상을 재시도하지 않고 삭제한다. 같은 거래 재전송은 캐시 성공을 반환할 뿐 보상을 다시 대기열에 넣지 않는다.
- **재현:** 실제 네 모듈을 연결하고 progression facade에 Sale award 1회만 PROFILE_UNAVAILABLE을 반환하는 실패 주입을 추가한다. 진열→판매 OK→재시도 tick 전에 depart→tick→같은 context 재연결→동일 sellLine 재전송. 상품 Sold/점포자금243/판매1건은 유지되지만 Wallet=0, XP=2, pending=없음이다. 퇴장 없는 대조군은 재시도 후 Wallet=2, XP=7이다. 프로필 자체는 두 경우 모두 같은 유효 epoch다.
- **영향/조건:** 확정 판매 후 일시적 보상 실패와 퇴장/소속 해제가 겹칠 때 보상이 누락된다. 장애 없는 판매의 누락이나 개인돈 복제는 확인하지 않았다. PROFILE_UNAVAILABLE은 통제된 실패 주입이며 현재 Main에서 실제 발생시키는 경로·빈도는 미확인이다.
- **최소수정:** context 부재만으로 미지급 기록을 폐기하지 않는다. 퇴장/교대 해제 및 프로필 최종 저장 전에 원래 TransactionId/epoch의 보상을 처리하거나 명시적으로 실패를 인계한다. 예전 보상을 새 epoch로 재발급해서는 안 된다.
- **검증:** 일시 실패→재시도 전 depart/endShift→같은 유효 epoch의 최종 저장 시 지급 결과를 확인한다. 재시도·재전송 중복 지급 없음과 실제 epoch 상실 시 오래된 보상 거절도 함께 검사한다. 기존 spec의 실패 재시도는 context가 유지되는 경우뿐이다.

## 그 외 판단과 미검증

로드/저장 실패를 기본 프로필로 대체해 기존 값을 덮는 경로, 정상 단일 큐 조건의 마지막 공용 재고 중복 판매, 같은 서비스 생명주기의 중복 거래 개인돈 복제, 도난/회수의 이중 상품 생성·타점포 회수 권한 우회는 검토 범위 내 확인되지 않았다. 이는 해당 조건을 벗어난 안전성 보증이 아니다.

Progression의 소비 TransactionId 표는 메모리에 있고 저장된 cursor만으로 거래 ID를 복원하지 않는다. 동일 epoch를 유지한 채 Progression 인스턴스를 교체하면 재지급 가능성이 있으나 계약은 서버 생명주기 동안 소비표 유지를 요구한다. 실제 인스턴스 교체 경로를 확인하지 않았으므로 별도 확정 결함으로 집계하지 않았다.

Studio, 실제 DataStore/CAS/네트워크 장애, 다중 클라이언트 동시 실행, 실제 거리·시야·이동/사망 검사, 현재 Main의 직렬 큐·요청 캐시·재접속 연결은 미검증이다. 외부 API·계정·게시·판매·로그인 정보에는 접근하지 않았다. 발견 사항의 수정과 Studio 검증은 정식 검토·통합 담당에게 인계한다.
