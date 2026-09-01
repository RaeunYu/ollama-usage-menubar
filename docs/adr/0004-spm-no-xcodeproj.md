# Xcode 프로젝트 없이 SPM + 번들 스크립트로 빌드한다

개인용 무서명 앱이고, 빌드·검증은 주로 에이전트가 CLI에서 수행한다. Swift Package 하나로 라이브러리(`OllamaUsageKit`, 로직)와 실행 파일(앱)을 관리하고, `scripts/make-app.sh`가 실행 파일과 Info.plist를 조립해 `.app` 번들을 만든다. .xcodeproj나 xcodegen은 쓰지 않는다 — 빌드 경로를 하나로 유지해 CLI 검증 가능성을 지키기 위함이다. 배포·서명이 필요해지는 시점에 재검토한다.