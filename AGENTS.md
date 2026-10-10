# AGENTS.md — Ollama Usage (menubar)

Ollama Cloud 크레딧 잔액을 메뉴바에 표시하는 개인용 macOS 앱. Swift Package Manager 단일 패키지로 빌드한다(Xcode 프로젝트 없음 — [ADR-0004](docs/adr/0004-spm-no-xcodeproj.md)).

## 문서 포인터

- **도메인 용어**는 `CONTEXT.md` — 용어를 쓰거나 새로 만들 때 먼저 맞춘다.
- **확정 스펙**은 `docs/spec/mvp.md` — 요구사항 범위를 판단할 때 기준으로 삼는다.
- **API 사실(스키마·엔드포인트·레이트 리밋·레거시 분기)**은 `docs/research/ollama-cloud-balance-api.md` — 데이터 소스를 건드리는 작업이면 먼저 읽는다. 2026-09 시점의 구 `/api/usage` 기록은 `docs/research/ollama-cloud-usage-credits-api.md`에 있다(대체됨).
- **"왜 이렇게?" 의문이 드는 구조**는 `docs/adr/` — 코드를 고치려다 놀랐다면 ADR부터 읽는다.

## 작업 방식

- 동작 추가는 `tdd` 스킬의 red→green 슬라이스로 한다. 테스트는 아래 합의된 seam에서만 쓴다.
- 완료 기준: `swift build && swift run usage-tests` 통과 (exit 0).

## 빌드·실행

- `swift build` / `swift run usage-tests`
- 앱 번들: `scripts/make-app.sh` → `.build/Ollama Usage.app`
- 테스트: 자체 마이크로 러너(ADR-0005) — 이 CLT 툴체인(Swift 6.0.2)에 XCTest·swift-testing 내장이 모두 없어서다.

## 환경 함정

- 빌드 SDK는 CommandLineTools의 macOS 15.1이다(시스템은 26.3). macOS 26 전용 API를 쓰지 않는다; 26 전용 기능이 필요해지면 그때 툴체인을 올린다.
- `/api/balance`는 공식 문서화된 엔드포인트다(https://docs.ollama.com/api/balance.md): 제공 크레딧 `allowance_usd`, 잔여 크레딧 `included.balance_usd`, 플랜 주기 `period.from`/`until`. 그래도 파서는 필드 누락·추가·타입 변화, 그리고 레거시 플랜 분기(`included`는 `oneOf` — `session`/`weekly`만 오는 경우)에 관대하게 유지한다.
- 레이트 리밋: 사용자당 분당 10회(문서화됨). 기본 60초 폴링이 서비스 권장값이다 — 간격을 줄일 때 이 한도를 넘지 않게 한다.
- API 키는 Keychain에만 둔다(ADR-0003). 설정 파일·코드·테스트에 넣지 않는다.
