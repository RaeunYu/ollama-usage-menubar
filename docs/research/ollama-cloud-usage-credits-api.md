<!--
이 파일은 이 저장소의 리서치 노트 위치를 확립한다: docs/research/
(작성 시점에 저장소에 문서 컨벤션이 없었으므로, 이후 리서치 문서는 docs/research/*.md 에 둔다.)

작성일: 2026-09-01 (모든 출처 접근일)
조사 방법: 1차 소스만 사용 — ollama.com 공식 페이지/블로그, docs.ollama.com 공식 문서,
ollama/ollama 공식 GitHub 저장소(코드/이슈/PR), 그리고 ollama.com 엔드포인트에 대한 직접 비인증 probe.
-->
# Ollama Cloud 사용량·크레딧 API 조사 (메뉴바 앱 기초 리서치)

> 접근일 명기: 아래 모든 링크의 접근일은 **2026-09-01 (UTC)** 이다. Ollama Cloud 가격·문서는 변동이 잦은 신생 문서이므로, 인용한 날짜 기준으로 읽을 것.

---

## 1. 한 줄 요약

**판정: PARTIAL** — 계정 사용량 조회 엔드포인트 `GET https://ollama.com/api/usage` 가 **실제로 존재하며** (비인증 시 `401 {"error":"invalid credentials"}`, Ollama 스태프가 이슈에서 직접 사용법 공개), **응답 스키마와 레이트 리밋은 공식 문서화되어 있지 않다**. → 메뉴바 앱은 이 엔드포인트를 베타적 사설 API로 사용하되 스키마 변경(특히 2026-08-31 가격 개편 이후 `session`/`weekly` 필드의 유효성)을 견디도록 설계해야 한다.

---

## 2. Q1. 현재 Ollama Cloud 가격 모델 — credits/tokens 전환

### 전환 발표 (공식 블로그, 날짜 명시)

- 공식 블로그 포스트 **"Ollama's transparent pricing"**, 게재일 **August 31, 2026**: [ollama.com/blog/transparent-pricing](https://ollama.com/blog/transparent-pricing) (접근일 2026-09-01)
  - 첫 문단: "Ollama's Pro, Max, and Team plans now use transparent per-token pricing. Based on your feedback, every plan includes a monthly pool of usage credits."
  - 구모델(종료)에 대한 유일한 공식 서술 (FAQ 섹션 "Why make this change?"):
    > "we received feedback that **GPU-time based billing** was difficult to predict, especially as open models have grown much larger (Kimi K3 has 2.8 trillion parameters). Now, usage is based on industry-standard token pricing."
  - 구모델의 제한도 언급: "Ollama's new pricing has **no service fees and no 5-hour or weekly limits**."
  - 즉 공식 문구는 "GPU-hours"가 아니라 **"GPU-time based billing"** 이며, 5시간 세션/주간 한도 체계였음을 확인한다.

### 현재 유닛 구조 (크레딧이 무엇인가)

- 크레딧은 **달러화 표기의 "usage credits" 풀**이고, 소비는 **토큰 단위**로 각 모델의 공개 단가로 계산된다. "credit-based tokens"라는 문구는 공식 페이지에 그대로(verbatim) 등장하지 않는다 — 공식 표현은 "monthly pool of usage credits" + "per-token pricing" 이다. (전자: [blog/transparent-pricing](https://ollama.com/blog/transparent-pricing), 후자: [ollama.com/pricing](https://ollama.com/pricing), 접근일 2026-09-01)
- [ollama.com/pricing](https://ollama.com/pricing) FAQ "How is usage measured?":
  > "Usage is measured in tokens at each model's rates. The model pricing table lists the input, cached input, and output price per million tokens for every cloud model."
- 모델 가격표 (동일 페이지, "Prices are per million tokens") — 예시 (전체는 원문 참조):
  | Model | Input | Cached input | Output |
  |---|---|---|---|
  | `deepseek-v4-flash` | $0.44 | $0.014 | $1.32 |
  | `glm-5.3-flash` | $0.15 | $0.03 | $0.50 |
  | `kimi-k3` | $3.00 | $0.30 | $15.00 |
  | `qwen3.5:397b` | $0.60 | $0.60 | $3.60 |

### 티어 및 무료 허용량 (pricing 페이지 + 블로그 일치, 접근일 2026-09-01)

| 티어 | 월요금 | 포함 usage credits | 비고 |
|---|---|---|---|
| Free | $0 | "starter amount" (**금액 미공개** — "a starter amount of usage for a smaller set of starter models") | starter 모델만; 크레딧 추가 시 전 모델 사용 가능, 구독 불필요 |
| Pro | $20/mo (연간 $200/yr, 월 $16.67 환산) | **$60/mo** | 동시 요청 3개 |
| Max | $100/mo | **$300/mo** | 동시 요청 10개, 신모델 조기 접근 |
| Team | $500/mo | **$1,000/mo** (팀 전체 공유, unlimited users) | 동시 요청 10개 |
| Enterprise | Custom | 미공개 | 볼륨 가격 |

출처: [ollama.com/pricing](https://ollama.com/pricing), [blog/transparent-pricing](https://ollama.com/blog/transparent-pricing) (접근일 2026-09-01).

### 리셋/롤오버 규칙

- "On Pro, Max, and Team plans, included usage resets monthly on the same day of the month your subscription started, including on annual plans. On the Free plan, usage resets monthly from the date you signed up." — [pricing FAQ](https://ollama.com/pricing)
- "Does unused included usage roll over to the next month? **No.**" — 동일 출처
- 포함 크레딧 소진 후: "you can keep going at the same per-token rate" (extra usage balance에서 차감) — [blog](https://ollama.com/blog/transparent-pricing), [pricing FAQ "How does extra usage work?"](https://ollama.com/pricing)

### 타임라인

- **2025-09-19**: Cloud models 프리뷰 출시 ([blog/cloud-models](https://ollama.com/blog/cloud-models), 접근일 2026-09-01)
- **2026-08-31**: GPU-time → per-token/usage-credits 전환 발표 ([blog/transparent-pricing](https://ollama.com/blog/transparent-pricing)). 기존 구독자는 유지, 신규 가격으로 즉시 전환 가능. 전환 시 "usage is reset: the new plan's full monthly amount is available as soon as you switch, and the **session and weekly limits of the old plans no longer apply**" ([pricing FAQ](https://ollama.com/pricing)).

---

## 3. Q2. 사용량/크레딧 조회 API — **판정: PARTIAL**

### 3.1 판정 요약

| 항목 | 상태 | 근거 |
|---|---|---|
| 엔드포인트 존재 자체 | **YES** (직접 확인) | 비인증 `GET` → `401 {"error":"invalid credentials"}` (존재하지 않는 경로는 `404 {"error":"path \"...\" not found"}`가 반환됨을 함께 확인) |
| 공식 스태프 사용법 공개 | **YES** | ollama/ollama 이슈 #17451 종결 코멘트에 curl 명령 |
| 응답 스키마 문서화 | **NO** | docs.ollama.com 의 "Usage" 문서는 계정 사용량이 아니라 **응답별 토큰 메트릭**을 설명함 (아래 3.4) |
| 레이트 리밋 문서화 | **NO** | 어느 공식 문서에서도 찾지 못함 (미확인 — 없다고 단정 아님) |

### 3.2 엔드포인트와 인증 (확인된 것)

- **`GET https://ollama.com/api/usage`** — Ollama 스태프 **rick-github** 이 이슈 [#17451 "Provide api for querying plan usage"](https://github.com/ollama/ollama/issues/17451) (2026-07-29 종결, state_reason: duplicate) 에 남긴 종결 코멘트 원문:
  ```console
  curl -H "Authorization: $OLLAMA_API_KEY" https://ollama.com/api/usage
  ```
  (접근일 2026-09-01. 코멘트는 승인의 의미로 "duplicate" 처리와 함께 이 명령을 제시했다.)
- 인증 헤더: 공식 문서의 표준 패턴은 **`Authorization: Bearer $OLLAMA_API_KEY`** ([docs.ollama.com/api/authentication](https://docs.ollama.com/api/authentication), 접근일 2026-09-01). 스태프 코멘트는 `Bearer ` 접두사 없이 raw key 를 넣는 예시였다 — 두 형식 모두 시도해 볼 가치가 있으나, **본 조사에서는 API 키가 없어 인증 성공 응답을 직접 검증하지 못했다 (미검증)**.
- 비인증 probe 결과 (접근일 2026-09-01, 본 조사에서 직접 수행):
  - `GET https://ollama.com/api/usage` → **HTTP 401** `{"error":"invalid credentials"}` ← 엔드포인트 존재
  - `GET /api/me/usage`, `/api/account/usage`, `/api/subscription`, `/api/billing`, `/api/credits` → 전부 **HTTP 404** `{"error":"path \"...\" not found"}` ← 위 추측 경로들은 없음
  - `POST /api/me` → HTTP 401 `{"error":"invalid credentials"}` (GET 으로는 405 Method Not Allowed) ← 엔드포인트 존재, POST 전용

### 3.3 응답 스키마 — 공식 코드 힌트 (문서화 아님, 주의)

- **공식 저장소의 오픈 PR** [#17421 "Add account usage command"](https://github.com/ollama/ollama/pull/17421) (2026-07-27 생성, **작성자 ParthSareen, author_association: MEMBER**, 2026-09-01 기준 미병합). 이 PR은 `api/client.go` 에 다음을 추가한다:
  ```go
  // Usage returns the authenticated user's recent activity and included-usage
  // limits.
  func (c *Client) Usage(ctx context.Context) (*UsageResponse, error) {
      var resp UsageResponse
      if err := c.do(ctx, http.MethodGet, "/api/usage", nil, &resp); err != nil {
          return nil, err
      }
      return &resp, nil
  }
  ```
  그리고 `api/types.go` 의 스키마 매핑:
  ```go
  type UsageResponse struct {
      Activity UsageActivity `json:"activity"`
      Limits   UsageLimits   `json:"limits"`
  }
  type UsageActivity struct {
      Cost   string      `json:"cost"`
      Period UsagePeriod `json:"period"`
      Models []UsageModel `json:"models"`
  }
  type UsagePeriod struct {
      Type       string    `json:"type"`
      StartingAt time.Time `json:"starting_at"`
      EndingAt   time.Time `json:"ending_at"`
  }
  type UsageLimits struct {
      Session UsageLimit `json:"session"`
      Weekly  UsageLimit `json:"weekly"`
  }
  type UsageLimit struct {
      Usage  float64      `json:"usage"`
      Models []UsageModel `json:"models"`
  }
  type UsageModel struct {
      Name         string `json:"name"`
      RequestCount int    `json:"request_count"`
      Cost         string `json:"cost,omitempty"`
  }
  ```
  **주의**: 이는 서버가 반환하는 실제 스키마의 문서가 아니라, PR 작성자(스태프)가 클라이언트에서 매핑한 기대 구조이며 미병합 상태다. 또한 작성일이 2026-07-27 로 8-31 가격 개편 이전이라, `session`(구 5시간)·`weekly` 한도 필드는 **개편 후에는 달라졌거나 무의미할 수 있다 (미검증)**.
- **서드파티 (비공식, 미검증)**: [can1357/oh-my-pi PR #10101](https://github.com/can1357/oh-my-pi/pull/10101) 은 "observed 2026-08-27" 라며 같은 구조를 보고한다: `activity.cost`, `activity.period.type: "last_4_weeks"`, `limits.session.usage` (0..1 정규화된 비율), `limits.session.models[].{name, request_count}` 등. PR #17421 의 Go 구조체와 정확히 일치한다. **단, 서드파티 관측치이므로 공식 보증 없음 — 스키마 확정 전까지는 방어적으로 파싱할 것.**
- 공식 OpenAPI 스펙 ([docs.ollama.com/openapi.yaml](https://docs.ollama.com/openapi.yaml), 접근일 2026-09-01) 의 `paths` 는 `/api/generate, /api/chat, /api/embed, /api/tags, /api/ps, /api/show, /api/create, /api/copy, /api/pull, /api/push, /api/delete, /api/version` 뿐이며, **`/api/usage`·`/api/me` 는 스펙에 없다** — 즉 계정 계열 엔드포인트는 공식 스펙 밖의 사실상 비공개 표면이다.

### 3.4 혼동 주의: docs 의 "Usage" 페이지는 계정 사용량 API가 아니다

- [docs.ollama.com/api/usage](https://docs.ollama.com/api/usage) (접근일 2026-09-01) 는 **API 응답에 포함되는 성능/토큰 메트릭**(`total_duration`, `load_duration`, `prompt_eval_count`, `prompt_eval_duration`, `eval_count`, `eval_duration`; 시간 단위 nanoseconds)을 설명하는 페이지다. 계정 크레딧/한도 조회와는 무관하다. 검색 시 이 문서를 "usage API 문서"로 오독하기 쉬우므로 명시해 둔다.

### 3.5 대시보드와 로드맵

- 사용량 대시보드: **`https://ollama.com/settings`** — pricing FAQ "Check your usage **here** anytime" 의 링크가 `href="/settings"` 로 확인됨 ([ollama.com/pricing](https://ollama.com/pricing), 접근일 2026-09-01). 과거(구 요금제) 대시보드의 Plan/Session/Weekly usage 표시 사례: 이슈 [#17639](https://github.com/ollama/ollama/issues/17639) (2026-08-09).
- 계정 정보 엔드포인트: `POST https://ollama.com/api/me` (존재 확인, 위 probe) — 공식 Go 클라이언트 `Client.Whoami()` 가 사용하며 응답 타입은 `UserResponse{id, email, name, bio?, avatarurl?, firstname?, lastname?, plan?}` ([ollama/ollama `api/types.go`](https://github.com/ollama/ollama/blob/main/api/types.go), `api/client.go` 의 `Whoami`, 접근일 2026-09-01). 플랜 이름은 알 수 있으나 사용량/잔여 크레딧은 없다.
- 로컬 프록시 경로: 로컬 서버가 `POST http://localhost:11434/api/me` 를 노출하고 ollama.com 으로 프록시한다 (`server/routes.go` 의 `WhoamiHandler` — [routes.go L1891, L2184](https://github.com/ollama/ollama/blob/main/server/routes.go), 접근일 2026-09-01). 사용자가 Ollama 앱에 로그인만 되어 있으면 API 키 없이도 플랜 확인 가능.
- 로드맵/요청 이슈 (공식 저장소):
  - [#12532 "Cloud usage stats."](https://github.com/ollama/ollama/issues/12532) (2025-10-07, open): "`/api/me`" 로 usage stats 제공 요청
  - [#15132 "Account Usage API Endpoint"](https://github.com/ollama/ollama/issues/15132) (2026-03-29, closed as duplicate, 코멘트 0)
  - [#17451](https://github.com/ollama/ollama/issues/17451) (2026-07-29, closed as duplicate) — 종결 코멘트가 곧 "이미 있다"는 답변
  - PR [#17421](https://github.com/ollama/ollama/pull/17421) (open, 2026-09-01 기준 미병합): `ollama usage` CLI + 로컬 `GET /api/usage` 프록시 — 병합되면 메뉴바 앱의 2차 경로가 될 수 있음

### 3.6 결론

- **YES 부분**: `GET https://ollama.com/api/usage` + `Authorization` 헤더(API 키)로 계정 사용량 조회가 실제로 동작한다는 것 — 스태프 코멘트 + 비인증 401 존재 확인.
- **NO 부분**: 응답 스키마·레이트 리밋·안정성 보장의 공식 문서화가 전무하며, OpenAPI 스펙에도 없다. 또한 8-31 가격 개편으로 구 `session`/`weekly` 필드의 의미가 바뀌었을 가능성을 배제할 수 없다.
- 종합 판정: **PARTIAL** — "존재하지만 비공식·무문서". 스키마는 PR #17421 (스태프) + oh-my-pi (서드파티) 의 상호 일치하는 두 관측으로 추정하되, 앱은 스키마 미스매치에 관대해야 한다.

### 3.7 실측 스냅샷 (2026-09-01, API 키 보유 사용자가 직접 curl 로 취득)

> 부록의 "인증된 응답 미관찰" 한계를 부분 해소한 자료. 사용자가 인증 요청으로 직접 취득한 실제 응답이다.

```json
{
    "activity": {
        "cost": "0.00000",
        "period": {
            "type": "last_4_weeks",
            "starting_at": "2026-08-10T00:00:00Z",
            "ending_at": "2026-09-01T08:45:10.076049294Z"
        },
        "models": []
    },
    "limits": {
        "monthly": {
            "usage": 0.002,
            "models": [
                {
                    "name": "glm-5.3-flash",
                    "request_count": 29
                },
                {
                    "name": "web search",
                    "request_count": 4
                },
                {
                    "name": "gpt-oss:120b",
                    "request_count": 1
                }
            ]
        }
    }
}
```

실측이 확정/변경한 것:

- **`limits.monthly`** — 스태프 PR #17421 과 서드파티 관측의 `limits{session, weekly}` 가 **실제로는 `limits.monthly{usage, models[]}` 로 바뀌어 있음을 확인**. 3.3 절의 추정 스키마는 개편 전 구조로 확정된다(참고용으로만).
- `activity.period.type` 은 여전히 `"last_4_weeks"` 이며 `ending_at` 이 관측 시각과 일치해 롤링 윈도우로 보였으나, 후속 확인(사용자 보고, 2차 소스)에서 **공식 SNS 가 월간 리셋을 "매월 1일"로 공지**했다고 하며, 본 스냅샷의 `ending_at` 일자(2026-09-01)와 정확히 일치한다. → 앱은 갱신 예정일을 `period.ending_at` 의 `YYYY-MM-DD` 파싱으로 산출하기로 결정 (정책 변경 여지가 있으므로 리셋일을 하드코드하지 않는다).
- **`limits.monthly.usage` 의 단위가 사용자 실측으로 확정**: 사용 크레딧 / 제공 크레딧 **비율**. 계정 소유자 관찰 — 제공 $60, 대시보드 사용량 $0.14 → 0.14/60 = 0.00233 ≈ 관측값 0.002 (스냅샷 시점 차이로 미세 오차). 따라서 잔여 비율 = `1 - limits.monthly.usage` 로 서버 값에서 직접 산출 가능하며, 달러 표시는 설정 파일의 풀 금액과 조합해 계산한다. `activity.cost` (소수 5자리 문자열) 는 금액으로 보이나 표시에는 서버 비율을 1순위로 쓰고, cost 는 raw JSON 디버그 뷰로 관찰을 지속한다.
- `activity.models` 는 빈 배열로 관측됨(usage 총량이 작아서일 수 있음) — 모델별 내역은 `limits.monthly.models[].{name, request_count}` 쪽에 있었음.

---

## 4. Q3. API 키 발급 방법

- 발급 URL: **`https://ollama.com/settings/keys`** — 공식 문서 원문: "First, create an [API key](https://ollama.com/settings/keys), then set the `OLLAMA_API_KEY` environment variable" ([docs.ollama.com/api/authentication](https://docs.ollama.com/api/authentication), 접근일 2026-09-01)
- 만료/폐기: "API keys don't currently expire, however you can revoke them at any time in your [API keys settings](https://ollama.com/settings/keys)." (동일 출처)
- 계정 로그인 플로우: CLI에서 `ollama signin` (동일 출처; 로컬 Ollama 설치가 ollama.com 인증을 대행)
- 참고: 로그아웃 상태에서 `https://ollama.com/settings/keys` 에 접근하면 404 안내 문구가 렌더링된다 (본 조사 probe, 2026-09-01) — 로그인 필수 페이지로 보면 된다.
- 빌링/플랜 설정: `https://ollama.com/settings/billing` ([pricing FAQ](https://ollama.com/pricing)의 "billing settings" 링크, 200 확인)

---

## 5. Q4. 베이스라인 클라우드 API 서페이스 (참고용)

- **네이티브 API base URL**: `https://ollama.com/api` — "For direct access to ollama.com's API served at `https://ollama.com/api`, authentication via API keys is required." ([docs.ollama.com/api/introduction](https://docs.ollama.com/api/introduction), [cloud](https://docs.ollama.com/cloud))
- **엔드포인트 집합** (공식 OpenAPI 스펙 [openapi.yaml](https://docs.ollama.com/openapi.yaml), 접근일 2026-09-01): `/api/generate`, `/api/chat`, `/api/embed`, `/api/tags`, `/api/ps`, `/api/show`, `/api/create`, `/api/copy`, `/api/pull`, `/api/push`, `/api/delete`, `/api/version`
- **인증 헤더**: `Authorization: Bearer $OLLAMA_API_KEY` ([authentication](https://docs.ollama.com/api/authentication)); 스펙의 securitySchemes: `bearerAuth: {type: http, scheme: bearer, bearerFormat: API Key}`
- **모델 목록**: `GET https://ollama.com/api/tags` — [cloud 문서](https://docs.ollama.com/cloud)가 이 형태로 안내. 응답은 `models[].{name, model, modified_at, size, digest, details{...}}` ([api/tags](https://docs.ollama.com/api/tags)). **비인증 GET 도 200 응답을 확인** (본 조사 probe, 2026-09-01).
- **응답의 usage/토큰 필드**: 네이티브 `/api/chat`·`/api/generate` 응답에 `prompt_eval_count` (입력 토큰), `eval_count` (출력 토큰) 포함 ([api/usage](https://docs.ollama.com/api/usage), [api/chat](https://docs.ollama.com/api/chat), 접근일 2026-09-01). 스트리밍 시 "usage fields are included as part of the final chunk, where `done` is `true`" (동일 출처).
- **OpenAI 호환**: `/v1/chat/completions`, `/v1/completions`, `/v1/models`, `/v1/models/{model}`, `/v1/embeddings`, `/v1/responses`; 스트리밍 `stream_options.include_usage` 지원 ([api/openai-compatibility](https://docs.ollama.com/api/openai-compatibility), 접근일 2026-09-01). 클라우드 직결 base URL `https://ollama.com/v1` 이 실동작함은 이슈 [#17639](https://github.com/ollama/ollama/issues/17639) (402 사례) 와 본 조사의 `GET /v1/models` 200 probe 로 확인. 참고: `GET /v1/chat/completions` → 405 (POST 전용).
- **Anthropic 호환**: `/v1/messages`; 응답 지원 필드에 `usage` (input_tokens, output_tokens) 명시 ([api/anthropic-compatibility](https://docs.ollama.com/api/anthropic-compatibility), 접근일 2026-09-01).
- **에러 포맷**: `{"error": "..."}` JSON; 상태코드 표에 `429` (rate limit), `502` (cloud model 도달 불가) 문서화 ([api/errors](https://docs.ollama.com/api/errors), 접근일 2026-09-01). 청구 관련 `402 Payment Required` 사례: 이슈 [#17639](https://github.com/ollama/ollama/issues/17639) — 에러 원문: "this model uses extra usage only (not included plan usage) and your extra usage balance is empty, add extra usage or turn on auto reload at https://ollama.com/settings".

---

## 6. 메뉴바 앱에 주는 시사점

- **`GET https://ollama.com/api/usage` 를 1순위 데이터 소스로 설계하되 무문서 API임을 전제할 것** — `Authorization: Bearer <API key>` (스태프 예시는 `Bearer` 없이 raw key). 스키마는 PR #17421/서드파티 관측 기준 `activity{cost, period, models[]}` + `limits{session, weekly}` 로 추정되나 8-31 가격 개편 이후 필드 의미가 바뀌었을 수 있으므로, 파서는 필드 누락/추가에 관대하게 작성하고 원문 JSON 뷰를 디버그 패널에 제공할 것.
- **예상 표시 지표와 한도 로직**: 포함 크레딧은 달러 풀(Pro $60/Max $300/Team $1,000)이고, 소비는 모델별 백만 토큰당 단가로 계산되며 매월 구독 시작일에 리셋(롤오버 없음) — 메뉴바에는 "이번 달 소진액 / 풀"과 리셋일 카운트다운이 가장 자연스러운 1차 지표.
- **폴링 전략**: usage API의 레이트 리밋이 문서화되어 있지 않으므로 (미확인), 보수적인 폴링(예: 60초 이상) + `429` 백오프 구현이 필수. 실시간 소진 추정의 보조 수단으로 `/api/chat` 등 응답의 `prompt_eval_count`/`eval_count` 를 누적해 로컬 가계부를 병행하면 대시보드 지연·레이트리밋 리스크를 줄일 수 있다.
- **인증 UX**: API 키는 `https://ollama.com/settings/keys` 에서 발급(무만료, 수동 폐기) — 앱 첫 실행 온보딩에서 이 URL로 안내하고 키를 Keychain에 저장. 대안으로, 사용자가 Ollama 앱에 로그인만 해 두면 `POST http://localhost:11434/api/me` 프록시로 API 키 없이 플랜 확인이 가능하다(사용량은 아님).
- **실패 시나리오 처리**: 크레딧 소진 시 모델 요청이 `402 Payment Required`로 실패할 수 있고(이슈 #17639), 일부 기능(web_search/web_fetch)은 사용량 소진 시 200 + 빈 본문으로 와감된 사례가 있다(이슈 #16045) — 메뉴바 앱은 "남은 크레딧 0"과 "API 오류"를 구분 표시해야 한다.

---

## 부록: 조사 제약 (명시적 한계)

- **인증된 `/api/usage` 응답을 직접 관찰하지 못했다** (API 키 보유 계정이 없어서). 위 스키마는 공식 저장소의 스태프 PR과 서드파티 관측치의 교차 검증일 뿐이며, 둘 다 2026-08-31 가격 개편 전 시점의 구조다. 앱 개발 시 첫 키 발급 후 실제 응답을 캡처해 이 문서에 보강할 것.
- usage 엔드포인트의 **레이트 리밋/SLA/문서화된 안정성 보장은 발견하지 못했다** (공식 문서 어디에도 없음을 확인한 것이지, 존재하지 않음이 확인된 것은 아님).
- Free 플랜의 starter 크레딧 **정확 금액은 어디에도 공개되어 있지 않다** ("starter amount" 표현만 존재).
- GitHub 이슈/PR은 공식 저장소의 것이라 1차 소스로 취급했으나, 이슈 본문(사용자 작성)의 서술은 당사자 보고다. 검증 가능한 것(엔드포인트 401/404/405 probe, 스태프 코멘트, 스태프 PR 코드)과 아닌 것(이슈 본문의 402 사례, 서드파티 스키마 관측)을 위 표기로 구분했다.