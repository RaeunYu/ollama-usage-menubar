# AGENTS.md — Ollama Usage (menubar)

Ollama Cloud 크레딧 사용량을 메뉴바에 표시하는 개인용 macOS 앱. Swift Package Manager 단일 패키지로 빌드한다(Xcode 프로젝트 없음 — [ADR-0004](docs/adr/0004-spm-no-xcodeproj.md)).

## 문서 포인터

- **도메인 용어**는 `CONTEXT.md` — 용어를 쓰거나 새로 만들 때 먼저 맞춘다.
- **확정 스펙**은 `docs/spec/mvp.md` — 요구사항 범위를 판단할 때 기준으로 삼는다.
- **API 사실(스키마·엔드포인트·무문서 리스크)**은 `docs/research/ollama-cloud-usage-credits-api.md` — 사용량 데이터 소스를 건드리는 작업이면 먼저 읽는다.
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
- `/api/usage`는 무문서 API다(ADR-0001): 디코딩은 필드 누락·추가에 관대하게 유지한다.
- API 키는 Keychain에만 둔다(ADR-0003). 설정 파일·코드·테스트에 넣지 않는다.