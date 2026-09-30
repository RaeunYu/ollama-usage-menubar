# Ollama Usage (menubar)

Ollama Cloud 구독의 **크레딧 사용량을 macOS 메뉴바에서 실시간에 가깝게** 보여주는 개인용 앱입니다. 메뉴바에는 잔여 %와 progress bar가 함께 표시되고, 드롭다운에서 제공 크레딧·잔여 크레딧·갱신 예정일·모델별 요청 수를 확인할 수 있습니다.

> Ollama Cloud가 2026-08-31에 GPU-time 과금에서 **토큰 단가 기반 크레딧 풀**로 요금제를 전환하면서, "이번 달 크레딧이 얼마나 남았나"를 한눈에 보고 싶어 만든 도구입니다. 이 전환 이후의 요금 구조와 사용량 조회 API에 대한 1차 소스 조사는 [docs/research/ollama-cloud-usage-credits-api.md](docs/research/ollama-cloud-usage-credits-api.md)에 정리되어 있습니다.

## 동작

- **메뉴바**: 잔여 % 텍스트 + progress bar. 잔여 비율에 따라 색상 단계 적용 (≥50% 녹 / 20~49% 노랑 / <20% 빨강 — 임계값·색상은 설정 파일에서 변경 가능)
- **드롭다운**: 잔여 크레딧(달러+%) · 제공 크레딧 · 갱신 예정일 · 모델별 요청 수
- **폴링**: 기본 60초 + 메뉴를 열면 즉시 갱신 + `429` 지수 백오프(상한 10분)
- **상태 구분**: 크레딧 소진(402) / API 키 문제(401) / 요청 과다(429) / 네트워크 실패를 서로 다르게 표시

데이터 소스는 Ollama가 공식 문서화하지 않은 `GET https://ollama.com/api/usage`입니다. 스태프가 사용법을 공개한 엔드포인트를 직접 확인해 채택했고([ADR-0001](docs/adr/0001-undocumented-usage-api.md)), 스키마가 언제든 바뀔 수 있다는 전제로 파서를 필드 누락·추가·타입 변화에 관대하게 유지합니다.

## 요구 사항

- **Apple Silicon Mac, macOS 15 이상** (macOS 26 Tahoe에서 개발·검증)
- **Ollama 계정과 API 키** — [ollama.com/settings/keys](https://ollama.com/settings/keys)에서 발급. 무료 플랜(starter 크레딧)으로도 동작합니다. 단, Free 플랜은 제공 크레딧 금액이 비공개라 달러 환산 표시 대신 % 위주로 보입니다.

## GitHub에서 받아 설치하기 (소스 빌드)

저장소에 실행 파일은 커밋하지 않으므로, 아래처럼 직접 빌드합니다. Xcode 또는 Command Line Tools(Swift 6.0+)가 필요합니다.

```bash
git clone <이 저장소 URL>
cd ollama-usage-menubar
./scripts/make-app.sh          # swift build(release) + .app 번들 조립 + 애드혹 서명
open ".build/Ollama Usage.app"
```

첫 실행 후:

1. 메뉴바에 새 아이콘이 나타납니다 (키가 없으면 `키`로 표시).
2. 아이콘 클릭 → **API 키 설정…** → 키 붙여넣기 → 저장. 키는 **Keychain에만** 저장되고 설정 파일이나 코드에 기록되지 않습니다.
3. 60초 안에 메뉴바에 사용량이 표시되기 시작합니다.

설정 파일은 `~/Library/Application Support/OllamaUsage/config.json`에 자동 생성되며, 모든 속성에 한국어 설명이 달려 있습니다:

```json
"monthly_pool_usd": {
    "description": "제공 크레딧 — 플랜이 매월 부여하는 크레딧 총액(달러). 예: Pro 60, Max 300, Team 1000",
    "value": 60
}
```

`polling_interval_seconds`(10~300초), `billing_day_of_month`(갱신 기준일 — 구독을 시작한 날), `color_stages`(임계값+hex)도 같은 파일에서 바꿀 수 있고, 저장 즉시 다음 폴링에 반영됩니다.

## 친구에게 전달하기 (zip)

빌드가 번거로운 상대에게는 빌드된 `.app`을 zip으로 직접 전달하는 방법이 있습니다. 상세 절차는 [docs/spec/mvp.md](docs/spec/mvp.md)와 아래 요약을 참고하세요:

```bash
./scripts/make-app.sh release
ditto -c -k --sequesterRsrc --keepParent ".build/Ollama Usage.app" ~/Desktop/OllamaUsage.zip
```

받는 쪽 주의사항: Gatekeeper가 무서명(애드혹 서명) 앱을 막으므로 **우클릭 → 열기**로 한 번 허용하거나 `xattr -cr "Ollama Usage.app"` 실행이 필요합니다. 그리고 API 키는 각자 자신의 키를 키체인에 넣습니다(전달자의 키가 앱에 포함되지 않습니다).

## 문서 — 이 프로젝트의 기록

| 문서 | 내용 |
|---|---|
| [CONTEXT.md](CONTEXT.md) | 도메인 용어집 (크레딧, 제공 크레딧/Pool, 사용·잔여 비율, 갱신 예정일, 소진…) |
| [docs/spec/mvp.md](docs/spec/mvp.md) | 확정 스펙 (Spec 리뷰의 기준) |
| [docs/research/](docs/research/ollama-cloud-usage-credits-api.md) | Ollama Cloud 요금 개편·사용량 API 1차 소스 조사 (엔드포인트 실측 스냅샷 포함) |
| [docs/adr/](docs/adr/) | 설계 결정 기록 |

아키텍처 결정 요약:

- **무문서 API를 1차 데이터 소스로** — `/api/usage`는 공식 문서가 없지만 엔드포인트 실존이 확인된 엔드포인트. 스키마 변경에 관대한 파싱으로 대응 ([ADR-0001](docs/adr/0001-undocumented-usage-api.md))
- **잔여 계산은 서버 값 단일 출처** — 서버가 주는 사용 비율을 그대로 쓰고, 앱이 직접 나누지 않는다 ([ADR-0002](docs/adr/0002-remaining-from-server-ratio.md))
- **API 키는 Keychain 전용** — 설정 파일에는 절대 저장하지 않는다 ([ADR-0003](docs/adr/0003-keychain-only-api-key.md))
- **Xcode 프로젝트 없이 SPM + 번들 스크립트** ([ADR-0004](docs/adr/0004-spm-no-xcodeproj.md))
- **자체 마이크로 테스트 러너** — CLT 툴체인에 XCTest·swift-testing이 모두 없어서 ([ADR-0005](docs/adr/0005-micro-test-runner.md))
- **애드혹 서명** — 키체인 ACL 안정화를 위한 최소 코드사인 ([ADR-0006](docs/adr/0006-adhoc-codesign.md))

## 개발

```bash
swift build                # 빌드
swift run usage-tests      # 테스트 (자체 마이크로 러너, exit 0 = 통과)
./scripts/make-app.sh      # .app 번들
```

구조는 두 계층입니다: `Sources/OllamaUsageKit`(로직 — 스키마 디코딩, 잔여 계산, 설정 파일, API 클라이언트. 테스트 대상) + `Sources/OllamaUsage`(얇은 앱 껍데기 — MenuBarExtra UI, 키체인, 폴링 루프). 로직 변경은 합의된 seam에서 red→green으로 진행하고, 테스트는 관측된 실제 API 응답 리터럴을 기대값으로 삼습니다.

## 이 프로젝트를 만든 방식 — AI 에이전트 협업

이 저장소의 모든 코드와 문서는 **DeepSeek Harness**(에이전트 런타임, [@deepseek-ai/dsh](https://github.com/deepseek-ai/dsh)) 위에서 **Z.ai GLM(`glm-5.3-flash:cloud`)** 모델 에이전트가 사람과의 대화만으로 작성했습니다. 사람은 요구사항을 답하고 결과를 검수했고, 구현·조사·문서화·리뷰는 에이전트가 수행했습니다.

작업 흐름 전체를 관통한 에이전트 스킬은 **[Matt Pocock의 AI skills](https://github.com/mattpocock)** 컬렉션입니다:

| 스킬 | 이 프로젝트에서 한 일 |
|---|---|
| `ask-matt` | "이 프로젝트를 어떻게 시작할까" 요청을 스킬 흐름으로 라우팅 |
| `research` | Ollama Cloud 요금 개편·사용량 API를 1차 소스(공식 블로그·GitHub 이슈/PR·엔드포인트 probe)로 백그라운드 조사 → 인용 문서화 |
| `grilling` | 설계 인터뷰 — 결정 나무를 라운드마다 좁혀 12개 설계 결정을 확정 |
| `domain-modeling` | `CONTEXT.md` 용어집과 ADR 6건 기록 |
| `tdd` | 합의된 5개 seam에서 red→green 슬라이스 (테스트 14건) |
| `writing-for-agents` | 에이전트가 다시 읽을 `AGENTS.md` 작성 |
| `code-review` | 표준·스펙 두 축을 병렬 서브에이전트로 리뷰 → 발견 17건 반영 |

그 외에 설계 인터뷰에서 확정한 스펙은 [docs/spec/mvp.md](docs/spec/mvp.md)에, 커밋 히스토리는 슬라이스 단위로 남아 있습니다 — "대화 → 리서치 → 스펙 → TDD → 리뷰"의 전 과정이 저장소 안에서 추적 가능합니다.

## 참고

- 이 앱은 무문서 API에 의존합니다 — Ollama가 응답을 바꾸면 고장 날 수 있고, 그때를 위해 파서는 관대하게, 원문 JSON 복사 메뉴가 관측 창구로 유지됩니다.
- 개인 사용 전제로 만들어졌습니다(무서명·비공증). 배포가 필요해지면 서명·공증 절차를 추가하세요.
- MIT License.
