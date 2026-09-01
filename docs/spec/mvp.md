# Ollama Usage MVP 스펙 (확정본)

2026-09-01 인터뷰에서 확정된 "공유 이해 최종안" + 사용자 후속 수정(A8~A12, 메뉴바 UI 2건)을 기록한 것.
이 문서가 이 프로젝트의 Spec 리뷰 기준이다. 도메인 용어는 `CONTEXT.md`, 데이터 소스 사실은 `docs/research/ollama-cloud-usage-credits-api.md`, 설계 근거는 `docs/adr/`를 따른다.

## 데이터

- 소스: `GET https://ollama.com/api/usage`, `Authorization: Bearer <키>` — 무문서 API(ADR-0001). 디코딩은 필드 누락·추가·타입 변화에 관대하게.
- 잔여 비율 = `1 − limits.monthly.usage` (서버 계산 비율 1순위 — 실측: 사용/제공 비율, ADR-0002). `activity.cost`는 표시에 쓰지 않는다.
- 갱신 예정일 = `activity.period.ending_at`의 날짜 부분(YYYY-MM-DD)만 파싱. 리셋 주기(매월 1일)를 코드에 하드코드하지 않는다.

## 메뉴바

- 잔여 % 텍스트 **+ progress bar 그래픽을 함께** 표시. 위젯 2~3칸 폭 허용.
- (후속 수정) 숫자는 더 작아도 된다. 그래픽은 명확히 보여야 한다 — 메뉴바 소재 위에서 트랙·채움이 모두 식별 가능할 것.
- 색상 3단계: 잔여 ≥50% 녹 / 20~49% 노랑 / <20% 빨강 — 임계값과 hex(예: `#028384`) 모두 설정 파일에서 변경 가능.
- 상태 구분 표시: 소진(402, 정상 상태) / 키 문제(401) / 429 백오프 / 네트워크 실패 — 서로 다르게.

## 드롭다운

1. 제공(총) 크레딧 — API에 없으므로 **설정 파일**에서
2. 잔여 크레딧 (API 기반, 달러+퍼센트)
3. 갱신 예정일 (API 기반)
4. 사용한 모델들과 각각의 request_count (API 기반)

- 라벨은 한국어. 메뉴 열림 시 강제 갱신, 마지막 갱신 시각 표시.
- 보조 메뉴: "API 키 설정…", "설정 파일 열기", 종료.

## 설정 파일

- 위치 `~/Library/Application Support/OllamaUsage/config.json`, 첫 실행 시 기본 파일 생성.
- **모든 속성에 한국어 `description` 키를 병기**해 사용자가 파일만 읽고도 이해하게 한다. 색상은 hex.
- 필드: `monthly_pool_usd`, `polling_interval_seconds`(기본 60, 10~300으로 고정), `color_stages`(임계값+hex).
- 깨진 속성은 기본값으로 폴백. 전체가 깨진 JSON이면 기본값을 돌려주되 **사용자 파일을 절대 덮어쓰지 않는다**.
- **API 키는 이 파일에 절대 저장하지 않는다**(ADR-0003 — Keychain 전용).

## 폴링

- 기본 60초 백그라운드 폴링 + 드롭다운 열림 시 즉시 갱신 + 설정 파일에서 간격 조절.
- 429면 지수 백오프(상한 10분), 성공 시 복귀.

## 키

- macOS Keychain에만 저장. 첫 실행 온보딩 + 메뉴의 "API 키 설정…"에서 입력/삭제. 설정 파일·코드·테스트에 키를 두지 않는다.

## 플랫폼·배포·식별

- SwiftUI `MenuBarExtra`, Swift Package Manager 단일 패키지(Xcode 프로젝트 없음, ADR-0004), 개인용 로컬 빌드·무서명.
- 표시명 "Ollama Usage", Bundle ID `com.yulaeun.ollama-usage-menubar`.

## 범위 밖 (백로그)

- `eval_count` 기반 로컬 가계부, raw JSON 디버그 뷰, 다계정 지원.