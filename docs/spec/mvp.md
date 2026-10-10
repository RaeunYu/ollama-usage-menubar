# Ollama Usage MVP 스펙 (확정본)

2026-09-01 인터뷰에서 확정된 "공유 이해 최종안" + 사용자 후속 수정(A8~A12, 메뉴바 UI 2건, 2026-10 API 개편 대응)을 기록한 것.
이 문서가 이 프로젝트의 Spec 리뷰 기준이다. 도메인 용어는 `CONTEXT.md`, 데이터 소스 사실은 `docs/research/ollama-cloud-balance-api.md`, 설계 근거는 `docs/adr/`를 따른다.

## 데이터

- **단일 소스**: `GET https://ollama.com/api/balance`, `Authorization: Bearer <키>` — 쿼리 파라미터 없음. 공식 문서: https://docs.ollama.com/api/balance.md ([ADR-0008](adr/0008-balance-api-single-source.md)). 디코딩은 필드 누락·추가·타입 변화에 관대하게 (공식 스펙의 `included`는 `oneOf` — 레거시 플랜은 `session`/`weekly`만 준다. 그 경우 값을 비우고 `—`로 표시).
- **제공 크레딧** = `included.allowance_usd`, **잔여 크레딧** = `included.balance_usd` — 둘 다 서버 값 그대로.
- **잔여 비율** = 잔여 크레딧 ÷ 제공 크레딧 (앱은 나눗셈만; 제공량이 0이거나 없으면 `—`, 범위 밖이면 0~1 고정).
- **플랜 시작일** = `included.period.from`, **플랜 초기화** = `included.period.until` — 사용자 로컬 기준 날짜로 표시.
- `GET /api/usage`는 쓰지 않는다: 기간별 사용 통계(`range=24h|7d|30d`뿐)라 "이번 달 1일~오늘"을 지정할 수 없고, 잔액도 주지 않는다. 모델별 요청 수는 어느 엔드포인트에도 없어 **UI와 코드에서 제거**했다(공식 "Coming soon"에 모델별 내역이 예고되어 있으므로 나오면 재조사).

## 메뉴바

- 잔여 % 텍스트 **+ progress bar 그래픽을 함께** 표시. 위젯 2~3칸 폭 허용.
- (후속 수정) 숫자는 더 작아도 된다. 그래픽은 명확히 보여야 한다 — 메뉴바 소재 위에서 트랙·채움이 모두 식별 가능할 것.
- 색상 3단계: 잔여 ≥50% 녹 / 20~49% 노랑 / <20% 빨강 — 임계값과 hex(예: `#028384`) 모두 설정 파일에서 변경 가능.
- 상태 구분 표시: 소진(402 — 문서엔 없지만 오면 소진으로 해석) / 키 문제(401) / 계정 정지(403) / 429 백오프 / 잔액 조회 일시 불가(503) / 네트워크 실패 — 서로 다르게.

## 드롭다운

1. 잔여 크레딧 (달러 + 퍼센트) — 완성 결과물 기준 이 배치가 더 낫다는 사용자 확정(2026-09-03)
2. 제공 크레딧 (`allowance_usd`)
3. 플랜 시작일 (`period.from`)
4. 플랜 초기화 (`period.until`)

- 라벨은 한국어. 메뉴 열림 시 강제 갱신, 마지막 갱신 시각 표시.
- 보조 메뉴: "지금 새로고침"(⌘R), "API 키 설정…", "설정 파일 열기", "원문 JSON 복사"(스키마 관측 창구), "Ollama 설정 페이지", 종료.

## 설정 파일

- 위치 `~/Library/Application Support/OllamaUsage/config.json`, 첫 실행 시 기본 파일 생성.
- **모든 속성에 한국어 `description` 키를 병기**해 사용자가 파일만 읽고도 이해하게 한다. 색상은 hex.
- 필드: `polling_interval_seconds`(기본 60, 10~300으로 고정), `color_stages`(임계값+hex). 제공 크레딧·플랜 주기는 API가 주므로 설정에 없다.
- 깨진 속성은 기본값으로 폴백. 전체가 깨진 JSON이면 기본값을 돌려주되 **사용자 파일을 절대 덮어쓰지 않는다**.
- **API 키는 이 파일에 절대 저장하지 않는다**(ADR-0003 — Keychain 전용).

## 폴링

- 기본 60초 백그라운드 폴링(서비스 문서의 권장값 — 레이트 리밋은 사용자당 분당 10회) + 드롭다운 열림 시 즉시 갱신 + 설정 파일에서 간격 조절.
- 429면 지수 백오프(상한 10분), 성공 시 복귀.

## 키

- macOS Keychain에만 저장. 메뉴의 "API 키 설정…"에서 입력/삭제. 첫 실행 자동 팝업(온보딩)은 채택하지 않는다 — 다른 작업 중 창 노출이 방해가 되므로(2026-09-03 사용자 결정), 안내는 드롭다운의 키 오류 상태가 담당한다. 설정 파일·코드·테스트에 키를 두지 않는다.

## 플랫폼·배포·식별

- SwiftUI `MenuBarExtra`, Swift Package Manager 단일 패키지(Xcode 프로젝트 없음, ADR-0004), 개인용 로컬 빌드. 번들은 애드혹 서명(키체인 ACL 안정화 — ADR-0006), 배포·공증은 생략.
- 표시명 "Ollama Usage", Bundle ID `com.yulaeun.ollama-usage-menubar`.

## 개발 도구

- `OllamaUsage --label-preview` — 화면 캡처 권한 없이 메뉴바 라벨을 PNG로 렌더링해 검증하는 도구(다크/라이트, 색상 단계별).

## 범위 밖 (백로그)

- 레거시 플랜(`included.session`/`weekly`) 지원 — 지금은 `—`로 물러난다.
- API 키가 필요 없는 로컬 서버 프록시 경로(`localhost:11434/api/balance`, Ollama v0.40.1+).
- `eval_count` 기반 로컬 가계부, 다계정 지원.
- 모델·API 키별 내역 — 공식 문서의 "Coming soon"이 실제로 나오면 재조사.
