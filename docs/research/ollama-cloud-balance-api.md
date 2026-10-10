<!--
리서치 노트 위치 컨벤션: docs/research/ (선례: docs/research/ollama-cloud-usage-credits-api.md)

작성일 / 모든 출처 접근일: 2026-10-10 (UTC)
조사 방법: 1차 소스만 사용 — docs.ollama.com 공식 문서(.md 원문), 공식 OpenAPI 스펙
(docs.ollama.com/openapi.yaml), 그 문서의 업스트림 소스인 ollama/ollama 저장소의
docs/api/*.mdx 와 커밋 이력/릴리스 태그, 그리고 ollama.com 엔드포인트에 대한 직접 비인증 probe.

대체 관계: 이 문서는 docs/research/ollama-cloud-usage-credits-api.md 의 /api/usage 관련
서술(구 `activity{...}` + `limits{monthly}` 스키마, 무문서 리스크)을 SUPERSEDE 한다.
-->

# Ollama Cloud Usage / Balance API 조사 (공식 문서화 이후)

> **모든 링크의 접근일: 2026-10-10 (UTC).** Ollama Cloud 문서는 신생이며 변경이 잦다 — 2026-10-07에 두 엔드포인트가 처음 문서화됐다(아래 §7). 인용한 날짜 기준으로 읽을 것.

---

## 0. 한 줄 요약

**현재 공식 문서화된 표면은 두 개다: `GET https://ollama.com/api/balance` (잔여 크레딧: `included.balance_usd` / `included.allowance_usd` / `included.period`, `purchased.balance_usd`) 와 `GET https://ollama.com/api/usage` (순수 시간범위 사용통계: `range` ∈ {`24h`,`7d`,`30d`}, `scope` ∈ {`self`,`team`}, `granularity` ∈ {`hour`,`day`}, `totals` + `buckets`)** — 둘 다 공식 문서 페이지와 **공식 OpenAPI 스펙에 포함**되어 있고, 모델별 내역은 "Coming soon"으로 명시된 미래 기능이다. 구 무문서 스키마(`activity.period`, `limits.monthly`)는 공식 표면 어디에도 더 이상 존재하지 않는다.

---

## 1. `GET /api/balance` — 잔여 크레딧

**출처: [docs.ollama.com/api/balance](https://docs.ollama.com/api/balance.md) (접근일 2026-10-10)**

### 1.1 경로 · 인증

- 경로: **`GET https://ollama.com/api/balance`** — 공식 curl 예시 원문:
  ```shell
  curl https://ollama.com/api/balance \
    -H "Authorization: Bearer $OLLAMA_API_KEY"
  ```
- 인증: **`Authorization: Bearer $OLLAMA_API_KEY`** (OpenAPI `security: [bearerAuth: []]`, `bearerAuth: {type: http, scheme: bearer, bearerFormat: API Key}`). 인증 헤더 표준은 [api/authentication](https://docs.ollama.com/api/authentication.md) 에도 동일하게 명시된다: "Use the API key in the `Authorization: Bearer` header."
- 쿼리 파라미터: 문서 원문 **"This endpoint takes no query parameters."** (다만 OpenAPI 응답 정의에는 `400 Invalid query parameters.` 가 있다 — 아래 §4 참조.)
- 서버: OpenAPI `servers: [{url: https://ollama.com, description: Ollama Cloud}]`.
- 사용 이력은 이 엔드포인트가 아니라 `/api/usage` 로 안내한다: "For usage history, see [Cloud usage](/api/cloud-usage)."

### 1.2 응답 스키마 (문서 예시 원문)

```json
{
  "included": {
    "balance_usd": 72.5,
    "allowance_usd": 100,
    "period": {
      "from": "2026-09-15T09:30:00Z",
      "until": "2026-10-15T09:30:00Z"
    }
  },
  "purchased": {
    "balance_usd": 25
  }
}
```

OpenAPI 정의(같은 페이지 하단 `GET /api/balance` 블록, `BalanceResponse`):

| 필드 | 타입(OpenAPI) | required | 설명(문서 원문) |
|---|---|---|---|
| `included` | object, **`oneOf` `IncludedBalance` \| `LegacyIncludedBalance`** | **yes** | — |
| `included.balance_usd` | `number` | yes (IncludedBalance) | "Remaining included credits in USD." |
| `included.allowance_usd` | `number` | yes (IncludedBalance) | "Included credits available for the full period in USD." |
| `included.period.from` | `string`, `format: date-time` | yes | "Start of the included period in UTC, inclusive." |
| `included.period.until` | `string`, `format: date-time` | yes | "End of the included period in UTC, exclusive." |
| `purchased` | object | **yes** | — |
| `purchased.balance_usd` | `number` | yes (purchased) | **"Remaining unexpired purchased credits in USD."** |

- **필드 타입은 전부 숫자(`number`)와 문자열(`date-time`)이며, 금액이 문자열로 오지 않는다.** 구 무문서 스키마의 `activity.cost` 가 `"0.00000"` (문자열) 이었던 것과 대비된다 (§5).
- **`purchased.balance_usd` 의 의미 — 문서가 명시적으로 답한다**: "Remaining **unexpired purchased credits** in USD." 즉 **추가로 구매(top-up)한 크레딧 중 아직 만료되지 않은 잔액**이다. 별도 만료 규칙 문장도 있다: "The purchased balance includes only unexpired credits." → 만료 개념이 있고, 만료분은 응답에서 제외된다.
- 잔액 소진 순서(포함 → 구매)는 이 페이지가 아니라 가격 FAQ가 규정한다: "Ollama uses included plan credits first, then draws from the purchased usage credit balance." ([ollama.com/pricing](https://ollama.com/pricing) FAQ "How do usage credits work?", 접근일 2026-10-10)
- **기간(period) 의미**: "The included period follows your plan's monthly reset schedule, including for annual subscriptions. Period timestamps are in UTC, with `from` inclusive and `until` exclusive."
- 팀: "All team members share the same included and purchased balances." (섹션 제목 `Teams`)

### 1.3 레거시 플랜 분기 (문서의 Accordion, 중요)

`included` 는 `oneOf` 이며, **레거시(session/weekly 한도) 플랜에서는 전혀 다른 모양**이 온다. 문서 원문: "Plans with session and weekly limits return `session` and `weekly` in `included`:"

```json
{
  "included": {
    "session": { "remaining_percent": 75, "resets_at": "2026-10-01T07:00:00Z" },
    "weekly":  { "remaining_percent": 40, "resets_at": "2026-10-05T00:00:00Z" }
  },
  "purchased": { "balance_usd": 25 }
}
```

- "`remaining_percent` ranges from `0` to `100`; `75` means 75% remains. `resets_at` is the next reset time in UTC."
- OpenAPI: `remaining_percent` `type: number, minimum: 0, maximum: 100`; `resets_at` `type: string, format: date-time`. `LegacyIncludedBalance.required = [session, weekly]`.
- **주의(파서 설계에 직접 영향)**: 레거시 응답에는 `balance_usd`·`allowance_usd`·`period` 가 **없다**. 반대로 현행 응답에는 `session`·`weekly` 가 없다. 즉 `included` 는 두 형태 중 하나이므로 앱은 양쪽을 분기해야 한다 (구 문서 ADR-0001의 "관대한 디코딩" 원칙이 그대로 유효하다).

### 1.4 optional 여부 정리

- 문서 기준으로 **현행 계정에서는 위 필드 전부가 required** 다 (`BalanceResponse.required = [included, purchased]`, `IncludedBalance.required = [balance_usd, allowance_usd, period]`, `period.required = [from, until]`, `purchased.required = [balance_usd]`).
- "optional 한 필드"는 **스키마 레벨에서는 없다** — 대신 **`included` 의 변이(oneOf) 두 갈래**가 optionality 를 대신한다.
- 단, 이는 어디까지나 서버 계약이다. 실무적 방어(필드 누락 허용)는 문서 근거가 아니라 앱의 판단이며, 기존 ADR-0001(관대한 디코딩)이 그 근거다 — **문서가 "필드가 빠질 수 있다"고 말한 적은 없다 (미검증/추론으로 표시)**.

---

## 2. `GET /api/usage` — 시간범위 사용통계 (모델별 내역 없음)

**출처: [docs.ollama.com/api/cloud-usage](https://docs.ollama.com/api/cloud-usage.md) (접근일 2026-10-10)** — 페이지 제목은 `Cloud usage`, 사이드바 제목은 `/api/usage`.

### 2.1 경로 · 인증

- 경로: **`GET https://ollama.com/api/usage`**, 공식 curl 예시 원문: `curl 'https://ollama.com/api/usage?range=24h' -H "Authorization: Bearer $OLLAMA_API_KEY"`
- 설명: "Usage statistics for cloud inference, web search, and web fetch."
- 인증은 balance 와 동일한 `bearerAuth` (Bearer API key).

### 2.2 `range` 허용값 — **정확히 3개다 (확인됨)**

OpenAPI `parameters`: `range`, `in query`, description "Completed UTC hours or days to include, plus the current partial hour or day.", `enum: [24h, 7d, 30d]`, **`default: 7d`**.

문서 표 원문:

| Range | Starts at | Bucket size | Buckets |
| - | - | - | - |
| `24h` | 24 hours before the start of the current UTC hour | Hour | 25 |
| `7d` | Seven days ago at 00:00 UTC | Day | 8 |
| `30d` | Thirty days ago at 00:00 UTC | Day | 31 |

- **"only 24h/7d/30d 인가?" → 그렇다. 다른 값은 공식 스펙에 없다.** 기본값 `7d` 를 포함해 enum 이 세 값으로 닫혀 있다.
- 범위 끝은 항상 요청 시각: "Every range ends at the time of the request."
- 잘못된/중복 파라미터는 400: "Unsupported or repeated query parameters return `400`."
- 나의 비인증 probe: `?range=1y` 및 `?bogus=1` 모두 `401 {"error":"invalid credentials"}` 를 반환했다 (접근일 2026-10-10) — **인증이 파라미터 검증보다 먼저 일어나므로, 잘못된 range 의 400 동작은 API 키 없이 검증할 수 없었다 (미검증)**.

### 2.3 `scope`

- OpenAPI: `scope`, `enum: [self, team]`, **`default: self`**, "Your requests, or your team's requests. Team scope requires being a team admin."
- 문서: "By default, everyone sees their own usage (`scope=self`)." / "Team admins can use `scope=team` to see usage for the whole team". 예시: `curl 'https://ollama.com/api/usage?range=7d&scope=team' ...`
- 팀 스코프 무권한 시 403 (아래 §4).

### 2.4 `granularity`

- OpenAPI: `enum: [hour, day]`, "Set automatically: hour for 24h, day for 7d and 30d." → **클라이언트가 지정하는 파라미터가 아니라 응답에 서버가 채워주는 값**이다 (요청 파라미터 목록에는 없다).

### 2.5 `buckets[].partial` — 의미가 명시되어 있다

- OpenAPI: `partial`, `type: boolean`, "Present and true for the current hour or day, which is still in progress."
- 문서 원문(강조): "**`partial` indicates whether the hour or day is still in progress, rather than whether all usage has been recorded.**"
- 즉 "데이터 수집이 덜 끝났다"가 아니라 "그 시간/날짜가 아직 진행 중"이라는 뜻이다. 별도로 "New usage may take time to appear." 라는 지연 경고가 페이지 상단에 있다.
- 버킷 순서/결측: "Buckets appear in chronological order, including zeroes for hours or days with no recorded requests." / "The final bucket covers the current hour or day and has `partial: true`."
- 경계: "All timestamps are in UTC. Each `from` is inclusive and each `until` is exclusive." / "The top-level `from` and `until` describe the entire range; each bucket has its own boundaries."

### 2.6 응답 스키마

OpenAPI `UsageResponse.required = [range, scope, granularity, from, until, totals, buckets]`:

| 필드 | 타입 | required | 설명(문서 원문) |
|---|---|---|---|
| `range` | `string` enum `24h/7d/30d` | yes | "Selected time range." |
| `scope` | `string` enum `self/team` | yes | "Selected usage scope." |
| `granularity` | `string` enum `hour/day` | yes | "Set automatically: hour for 24h, day for 7d and 30d." |
| `from` / `until` | `string` date-time | yes | "Start of the range in UTC, inclusive." / "End of the range in UTC, exclusive." |
| `totals` | `UsageMetrics` | yes | "Usage across the entire range." |
| `buckets[]` | `UsageBucket` | yes | "Usage in chronological order, including buckets with no recorded requests." |

`UsageMetrics` (OpenAPI) — **required 는 `request_count` 하나뿐이다**:

| 필드 | 타입 | required | 설명(문서 원문) |
|---|---|---|---|
| `request_count` | `integer`, `minimum: 0` | **yes** | "Number of recorded requests." |
| `usage_usd` | `number` | **no** | "Total value of the requests in USD, including usage covered by your plan and usage paid from purchased credits." |
| `input_tokens` | `integer` | **no** | "Recorded input tokens, including cached input tokens." |
| `cached_input_tokens` | `integer` | **no** | "Recorded input tokens read from cache, already included in `input_tokens`." |
| `output_tokens` | `integer` | **no** | "Recorded output tokens." |

`UsageBucket` = `allOf: [UsageMetrics, {required: [from, until], properties: from, until, partial}]` → 버킷은 `from`/`until` 이 required 이고, **`partial` 은 required 목록에 없다(= 생략 가능)**.

- **왜 4개 필드가 optional 인가 — 문서가 이유를 밝힌다**: 레거시 플랜 Accordion 원문 "For legacy plans, only request counts are available. If a bucket or total includes legacy requests, cost and token counts are omitted." → 곧 `usage_usd`/`input_tokens`/`cached_input_tokens`/`output_tokens` 는 **레거시 요청이 섞이면 응답에서 빠진다.** 파서는 이 4개가 없어도 동작해야 한다 (문서 근거 있음).

### 2.7 모델별(per-model) request count 는 정말 사라졌는가 — **그렇다 (문서 근거 확정)**

- 새 `UsageResponse` 스키마 어디에도 모델 이름/모델 배열 필드가 없다. `totals`·`buckets` 는 request 수와 토큰/금액 집계만 담는다.
- 같은 페이지 `Coming soon` 이 모델별 내역을 **미래 기능**으로 명시한다 (§3).
- **공식 문서 전체(및 OpenAPI 스펙)에 `models[].request_count` 류 필드가 존재하지 않는다** — 접근일 2026-10-10 기준 `docs.ollama.com/api/cloud-usage.md` 원문에 `last_4_weeks` 0회, `activity` 0회 출현(본 조사 grep).
- 비인증 probe 로는 인증된 응답 본문을 볼 수 없으므로 "서버가 실제로 모델 데이터를 절대 반환하지 않는다"까지는 확인하지 못했다. 다만 **문서화된 계약에서는 완전히 제거되었고, 모델별 내역의 부활은 "Coming soon"으로 예고된 신규 기능**이다. 잔여 레거시 필드가 응답에 남아 있을 가능성은 **미검증**이다 (§8).

---

## 3. "Coming Soon" 내용 — 원문 인용

**중요: `Coming soon` 섹션은 `/api/usage` (Cloud usage) 페이지에만 있고, `/api/balance` 페이지에는 없다.** (balance.md 원문 grep: "coming"/"soon" 0회 — 접근일 2026-10-10)

[docs.ollama.com/api/cloud-usage](https://docs.ollama.com/api/cloud-usage.md) `## Coming soon` 원문 그대로:

> We plan to add custom time ranges, usage breakdowns by model and API key, and breakdowns by team member for team admins.

해석 (프로젝트 영향):
- **custom time ranges** — 지금은 `range` 가 3값 enum 이지만 이후 임의 기간을 받게 될 수 있다.
- **usage breakdowns by model and API key** — 모델별 내역이 **다시 추가될 예정**이며, 그때는 지금과 **다른 필드 모양**으로 올 가능성이 높다 → 앱이 모델별 표시를 되살리려면 그때 재조사해야 한다.
- **breakdowns by team member for team admins** — 팀 관리자용.

업스트림 소스(`docs/api/cloud-usage.mdx`, [raw](https://raw.githubusercontent.com/ollama/ollama/main/docs/api/cloud-usage.mdx), 접근일 2026-10-10)에서도 같은 문장이 그대로 확인된다. balance 페이지에는 `## Teams` 섹션("All team members share the same included and purchased balances.")만 있고 Coming soon 은 없다.

---

## 4. 에러 · 레이트 리밋 (공식 문서 기준)

### 4.1 상태코드 — 두 엔드포인트 모두 OpenAPI 에 명시됨

[balance](https://docs.ollama.com/api/balance.md) / [cloud-usage](https://docs.ollama.com/api/cloud-usage.md) (접근일 2026-10-10):

| 코드 | `/api/balance` | `/api/usage` |
|---|---|---|
| `200` | "Current included and purchased balances." | "Usage for the selected range and scope." |
| `400` | "Invalid query parameters." | "Invalid query parameters." |
| `401` | "Invalid credentials." | "Invalid credentials." |
| `403` | "Account suspended." | "Account suspended or team scope requested without team admin access." |
| `429` | "Too many requests." + `Retry-After` | "Too many requests." + `Retry-After` |
| `503` | "Balance reporting is temporarily unavailable." | "Usage reporting is temporarily unavailable." |

- 에러 본문 형식: 두 페이지 모두 "Errors follow Ollama's [JSON error format](/api/errors#error-messages)." → `{"error": "..."}` ([api/errors](https://docs.ollama.com/api/errors.md)).
- `429` 의 `Retry-After` 헤더 스키마: `type: integer, minimum: 1`, "Seconds to wait before retrying."
- **`402` 는 두 엔드포인트의 응답 목록에 없고, 공식 에러 문서에도 없다.** [api/errors](https://docs.ollama.com/api/errors.md) 의 "Common status codes" 목록은 `200, 400, 404, 429, 500, 502` 뿐이다 (접근일 2026-10-10). 구 노트가 인용한 402 는 모델 요청 경로의 GitHub 이슈 사례이지 이 두 엔드포인트의 문서화된 계약이 아니다.
- 문서 내부 긴장 하나(명시): balance 는 본문에 **"This endpoint takes no query parameters."** 라고 하는데 OpenAPI 에는 `400 Invalid query parameters.` 가 있다. 즉 400 은 방어적으로 존재하되 정상 사용에서는 나올 일이 없다고 읽는 게 합리적이다 (해석).

### 4.2 레이트 리밋 — **문서화되어 있다 (구 노트의 "미확인" 해소)**

두 페이지의 `## Rate limits` 섹션이 **동일한 문장**으로 명시한다 (원문):

> This endpoint allows 10 requests per minute per user, shared across API keys and devices. We recommend polling once per minute. A `429` response includes a `Retry-After` header with the number of seconds to wait before retrying.

- **사용자당 분당 10회, API 키·기기 전체 공유** — 즉 앱 인스턴스가 여러 개여도 합산이다.
- **권장 폴링 주기: 분당 1회.** 메뉴바 앱 폴링 간격은 이 권장값 이상으로 두는 것이 문서에 부합한다.
- 429 시 `Retry-After`(초)를 반드시 존중할 것.

### 4.3 비인증 probe (본 조사 직접 수행, 접근일 2026-10-10)

| 요청 | 결과 |
|---|---|
| `GET https://ollama.com/api/balance` | **HTTP 401** `{"error":"invalid credentials"}` |
| `GET https://ollama.com/api/usage` | **HTTP 401** `{"error":"invalid credentials"}` |
| `GET https://ollama.com/api/usage?range=24h` | **HTTP 401** `{"error":"invalid credentials"}` |
| `GET https://ollama.com/api/usage?range=1y` | **HTTP 401** `{"error":"invalid credentials"}` |
| `GET https://ollama.com/api/usage?range=24h&bogus=1` | **HTTP 401** `{"error":"invalid credentials"}` |

→ 두 경로 모두 실재하며 인증을 요구한다. (401 본문은 문서의 `ErrorResponse{error: string}` 와 일치.)

---

## 5. 구 무문서 `/api/usage` 스키마(`activity.period` / `limits.monthly`)는 어디에도 남아 있는가

**결론: 공식 표면에서는 완전히 대체되었다. 다만 서버가 옛 클라이언트를 위해 옛 필드를 계속 반환하는지는 미검증이다.**

근거:

1. **공식 OpenAPI 스펙이 새 스키마만 정의한다.** [docs.ollama.com/openapi.yaml](https://docs.ollama.com/openapi.yaml) (접근일 2026-10-10) 의 `/api/usage` 는 `UsageResponse{range, scope, granularity, from, until, totals, buckets}` 이고, 구 `activity{...}` / `limits{...}` 스키마·필드는 **스펙 어디에도 정의되어 있지 않다**. `activity`, `last_4_weeks` 문자열은 스펙에 0회 출현 (본 조사 grep).
2. **문서 페이지 본문에도 구 필드 언급이 0회.** `docs.ollama.com/api/cloud-usage.md` 원문에 `last_4_weeks` 0회, `activity` 0회 (본 조사 grep, 접근일 2026-10-10).
3. **구 노트(2026-09-01)가 근거로 삼았던 "OpenAPI 스펙에 `/api/usage` 가 없다"는 사실도 더 이상 참이 아니다.** 그때 스펙의 paths 는 로컬 API 12개뿐이었는데, 지금은 `/api/usage` 와 `/api/balance` 가 **스펙에 정식 포함**되어 있다 (아래 §7의 2026-10-07 커밋).
4. **레거시 데이터는 옛 모양이 아니라 새 모양 안으로 흡수되었다** — 새 문서가 그렇게 서술한다:
   - usage: "For legacy **plans**, only request counts are available. If a bucket or total includes legacy requests, cost and token counts are omitted." → 레거시는 *별도 스키마*가 아니라 **새 스키마에서 optional 필드가 빠지는 형태**로 표현된다.
   - balance: 레거시는 `included.session` / `included.weekly` 로 **새 엔드포인트의 변이(oneOf)** 로 표현된다. 즉 구 `session`/`weekly` 개념 자체는 폐기되지 않았지만, **구 `/api/usage` 응답의 `limits.monthly` 자리로는 더 이상 오지 않는다.**
5. 문서화 이력: `/api/usage`·`/api/balance` 문서와 스펙 항목은 모두 단일 커밋 **f8646015 (2026-10-07T01:31:54Z, "server: proxy cloud usage and balance APIs (#18829)")** 에서 **추가(added)** 되었다 — 그 이전에는 두 엔드포인트를 설명하는 페이지가 **없었다** ([커밋 조회](https://api.github.com/repos/ollama/ollama/commits/f8646015), [docs/api/cloud-usage.mdx 이력](https://api.github.com/repos/ollama/ollama/commits?path=docs/api/cloud-usage.mdx), 접근일 2026-10-10).

**미검증으로 남는 것**: 인증된 실제 응답에 `activity`/`limits` 가 하위 호환용으로 아직 얹혀 오는지. 비인증 probe 는 401 만 돌려주므로 알 수 없고, ollama.com 백엔드 코드는 공개 저장소에 없다 — 공식 저장소의 `api/types.go`(1338줄)에는 `usage`/`balance` 문자열이 **대소문자 무시하고 0회** 등장하고, `api/client.go` 에도 `Whoami` 만 있고 `Usage`/`Balance` 클라이언트 메서드가 **없다** (본 조사 확인, 접근일 2026-10-10). 타입 정의는 문서/OpenAPI 쪽에만 존재한다. **API 키가 있는 계정으로 실제 응답을 캡처하면 즉시 확정 가능하다.**

---

## 6. 사용자 실측 응답 vs 공식 문서 — 대조 결과: **일치 (불일치 없음)**

사용자가 자기 계정에서 취득한 `/api/balance` 응답 원문(앱 테스트 리터럴 `Tests/main.swift` 의 `observedBalanceJSON`, 작성일 표기 2026-10-10):

```json
{
    "included": {
        "balance_usd": 58.84709,
        "allowance_usd": 60,
        "period": {
            "from": "2026-10-01T05:45:52Z",
            "until": "2026-11-01T05:45:52Z"
        }
    },
    "purchased": {
        "balance_usd": 0
    }
}
```

문서와의 대조:

| 항목 | 문서 | 실측 | 판정 |
|---|---|---|---|
| 최상위 키 | `included`, `purchased` (둘 다 required) | `included`, `purchased` | 일치 |
| `included.balance_usd` | `number`, required | `58.84709` (JSON number) | 일치 — **문자열 아님** |
| `included.allowance_usd` | `number`, required | `60` (JSON number, 정수로 직렬화) | 일치 |
| `included.period.from`/`until` | `string` date-time, required, UTC, from inclusive / until exclusive | `2026-10-01T05:45:52Z` / `2026-11-01T05:45:52Z` | 일치 |
| `purchased.balance_usd` | `number`, required, "unexpired purchased credits" | `0` | 일치 |
| 레거시 변이(`session`/`weekly`) | 레거시 플랜에서만 | **없음** | 일치 — 이 계정은 **현행(non-legacy) 플랜** |
| 문서에 없는 추가 필드 | — | **없음** | 일치 |

추가 관찰 (문서 해석, 명시):
- 실측 `period.from` → `period.until` 이 정확히 한 달 간격(`2026-10-01T05:45:52Z` → `2026-11-01T05:45:52Z`)이며, 문서 예시도 동일하게 한 달 간격(`2026-09-15` → `2026-10-15`)이다. 이는 문서 문장 "The included period follows your plan's monthly reset schedule, including for annual subscriptions." 와 부합한다.
- **시사점(앱 설계 관련, 문서 사실 아님)**: 이제 **다음 갱신 시각을 서버가 `included.period.until` 로 직접 준다**. ADR-0007 은 갱신 예정일을 설정 파일의 청구 앵커(`billing_day_of_month`)로 계산하기로 했는데, 서버 값이 생긴 지금은 **서버 값 1순위 + 설정 앵커는 폴백**으로 재검토할 근거가 문서에 생겼다. (실측 1건 + 문서 예시 1건에서 기간이 한 달 간격으로 관측됨 — 표본 2개.)
- 실측 `balance_usd`(58.84709)가 `allowance_usd`(60)보다 작고 소수점 5자리까지 오므로, 금액은 부동소수로 다루면 된다.

---

## 7. 부수 발견: 로컬 서버가 두 엔드포인트를 프록시한다 (API 키 불필요 경로)

- 커밋 **f8646015, 2026-10-07T01:31:54Z, "server: proxy cloud usage and balance APIs (#18829)"** ([커밋](https://api.github.com/repos/ollama/ollama/commits/f8646015), 접근일 2026-10-10) 원문 메시지:
  > Forward GET /api/usage and GET /api/balance through the local server using the signed-in account.
  > Add API documentation and tests for proxying, signing, and disabled cloud access.
- 변경 파일에 `server/routes.go`(+18) 가 포함되며, 라우트 등록과 핸들러가 추가된다:
  ```go
  r.GET("/api/balance", s.BalanceHandler)
  r.GET("/api/usage", s.UsageHandler)
  ```
  ```go
  func (s *Server) BalanceHandler(c *gin.Context) {
      c.Header("Cache-Control", "private, no-store")
      // Use the account signed into this server, regardless of caller credentials.
      c.Request.Header.Del("Authorization")
      proxyCloudRequest(c, nil, cloudErrBalanceUnavailable)
  }
  ```
  → **로컬 서버(`http://localhost:11434`)에 로그인돼 있으면 API 키 없이 조회 가능**하며, 호출자가 준 `Authorization` 헤더는 **무시/삭제**된다. 오류 문구 상수는 `"balance is unavailable"` / `"usage is unavailable"`.
- **어느 릴리스부터인지 검증함**: 릴리스 태그의 `server/routes.go` 를 직접 확인한 결과 **`v0.40.0`(2026-09-25) 에는 `BalanceHandler` 가 없고, `v0.40.1`(2026-10-07) 과 `v0.40.2`(2026-10-08) 에는 있다** (접근일 2026-10-10). → 로컬 프록시 경로는 **v0.40.1 이상** 필요.
- 본 조사 환경의 로컬 서버는 **v0.34.4** 이며 실제로 `GET http://localhost:11434/api/usage` → `404 404 page not found`, `GET http://localhost:11434/api/balance` → `404` 였다(`/api/version` 은 200) — 버전 조건과 일치하는 관측이다.
- 앱 관점: API 키 온보딩 없이 "Ollama 앱 로그인만 되어 있으면" 동작하는 2차 데이터 소스가 생겼다. 단 **최소 v0.40.1 요구**이고, 로컬 서버 버전이 낮으면 404 이므로 폴백 처리 필요.

---

## 8. 미검증 · 추론 · 한계 (명시)

문서 근거가 있는 사실과 구분해 아래에 모은다. **아래 항목은 이 문서에서 "사실"로 취급하면 안 된다.**

- **구 `activity`/`limits.monthly` 필드가 인증된 실응답에 여전히 얹혀 오는지**: 미검증 (API 키 필요). 문서 계약상으로는 제거됨.
- **잘못된 `range` 값의 실제 동작(400 vs 401 순서)**: 미검증. 인증이 파라미터 검증보다 먼저 일어나 401 만 관측됨.
- **`/api/balance` 가 실제로 항상 `purchased.balance_usd` 를 포함하는지**: 문서는 required 로 선언. 실측 1건에서도 포함됨. 표본 부족(1건).
- **`period.until` 이 항상 청구 앵커와 일치하는지**: 문서 문장 + 실측 1건 + 문서 예시 1건 = 표본 2건. 연간 구독에서의 거동은 문서 언급("including for annual subscriptions")만 있고 실측 없음.
- **Free/Team/Enterprise 플랜에서의 balance 응답 차이**: 문서는 `Teams` 공유만 언급. Free 플랜의 `allowance_usd` 가 무엇으로 오는지(문서의 "starter amount" 의 금액)는 **어디에도 공개되어 있지 않다**.
- **"필드가 누락될 수 있다"는 서술은 공식 문서에 없다.** 문서가 말하는 누락은 (a) `included` 의 레거시 변이, (b) `usage` 의 레거시 요청 시 cost/token 4필드 생략, (c) 버킷의 `partial` 생략 — 이 세 가지뿐이다. 그 외 방어적 파싱은 앱의 판단(ADR-0001)이다.
- **402 Payment Required**: 두 엔드포인트 및 공식 에러 문서에 없음. 구 노트가 인용한 402 는 모델 요청 경로의 이슈 사례이며 이 문서의 계약이 아니다.
- **`docs.ollama.com` 문서와 업스트림 `docs/api/*.mdx` 는 동일 내용으로 확인**(본 조사에서 양쪽 grep 결과 일치, 접근일 2026-10-10). 단 업스트림 `main` 은 조사 이후 바뀔 수 있다.
- **이 저장소의 `Sources/OllamaUsageKit/BalanceSnapshot.swift` 주석이 참조하는 `ADR-0008` 은 아직 존재하지 않는다**(`docs/adr/` 에 0001~0007 만 있음, 접근일 2026-10-10). 리서치 범위 밖이지만 문서 정합성 문제로 기록해 둔다.

---

## 9. 대체(supersede) 선언

> **이 문서는 `docs/research/ollama-cloud-usage-credits-api.md` 의 `/api/usage` 관련 부분을 SUPERSEDE 한다.**
>
> 구 문서(작성 2026-09-01)의 다음 내용은 **더 이상 유효하지 않다**:
> - `GET /api/usage` 가 **무문서 사설 API**라서 스키마를 스태프 PR(#17421)·서드파티 관측으로 추정해야 한다는 서술 — **이제 공식 문서 + OpenAPI 스펙에 정식 포함**이다.
> - 응답 스키마가 `activity{cost, period, models[]}` + `limits{monthly{usage, models[]}}` 라는 서술 — **완전히 교체되었다**: 이제 `{range, scope, granularity, from, until, totals, buckets}` 이며 `activity`/`limits` 는 스펙에 없다.
> - `limits.monthly.usage` = [사용/제공] 비율(ADR-0002 의 근거), `activity.cost`, `activity.period.type: "last_4_weeks"` 에 의존하는 계산 — **그 필드들은 공식 표면에서 사라졌다**. 잔여 크레딧은 이제 `included.balance_usd` (달러 그대로) 로 직접 온다.
> - "레이트 리밋이 문서화되어 있지 않다" — **이제 문서화되어 있다 (분당 10회, 분당 1회 폴링 권장)**.
> - "OpenAPI 스펙에 `/api/usage` 가 없다" — **이제 있다**.
>
> 구 문서에서 **여전히 유효한 부분**: API 키 발급 절차(`https://ollama.com/settings/keys`, 무만료·수동 폐기), `Authorization: Bearer` 표준, 8-31 가격 개편/크레딧 풀 구조, `POST https://ollama.com/api/me` 존재, 로컬 서버 프록시 개념. 단, ADR-0002(서버 비율 1순위)와 `docs/spec/mvp.md` 의 `1 − limits.monthly.usage` 기반 지표는 **이 문서 기준으로 재검토 대상**이다.
